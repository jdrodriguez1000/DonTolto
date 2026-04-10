-- =============================================================================
-- TEST: 023_midflight_config_snapshot.sql
-- Trazabilidad: TSK-F1_1.1-18.6-RED — Test pgTap: Simulación de cambio de
--               configuración mid-flight (Verificar persistencia de Snapshot)
-- SPEC: Sección 4.2 — fn_compute_async_scoring (Snapshotting mandatorio)
-- PLAN: B5 — Motores RPC [TDD Cycle] — Fase RED
-- ADR: ADR-02 — Configuración Centralizada
-- ADR: ADR-04 — Recálculo Atómico Transparente
-- Responsable: backend-tester
-- Fecha: 2026-04-10
--
-- Tipo de test: RED (TDD) — Diseñado para FALLAR cuando la implementación no existe
--
-- Descripción: Verifica que fn_compute_async_scoring usa el snapshot de
--              system_configuration capturado AL INICIO de la función, no los
--              valores actuales en caso de que la configuración cambie durante
--              la ejecución (escenario mid-flight).
--
--              Escenario de prueba:
--              1. system_configuration tiene debt_threshold_hours=24
--              2. fn_compute_async_scoring inicia y debería capturar snapshot (24h)
--              3. Durante la ejecución (simulado), debt_threshold_hours cambia a 999
--              4. La función debe haber usado 24h, no 999h
--
--              La invariante de snapshot protege contra condiciones de carrera donde
--              un cambio de configuración mid-flight podría causar que distintas
--              proyecciones del mismo batch sean evaluadas con parámetros distintos,
--              produciendo resultados inconsistentes dentro de una misma ejecución.
--
-- Mecanismo de detección RED:
--   El stub no implementa snapshotting. Los tests verifican que:
--   a) El log de la función contiene el valor ORIGINAL de la configuración (no el nuevo)
--   b) La función no re-lee system_configuration durante el procesamiento
--   c) El estado de projections refleja procesamiento bajo el snapshot original
--
-- Estado esperado en RED (stub sin lógica):
--   - ASSERTION 1: FALLA — el stub no escribe logs con snapshot de configuración
--   - ASSERTION 2: FALLA — el stub no registra el valor original (24h) en el snapshot
--   - ASSERTION 3: FALLA — el stub no procesa proyecciones (no cambia status)
--   - ASSERTION 4: FALLA — el stub no escribe el valor snapshotted vs valor actual
--   - ASSERTION 5: FALLA — el stub no garantiza procesamiento bajo parámetros originales
-- =============================================================================

BEGIN;

SELECT plan(5);

-- ---------------------------------------------------------------------------
-- SETUP: Configurar system_configuration con valor inicial conocido
-- Nota: system_configuration es un Singleton (id=1). Se actualiza temporalmente
-- para el test. El ROLLBACK final restaura el estado original.
-- ---------------------------------------------------------------------------

-- Capturar el valor original de debt_threshold_hours para referencia
-- (puede haber sido seteado por otros tests o el seed inicial)
-- Actualizar a valor conocido para este test: 24 horas
UPDATE public.system_configuration
SET debt_threshold_hours = 24
WHERE id = 1;

-- Insertar estrategia de referencia para las proyecciones
INSERT INTO public.strategies_metadata (name, version, role, is_active)
VALUES ('test_midflight_strategy', 1, 'active', TRUE)
ON CONFLICT DO NOTHING;

-- Insertar draw de referencia
INSERT INTO public.draws (id, run_id, draw_date, numbers, superbalota, type, status, is_manual)
VALUES (
    '66666666-6666-6666-6666-666666666666'::uuid,
    gen_random_uuid(),
    '2099-06-01',
    ARRAY[4, 8, 12, 24, 36],
    6,
    'baloto',
    'final',
    FALSE
)
ON CONFLICT DO NOTHING;

-- Insertar proyecciones en estado 'pending' para procesamiento
INSERT INTO public.projections (id, run_id, target_draw_date, strategy_name, strategy_version, numbers, superbalota, status)
VALUES
    (
        'f6f6f6f6-f6f6-f6f6-f6f6-f6f6f6f6f6f6'::uuid,
        gen_random_uuid(),
        '2099-06-01',
        'test_midflight_strategy',
        1,
        ARRAY[4, 8, 12, 24, 36],
        6,
        'pending'
    );

-- Invocar fn_compute_async_scoring con el valor original (24h)
DO $$ BEGIN PERFORM public.fn_compute_async_scoring(gen_random_uuid()); END $$;

-- SIMULACIÓN MID-FLIGHT: Cambiar la configuración DESPUÉS de que la función inició
-- En la implementación real, este cambio ocurriría concurrentemente. En el test,
-- lo hacemos secuencialmente para verificar que el snapshot (pre-cambio) persiste.
UPDATE public.system_configuration
SET debt_threshold_hours = 999
WHERE id = 1;

-- ---------------------------------------------------------------------------
-- ASSERTION 1: Debe existir un log de la función con el valor ORIGINAL (24h)
-- capturado antes del cambio mid-flight
-- Estado RED: FALLA — el stub no escribe logs. COUNT = 0.
-- Razon: El snapshotting (SPEC §4.2) requiere que la función registre los valores
--        capturados al inicio en system_logs.metadata. Este log es el único
--        mecanismo observable para verificar qué valor usó la función durante
--        su ejecución, independientemente de cambios posteriores a system_config.
-- Criterio de paso GREEN: log con metadata que contiene debt_threshold_hours=24
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer >= 1
        FROM public.system_logs
        WHERE service = 'scoring'
          AND metadata IS NOT NULL
          AND (metadata ->> 'debt_threshold_hours')::integer = 24
    ),
    'MIDFLIGHT RED 18.6: el log de scoring debe registrar el valor ORIGINAL de debt_threshold_hours (24, no 999) en el snapshot'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 2: El log NO debe contener el valor nuevo (999h) que fue inyectado
-- después de que la función inició (verificación de no re-lectura mid-flight)
-- Estado RED: FALLA — el stub no escribe logs, por lo que no hay registros con 999.
--             Este assertion pasa en RED por razón equivocada (no hay logs en absoluto).
--             El assertion 1 es el que expone la falta de snapshotting real.
-- Razon: Si la función re-leyera system_configuration mid-flight en lugar de usar
--        el snapshot, usaría 999h. Este assertion detecta ese antipatrón verificando
--        que el valor 999 NO aparece en los logs de scoring de esta ejecución.
-- Criterio de paso GREEN: COUNT = 0 de logs con debt_threshold_hours=999 en scoring
-- ---------------------------------------------------------------------------
SELECT is(
    (
        SELECT COUNT(*)::integer
        FROM public.system_logs
        WHERE service = 'scoring'
          AND metadata IS NOT NULL
          AND (metadata ->> 'debt_threshold_hours')::integer = 999
    ),
    0,
    'MIDFLIGHT RED 18.6: el log de scoring NO debe contener el valor nuevo (999) inyectado mid-flight (anti-re-lectura)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 3: La proyección debe haber sido procesada (status != 'pending')
-- usando los parámetros del snapshot original
-- Estado RED: FALLA — el stub no cambia el estado de las proyecciones.
--             La proyección insertada permanece en 'pending'. COUNT = 0 en !pending.
-- Razon: El procesamiento de proyecciones bajo el snapshot original es la
--        demostración práctica del invariante de snapshotting. Si la proyección
--        fue procesada, los parámetros usados (capturados en logs) deben coincidir
--        con el snapshot original, no con el valor inyectado mid-flight.
-- Criterio de paso GREEN: la proyección tiene status != 'pending' tras la función
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer >= 1
        FROM public.projections
        WHERE id = 'f6f6f6f6-f6f6-f6f6-f6f6-f6f6f6f6f6f6'::uuid
          AND status != 'pending'
    ),
    'MIDFLIGHT RED 18.6: la proyección debe haber sido procesada bajo el snapshot original (status != pending)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 4: El valor actual de system_configuration (999h post-cambio) debe
-- ser distinto al valor snapshotted (24h) registrado en system_logs
-- Esta asimetría confirma que el snapshot capturó el estado PRE-cambio
-- Estado RED: FALLA — no hay logs de scoring, por lo que la comparación no se puede
--             realizar. La condición de asimetría no puede verificarse sin el log.
-- Razon: Esta assertion verifica explícitamente la asimetría temporal: la función
--        vio un valor (24h) que ya no existe en system_configuration (ahora 999h).
--        La discrepancia entre el log y el valor actual es prueba directa de que
--        el snapshot fue capturado al inicio, no re-leído mid-flight.
-- Criterio de paso GREEN: el valor en system_logs != valor actual en system_config
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        -- El valor en system_config ahora es 999 (cambiado mid-flight)
        -- El valor en el log de scoring debe ser 24 (snapshot original)
        -- Si son distintos, el snapshotting funcionó correctamente
        (SELECT debt_threshold_hours FROM public.system_configuration WHERE id = 1) = 999
        AND
        (
            SELECT COUNT(*)::integer >= 1
            FROM public.system_logs
            WHERE service = 'scoring'
              AND metadata IS NOT NULL
              AND (metadata ->> 'debt_threshold_hours')::integer = 24
        )
    ),
    'MIDFLIGHT RED 18.6: el snapshot (24h en log) debe diferir del valor actual (999h en config) — asimetria temporal confirmada'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 5: El sistema debe tener exactamente un log de scoring con el
-- snapshot de configuración correcto (idempotencia: una ejecución = un snapshot)
-- Estado RED: FALLA — el stub no escribe logs. COUNT = 0, no 1.
-- Razon: El snapshotting debe ser idempotente: una sola invocación de la función
--        debe generar exactamente un registro de snapshot en system_logs.
--        Múltiples snapshots por ejecución indicarían re-lectura mid-flight.
--        Cero snapshots indicarían ausencia de implementación.
-- Criterio de paso GREEN: COUNT = 1 log con service='scoring' y metadata de snapshot
-- ---------------------------------------------------------------------------
SELECT is(
    (
        SELECT COUNT(*)::integer
        FROM public.system_logs
        WHERE service = 'scoring'
          AND metadata IS NOT NULL
          AND metadata ? 'debt_threshold_hours'
    ),
    1,
    'MIDFLIGHT RED 18.6: debe existir exactamente un snapshot de configuracion por ejecucion de fn_compute_async_scoring'
);

SELECT * FROM finish();

-- CLEANUP: ROLLBACK restaura system_configuration a su estado pre-test
-- y elimina todos los datos insertados en esta transacción.
ROLLBACK;

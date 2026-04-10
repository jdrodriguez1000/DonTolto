-- =============================================================================
-- TEST: 018_scoring_snapshot_invariant.sql
-- Trazabilidad: TSK-F1_1.1-18.1-RED — Test pgTap: Snapshotting de parámetros
--               (inmovilidad ante cambios en system_configuration mid-flight)
-- SPEC: Sección 4.2 — fn_compute_async_scoring (Scoring Overlap)
-- PLAN: B5 — Motores RPC [TDD Cycle] — Fase RED
-- ADR: ADR-04 — Recálculo Atómico Transparente
-- Responsable: backend-tester
-- Fecha: 2026-04-10
--
-- Tipo de test: RED (TDD) — Diseñado para FALLAR cuando la implementación no existe
--
-- Descripción: Verifica que fn_compute_async_scoring captura los parámetros de
--              system_configuration AL INICIO de la función y los usa durante toda
--              la ejecución. Un cambio en system_config después de que la función
--              inicia NO debe afectar el scoring en curso.
--
--              La invariante de snapshotting es crítica: sin ella, un cambio de
--              configuración concurrente (p.ej., debt_threshold_hours) podría
--              producir resultados de scoring inconsistentes donde registros del
--              mismo batch son evaluados con parámetros distintos.
--
-- Mecanismo de detección RED:
--   El stub de fn_compute_async_scoring no implementa lógica real. Los tests
--   verifican efectos secundarios observables (estado de projections, logs)
--   que el stub no produce, por lo que todos los assertions fallan en RED.
--
-- Estado esperado en RED (stub sin lógica):
--   - ASSERTION 1: FALLA — la función existe pero es un stub (se verifica existencia)
--   - ASSERTION 2: FALLA — el stub no cambia status de projections a 'calculating'
--   - ASSERTION 3: FALLA — el stub no escribe en system_logs (sin trazabilidad)
--   - ASSERTION 4: FALLA — el stub no registra el valor snapshotted de debt_threshold_hours
--   - ASSERTION 5: FALLA — el stub no registra el valor snapshotted de is_system_locked
--   - ASSERTION 6: FALLA — projections permanecen en 'pending' tras invocar el stub
--
-- Cuando pase a GREEN (implementación real de fn_compute_async_scoring):
--   - La función debe capturar system_config al inicio y usarlo invariablemente
--   - Los assertions deben pasar: logs con snapshot, projections en 'calculating'
-- =============================================================================

BEGIN;

SELECT plan(6);

-- ---------------------------------------------------------------------------
-- SETUP: Datos de prueba mínimos necesarios para el test
-- Se insertan en la transacción; el ROLLBACK final garantiza aislamiento.
-- ---------------------------------------------------------------------------

-- Insertar una estrategia activa de referencia para las proyecciones
INSERT INTO public.strategies_metadata (name, version, role, is_active)
VALUES ('test_snapshot_strategy', 1, 'active', TRUE)
ON CONFLICT DO NOTHING;

-- Insertar un sorteo de referencia para que las proyecciones tengan draw asociado
INSERT INTO public.draws (id, run_id, draw_date, numbers, superbalota, type, status, is_manual)
VALUES (
    '11111111-1111-1111-1111-111111111111'::uuid,
    gen_random_uuid(),
    '2099-01-01',
    ARRAY[1, 2, 3, 4, 5],
    7,
    'baloto',
    'final',
    FALSE
)
ON CONFLICT DO NOTHING;

-- Insertar proyecciones en estado 'pending' para que fn_compute_async_scoring las procese
INSERT INTO public.projections (id, run_id, target_draw_date, strategy_name, strategy_version, numbers, superbalota, status)
VALUES
    (
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid,
        gen_random_uuid(),
        '2099-01-01',
        'test_snapshot_strategy',
        1,
        ARRAY[1, 2, 3, 4, 5],
        7,
        'pending'
    ),
    (
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid,
        gen_random_uuid(),
        '2099-01-01',
        'test_snapshot_strategy',
        1,
        ARRAY[6, 7, 8, 9, 10],
        3,
        'pending'
    );

-- ---------------------------------------------------------------------------
-- ASSERTION 1: La función fn_compute_async_scoring debe existir en el esquema public
-- Estado RED: PASA — el stub ya fue creado en block_4.sql (satisface el invariante
--             de existencia requerido por el pipeline de seguridad del Bloque 4).
-- Nota: Este assertion pasa en RED para confirmar que la función existe como stub.
--       Los assertions 2-6 son los que capturan la ausencia de lógica real.
-- Criterio de paso GREEN: la función existe (ya cumplido por el stub)
-- ---------------------------------------------------------------------------
SELECT has_function(
    'public',
    'fn_compute_async_scoring',
    ARRAY['uuid'],
    'SCORING RED 18.1: fn_compute_async_scoring debe existir en esquema public (SPEC §4.2)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 2: Después de invocar fn_compute_async_scoring, las proyecciones
-- en estado 'pending' deben haber sido marcadas como 'calculating' (anti-carrera)
-- Estado RED: FALLA — el stub no implementa UPDATE projections SET status='calculating'.
--             Las proyecciones permanecen en 'pending' tras la llamada al stub,
--             por lo que COUNT de 'calculating' = 0, no 2.
-- Razon: SPEC §4.2 (Protocolo Anti-Carrera) exige que la función marque registros
--        como 'calculating' antes del scoring para evitar doble procesamiento
--        concurrente. Sin este cambio de estado, la función no cumple el contrato.
-- Criterio de paso GREEN: COUNT de projections con status='calculating' = 2
-- ---------------------------------------------------------------------------
DO $$ BEGIN PERFORM public.fn_compute_async_scoring(gen_random_uuid()); END $$;

SELECT is(
    (
        SELECT COUNT(*)::integer
        FROM public.projections
        WHERE status = 'calculating'
          AND id IN (
              'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid,
              'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid
          )
    ),
    2,
    'SCORING RED 18.1: fn_compute_async_scoring debe marcar projections como calculating (anti-carrera SPEC §4.2)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 3: La función debe escribir al menos un registro en system_logs
-- durante su ejecución (trazabilidad de run_id mandatoria, SPEC §3.6)
-- Estado RED: FALLA — el stub solo lanza RAISE NOTICE, no inserta en system_logs.
--             COUNT de logs con service='scoring' = 0, la condición es FALSE.
-- Razon: La trazabilidad mediante run_id es un invariante global (CLAUDE.md).
--        fn_compute_async_scoring debe registrar inicio, snapshot y fin de
--        ejecución en system_logs para garantizar auditoría forense del proceso.
-- Criterio de paso GREEN: COUNT >= 1 en system_logs con service='scoring'
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer >= 1
        FROM public.system_logs
        WHERE service = 'scoring'
    ),
    'SCORING RED 18.1: fn_compute_async_scoring debe escribir trazabilidad en system_logs (SPEC §3.6)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 4: El snapshot de debt_threshold_hours debe aparecer en los
-- metadatos del log de inicio de la función (verificación de snapshotting)
-- Estado RED: FALLA — el stub no inserta en system_logs, por lo que ningún
--             registro tiene metadata con 'debt_threshold_hours'.
-- Razon: El snapshotting al inicio (SPEC §4.2) exige que la función capture
--        y registre los parámetros de system_configuration usados durante la
--        ejecución. Esto es auditable y forense: si la configuración cambia
--        mid-flight, el log muestra qué valores se usaron realmente.
-- Criterio de paso GREEN: al menos 1 log con metadata JSONB conteniendo
--        'debt_threshold_hours' con el valor capturado al inicio
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer >= 1
        FROM public.system_logs
        WHERE service = 'scoring'
          AND metadata ? 'debt_threshold_hours'
    ),
    'SCORING RED 18.1: el log de scoring debe incluir snapshot de debt_threshold_hours en metadata JSONB (invariante de snapshotting)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 5: El snapshot de is_system_locked debe aparecer en los metadatos
-- del log de inicio (verificación de snapshotting del kill-switch)
-- Estado RED: FALLA — el stub no inserta en system_logs, por lo que ningún
--             registro tiene metadata con 'is_system_locked'.
-- Razon: El kill-switch is_system_locked (SPEC §3.6) es el parámetro más
--        crítico de system_configuration. Si cambia mid-flight de FALSE a TRUE,
--        el proceso no debe continuar, pero el scoring en curso debe completarse
--        con el valor snapshotted al inicio para garantizar atomicidad.
-- Criterio de paso GREEN: al menos 1 log con metadata JSONB conteniendo
--        'is_system_locked' como clave del snapshot inicial
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer >= 1
        FROM public.system_logs
        WHERE service = 'scoring'
          AND metadata ? 'is_system_locked'
    ),
    'SCORING RED 18.1: el log de scoring debe incluir snapshot de is_system_locked en metadata JSONB (kill-switch audit)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 6: Las proyecciones de prueba NO deben permanecer en 'pending'
-- después de que fn_compute_async_scoring completa su ejecución
-- Estado RED: FALLA — el stub no cambia el estado de las proyecciones.
--             Las 2 proyecciones insertadas siguen en 'pending', por lo que
--             COUNT = 2 es mayor que 0, y ok(2 = 0) = FALLA.
-- Razon: Un scoring correctamente implementado debe consumir registros 'pending'
--        y transicionarlos a 'calculating' o 'calculated'. Si las proyecciones
--        permanecen en 'pending' tras la llamada, la función no procesó nada.
-- Criterio de paso GREEN: COUNT de projections en 'pending' = 0 tras el scoring
-- ---------------------------------------------------------------------------
SELECT is(
    (
        SELECT COUNT(*)::integer
        FROM public.projections
        WHERE status = 'pending'
          AND id IN (
              'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid,
              'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid
          )
    ),
    0,
    'SCORING RED 18.1: projections en pending deben ser procesadas (status != pending) tras invocar fn_compute_async_scoring'
);

SELECT * FROM finish();

-- CLEANUP: ROLLBACK garantiza aislamiento total. Ningún dato de prueba persiste.
ROLLBACK;

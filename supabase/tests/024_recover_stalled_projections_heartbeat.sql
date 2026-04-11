-- =============================================================================
-- TEST: 024_recover_stalled_projections_heartbeat.sql
-- Trazabilidad: TSK-F1_1.1-22.1-RED — Test pgTap: Reseteo determinista de
--               registros con latido antiguo (>30m)
-- SPEC: Seccion 4.4 — fn_manage_lock & fn_monitor_and_activate_fallback
-- PLAN: B5b — Automatizacion & Orquestacion [TDD Cycle] — Fase RED
-- ADR: ADR-03 — Locking con TTL (60 min)
-- Responsable: backend-tester
-- Fecha: 2026-04-10
--
-- Tipo de test: RED (TDD) — Disenado para FALLAR cuando la implementacion no existe
--
-- Descripcion: Verifica el comportamiento deterministico de fn_recover_stalled_projections.
--              La funcion debe resetear (limpiar worker_id y marcar status='pending')
--              SOLO aquellos registros de projections cuyo last_heartbeat sea
--              anterior a 30 minutos (worker zombie). Registros con heartbeat
--              reciente (< 30 min) NO deben ser tocados.
--
--              Escenario de prueba:
--              1. Se insertan dos proyecciones en estado 'calculating':
--                 - Proyeccion A: last_heartbeat = ahora - 45 min (zombie confirmado)
--                 - Proyeccion B: last_heartbeat = ahora - 10 min (worker activo)
--              2. Se invoca fn_recover_stalled_projections()
--              3. Solo la Proyeccion A debe resetearse a status='pending' con worker_id=NULL
--              4. La Proyeccion B debe permanecer en status='calculating' (worker vivo)
--
--              Invariante de resiliencia (PLAN B5b):
--              La funcion de recuperacion es el mecanismo anti-zombie del sistema.
--              Si reseteara workers activos (< 30 min), causaria condiciones de carrera
--              donde dos workers competirian por el mismo registro. El umbral de 30 min
--              da margen suficiente al worker lento antes de considerarlo muerto.
--
-- Mecanismo de deteccion RED:
--   La funcion fn_recover_stalled_projections NO EXISTE aun (ni la columna worker_id
--   ni la columna last_heartbeat en projections). Los tests verifican que:
--   a) La funcion existe y es invocable (confirmacion de stub — espera FALLO)
--   b) El registro zombie (>30m) es reseteado a status='pending'
--   c) El registro activo (<30m) permanece en status='calculating'
--   d) El worker_id del zombie es limpiado (NULL tras reset)
--   e) El worker_id del registro activo se preserva intacto
--
-- GAP TECNICO DETECTADO (Documentacion):
--   La SPEC §3.4 no incluye las columnas worker_id y last_heartbeat en la tabla
--   projections. El PLAN B5b (hito de aceptacion) las menciona como parte de
--   fn_recover_stalled_projections. La implementacion GREEN debera:
--   1. Ejecutar ALTER TABLE projections ADD COLUMN worker_id TEXT;
--   2. Ejecutar ALTER TABLE projections ADD COLUMN last_heartbeat TIMESTAMPTZ;
--   3. Crear la funcion fn_recover_stalled_projections() como SECURITY DEFINER.
--   Este test asume la existencia de dichas columnas en el estado GREEN.
--
-- Estado esperado en RED (funcion y columnas inexistentes):
--   - ASSERTION 1: FALLA — fn_recover_stalled_projections no existe (has_function=false)
--   - ASSERTION 2: FALLA — funcion no existe; proyeccion zombie no se resetea
--   - ASSERTION 3: FALLA — funcion no existe; proyeccion activa tampoco se verifica
--   - ASSERTION 4: FALLA — columna worker_id no existe; query lanza excepcion
--   - ASSERTION 5: FALLA — columna last_heartbeat no existe; query lanza excepcion
-- =============================================================================

BEGIN;

SELECT plan(5);

-- ---------------------------------------------------------------------------
-- SETUP: Insertar estrategia de referencia para las proyecciones
-- ---------------------------------------------------------------------------
INSERT INTO public.strategies_metadata (name, version, role, is_active)
VALUES ('test_stall_recovery_strategy', 1, 'active', TRUE)
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- SETUP: Insertar draw de referencia para las proyecciones
-- (target_draw_date en el futuro para evitar colision con datos reales)
-- ---------------------------------------------------------------------------
INSERT INTO public.draws (id, run_id, draw_date, numbers, superbalota, type, status, is_manual)
VALUES (
    '77777777-7777-7777-7777-777777777777'::uuid,
    gen_random_uuid(),
    '2099-07-01',
    ARRAY[2, 9, 15, 28, 40],
    7,
    'baloto',
    'final',
    FALSE
)
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- NOTA SOBRE LAS INSERCIONES DE PROYECCION:
-- Las columnas worker_id y last_heartbeat no existen en el esquema actual.
-- En la fase RED, los DO blocks que intentan insertarlas fallan silenciosamente
-- (son capturados por EXCEPTION). Las assertions 4 y 5 verifican la existencia
-- de dichas columnas — fallaran en RED por diseno.
-- En la fase GREEN, el db-manager debera ejecutar las migraciones ALTER TABLE
-- antes de que este test pueda pasar completamente.
-- ---------------------------------------------------------------------------

-- Intentar insertar proyeccion ZOMBIE (last_heartbeat > 30 min — candidata a reset)
-- Este bloque falla silenciosamente en RED porque la columna no existe
DO $$
BEGIN
    INSERT INTO public.projections
        (id, run_id, target_draw_date, strategy_name, strategy_version,
         numbers, superbalota, status, worker_id, last_heartbeat)
    VALUES (
        'a7a7a7a7-a7a7-a7a7-a7a7-a7a7a7a7a7a7'::uuid,
        gen_random_uuid(),
        '2099-07-01',
        'test_stall_recovery_strategy',
        1,
        ARRAY[2, 9, 15, 28, 40],
        7,
        'calculating',
        'b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1'::uuid,
        now() - interval '45 minutes'
    );
EXCEPTION WHEN undefined_column THEN
    -- Columna worker_id o last_heartbeat aun no existe — estado RED esperado
    RAISE NOTICE 'RED expected: columna worker_id/last_heartbeat no existe aun en projections';
END $$;

-- Intentar insertar proyeccion ACTIVA (last_heartbeat < 30 min — NO debe ser reseteada)
-- Este bloque falla silenciosamente en RED porque la columna no existe
DO $$
BEGIN
    INSERT INTO public.projections
        (id, run_id, target_draw_date, strategy_name, strategy_version,
         numbers, superbalota, status, worker_id, last_heartbeat)
    VALUES (
        'b8b8b8b8-b8b8-b8b8-b8b8-b8b8b8b8b8b8'::uuid,
        gen_random_uuid(),
        '2099-07-01',
        'test_stall_recovery_strategy',
        1,
        ARRAY[2, 9, 15, 28, 40],
        7,
        'calculating',
        'b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2'::uuid,
        now() - interval '10 minutes'
    );
EXCEPTION WHEN undefined_column THEN
    RAISE NOTICE 'RED expected: columna worker_id/last_heartbeat no existe aun en projections';
END $$;

-- Invocar la funcion de recuperacion (no existe en RED — capturado por EXCEPTION)
DO $$
BEGIN
    PERFORM public.fn_recover_stalled_projections();
EXCEPTION WHEN undefined_function THEN
    RAISE NOTICE 'RED expected: fn_recover_stalled_projections no existe aun';
END $$;

-- ---------------------------------------------------------------------------
-- ASSERTION 1: La funcion fn_recover_stalled_projections debe existir
-- Estado RED: FALLA — la funcion no ha sido creada aun. has_function() = false.
-- Razon: La existencia de la funcion es el prerequisito para cualquier otro
--        assertion de comportamiento. En RED confirma que el stub no ha sido
--        creado todavia (diferente al patron de Bloque 5 donde existia un stub).
-- Criterio de paso GREEN: la funcion existe con firma: fn_recover_stalled_projections()
-- ---------------------------------------------------------------------------
SELECT has_function(
    'public',
    'fn_recover_stalled_projections',
    ARRAY[]::text[],
    'STALL RED 22.1: fn_recover_stalled_projections debe existir antes de verificar comportamiento deterministico'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 2: La proyeccion zombie (last_heartbeat > 30 min) debe haber sido
-- reseteada a status='pending' por fn_recover_stalled_projections
-- Estado RED: FALLA — la funcion no existe y la columna last_heartbeat tampoco.
--             La proyeccion zombie nunca fue insertada (DO block con EXCEPTION).
--             COUNT = 0, no se puede verificar el reset.
-- Razon: El hito de aceptacion del PLAN B5b exige que la funcion solo resetee
--        registros con last_heartbeat anterior a 30 min. El reset es la operacion
--        central que elimina al worker zombie del sistema y libera el registro
--        para que un nuevo worker sano lo retome.
-- Criterio de paso GREEN: proyeccion a7a7... tiene status='pending' y worker_id=NULL
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer = 1
        FROM public.projections
        WHERE id = 'a7a7a7a7-a7a7-a7a7-a7a7-a7a7a7a7a7a7'::uuid
          AND status = 'pending'
    ),
    'STALL RED 22.1: proyeccion zombie (>30m sin heartbeat) debe resetearse a status=pending tras fn_recover_stalled_projections'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 3: La proyeccion con worker activo (last_heartbeat < 30 min) NO debe
-- ser reseteada — debe permanecer en status='calculating'
-- Estado RED: FALLA — la funcion no existe y la columna tampoco. La proyeccion
--             activa nunca fue insertada. COUNT = 0; la condicion status='calculating' falla.
-- Razon: Esta es la invariante critica del DoD: "Test falla si se resetea un
--        worker_id con latido inferior a 30m." Si la funcion reseteara workers
--        activos, causaria corrupcion de datos al dejar el worker original
--        procesando un registro que otro worker ya reclamo.
-- Criterio de paso GREEN: proyeccion b8b8... tiene status='calculating' (intacto)
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer = 1
        FROM public.projections
        WHERE id = 'b8b8b8b8-b8b8-b8b8-b8b8-b8b8b8b8b8b8'::uuid
          AND status = 'calculating'
    ),
    'STALL RED 22.1: proyeccion con worker activo (<30m de heartbeat) NO debe resetearse — debe permanecer en calculating'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 4: El campo worker_id de la proyeccion zombie debe ser NULL tras el reset
-- (limpieza total del claim del worker muerto)
-- Estado RED: FALLA — la columna worker_id no existe en projections. La query
--             lanza undefined_column y el test falla por error de ejecucion.
-- Razon: El worker_id es el "claim token" que identifica que worker posee el
--        registro. Si el reset no limpia el worker_id, otro worker no podra
--        tomar posesion del registro porque la columna seguira apuntando al zombie.
-- Criterio de paso GREEN: worker_id IS NULL para la proyeccion a7a7...
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer = 1
        FROM public.projections
        WHERE id = 'a7a7a7a7-a7a7-a7a7-a7a7-a7a7a7a7a7a7'::uuid
          AND worker_id IS NULL
    ),
    'STALL RED 22.1: worker_id de proyeccion zombie debe limpiarse (NULL) tras reset deterministico'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 5: El campo worker_id del worker activo debe preservarse intacto
-- (la funcion no debe tocar registros con heartbeat reciente)
-- Estado RED: FALLA — la columna worker_id no existe. La query lanza
--             undefined_column y el test falla por error de ejecucion.
-- Razon: La funcion debe ser quirurgica: modificar SOLO los registros calificados
--        por el umbral de 30 min. Cualquier UPDATE que afecte registros activos
--        es una violacion del contrato de resiliencia definido en PLAN B5b.
-- Criterio de paso GREEN: worker_id = 'b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2'::uuid para la proyeccion b8b8...
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer = 1
        FROM public.projections
        WHERE id = 'b8b8b8b8-b8b8-b8b8-b8b8-b8b8b8b8b8b8'::uuid
          AND worker_id = 'b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2'::uuid
    ),
    'STALL RED 22.1: worker_id del worker activo debe preservarse intacto (funcion no debe tocar heartbeats recientes)'
);

SELECT * FROM finish();

-- CLEANUP: ROLLBACK garantiza aislamiento total. Nada persiste en la base de datos.
ROLLBACK;

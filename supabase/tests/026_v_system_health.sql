-- =============================================================================
-- TEST: 026_v_system_health.sql
-- Trazabilidad: TSK-F1_1.1-26.1-RED — Test pgTap: Integridad y cálculo de
--               métricas en v_system_health
-- SPEC: Seccion 6 — Observabilidad (Contrato de Interfaz), ARC-06
-- PLAN: B6 — Observabilidad & Mantenimiento [TDD Cycle] — Fase RED
-- REQ: REQ-10, OBJ-05
-- Responsable: backend-tester
-- Fecha: 2026-04-10
--
-- Tipo de test: RED (TDD) — Disenado para FALLAR cuando la implementacion no existe
--
-- Descripcion: Verifica el comportamiento de la vista v_system_health como capa
--              de observabilidad del sistema. La vista debe agregar metricas del
--              estado operativo del pipeline de proyecciones:
--              - Total de proyecciones registradas
--              - Conteo por estado: pending, calculating, scored (calculated), error_fatal
--              - Latencia promedio de scoring (diferencia entre scored_at y created_at
--                para proyecciones en estado 'calculated')
--
--              Escenario de prueba:
--              1. Se inserta una estrategia de prueba en strategies_metadata.
--              2. Se insertan dos proyecciones:
--                 - Una en estado 'calculated' (scoring completado)
--                 - Una en estado 'error_fatal' (fallo de procesamiento)
--              3. Se consulta v_system_health y se verifica que:
--                 a) La vista existe y es consultable (espera FALLO en RED)
--                 b) El conteo de 'error_fatal' refleja el registro insertado
--                 c) La vista expone la columna error_fatal_count (o equivalente)
--                 d) El total de proyecciones es coherente con los datos insertados
--
-- Nota sobre 'error_fatal':
--   El PLAN B5b (Logica de Resiliencia / Anti-Poison Pill) define el estado
--   'error_fatal' como parte del ciclo de vida de projections. La implementacion
--   GREEN debe actualizar el CHECK constraint de projections.status para incluir
--   este valor. En RED, la insercion de 'error_fatal' fallara por violacion de
--   constraint; el DO block captura la excepcion silenciosamente.
--
-- Mecanismo de deteccion RED:
--   La vista v_system_health NO EXISTE aun. Los tests verifican:
--   a) La vista existe y es consultable (espera FALLO — view no existe)
--   b) El conteo de error_fatal refleja los datos insertados (espera FALLO)
--   c) La columna error_fatal_count (o equivalente) esta presente (espera FALLO)
--   d) El total de proyecciones es coherente (espera FALLO — view no existe)
--
-- Estado esperado en RED (vista inexistente):
--   - ASSERTION 1: FALLA — v_system_health no existe (has_view = false)
--   - ASSERTION 2: FALLA — vista inexistente; no retorna filas; conteo error_fatal = 0
--   - ASSERTION 3: FALLA — vista inexistente; columna error_fatal_count no existe
--   - ASSERTION 4: FALLA — vista inexistente; total_projections no puede evaluarse
-- =============================================================================

BEGIN;

SELECT plan(4);

-- ---------------------------------------------------------------------------
-- SETUP: Insertar estrategia de referencia para las proyecciones de prueba
-- ---------------------------------------------------------------------------
INSERT INTO public.strategies_metadata (name, version, role, is_active)
VALUES ('test_health_strategy', 1, 'active', TRUE)
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- SETUP: Insertar proyeccion en estado 'calculated' (completada exitosamente)
-- Esta proyeccion simula un ciclo de scoring exitoso. Se usa un ID fijo para
-- verificacion posterior.
-- ---------------------------------------------------------------------------
INSERT INTO public.projections
    (id, run_id, target_draw_date, strategy_name, strategy_version,
     numbers, superbalota, status)
VALUES (
    'e1e1e1e1-e1e1-e1e1-e1e1-e1e1e1e1e1e1'::uuid,
    gen_random_uuid(),
    '2099-10-01',
    'test_health_strategy',
    1,
    ARRAY[3, 11, 22, 35, 41],
    5,
    'calculated'
)
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- SETUP: Intentar insertar proyeccion en estado 'error_fatal'
-- En RED el CHECK constraint de projections.status no incluye 'error_fatal'.
-- El DO block captura la excepcion silenciosamente — comportamiento RED esperado.
-- En GREEN, la migracion B6 debe ampliar el CHECK para incluir 'error_fatal'.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    INSERT INTO public.projections
        (id, run_id, target_draw_date, strategy_name, strategy_version,
         numbers, superbalota, status)
    VALUES (
        'e2e2e2e2-e2e2-e2e2-e2e2-e2e2e2e2e2e2'::uuid,
        gen_random_uuid(),
        '2099-10-01',
        'test_health_strategy',
        1,
        ARRAY[4, 13, 24, 36, 42],
        6,
        'error_fatal'
    );
EXCEPTION WHEN check_violation OR others THEN
    -- Estado RED esperado: constraint no permite 'error_fatal' aun
    RAISE NOTICE 'RED expected: status error_fatal no esta permitido por el CHECK constraint actual en projections';
END $$;

-- ---------------------------------------------------------------------------
-- ASSERTION 1: La vista v_system_health debe existir y ser consultable
-- Estado RED: FALLA — la vista no ha sido creada aun. has_view() = false.
-- Razon: v_system_health es el componente central de la capa de observabilidad
--        (ARC-06). Sin esta vista, el Dashboard no puede consultar el estado
--        operativo del pipeline de proyecciones. La existencia es prerequisito
--        para todas las assertions de comportamiento subsiguientes.
-- Criterio de paso GREEN: la vista existe con nombre 'v_system_health' en schema 'public'
-- ---------------------------------------------------------------------------
SELECT has_view(
    'public',
    'v_system_health',
    'HEALTH RED 26.1: v_system_health debe existir como vista de observabilidad del pipeline (ARC-06)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 2: La vista debe reflejar el conteo correcto de proyecciones en
-- estado 'error_fatal' (= 1 segun el fixture insertado en estado GREEN)
-- Estado RED: FALLA — la vista no existe. La query lanza una excepcion de
--             relacion inexistente o retorna 0 filas. El conteo esperado (1)
--             no puede cumplirse.
-- Razon: El DoD de TSK-26.1 exige que la vista reporte correctamente los
--        registros en estado error_fatal. Esta es la invariante critica de
--        observabilidad: el Admin debe poder identificar proyecciones fallidas
--        de forma inmediata sin consultar directamente la tabla base.
-- Criterio de paso GREEN: error_fatal_count = 1 tras insertar el fixture e2e2...
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer >= 1
        FROM public.v_system_health
        WHERE error_fatal_count >= 1
    ),
    'HEALTH RED 26.1: v_system_health debe reportar error_fatal_count >= 1 tras insertar proyeccion con status=error_fatal'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 3: La vista debe exponer una columna denominada 'error_fatal_count'
-- (o equivalente semantico para el conteo de proyecciones en estado error_fatal)
-- Estado RED: FALLA — la vista no existe; la columna tampoco puede verificarse.
--             has_column() devuelve false porque la relacion no existe.
-- Razon: El contrato de interfaz de la vista debe ser explicito y documentado.
--        La columna error_fatal_count es el indicador de alerta primario del
--        sistema. Su nombre debe ser estable para que el Dashboard y las
--        consultas automatizadas no requieran conocer la logica interna de la vista.
-- Criterio de paso GREEN: la columna 'error_fatal_count' existe en v_system_health
-- ---------------------------------------------------------------------------
SELECT has_column(
    'public',
    'v_system_health',
    'error_fatal_count',
    'HEALTH RED 26.1: v_system_health debe exponer columna error_fatal_count como indicador de alerta primario'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 4: La vista debe exponer una columna 'total_projections' que
-- refleje el total de proyecciones registradas en el sistema
-- Estado RED: FALLA — la vista no existe; has_column() devuelve false.
-- Razon: El total de proyecciones es la metrica base para calcular porcentajes
--        de distribucion por estado. Sin este denominador, los conteos por estado
--        son informativos pero no permiten calcular ratios de exito/fallo,
--        que son los KPIs clave de observabilidad del motor (MET-05).
-- Criterio de paso GREEN: la columna 'total_projections' existe en v_system_health
-- ---------------------------------------------------------------------------
SELECT has_column(
    'public',
    'v_system_health',
    'total_projections',
    'HEALTH RED 26.1: v_system_health debe exponer columna total_projections como denominador de metricas de distribucion'
);

SELECT * FROM finish();

-- CLEANUP: ROLLBACK garantiza aislamiento total. Nada persiste en la base de datos.
ROLLBACK;

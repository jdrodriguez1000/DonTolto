-- =============================================================================
-- TEST: 027_v_strategy_delta.sql
-- Trazabilidad: TSK-F1_1.1-26.2-RED — Test pgTap: Validacion de desvios en
--               v_strategy_delta
-- SPEC: Seccion 6 — Observabilidad (Contrato de Interfaz), ARC-06
--       "Pivote de performance comparando estrategias de rol active vs control"
--       Atributos: draw_date, type, strategy_name, avg_score, is_control_delta
-- PLAN: B6 — Observabilidad & Mantenimiento [TDD Cycle] — Fase RED
-- REQ: REQ-10, OBJ-04
-- Responsable: backend-tester
-- Fecha: 2026-04-10
--
-- Tipo de test: RED (TDD) — Disenado para FALLAR cuando la implementacion no existe
--
-- Descripcion: Verifica el comportamiento de la vista v_strategy_delta como
--              herramienta de analisis comparativo de performance entre estrategias.
--              La vista debe calcular:
--              - El score promedio (avg_score) por estrategia para cada sorteo
--              - Un indicador de delta (is_control_delta o avg_delta_vs_control)
--                que mida la diferencia entre estrategias activas y la estrategia
--                de control para el mismo sorteo
--
--              La SPEC §6 define el contrato:
--              Atributos: draw_date, type, strategy_name, avg_score, is_control_delta
--              Logica: Pivote de performance comparando roles active vs control.
--
--              Escenario de prueba:
--              1. Se insertan dos estrategias: una 'active' y una 'control'
--              2. Se inserta un sorteo de referencia en draws
--              3. Se insertan dos proyecciones (una por estrategia)
--              4. Se insertan registros de performance:
--                 - Estrategia active: hits_count=3, has_sb=FALSE → score=3
--                 - Estrategia control: hits_count=1, has_sb=FALSE → score=1
--              5. Se consulta v_strategy_delta y se verifica que:
--                 a) La vista existe y es consultable
--                 b) El avg_score de la estrategia active es 3.0
--                 c) El avg_score de la estrategia control es 1.0
--                 d) La columna is_control_delta o avg_delta_vs_control existe
--
-- Mecanismo de deteccion RED:
--   La vista v_strategy_delta NO EXISTE aun. Los tests verifican:
--   a) La vista existe (espera FALLO — view no existe)
--   b) El avg_score de la estrategia active es el esperado (espera FALLO)
--   c) El avg_score de la estrategia control es el esperado (espera FALLO)
--   d) La columna de comparacion (is_control_delta) existe (espera FALLO)
--
-- Estado esperado en RED (vista inexistente):
--   - ASSERTION 1: FALLA — v_strategy_delta no existe (has_view = false)
--   - ASSERTION 2: FALLA — vista inexistente; avg_score de estrategia active no accesible
--   - ASSERTION 3: FALLA — vista inexistente; avg_score de estrategia control no accesible
--   - ASSERTION 4: FALLA — vista inexistente; columna is_control_delta no existe
-- =============================================================================

BEGIN;

SELECT plan(4);

-- ---------------------------------------------------------------------------
-- SETUP: Insertar estrategia ACTIVE de referencia para pruebas de delta
-- ---------------------------------------------------------------------------
INSERT INTO public.strategies_metadata (name, version, role, is_active)
VALUES ('test_active_delta_strategy', 1, 'active', TRUE)
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- SETUP: Insertar estrategia CONTROL de referencia (linea base del delta)
-- La estrategia de control es el denominador del analisis comparativo.
-- ---------------------------------------------------------------------------
INSERT INTO public.strategies_metadata (name, version, role, is_active)
VALUES ('test_control_delta_strategy', 1, 'control', TRUE)
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- SETUP: Insertar sorteo de referencia para asociar performance
-- Se usa una fecha futura lejana para evitar colisiones con datos reales.
-- ---------------------------------------------------------------------------
INSERT INTO public.draws
    (id, run_id, draw_date, numbers, superbalota, type, status, is_manual)
VALUES (
    'f1f1f1f1-f1f1-f1f1-f1f1-f1f1f1f1f1f1'::uuid,
    gen_random_uuid(),
    '2099-11-01',
    ARRAY[5, 14, 23, 32, 41],
    8,
    'baloto',
    'final',
    FALSE
)
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- SETUP: Insertar proyeccion para estrategia ACTIVE
-- Numeros que producen 3 aciertos contra el sorteo de referencia.
-- ---------------------------------------------------------------------------
INSERT INTO public.projections
    (id, run_id, target_draw_date, strategy_name, strategy_version,
     numbers, superbalota, status)
VALUES (
    'f2f2f2f2-f2f2-f2f2-f2f2-f2f2f2f2f2f2'::uuid,
    gen_random_uuid(),
    '2099-11-01',
    'test_active_delta_strategy',
    1,
    ARRAY[5, 14, 23, 32, 41],
    9,
    'calculated'
)
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- SETUP: Insertar proyeccion para estrategia CONTROL
-- Numeros que producen 1 acierto contra el sorteo de referencia.
-- ---------------------------------------------------------------------------
INSERT INTO public.projections
    (id, run_id, target_draw_date, strategy_name, strategy_version,
     numbers, superbalota, status)
VALUES (
    'f3f3f3f3-f3f3-f3f3-f3f3-f3f3f3f3f3f3'::uuid,
    gen_random_uuid(),
    '2099-11-01',
    'test_control_delta_strategy',
    1,
    ARRAY[5, 10, 20, 30, 40],
    9,
    'calculated'
)
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- SETUP: Insertar performance para la proyeccion ACTIVE
-- hits_count=3, has_sb=FALSE → score GENERATED = 3
-- Simula una estrategia active con rendimiento superior al control.
-- ---------------------------------------------------------------------------
INSERT INTO public.performance
    (id, draw_id, projection_id, hits_count, has_sb, is_verified)
VALUES (
    'f4f4f4f4-f4f4-f4f4-f4f4-f4f4f4f4f4f4'::uuid,
    'f1f1f1f1-f1f1-f1f1-f1f1-f1f1f1f1f1f1'::uuid,
    'f2f2f2f2-f2f2-f2f2-f2f2-f2f2f2f2f2f2'::uuid,
    3,
    FALSE,
    TRUE
)
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- SETUP: Insertar performance para la proyeccion CONTROL
-- hits_count=1, has_sb=FALSE → score GENERATED = 1
-- Simula la linea base de la estrategia de control.
-- ---------------------------------------------------------------------------
INSERT INTO public.performance
    (id, draw_id, projection_id, hits_count, has_sb, is_verified)
VALUES (
    'f5f5f5f5-f5f5-f5f5-f5f5-f5f5f5f5f5f5'::uuid,
    'f1f1f1f1-f1f1-f1f1-f1f1-f1f1f1f1f1f1'::uuid,
    'f3f3f3f3-f3f3-f3f3-f3f3-f3f3f3f3f3f3'::uuid,
    1,
    FALSE,
    TRUE
)
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- ASSERTION 1: La vista v_strategy_delta debe existir y ser consultable
-- Estado RED: FALLA — la vista no ha sido creada aun. has_view() = false.
-- Razon: v_strategy_delta es el componente analitico de ARC-06. Permite al
--        Dashboard visualizar que estrategias superan a la linea base de control,
--        sustentando las decisiones de activacion/archivo de estrategias (REQ-10).
--        Sin esta vista, el sistema carece de la capacidad de benchmarking
--        comparativo definida en la SPEC §6.
-- Criterio de paso GREEN: la vista existe con nombre 'v_strategy_delta' en schema 'public'
-- ---------------------------------------------------------------------------
SELECT has_view(
    'public',
    'v_strategy_delta',
    'DELTA RED 26.2: v_strategy_delta debe existir como vista de analisis comparativo de performance (ARC-06, SPEC §6)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 2: El avg_score de la estrategia active debe ser 3.0
-- (reflejo del fixture de performance: hits_count=3, has_sb=FALSE → score=3)
-- Estado RED: FALLA — la vista no existe. La query lanza relacion inexistente.
--             El resultado esperado (avg_score = 3.0) no puede evaluarse.
-- Razon: La precision del calculo de avg_score es el nucleo del contrato de la
--        vista. Un error de un decimal en el promedio produciria deltas incorrectos
--        que llevarian al Dashboard a mostrar rankings erroneos de estrategias.
--        El SPEC §6 especifica 'avg_score' como atributo obligatorio de la vista.
-- Criterio de paso GREEN: avg_score = 3.0 para 'test_active_delta_strategy' en
--        draw_date='2099-11-01', type='baloto'
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer = 1
        FROM public.v_strategy_delta
        WHERE strategy_name = 'test_active_delta_strategy'
          AND draw_date = '2099-11-01'::date
          AND type = 'baloto'
          AND avg_score = 3.0
    ),
    'DELTA RED 26.2: v_strategy_delta debe calcular avg_score=3.0 para estrategia active con hits_count=3 y has_sb=FALSE'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 3: El avg_score de la estrategia control debe ser 1.0
-- (reflejo del fixture de performance: hits_count=1, has_sb=FALSE → score=1)
-- Estado RED: FALLA — la vista no existe. La query lanza relacion inexistente.
--             El resultado esperado (avg_score = 1.0) no puede evaluarse.
-- Razon: La linea base de control es el denominador del calculo de delta. Si
--        el avg_score del control no se calcula correctamente, el delta entre
--        estrategias sera incorrecto y el sistema de ranking sera inutil.
--        La SPEC §6 define 'is_control_delta' como un atributo derivado del
--        pivote entre roles 'active' y 'control'.
-- Criterio de paso GREEN: avg_score = 1.0 para 'test_control_delta_strategy' en
--        draw_date='2099-11-01', type='baloto'
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer = 1
        FROM public.v_strategy_delta
        WHERE strategy_name = 'test_control_delta_strategy'
          AND draw_date = '2099-11-01'::date
          AND type = 'baloto'
          AND avg_score = 1.0
    ),
    'DELTA RED 26.2: v_strategy_delta debe calcular avg_score=1.0 para estrategia control con hits_count=1 y has_sb=FALSE'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 4: La vista debe exponer la columna 'is_control_delta' (o atributo
-- equivalente de comparacion segun SPEC §6)
-- Estado RED: FALLA — la vista no existe; has_column() devuelve false porque
--             la relacion no puede ser encontrada en el catalogo.
-- Razon: La columna 'is_control_delta' es el contrato de interfaz de la vista
--        definido explicitamente en la SPEC §6. Esta columna permite al Dashboard
--        identificar directamente si una estrategia supera a la linea de control,
--        sin requerir calculos adicionales del lado del cliente. La estabilidad
--        de este nombre de columna es critica para la integracion con el frontend.
-- Criterio de paso GREEN: la columna 'is_control_delta' existe en v_strategy_delta
-- ---------------------------------------------------------------------------
SELECT has_column(
    'public',
    'v_strategy_delta',
    'is_control_delta',
    'DELTA RED 26.2: v_strategy_delta debe exponer columna is_control_delta segun contrato de interfaz SPEC §6'
);

SELECT * FROM finish();

-- CLEANUP: ROLLBACK garantiza aislamiento total. Nada persiste en la base de datos.
ROLLBACK;

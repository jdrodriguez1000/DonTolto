-- =============================================================================
-- TEST: 021_transaction_atomicity.sql
-- Trazabilidad: TSK-F1_1.1-18.4-RED — Test pgTap: Atomicidad de transacciones
--               ante fallos parciales (Savepoint Trigger)
-- SPEC: Sección 4.3 §4 — Recálculo Atómico y Trazabilidad Forense
-- PLAN: B5 — Motores RPC [TDD Cycle] — Fase RED
-- ADR: ADR-04 — Recálculo Atómico Transparente
-- Responsable: backend-tester
-- Fecha: 2026-04-10
--
-- Tipo de test: RED (TDD) — Diseñado para FALLAR cuando la implementación no existe
--
-- Descripción: Verifica la atomicidad transaccional del recálculo en
--              fn_verify_and_promote_draw. Cuando el proceso de promoción implica:
--              (1) backup forense en system_logs
--              (2) DELETE de performance del draw anterior
--              (3) RESET de projections.status='pending'
--              (4) promoción del nuevo draw a draws
--
--              Si cualquier paso falla, TODOS deben revertirse (atomicidad total).
--              El sistema no debe quedar en estado inconsistente: sin backup forense
--              pero con datos borrados, o con draws promovido pero performance intacto.
--
--              Contrato de atomicidad (SPEC §4.3 §4, ADR-04):
--              - El recálculo usa una transacción que incluye backup + DELETE + RESET + INSERT
--              - Un fallo en cualquier paso revierte toda la operación
--              - El estado pre-operación debe ser restaurable sin pérdida de datos
--
-- Mecanismo de detección RED:
--   Se configura un escenario con un draw 'transient' ya existente (con performance
--   y projections asociados). Se intenta la promoción que requeriría recálculo atómico.
--   El stub no implementa la secuencia atómica, por lo que los estados quedan
--   inconsistentes o vacíos (no se borró performance, no se resetearon projections).
--
-- Estado esperado en RED (stub sin lógica):
--   - ASSERTION 1: FALLA — el stub no inserta backup en system_logs (level=audit)
--   - ASSERTION 2: FALLA — el stub no elimina registros de performance del draw anterior
--   - ASSERTION 3: FALLA — el stub no resetea projections.status a 'pending'
--   - ASSERTION 4: FALLA — el stub no promueve el nuevo draw a 'final'
--   - ASSERTION 5: FALLA — el estado del sistema es inconsistente (parcialmente modificado)
-- =============================================================================

BEGIN;

SELECT plan(5);

-- ---------------------------------------------------------------------------
-- SETUP: Crear escenario con draw 'transient' anterior + performance + projections
-- Simula el estado post-Fallback: existe un draw transient del Scraper que
-- ahora el Admin va a corregir, requiriendo recálculo atómico completo.
-- ---------------------------------------------------------------------------

-- Draw anterior en estado 'transient' (creado por Fallback del Scraper)
INSERT INTO public.draws (id, run_id, draw_date, numbers, superbalota, type, status, is_manual)
VALUES (
    '22222222-2222-2222-2222-222222222222'::uuid,
    gen_random_uuid(),
    '2099-04-01',
    ARRAY[3, 7, 11, 22, 33],
    5,
    'baloto',
    'transient',
    FALSE
);

-- Insertar estrategia de referencia para las proyecciones
INSERT INTO public.strategies_metadata (name, version, role, is_active)
VALUES ('test_atomicity_strategy', 1, 'control', TRUE)
ON CONFLICT DO NOTHING;

-- Proyecciones calculadas para ese draw transient (ya procesadas)
INSERT INTO public.projections (id, run_id, target_draw_date, strategy_name, strategy_version, numbers, superbalota, status)
VALUES (
    '33333333-3333-3333-3333-333333333333'::uuid,
    gen_random_uuid(),
    '2099-04-01',
    'test_atomicity_strategy',
    1,
    ARRAY[3, 7, 11, 22, 33],
    5,
    'calculated'
);

-- Performance calculada para ese draw transient (debe ser eliminada en recálculo)
INSERT INTO public.performance (draw_id, projection_id, hits_count, has_sb)
VALUES (
    '22222222-2222-2222-2222-222222222222'::uuid,
    '33333333-3333-3333-3333-333333333333'::uuid,
    5,
    TRUE
);

-- Entradas en la cola: Admin corrige el sorteo con números distintos al Scraper
INSERT INTO public.manual_verification_queue
    (id, run_id, draw_date, numbers, superbalota, type, entry_source, is_verified, is_conflict)
VALUES (
    'b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2'::uuid,
    gen_random_uuid(),
    '2099-04-01',
    ARRAY[3, 7, 11, 22, 33],
    5,
    'baloto',
    'scraper',
    FALSE,
    FALSE
);

INSERT INTO public.manual_verification_queue
    (id, run_id, draw_date, numbers, superbalota, type, entry_source, is_verified, is_conflict)
VALUES (
    'c3c3c3c3-c3c3-c3c3-c3c3-c3c3c3c3c3c3'::uuid,
    gen_random_uuid(),
    '2099-04-01',
    ARRAY[3, 7, 11, 22, 33],
    5,
    'baloto',
    'admin',
    FALSE,
    FALSE
);

-- Invocar la función que debe ejecutar el recálculo atómico
DO $$ BEGIN PERFORM public.fn_verify_and_promote_draw('2099-04-01'::date, 'baloto'); END $$;

-- ---------------------------------------------------------------------------
-- ASSERTION 1: Debe existir un registro de backup forense en system_logs
-- con level='audit' y metadata JSONB con el estado previo de performance
-- Estado RED: FALLA — el stub no inserta en system_logs. El backup forense no
--             existe; la información del draw transient se perdería en el recálculo.
-- Razon: SPEC §4.3 §4 exige que ANTES de borrar performance, se inserte en
--        system_logs un snapshot del estado previo (metadata = JSONB_AGG del
--        estado anterior). Sin este backup, cualquier error posterior hace
--        irrecuperable el historial de scores calculados.
-- Criterio de paso GREEN: COUNT >= 1 en system_logs con level='audit' para la
--        fecha/tipo del recálculo, con metadata JSONB no nulo
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer >= 1
        FROM public.system_logs
        WHERE level = 'audit'
          AND message ILIKE '%2099-04-01%'
          AND metadata IS NOT NULL
    ),
    'ATOMICITY RED 18.4: debe existir backup forense en system_logs (level=audit) ANTES del recálculo (SPEC §4.3 §4)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 2: Los registros de performance del draw anterior (transient)
-- deben haber sido eliminados tras el recálculo exitoso
-- Estado RED: FALLA — el stub no ejecuta DELETE en performance. El registro
--             insertado en el SETUP sigue existiendo; COUNT = 1, no 0.
-- Razon: ADR-04 define el recálculo atómico: eliminar performance del draw anterior
--        garantiza que el nuevo draw promovido sea calculado desde cero sin
--        contaminación de scores previos. Sin este DELETE, la tabla performance
--        tendría dobles registros para el mismo draw_date/type.
-- Criterio de paso GREEN: COUNT = 0 en performance para el draw_id anterior
-- ---------------------------------------------------------------------------
SELECT is(
    (
        SELECT COUNT(*)::integer
        FROM public.performance
        WHERE draw_id = '22222222-2222-2222-2222-222222222222'::uuid
    ),
    0,
    'ATOMICITY RED 18.4: performance del draw transient anterior debe eliminarse en recálculo atómico (ADR-04)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 3: Las proyecciones del draw anterior deben resetearse a status='pending'
-- para ser recalculadas por el siguiente ciclo del Job de Scoring
-- Estado RED: FALLA — el stub no actualiza projections.status. La proyección
--             insertada sigue en 'calculated'; la condición status='pending' retorna 0.
-- Razon: SPEC §4.3 §4 exige reset de projections.status='pending' como parte del
--        recálculo atómico. Sin este reset, las proyecciones quedan en 'calculated'
--        pero con un draw_id inválido (el transient fue reemplazado). El Engine
--        Python nunca recalcularía los aciertos contra el nuevo sorteo final.
-- Criterio de paso GREEN: la proyección del draw anterior tiene status='pending'
-- ---------------------------------------------------------------------------
SELECT is(
    (
        SELECT status
        FROM public.projections
        WHERE id = '33333333-3333-3333-3333-333333333333'::uuid
    ),
    'pending',
    'ATOMICITY RED 18.4: projections deben resetearse a pending tras recálculo atómico (SPEC §4.3 §4)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 4: El nuevo draw debe aparecer en draws con status='final'
-- (la promoción ocurre como última etapa del recálculo atómico)
-- Estado RED: FALLA — el stub no actualiza el draw existente ni inserta uno nuevo.
--             El draw '22222222...' permanece como 'transient'; no hay 'final'.
-- Razon: El recálculo atómico culmina con la promoción del draw a status='final'.
--        Si esta etapa falla y el sistema hace rollback, el draw transient debe
--        permanecer (reversibilidad). Si tiene éxito, el draw queda como 'final'.
-- Criterio de paso GREEN: existe al menos un draw 'final' para la fecha/tipo
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer >= 1
        FROM public.draws
        WHERE draw_date = '2099-04-01'
          AND type = 'baloto'
          AND status = 'final'
    ),
    'ATOMICITY RED 18.4: debe existir un draw con status=final para la fecha/tipo tras recálculo exitoso (SPEC §4.3 §4)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 5: El estado del sistema debe ser consistente: si el draw es 'final',
-- entonces performance del draw transient debe ser 0 (no puede haber partial state)
-- Estado RED: FALLA — el stub no ejecuta ninguna lógica. El draw permanece
--             'transient' y performance sigue existiendo. La condición compuesta
--             es: draw final (FALSE) AND performance = 0 (FALSE) = FALSE.
-- Razon: La invariante de atomicidad garantiza que el sistema nunca quede en
--        estado partial: (draw=final Y performance del anterior > 0) sería
--        inconsistente. La transacción atómica garantiza que o todo ocurre
--        o nada ocurre. Este assertion detecta estados intermedios ilegales.
-- Criterio de paso GREEN: o bien (draw=final Y perf_anterior=0) o bien (draw=transient Y perf_anterior>0)
--        Ambos son consistentes. Solo el estado parcial falla.
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        -- Estado consistente A: promoción exitosa (draw final + performance limpio)
        (
            SELECT COUNT(*)::integer >= 1
            FROM public.draws
            WHERE draw_date = '2099-04-01'
              AND type = 'baloto'
              AND status = 'final'
        )
        AND
        (
            SELECT COUNT(*)::integer = 0
            FROM public.performance
            WHERE draw_id = '22222222-2222-2222-2222-222222222222'::uuid
        )
    )
    OR
    (
        -- Estado consistente B: rollback total (draw transient + performance intacto)
        (
            SELECT COUNT(*)::integer >= 1
            FROM public.draws
            WHERE draw_date = '2099-04-01'
              AND type = 'baloto'
              AND status = 'transient'
        )
        AND
        (
            SELECT COUNT(*)::integer >= 1
            FROM public.performance
            WHERE draw_id = '22222222-2222-2222-2222-222222222222'::uuid
        )
        AND
        (
            -- Y además el backup forense existe (fue el primer paso antes del rollback)
            SELECT COUNT(*)::integer >= 1
            FROM public.system_logs
            WHERE level = 'audit'
        )
    ),
    'ATOMICITY RED 18.4: el sistema debe estar en estado consistente (o todo exito o rollback total — sin estados parciales)'
);

SELECT * FROM finish();

-- CLEANUP: ROLLBACK garantiza aislamiento total.
ROLLBACK;

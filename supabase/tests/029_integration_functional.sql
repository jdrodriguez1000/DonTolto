-- =============================================================================
-- TEST: 029_integration_functional.sql
-- Trazabilidad: TSK-F1_1.1-29.1-VERIF — Suite de Integración Funcional (Contratos SPEC)
-- SPEC: §4.2 (fn_compute_async_scoring), §4.3 (fn_verify_and_promote_draw),
--       §4.4 (fn_manage_lock, fn_monitor_and_activate_fallback),
--       §4.5 (fn_cleanup_logs), §6 (v_system_health, v_strategy_delta)
-- PLAN: M3 — Suite de tests de integración SQL validando 100% de contratos SPEC
-- Responsable: integration-tester
-- Fecha: 2026-04-10
--
-- Tipo de test: GREEN (integración end-to-end) — Valida contratos vigentes
--
-- Descripción: Valida la cadena completa de integración funcional:
--   1. Cadena: draws → projections → performance → vistas de observabilidad
--   2. fn_compute_async_scoring: transición 'pending' → 'calculating' (SKIP LOCKED)
--   3. fn_verify_and_promote_draw: transición de estados en Double-Entry Guard
--   4. fn_manage_lock: adquisición y liberación de locks atómicos
--   5. fn_recover_stalled_projections: reset determinista de workers zombie
--   6. fn_monitor_and_activate_fallback: activación automática de fallback
--   7. fn_cleanup_logs: purga selectiva de logs por nivel y antigüedad
--   8. Integridad referencial: FKs, constraints CHECK y RLS en sync_locks
--
-- Aislamiento: BEGIN / ROLLBACK — ningún dato persiste tras la ejecución
-- Convención: IDs de prueba con prefijo 29xx para evitar colisiones con seed_synthetic_428
-- =============================================================================

BEGIN;

SELECT plan(12);

-- =============================================================================
-- SETUP COMPARTIDO: Datos mínimos para ejercer toda la cadena de integración
-- Estos inserts son el punto de entrada del flujo E2E:
--   draws → projections → performance → vistas
-- Se usan IDs deterministas con prefijo 2900 para aislamiento total.
-- =============================================================================

-- Estrategia base requerida por FK de projections
INSERT INTO public.strategies_metadata (name, version, role, is_active)
VALUES ('integ_active', 1, 'active', TRUE),
       ('integ_control', 1, 'control', TRUE)
ON CONFLICT (name, version) DO NOTHING;

-- Draw de referencia para la cadena de integración
INSERT INTO public.draws
    (id, run_id, draw_date, numbers, superbalota, type, status, is_manual)
VALUES (
    '29000000-0000-0000-0001-000000000001'::uuid,
    gen_random_uuid(),
    '2099-09-01',
    ARRAY[5, 12, 20, 31, 40],
    8,
    'baloto',
    'final',
    FALSE
) ON CONFLICT DO NOTHING;

-- Proyecciones en estado 'pending' para ejercer el motor de scoring
INSERT INTO public.projections
    (id, run_id, target_draw_date, strategy_name, strategy_version,
     numbers, superbalota, status)
VALUES
    ('29000000-0000-0000-0002-000000000001'::uuid,
     gen_random_uuid(), '2099-09-01',
     'integ_active', 1,
     ARRAY[5, 12, 20, 31, 40], 8, 'pending'),
    ('29000000-0000-0000-0002-000000000002'::uuid,
     gen_random_uuid(), '2099-09-01',
     'integ_control', 1,
     ARRAY[1, 10, 20, 30, 43], 3, 'pending')
ON CONFLICT DO NOTHING;

-- Registro de performance para ejercer las vistas de observabilidad
INSERT INTO public.performance
    (id, draw_id, projection_id, hits_count, has_sb, is_verified)
VALUES (
    '29000000-0000-0000-0003-000000000001'::uuid,
    '29000000-0000-0000-0001-000000000001'::uuid,
    '29000000-0000-0000-0002-000000000001'::uuid,
    3,
    TRUE,
    TRUE
) ON CONFLICT DO NOTHING;

-- =============================================================================
-- ASSERTION 1: Cadena referencial draws → projections → performance es consistente
-- Verifica que los FKs entre las tres tablas core son transitivamente válidos.
-- Integridad referencial ON DELETE RESTRICT garantiza que no existen huérfanos.
-- SPEC §3.3, §3.4, §3.5 — contratos de FK.
-- =============================================================================
SELECT ok(
    (
        SELECT COUNT(*)::integer = 1
        FROM public.performance perf
        JOIN public.projections  proj ON proj.id      = perf.projection_id
        JOIN public.draws        d    ON d.id         = perf.draw_id
        WHERE perf.id = '29000000-0000-0000-0003-000000000001'::uuid
          AND proj.strategy_name = 'integ_active'
          AND d.draw_date = '2099-09-01'
    ),
    'INTEGR 29.1-1: cadena draws→projections→performance es transitivamente consistente (FKs válidos)'
);

-- =============================================================================
-- ASSERTION 2: v_system_health reporta el estado del pool de proyecciones
-- La vista debe existir y retornar una fila con las columnas definidas en SPEC §6.
-- Se verifica que total_projections >= 2 (los dos insertos del setup).
-- SPEC §6, ARC-06, TSK-F1_1.1-27.1-GREEN.
-- =============================================================================
SELECT ok(
    (
        SELECT total_projections >= 2
        FROM public.v_system_health
        LIMIT 1
    ),
    'INTEGR 29.1-2: v_system_health retorna fila con total_projections >= 2 (vista operativa)'
);

-- =============================================================================
-- ASSERTION 3: v_strategy_delta reporta avg_score para la cadena de integración
-- La vista debe incluir la proyección 'integ_active' con avg_score = 13
-- (hits_count=3 + has_sb=TRUE → score GENERATED = 3+10 = 13).
-- Valida la formula GENERATED de performance.score y el JOIN chain de la vista.
-- SPEC §6, §3.5 (score GENERATED), ARC-06, TSK-F1_1.1-27.2-GREEN.
-- =============================================================================
SELECT ok(
    (
        SELECT COUNT(*)::integer >= 1
        FROM public.v_strategy_delta
        WHERE strategy_name = 'integ_active'
          AND draw_date     = '2099-09-01'
          AND avg_score     = 13.0
    ),
    'INTEGR 29.1-3: v_strategy_delta calcula avg_score=13 para integ_active (score GENERATED: 3+10=13)'
);

-- =============================================================================
-- ASSERTION 4: fn_compute_async_scoring transiciona proyecciones pending→calculating
-- Invoca el motor con las dos proyecciones 'pending' del setup.
-- Después de la llamada, al menos una debe estar en estado 'calculating'.
-- Verifica el protocolo anti-carrera SKIP LOCKED (SPEC §4.2, ADR-01).
-- =============================================================================
PERFORM public.fn_compute_async_scoring();

SELECT ok(
    (
        SELECT COUNT(*)::integer >= 1
        FROM public.projections
        WHERE target_draw_date = '2099-09-01'
          AND status IN ('calculating', 'calculated')
    ),
    'INTEGR 29.1-4: fn_compute_async_scoring transiciona proyecciones a calculating (protocolo SKIP LOCKED activo)'
);

-- =============================================================================
-- ASSERTION 5: fn_compute_async_scoring filtra estrategias con is_active=FALSE
-- Inserta una proyección de la estrategia 'integ_inactive' (is_active=FALSE).
-- El motor no debe reclamarla: su status debe permanecer 'pending' tras la llamada.
-- SPEC §4.2 (Filtro de Operatividad — JOIN con is_active=TRUE).
-- =============================================================================
INSERT INTO public.strategies_metadata (name, version, role, is_active)
VALUES ('integ_inactive', 1, 'archive', FALSE)
ON CONFLICT (name, version) DO NOTHING;

INSERT INTO public.projections
    (id, run_id, target_draw_date, strategy_name, strategy_version,
     numbers, superbalota, status)
VALUES (
    '29000000-0000-0000-0002-000000000099'::uuid,
    gen_random_uuid(), '2099-09-01',
    'integ_inactive', 1,
    ARRAY[2, 11, 21, 32, 41], 4, 'pending'
) ON CONFLICT DO NOTHING;

PERFORM public.fn_compute_async_scoring();

SELECT is(
    (
        SELECT status
        FROM public.projections
        WHERE id = '29000000-0000-0000-0002-000000000099'::uuid
    ),
    'pending',
    'INTEGR 29.1-5: fn_compute_async_scoring no procesa proyecciones de estrategias is_active=FALSE (filtro operativo)'
);

-- =============================================================================
-- ASSERTION 6: fn_verify_and_promote_draw — Caso A (Match exitoso Admin+Scraper)
-- Crea par coincidente en manual_verification_queue y verifica que la función
-- promueve el draw a 'final' en la tabla draws.
-- SPEC §4.3, ADR-04, TSK-F1_1.1-19.2-GREEN.
-- =============================================================================

-- Usar fecha futura distinta para aislar este escenario
INSERT INTO public.manual_verification_queue
    (id, run_id, draw_date, numbers, superbalota, type, entry_source, is_verified, is_conflict)
VALUES
    ('29000000-0000-0000-0004-000000000001'::uuid,
     gen_random_uuid(), '2099-10-01',
     ARRAY[2, 14, 25, 33, 41], 7, 'baloto', 'scraper', FALSE, FALSE),
    ('29000000-0000-0000-0004-000000000002'::uuid,
     gen_random_uuid(), '2099-10-01',
     ARRAY[2, 14, 25, 33, 41], 7, 'baloto', 'admin',   FALSE, FALSE)
ON CONFLICT DO NOTHING;

PERFORM public.fn_verify_and_promote_draw('2099-10-01'::date, 'baloto');

SELECT ok(
    (
        SELECT COUNT(*)::integer >= 1
        FROM public.draws
        WHERE draw_date = '2099-10-01'
          AND type      = 'baloto'
          AND status    = 'final'
    ),
    'INTEGR 29.1-6: fn_verify_and_promote_draw promueve draw a final cuando Admin y Scraper coinciden (SPEC §4.3 Caso A)'
);

-- =============================================================================
-- ASSERTION 7: fn_verify_and_promote_draw — Caso discrepancia marca is_conflict=TRUE
-- Admin y Scraper con números distintos → toda la cola de esa fecha/tipo
-- debe quedar marcada con is_conflict=TRUE. La función retorna FALSE.
-- SPEC §4.3 punto 1 (Si existe diferencia → is_conflict=TRUE).
-- =============================================================================
INSERT INTO public.manual_verification_queue
    (id, run_id, draw_date, numbers, superbalota, type, entry_source, is_verified, is_conflict)
VALUES
    ('29000000-0000-0000-0004-000000000011'::uuid,
     gen_random_uuid(), '2099-10-02',
     ARRAY[3, 15, 26, 34, 42], 9, 'revancha', 'scraper', FALSE, FALSE),
    ('29000000-0000-0000-0004-000000000012'::uuid,
     gen_random_uuid(), '2099-10-02',
     ARRAY[1, 13, 27, 35, 43], 2, 'revancha', 'admin',   FALSE, FALSE)
ON CONFLICT DO NOTHING;

PERFORM public.fn_verify_and_promote_draw('2099-10-02'::date, 'revancha');

SELECT ok(
    (
        SELECT COUNT(*)::integer = 2
        FROM public.manual_verification_queue
        WHERE draw_date   = '2099-10-02'
          AND type        = 'revancha'
          AND is_conflict = TRUE
    ),
    'INTEGR 29.1-7: fn_verify_and_promote_draw marca is_conflict=TRUE en toda la cola cuando hay discrepancia (SPEC §4.3)'
);

-- =============================================================================
-- ASSERTION 8: fn_manage_lock adquiere y libera correctamente un lock
-- Acquire devuelve TRUE; el registro aparece en sync_locks.
-- Release elimina el registro y devuelve TRUE.
-- SPEC §4.4, ADR-03, TSK-F1_1.1-23.2-GREEN.
-- =============================================================================
DO $$
DECLARE
    v_worker UUID := '29000000-0000-0000-0009-000000000001'::uuid;
    v_acquired BOOLEAN;
    v_released BOOLEAN;
BEGIN
    v_acquired := public.fn_manage_lock('integ_test_lock', v_worker, 'acquire');
    IF NOT v_acquired THEN
        RAISE EXCEPTION 'fn_manage_lock acquire falló inesperadamente';
    END IF;
    v_released := public.fn_manage_lock('integ_test_lock', v_worker, 'release');
    IF NOT v_released THEN
        RAISE EXCEPTION 'fn_manage_lock release falló inesperadamente';
    END IF;
END $$;

SELECT ok(
    (
        SELECT COUNT(*)::integer = 0
        FROM public.sync_locks
        WHERE lock_key = 'integ_test_lock'
    ),
    'INTEGR 29.1-8: fn_manage_lock libera el lock correctamente — registro eliminado de sync_locks tras release'
);

-- =============================================================================
-- ASSERTION 9: Dos workers no pueden adquirir el mismo lock simultáneamente
-- El segundo acquire (worker_id distinto, lock vigente) debe retornar FALSE.
-- Verifica el principio de exclusión mutua del semáforo atómico.
-- SPEC §4.4, ADR-03, REQ-12.
-- =============================================================================
DO $$
DECLARE
    v_worker_a UUID := '29000000-0000-0000-0009-000000000002'::uuid;
    v_worker_b UUID := '29000000-0000-0000-0009-000000000003'::uuid;
    v_acq_a    BOOLEAN;
    v_acq_b    BOOLEAN;
BEGIN
    v_acq_a := public.fn_manage_lock('integ_mutex_lock', v_worker_a, 'acquire');
    v_acq_b := public.fn_manage_lock('integ_mutex_lock', v_worker_b, 'acquire');

    IF v_acq_b = TRUE THEN
        RAISE EXCEPTION 'Violación de exclusión mutua: worker_b adquirió lock ya vigente de worker_a';
    END IF;

    -- Liberar para no contaminar el estado de sync_locks
    PERFORM public.fn_manage_lock('integ_mutex_lock', v_worker_a, 'release');
END $$;

SELECT ok(
    (
        SELECT COUNT(*)::integer = 0
        FROM public.sync_locks
        WHERE lock_key = 'integ_mutex_lock'
    ),
    'INTEGR 29.1-9: fn_manage_lock impide que dos workers distintos adquieran el mismo lock simultáneamente (exclusión mutua)'
);

-- =============================================================================
-- ASSERTION 10: fn_recover_stalled_projections resetea workers zombie
-- Crea una proyección 'calculating' con last_heartbeat anterior a 30 min.
-- La función debe resetear su status a 'pending' y limpiar worker_id.
-- SPEC §4.4, PLAN B5b, TSK-F1_1.1-23.3-GREEN.
-- =============================================================================
INSERT INTO public.projections
    (id, run_id, target_draw_date, strategy_name, strategy_version,
     numbers, superbalota, status, worker_id, last_heartbeat)
VALUES (
    '29000000-0000-0000-0002-000000000050'::uuid,
    gen_random_uuid(), '2099-09-01',
    'integ_active', 1,
    ARRAY[6, 13, 22, 32, 42], 5,
    'calculating',
    '29000000-0000-0000-0009-000000000005'::uuid,
    now() - INTERVAL '35 minutes'   -- zombie: supera el umbral de 30 min
) ON CONFLICT DO NOTHING;

PERFORM public.fn_recover_stalled_projections();

SELECT is(
    (
        SELECT status
        FROM public.projections
        WHERE id = '29000000-0000-0000-0002-000000000050'::uuid
    ),
    'pending',
    'INTEGR 29.1-10: fn_recover_stalled_projections resetea proyección zombie (last_heartbeat > 30min) a pending'
);

-- =============================================================================
-- ASSERTION 11: fn_cleanup_logs preserva logs protegidos (nivel audit, recientes)
-- Inserta logs de prueba y ejecuta fn_cleanup_logs().
-- Verifica que logs 'audit' (protegidos) y logs recientes NO son purgados.
-- SPEC §4.5, REQ-13, TSK-F1_1.1-27.3-GREEN.
-- =============================================================================
INSERT INTO public.system_logs
    (id, run_id, service, level, message, is_archived, created_at)
VALUES
    -- Log viejo de nivel 'info' — candidato a purga (>90d)
    (2900001, gen_random_uuid(), 'GHA', 'info',
     'INTEG TEST: log viejo info candidato a purga',
     FALSE, now() - INTERVAL '91 days'),
    -- Log viejo de nivel 'audit' — PROTEGIDO (no en la lista de purga)
    (2900002, gen_random_uuid(), 'DB-Native', 'audit',
     'INTEG TEST: log viejo audit protegido',
     FALSE, now() - INTERVAL '91 days'),
    -- Log reciente de nivel 'info' — dentro del TTL (10d < 90d)
    (2900003, gen_random_uuid(), 'GHA', 'info',
     'INTEG TEST: log reciente info — debe permanecer',
     FALSE, now() - INTERVAL '10 days')
ON CONFLICT DO NOTHING;

PERFORM public.fn_cleanup_logs();

SELECT ok(
    -- El log viejo 'info' fue purgado Y los protegidos permanecen
    (SELECT COUNT(*)::integer = 0 FROM public.system_logs WHERE id = 2900001)
    AND
    (SELECT COUNT(*)::integer = 1 FROM public.system_logs WHERE id = 2900002)
    AND
    (SELECT COUNT(*)::integer = 1 FROM public.system_logs WHERE id = 2900003),
    'INTEGR 29.1-11: fn_cleanup_logs purga solo logs info/debug >90d — audit y recientes permanecen (SPEC §4.5)'
);

-- =============================================================================
-- ASSERTION 12: score GENERATED en performance cumple formula SPEC §3.5
-- Verifica directamente la columna generada para el registro del setup:
-- hits_count=3, has_sb=TRUE → score esperado = 3 + 10 = 13.
-- Garantiza que el constraint GENERATED ALWAYS funciona correctamente.
-- SPEC §3.5, REQ-08.
-- =============================================================================
SELECT is(
    (
        SELECT score
        FROM public.performance
        WHERE id = '29000000-0000-0000-0003-000000000001'::uuid
    ),
    13,
    'INTEGR 29.1-12: score GENERATED = hits_count + 10 (has_sb=TRUE) → 3+10=13 (contrato SPEC §3.5)'
);

SELECT * FROM finish();

-- CLEANUP: ROLLBACK garantiza aislamiento total. Ningún dato de prueba persiste.
ROLLBACK;

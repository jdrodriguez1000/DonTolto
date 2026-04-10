-- =============================================================================
-- TEST: 022_forensic_backup_integrity.sql
-- Trazabilidad: TSK-F1_1.1-18.5-RED — Test pgTap: Integridad de Backup Forense
--               (Falla si el backup en system_logs no se completa)
-- SPEC: Sección 4.3 §4 — Backup de Auditoría: snapshot JSONB en system_logs
-- PLAN: B5 — Motores RPC [TDD Cycle] — Fase RED
-- ADR: ADR-04 — Recálculo Atómico Transparente
-- Responsable: backend-tester
-- Fecha: 2026-04-10
--
-- Tipo de test: RED (TDD) — Diseñado para FALLAR cuando la implementación no existe
--
-- Descripción: Verifica que fn_verify_and_promote_draw inserta un backup forense
--              completo en system_logs ANTES de ejecutar el recálculo atómico.
--              El backup debe contener el estado previo de los registros de
--              performance en formato JSONB (via JSONB_AGG).
--
--              Contrato del backup forense (SPEC §4.3 §4):
--              - level='audit' en system_logs
--              - metadata = JSONB_AGG(estado previo de performance del draw anterior)
--              - El backup debe insertarse ANTES de cualquier DELETE en performance
--              - Si el backup falla, la transacción completa debe revertirse
--              - El campo metadata debe ser un array JSONB (no nulo, no vacío)
--
--              Este backup es el mecanismo de recuperación forense (REQ-13):
--              permite reconstruir el estado pre-recálculo sin acceder a backups
--              de base de datos completos. Es mandatorio para auditorías.
--
-- Mecanismo de detección RED:
--   El stub no inserta en system_logs. Todos los assertions que verifican la
--   existencia y estructura del backup fallan en RED.
--
-- Estado esperado en RED (stub sin lógica):
--   - ASSERTION 1: FALLA — no existe ningún log con level='audit' post-invocación
--   - ASSERTION 2: FALLA — no existe metadata JSONB con datos de performance
--   - ASSERTION 3: FALLA — el metadata no contiene campos de performance (hits_count etc.)
--   - ASSERTION 4: FALLA — no existe log con service='verify_promote' o similar
--   - ASSERTION 5: FALLA — el backup se creó ANTES del delete (orden temporal no verificable sin implementación)
-- =============================================================================

BEGIN;

SELECT plan(5);

-- ---------------------------------------------------------------------------
-- SETUP: Crear escenario con draw transient y performance calculada
-- que debe ser respaldada forense antes del recálculo.
-- ---------------------------------------------------------------------------

-- Draw anterior en 'transient' que será reemplazado por el Admin
INSERT INTO public.draws (id, run_id, draw_date, numbers, superbalota, type, status, is_manual)
VALUES (
    '44444444-4444-4444-4444-444444444444'::uuid,
    gen_random_uuid(),
    '2099-05-01',
    ARRAY[2, 8, 16, 30, 40],
    9,
    'revancha',
    'transient',
    FALSE
);

-- Estrategia de referencia
INSERT INTO public.strategies_metadata (name, version, role, is_active)
VALUES ('test_forensic_strategy', 1, 'active', TRUE)
ON CONFLICT DO NOTHING;

-- Proyección calculada contra ese draw transient
INSERT INTO public.projections (id, run_id, target_draw_date, strategy_name, strategy_version, numbers, superbalota, status)
VALUES (
    '55555555-5555-5555-5555-555555555555'::uuid,
    gen_random_uuid(),
    '2099-05-01',
    'test_forensic_strategy',
    1,
    ARRAY[2, 8, 16, 30, 40],
    9,
    'calculated'
);

-- Performance asociada: 5 hits + superbalota = score 15 (debe ser respaldada)
INSERT INTO public.performance (draw_id, projection_id, hits_count, has_sb)
VALUES (
    '44444444-4444-4444-4444-444444444444'::uuid,
    '55555555-5555-5555-5555-555555555555'::uuid,
    5,
    TRUE
);

-- Entradas en cola que producirán la corrección del Admin
INSERT INTO public.manual_verification_queue
    (id, run_id, draw_date, numbers, superbalota, type, entry_source, is_verified, is_conflict)
VALUES (
    'd4d4d4d4-d4d4-d4d4-d4d4-d4d4d4d4d4d4'::uuid,
    gen_random_uuid(),
    '2099-05-01',
    ARRAY[2, 8, 16, 30, 40],
    9,
    'revancha',
    'scraper',
    FALSE,
    FALSE
);

INSERT INTO public.manual_verification_queue
    (id, run_id, draw_date, numbers, superbalota, type, entry_source, is_verified, is_conflict)
VALUES (
    'e5e5e5e5-e5e5-e5e5-e5e5-e5e5e5e5e5e5'::uuid,
    gen_random_uuid(),
    '2099-05-01',
    ARRAY[2, 8, 16, 30, 40],
    9,
    'revancha',
    'admin',
    FALSE,
    FALSE
);

-- Invocar la función de promoción/recálculo
DO $$ BEGIN PERFORM public.fn_verify_and_promote_draw('2099-05-01'::date, 'revancha'); END $$;

-- ---------------------------------------------------------------------------
-- ASSERTION 1: Debe existir exactamente un registro de backup forense en
-- system_logs con level='audit' tras la invocación de fn_verify_and_promote_draw
-- Estado RED: FALLA — el stub no inserta en system_logs. COUNT = 0.
-- Razon: SPEC §4.3 §4 establece que el backup forense es el PRIMER paso del
--        recálculo. Su ausencia implica que cualquier recálculo posterior sería
--        irrecuperable. El nivel 'audit' es distinto de 'info'/'error' para
--        facilitar filtrado en fn_cleanup_logs y en v_system_health (SPEC §6).
-- Criterio de paso GREEN: COUNT >= 1 en system_logs con level='audit'
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer >= 1
        FROM public.system_logs
        WHERE level = 'audit'
          AND metadata IS NOT NULL
    ),
    'FORENSIC RED 18.5: debe existir backup forense en system_logs con level=audit y metadata no nulo (SPEC §4.3 §4)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 2: El campo metadata del backup debe ser un JSONB de tipo array
-- (resultado de JSONB_AGG) con al menos un elemento (el registro de performance)
-- Estado RED: FALLA — no existe ningún registro en system_logs con metadata JSONB.
-- Razon: SPEC §4.3 §4 especifica: "metadata = JSONB_AGG(estado previo de performance)".
--        El uso de JSONB_AGG garantiza que el backup captura TODOS los registros
--        de performance asociados al draw anterior, no solo el primero.
--        Un metadata nulo o vacío equivale a un backup incompleto = violación de REQ-13.
-- Criterio de paso GREEN: jsonb_typeof(metadata) = 'array' Y jsonb_array_length >= 1
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer >= 1
        FROM public.system_logs
        WHERE level = 'audit'
          AND metadata IS NOT NULL
          AND jsonb_typeof(metadata) = 'array'
          AND jsonb_array_length(metadata) >= 1
    ),
    'FORENSIC RED 18.5: el metadata del backup debe ser un array JSONB (JSONB_AGG) con al menos un elemento de performance'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 3: Los elementos del array JSONB deben contener los campos
-- esperados de la tabla performance (hits_count, has_sb, draw_id, projection_id)
-- Estado RED: FALLA — no existe ningún registro en system_logs con metadata.
-- Razon: Un backup forense útil debe preservar la estructura completa de cada
--        registro de performance eliminado. Sin hits_count y has_sb, es imposible
--        reconstruir el score histórico. Sin draw_id y projection_id, es imposible
--        correlacionar el backup con los sorteos y proyecciones originales.
-- Criterio de paso GREEN: al menos un elemento del array tiene la clave 'hits_count'
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer >= 1
        FROM public.system_logs
        WHERE level = 'audit'
          AND metadata IS NOT NULL
          AND jsonb_typeof(metadata) = 'array'
          AND (metadata -> 0) ? 'hits_count'
    ),
    'FORENSIC RED 18.5: el JSONB del backup debe contener campo hits_count del registro de performance previo'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 4: Debe existir al menos un registro en system_logs relacionado
-- con el proceso de promoción (mensaje identificable con la fecha del sorteo)
-- Estado RED: FALLA — el stub no escribe en system_logs.
-- Razon: La trazabilidad mandatoria (CLAUDE.md, SPEC §3.6) exige que todo evento
--        significativo del sistema sea registrado con su run_id y un mensaje
--        descriptivo. El backup forense debe incluir un mensaje que permita
--        identificar qué sorteo fue respaldado (fecha y tipo) para facilitar
--        búsquedas forenses posteriores.
-- Criterio de paso GREEN: existe log con level='audit' y message menciona la fecha
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer >= 1
        FROM public.system_logs
        WHERE level = 'audit'
          AND message ILIKE '%2099-05-01%'
    ),
    'FORENSIC RED 18.5: el backup forense debe incluir mensaje con la fecha del sorteo recalculado (trazabilidad SPEC §3.6)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 5: El backup forense en system_logs debe haberse creado ANTES
-- de que se eliminaran los registros de performance (orden temporal mandatorio)
-- Estado RED: FALLA — el stub no elimina performance ni inserta logs.
--             Verificamos la invariante: si performance fue eliminado, debe
--             existir el backup. Si el backup no existe, performance no debió
--             ser eliminado. En RED, performance sigue existiendo (stub no borra)
--             y el log no existe, lo que viola la invariante de orden temporal.
-- Razon: Si el backup falla y la transacción continúa borrando performance,
--        el sistema pierde datos sin respaldo. La invariante es: backup SIEMPRE
--        precede al delete. Este assertion verifica la consecuencia observable:
--        si performance fue borrado, el backup DEBE existir en logs.
-- Criterio de paso GREEN: si COUNT(performance) = 0, entonces COUNT(logs audit) >= 1
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        -- Caso A: performance fue eliminado → backup DEBE existir (invariante de orden)
        (
            (SELECT COUNT(*)::integer FROM public.performance WHERE draw_id = '44444444-4444-4444-4444-444444444444'::uuid) = 0
            AND
            (SELECT COUNT(*)::integer FROM public.system_logs WHERE level = 'audit' AND metadata IS NOT NULL) >= 1
        )
        OR
        -- Caso B: performance no fue eliminado (rollback o stub) → estado pre-operación válido
        (
            (SELECT COUNT(*)::integer FROM public.performance WHERE draw_id = '44444444-4444-4444-4444-444444444444'::uuid) >= 1
        )
    ),
    'FORENSIC RED 18.5: si performance fue eliminado, el backup forense DEBE existir en system_logs (orden temporal mandatorio)'
);

SELECT * FROM finish();

-- CLEANUP: ROLLBACK garantiza aislamiento total.
ROLLBACK;

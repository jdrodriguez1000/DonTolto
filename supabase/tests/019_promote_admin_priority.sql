-- =============================================================================
-- TEST: 019_promote_admin_priority.sql
-- Trazabilidad: TSK-F1_1.1-18.2-RED — Test pgTap: Resolución de conflictos de
--               promoción (Admin > Scraper)
-- SPEC: Sección 4.3 — fn_verify_and_promote_draw (Double-Entry)
-- PLAN: B5 — Motores RPC [TDD Cycle] — Fase RED
-- ADR: ADR-04 — Recálculo Atómico Transparente
-- Responsable: backend-tester
-- Fecha: 2026-04-10
--
-- Tipo de test: RED (TDD) — Diseñado para FALLAR cuando la implementación no existe
--
-- Descripción: Verifica que fn_verify_and_promote_draw respeta la jerarquía de
--              autoridad Admin > Scraper. Cuando existen dos entradas para la misma
--              fecha/tipo (una de 'scraper' y una de 'admin') con los mismos números,
--              la función debe promover el sorteo a la tabla draws usando los datos
--              del registro Admin (ORDER BY created_at DESC LIMIT 1 prioriza Admin).
--
--              Contrato crítico (SPEC §4.3):
--              - scraper_entry vs admin_entry se comparan por (draw_date, type)
--              - Admin tiene prioridad: ORDER BY created_at DESC LIMIT 1
--              - Si coinciden: promueve a draws con status='final', is_manual=TRUE
--              - Un Scraper nunca puede sobrescribir la decisión de un Admin
--
-- Mecanismo de detección RED:
--   El stub de fn_verify_and_promote_draw solo hace RAISE NOTICE y retorna FALSE.
--   Los tests verifican que draws tiene el registro promovido y que los registros
--   de cola están marcados como is_verified=TRUE, lo cual el stub no implementa.
--
-- Estado esperado en RED (stub sin lógica):
--   - ASSERTION 1: FALLA — el stub retorna FALSE, no TRUE (match exitoso esperado)
--   - ASSERTION 2: FALLA — el stub no inserta en draws; COUNT en draws = 0
--   - ASSERTION 3: FALLA — el stub no marca registros como is_verified=TRUE en cola
--   - ASSERTION 4: FALLA — draws no tiene el registro con is_manual=TRUE
--   - ASSERTION 5: FALLA — draws no tiene el registro con status='final'
--
-- Cuando pase a GREEN (implementación real de fn_verify_and_promote_draw):
--   - El sorteo con datos del Admin debe aparecer en draws con final/is_manual=TRUE
--   - Los registros de la cola deben marcarse como is_verified=TRUE
-- =============================================================================

BEGIN;

SELECT plan(5);

-- ---------------------------------------------------------------------------
-- SETUP: Insertar par de entradas (scraper + admin) con los mismos números
-- para la misma fecha y tipo. Admin fue insertado después (created_at más reciente).
-- ---------------------------------------------------------------------------

-- Entrada del Scraper (primera en llegar)
INSERT INTO public.manual_verification_queue
    (id, run_id, draw_date, numbers, superbalota, type, entry_source, is_verified, is_conflict)
VALUES (
    'cccccccc-cccc-cccc-cccc-cccccccccccc'::uuid,
    gen_random_uuid(),
    '2099-02-01',
    ARRAY[5, 10, 15, 20, 25],
    12,
    'baloto',
    'scraper',
    FALSE,
    FALSE
);

-- Entrada del Admin (llega después — tiene prioridad por ORDER BY created_at DESC)
-- Mismos números que el Scraper: debe provocar match exitoso y promoción
INSERT INTO public.manual_verification_queue
    (id, run_id, draw_date, numbers, superbalota, type, entry_source, is_verified, is_conflict)
VALUES (
    'dddddddd-dddd-dddd-dddd-dddddddddddd'::uuid,
    gen_random_uuid(),
    '2099-02-01',
    ARRAY[5, 10, 15, 20, 25],
    12,
    'baloto',
    'admin',
    FALSE,
    FALSE
);

-- ---------------------------------------------------------------------------
-- ASSERTION 1: fn_verify_and_promote_draw debe retornar TRUE cuando hay match exitoso
-- Estado RED: FALLA — el stub siempre retorna FALSE (RETURN FALSE en el stub).
-- Razon: SPEC §4.3 define el valor de retorno TRUE como señal de promoción exitosa.
--        El llamador (pg_cron / Edge Function) usa este booleano para decidir si
--        el sorteo fue promovido y si debe disparar el ciclo de scoring posterior.
--        Un FALSE del stub hace imposible la integración con los sistemas aguas abajo.
-- Criterio de paso GREEN: la función retorna TRUE cuando scraper y admin coinciden
-- ---------------------------------------------------------------------------
SELECT is(
    public.fn_verify_and_promote_draw('2099-02-01'::date, 'baloto'),
    TRUE,
    'PROMOTE RED 18.2: fn_verify_and_promote_draw debe retornar TRUE cuando Admin y Scraper coinciden (SPEC §4.3)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 2: Después de la promoción, debe existir un registro en draws
-- para la fecha y tipo del sorteo promovido
-- Estado RED: FALLA — el stub no inserta en draws; la tabla queda vacía para
--             la fecha '2099-02-01'. COUNT = 0, la condición COUNT >= 1 es FALSE.
-- Razon: La promoción es el efecto secundario observable más crítico de la función.
--        Sin inserción en draws, el sorteo no existe oficialmente en el sistema
--        y el Engine Python no puede calcular aciertos (no hay draw_id válido).
-- Criterio de paso GREEN: COUNT >= 1 en draws para la fecha/tipo especificados
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer >= 1
        FROM public.draws
        WHERE draw_date = '2099-02-01'
          AND type = 'baloto'
    ),
    'PROMOTE RED 18.2: fn_verify_and_promote_draw debe insertar el sorteo promovido en la tabla draws (SPEC §4.3)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 3: Los registros en manual_verification_queue para esa fecha/tipo
-- deben estar marcados como is_verified=TRUE tras la promoción
-- Estado RED: FALLA — el stub no actualiza is_verified. Ambos registros de la
--             cola permanecen con is_verified=FALSE. COUNT de is_verified=TRUE = 0.
-- Razon: SPEC §4.3 exige que los registros sobrantes de la cola sean marcados
--        como is_verified=TRUE para limpieza posterior por fn_cleanup_logs.
--        Sin esta marcación, la cola acumula basura y los jobs de limpieza
--        no pueden distinguir registros procesados de pendientes.
-- Criterio de paso GREEN: COUNT de registros is_verified=TRUE = 2 (ambas entradas)
-- ---------------------------------------------------------------------------
SELECT is(
    (
        SELECT COUNT(*)::integer
        FROM public.manual_verification_queue
        WHERE draw_date = '2099-02-01'
          AND type = 'baloto'
          AND is_verified = TRUE
    ),
    2,
    'PROMOTE RED 18.2: los registros de la cola deben marcarse is_verified=TRUE tras promoción exitosa (SPEC §4.3)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 4: El registro promovido en draws debe tener is_manual=TRUE
-- Estado RED: FALLA — el stub no inserta en draws, por lo que no existe ningún
--             registro con is_manual=TRUE para la fecha '2099-02-01'.
-- Razon: SPEC §4.3 es explícita: cuando se promueve via Double-Entry (Admin+Scraper),
--        el campo is_manual=TRUE identifica el origen del registro para trazabilidad
--        y para diferenciar registros del Scraper autónomo (is_manual=FALSE).
--        Esta distinción es crítica para el Dashboard y los reportes de calidad.
-- Criterio de paso GREEN: el registro en draws tiene is_manual=TRUE
-- ---------------------------------------------------------------------------
SELECT ok(
    COALESCE(
        (
            SELECT is_manual
            FROM public.draws
            WHERE draw_date = '2099-02-01'
              AND type = 'baloto'
            LIMIT 1
        ),
        FALSE
    ),
    'PROMOTE RED 18.2: el registro promovido en draws debe tener is_manual=TRUE (trazabilidad Double-Entry SPEC §4.3)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 5: El registro promovido en draws debe tener status='final'
-- Estado RED: FALLA — el stub no inserta en draws, por lo que la consulta
--             retorna NULL; COALESCE convierte NULL en '' que != 'final'.
-- Razon: SPEC §4.3 define que una promoción exitosa via Double-Entry Admin+Scraper
--        resulta en status='final' (verificado). status='transient' se reserva
--        para el Fallback de 24h (solo Scraper, sin confirmación Admin).
--        El status='final' habilita el Engine Python para calcular proyecciones
--        contra ese draw_id sin riesgo de scoring sobre un sorteo provisional.
-- Criterio de paso GREEN: el registro en draws tiene status='final'
-- ---------------------------------------------------------------------------
SELECT is(
    COALESCE(
        (
            SELECT status
            FROM public.draws
            WHERE draw_date = '2099-02-01'
              AND type = 'baloto'
            LIMIT 1
        ),
        'none'
    ),
    'final',
    'PROMOTE RED 18.2: el sorteo promovido debe tener status=final en draws (no transient — SPEC §4.3)'
);

SELECT * FROM finish();

-- CLEANUP: ROLLBACK garantiza aislamiento total. Ningún dato persiste.
ROLLBACK;

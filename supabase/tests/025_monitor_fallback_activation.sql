-- =============================================================================
-- TEST: 025_monitor_fallback_activation.sql
-- Trazabilidad: TSK-F1_1.1-22.2-RED — Test pgTap: Deteccion y activacion de
--               modo fallback ante retrasos > 24h
-- SPEC: Seccion 4.4 — fn_monitor_and_activate_fallback
-- SPEC: Seccion 3.6 — system_configuration (debt_threshold_hours = 24)
-- PLAN: B5b — Automatizacion & Orquestacion [TDD Cycle] — Fase RED
-- ADR: ADR-02 — Configuracion Centralizada
-- REQ: REQ-09 — Monitor de Fallback
-- Responsable: backend-tester
-- Fecha: 2026-04-10
--
-- Tipo de test: RED (TDD) — Disenado para FALLAR cuando la implementacion no existe
--
-- Descripcion: Verifica que fn_monitor_and_activate_fallback detecta registros
--              huerfanos en manual_verification_queue cuyo created_at excede
--              el umbral de debt_threshold_hours (24h por defecto) y activa el
--              modo fallback promoviendo el draw a estado 'transient'.
--
--              Escenario de prueba:
--              1. system_configuration tiene debt_threshold_hours = 24h
--              2. Se inserta un registro en manual_verification_queue con
--                 created_at = ahora - 25 horas (supera el umbral de 24h)
--                 y entry_source = 'scraper', is_verified = FALSE
--              3. Se invoca fn_monitor_and_activate_fallback()
--              4. El sistema debe:
--                 a) Detectar el registro huerfano (> 24h sin verificacion)
--                 b) Invocar fn_verify_and_promote_draw forzando status='transient'
--                 c) Registrar en system_logs la activacion del fallback (nivel 'error')
--                 d) El registro en MVQ debe quedar con is_verified = TRUE
--                 e) El draw debe aparecer en draws con status = 'transient'
--
--              Contrato SPEC §4.4:
--              "Busca registros en manual_verification_queue con
--               created_at < now() - (SELECT debt_threshold_hours FROM system_configuration) * interval '1 hour'
--               y is_verified = false. Por cada hallazgo: invoca fn_verify_and_promote_draw
--               forzando status = 'transient'."
--
-- Mecanismo de deteccion RED:
--   La funcion fn_monitor_and_activate_fallback NO EXISTE aun. Los tests verifican:
--   a) La funcion existe y es invocable (espera FALLO en RED)
--   b) El draw huerfano >24h es promovido a draws con status='transient'
--   c) El registro en MVQ queda marcado is_verified=TRUE (consumido por fallback)
--   d) Se registra una entrada en system_logs (level='error') documentando el fallback
--   e) Registros con created_at < 24h (recientes) NO son procesados por el fallback
--
-- Estado esperado en RED (funcion inexistente):
--   - ASSERTION 1: FALLA — fn_monitor_and_activate_fallback no existe (has_function=false)
--   - ASSERTION 2: FALLA — funcion no existe; el draw huerfano no se promueve a 'transient'
--   - ASSERTION 3: FALLA — funcion no existe; MVQ no se marca como is_verified=TRUE
--   - ASSERTION 4: FALLA — funcion no existe; no se escribe log de activacion fallback
--   - ASSERTION 5: FALLA — funcion no existe; el registro reciente permanece sin procesar
--                          (este assertion paradojicamente puede pasar en RED por razon
--                          incorrecta — la condicion de no-procesamiento se cumple porque
--                          la funcion no hace nada; ASSERTION 2 es el discriminador clave)
-- =============================================================================

BEGIN;

SELECT plan(5);

-- ---------------------------------------------------------------------------
-- SETUP: Configurar system_configuration con umbral conocido (24h)
-- El ROLLBACK final restaura el estado original del Singleton.
-- ---------------------------------------------------------------------------
UPDATE public.system_configuration
SET debt_threshold_hours = 24
WHERE id = 1;

-- ---------------------------------------------------------------------------
-- SETUP: Registro HUERFANO en MVQ — supera el umbral de 24h
-- Solo tiene entry_source='scraper' (no existe par de Admin).
-- created_at manipulado a 25h en el pasado para superar el umbral.
-- ---------------------------------------------------------------------------
INSERT INTO public.manual_verification_queue
    (id, run_id, draw_date, numbers, superbalota, type, entry_source, is_verified, is_conflict, created_at)
VALUES (
    'c9c9c9c9-c9c9-c9c9-c9c9-c9c9c9c9c9c9'::uuid,
    gen_random_uuid(),
    '2099-08-01',
    ARRAY[5, 12, 18, 31, 42],
    9,
    'baloto',
    'scraper',
    FALSE,
    FALSE,
    now() - interval '25 hours'
);

-- ---------------------------------------------------------------------------
-- SETUP: Registro RECIENTE en MVQ — NO supera el umbral de 24h
-- Solo tiene entry_source='scraper'; created_at hace 2 horas (bien dentro del umbral).
-- La funcion NO debe procesarlo.
-- ---------------------------------------------------------------------------
INSERT INTO public.manual_verification_queue
    (id, run_id, draw_date, numbers, superbalota, type, entry_source, is_verified, is_conflict, created_at)
VALUES (
    'd0d0d0d0-d0d0-d0d0-d0d0-d0d0d0d0d0d0'::uuid,
    gen_random_uuid(),
    '2099-09-01',
    ARRAY[1, 7, 14, 25, 38],
    3,
    'baloto',
    'scraper',
    FALSE,
    FALSE,
    now() - interval '2 hours'
);

-- Invocar la funcion de monitoreo (no existe en RED — capturado por EXCEPTION)
DO $$
BEGIN
    PERFORM public.fn_monitor_and_activate_fallback();
EXCEPTION WHEN undefined_function THEN
    RAISE NOTICE 'RED expected: fn_monitor_and_activate_fallback no existe aun';
END $$;

-- ---------------------------------------------------------------------------
-- ASSERTION 1: La funcion fn_monitor_and_activate_fallback debe existir
-- Estado RED: FALLA — la funcion no ha sido creada aun. has_function() = false.
-- Razon: La existencia de la funcion es el prerequisito de toda la orquestacion
--        de fallback. SPEC §4.4 y PLAN B5b la definen como un componente critico
--        de resiliencia ejecutado por pg_cron cada hora. Sin esta funcion,
--        los sorteos huerfanos nunca serian promovidos automaticamente.
-- Criterio de paso GREEN: la funcion existe con firma: fn_monitor_and_activate_fallback()
-- ---------------------------------------------------------------------------
SELECT has_function(
    'public',
    'fn_monitor_and_activate_fallback',
    ARRAY[]::text[],
    'FALLBACK RED 22.2: fn_monitor_and_activate_fallback debe existir para activar modo fallback ante retrasos >24h'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 2: El draw huerfano (>24h en MVQ sin verificacion) debe aparecer
-- en la tabla draws con status='transient' tras invocar el monitor de fallback
-- Estado RED: FALLA — la funcion no existe. La promotcion no ocurre. El draw
--             '2099-08-01'/'baloto' no existe en draws (COUNT = 0).
-- Razon: SPEC §4.4 define que el fallback invoca fn_verify_and_promote_draw
--        forzando status='transient'. Este es el mecanismo de resolucion automatica
--        para sorteos que no recibieron verificacion manual en tiempo. Sin la
--        promocion a 'transient', el sistema quedaria bloqueado indefinidamente
--        esperando una entrada Admin que nunca llego.
-- Criterio de paso GREEN: existe un draw con draw_date='2099-08-01', type='baloto',
--        status='transient' en la tabla draws
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer >= 1
        FROM public.draws
        WHERE draw_date = '2099-08-01'::date
          AND type = 'baloto'
          AND status = 'transient'
    ),
    'FALLBACK RED 22.2: draw huerfano (>24h en MVQ) debe ser promovido a draws con status=transient (SPEC §4.4)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 3: El registro huerfano en MVQ debe estar marcado como is_verified=TRUE
-- (consumido por el proceso de fallback — no debe ser reprocesado en ciclos futuros)
-- Estado RED: FALLA — la funcion no existe. El registro c9c9... permanece con
--             is_verified=FALSE. COUNT = 0 para is_verified=TRUE.
-- Razon: SPEC §4.3 §2 define que los registros procesados en MVQ se marcan con
--        is_verified=TRUE para evitar doble procesamiento. Si el fallback no
--        marca el registro, el siguiente ciclo del pg_cron lo volveria a detectar
--        como huerfano e intentaria crear un segundo draw duplicado para la misma
--        fecha/tipo, violando el indice unico idx_draws_date_type.
-- Criterio de paso GREEN: el registro c9c9... tiene is_verified=TRUE en MVQ
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer = 1
        FROM public.manual_verification_queue
        WHERE id = 'c9c9c9c9-c9c9-c9c9-c9c9-c9c9c9c9c9c9'::uuid
          AND is_verified = TRUE
    ),
    'FALLBACK RED 22.2: registro huerfano en MVQ debe marcarse is_verified=TRUE tras activacion de fallback'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 4: Debe existir un registro en system_logs documentando la activacion
-- del modo fallback (level='error', service documentando el fallback activado)
-- Estado RED: FALLA — la funcion no existe. No se escribe ningun log. COUNT = 0.
-- Razon: SPEC §4.3 §3 define que si pasadas 24h solo existe un scraper entry
--        sin par Admin, se mueve a draws como 'transient' y se loguea 'error'.
--        La trazabilidad del fallback en system_logs es critica para la
--        observabilidad operativa: el Dashboard y las alertas dependen de estos
--        logs para notificar al Admin que un sorteo fue promovido automaticamente
--        sin verificacion manual, requiriendo atencion.
-- Criterio de paso GREEN: COUNT >= 1 en system_logs con level='error' y mensaje
--        que referencia la fecha '2099-08-01' o el mecanismo de fallback
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer >= 1
        FROM public.system_logs
        WHERE level = 'error'
          AND message ILIKE '%fallback%'
          AND message ILIKE '%2099-08-01%'
    ),
    'FALLBACK RED 22.2: debe registrarse log level=error en system_logs documentando activacion de fallback para draw 2099-08-01'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 5: El registro RECIENTE en MVQ (< 24h) NO debe haber sido procesado
-- por el monitor de fallback — debe permanecer con is_verified=FALSE
-- Estado RED: FALLA — la funcion no existe. El registro reciente d0d0... nunca
--             fue tocado por ninguna funcion. is_verified sigue siendo FALSE.
--             Este assertion puede pasar en RED por razon incorrecta (la funcion
--             no hace nada). ASSERTION 2 es el discriminador definitivo del RED:
--             si la funcion existiera pero procesara todo sin discriminar por
--             umbral, ASSERTION 5 fallaria y ASSERTION 2 pasaria — estado incorrecto.
-- Razon: La condicion de 24h es el limite de seguridad que protege al sistema
--        de activar fallback prematuramente. Un draw con 2h en MVQ todavia
--        esta dentro del plazo normal de verificacion manual del Admin.
-- Criterio de paso GREEN: el registro d0d0... tiene is_verified=FALSE (intacto)
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer = 1
        FROM public.manual_verification_queue
        WHERE id = 'd0d0d0d0-d0d0-d0d0-d0d0-d0d0d0d0d0d0'::uuid
          AND is_verified = FALSE
    ),
    'FALLBACK RED 22.2: registro reciente (<24h en MVQ) NO debe ser procesado por fallback — debe permanecer is_verified=FALSE'
);

SELECT * FROM finish();

-- CLEANUP: ROLLBACK garantiza aislamiento total. Nada persiste en la base de datos.
ROLLBACK;

-- =============================================================================
-- MIGRACIÓN: 20260410000008_block_5b.sql
-- Trazabilidad: Bloque 6 — TSK-F1_1.1-23.1 a 23.4-GREEN (Orquestación & Resiliencia)
-- Objetos:
--   ALTER TABLE projections ADD COLUMN worker_id UUID
--   ALTER TABLE projections ADD COLUMN last_heartbeat TIMESTAMPTZ
--   TABLE sync_locks                        — Control de concurrencia con TTL 60m
--   fn_manage_lock(TEXT, UUID, TEXT)         — Adquirir / liberar locks atómicos
--   fn_recover_stalled_projections()         — Reset determinista de workers zombie
--   fn_monitor_and_activate_fallback()       — Activación automática de fallback > 24h
-- SPEC: §3.7 (sync_locks), §4.4 (fn_manage_lock, fn_monitor_and_activate_fallback)
-- PLAN: B5b — Automatización & Orquestación
-- ADR: ADR-03 (Locking TTL 60 min), ADR-06 (RLS High-Performance SECURITY DEFINER)
-- REQ: REQ-09 (Monitor de Fallback), REQ-12 (Atomic Locking)
-- Fecha: 2026-04-10
-- Dependencia: 20260410000007_block_5a_refact.sql
-- Tests que valida: 024_recover_stalled_projections_heartbeat.sql (5 assertions)
--                   025_monitor_fallback_activation.sql (5 assertions)
-- =============================================================================

BEGIN;

-- =============================================================================
-- BLOQUE 1: ALTER TABLE projections — Columnas de concurrencia
-- Prerequisito para fn_recover_stalled_projections y el protocolo anti-carrera.
-- worker_id: UUID del worker que tiene el claim sobre el registro.
-- last_heartbeat: Marca de tiempo del último latido del worker activo.
-- Se utiliza ADD COLUMN IF NOT EXISTS para idempotencia segura en re-ejecuciones.
-- SPEC §3.4 Gap documentado en cert_block6_RED_20260410.md §2.3.
-- =============================================================================

-- Columna de claim: identifica qué worker posee el registro en estado 'calculating'.
ALTER TABLE public.projections
    ADD COLUMN IF NOT EXISTS worker_id UUID;

COMMENT ON COLUMN public.projections.worker_id IS
    'UUID del worker que posee el claim sobre este registro. NULL cuando status=pending o calculated. '
    'Limpiado por fn_recover_stalled_projections() si last_heartbeat supera el umbral zombie (30 min). '
    'TSK-F1_1.1-23.3-GREEN. PLAN B5b.';

-- Columna de latido: marca de tiempo del último heartbeat del worker activo.
ALTER TABLE public.projections
    ADD COLUMN IF NOT EXISTS last_heartbeat TIMESTAMPTZ;

COMMENT ON COLUMN public.projections.last_heartbeat IS
    'Marca de tiempo del último latido emitido por el worker activo. '
    'Si last_heartbeat < now() - interval ''30 min'' y status=''calculating'', '
    'el worker se considera zombie y fn_recover_stalled_projections() resetea el registro. '
    'TSK-F1_1.1-23.3-GREEN. PLAN B5b.';


-- =============================================================================
-- BLOQUE 2: TABLA sync_locks — Semáforo atómico con TTL de 60 minutos
-- Implementa el contrato ADR-03: locking basado en TTL para evitar condiciones
-- de carrera entre múltiples instancias del Motor Python (GHA).
-- lock_key es PK: solo puede existir un lock por nombre de proceso.
-- expires_at se calcula siempre como acquired_at + 60 minutos.
-- worker_id es UUID (no TEXT) para consistencia de tipos con projections.
-- metadata JSONB permite añadir contexto operativo sin alterar el esquema.
-- SPEC §3.7, ADR-03, REQ-12.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.sync_locks (
    lock_key    VARCHAR(100) NOT NULL,
    run_id      UUID         NOT NULL,
    acquired_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    expires_at  TIMESTAMPTZ  NOT NULL
                GENERATED ALWAYS AS (acquired_at + INTERVAL '60 minutes') STORED,
    worker_id   UUID         NOT NULL,
    metadata    JSONB,

    CONSTRAINT pk_sync_locks PRIMARY KEY (lock_key)
);

COMMENT ON TABLE public.sync_locks IS
    'Semáforo atómico para control de concurrencia entre instancias del Motor Python (GHA). '
    'Cada proceso adquiere un lock por su nombre (lock_key) antes de ejecutar. '
    'TTL de 60 minutos garantizado mediante columna GENERATED expires_at. '
    'Un job de pg_cron elimina locks expirados cada 5 minutos. '
    'ADR-03, REQ-12, TSK-F1_1.1-23.1-GREEN.';

COMMENT ON COLUMN public.sync_locks.lock_key IS
    'Nombre del proceso que posee el lock (ej: ''scoring'', ''scraper''). PK — unicidad garantizada.';

COMMENT ON COLUMN public.sync_locks.run_id IS
    'UUID de la ejecución (run_id GHA) que adquirió el lock. Trazabilidad con system_logs.';

COMMENT ON COLUMN public.sync_locks.acquired_at IS
    'Timestamp de adquisición del lock. Base de cálculo para expires_at (TTL 60 min).';

COMMENT ON COLUMN public.sync_locks.expires_at IS
    'TTL absoluto del lock: acquired_at + 60 minutos. GENERATED ALWAYS garantiza consistencia. '
    'Cuando expires_at < now(), el lock se considera expirado y puede ser sobreescrito.';

COMMENT ON COLUMN public.sync_locks.worker_id IS
    'UUID del worker que posee el lock. Validado en fn_manage_lock para garantizar que '
    'solo el propietario puede liberar el lock (modo ''release'').';

COMMENT ON COLUMN public.sync_locks.metadata IS
    'Contexto operativo opcional en formato JSONB (ej: {"gha_run": "123", "branch": "main"}).';

-- Índice para consultas de expiración usadas por el job de limpieza pg_cron.
CREATE INDEX IF NOT EXISTS idx_sync_locks_expires_at
    ON public.sync_locks (expires_at);

COMMENT ON INDEX public.idx_sync_locks_expires_at IS
    'Optimiza el DELETE periódico de locks expirados ejecutado por el job pg_cron de limpieza. '
    'TSK-F1_1.1-23.1-GREEN.';

-- RLS: deny-by-default obligatorio (db-management skill: Protocolo de Seguridad RLS).
ALTER TABLE public.sync_locks ENABLE ROW LEVEL SECURITY;

-- Solo service_role puede operar locks (el Motor Python usa service_role).
CREATE POLICY "sync_locks_service_all" ON public.sync_locks
    FOR ALL
    TO service_role
    USING (TRUE)
    WITH CHECK (TRUE);

COMMENT ON POLICY "sync_locks_service_all" ON public.sync_locks IS
    'El service_role (Motor Python GHA) es el único actor autorizado para adquirir, '
    'mantener y liberar locks. web_anon y authenticated no tienen acceso. '
    'ADR-03, TSK-F1_1.1-23.1-GREEN.';


-- =============================================================================
-- BLOQUE 3: FUNCIÓN fn_manage_lock — Adquirir y liberar locks atómicos
-- Contrato de la SPEC §4.4 y PLAN B5b:
--   Modo 'acquire':
--     - Inserta el lock si no existe o si el lock existente ha expirado.
--     - Retorna TRUE si adquirió el lock con éxito.
--     - Retorna FALSE si existe un lock vigente de otro worker.
--     - Atómica mediante INSERT ... ON CONFLICT DO UPDATE.
--   Modo 'release':
--     - Elimina el lock identificado por (lock_key, worker_id).
--     - Solo el propietario puede liberar su propio lock.
--     - Si no existe el lock o el worker_id no coincide, no hace nada.
-- ADR-03, ADR-06, REQ-12, TSK-F1_1.1-23.2-GREEN.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_manage_lock(
    p_lock_key  TEXT,
    p_worker_id UUID,
    p_mode      TEXT  -- 'acquire' | 'release'
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = extensions, public
AS $$
DECLARE
    v_existing_worker UUID;
    v_existing_expires TIMESTAMPTZ;
BEGIN
    -- Validar parámetro de modo
    IF p_mode NOT IN ('acquire', 'release') THEN
        RAISE EXCEPTION 'fn_manage_lock: modo inválido "%". Use ''acquire'' o ''release''.', p_mode;
    END IF;

    -- -------------------------------------------------------------------------
    -- MODO RELEASE: eliminar el lock si el worker_id coincide con el propietario
    -- -------------------------------------------------------------------------
    IF p_mode = 'release' THEN
        DELETE FROM public.sync_locks
         WHERE lock_key  = p_lock_key
           AND worker_id = p_worker_id;

        -- Retorna TRUE si se eliminó el lock (rowcount > 0), FALSE si no existía
        RETURN FOUND;
    END IF;

    -- -------------------------------------------------------------------------
    -- MODO ACQUIRE: INSERT atómico con manejo de conflicto
    -- Estrategia ON CONFLICT:
    --   1. Si no existe lock → INSERT directo → adquiere.
    --   2. Si existe lock expirado (expires_at <= now()) → UPDATE atómico → adquiere.
    --   3. Si existe lock vigente de otro worker → no actualiza → retorna FALSE.
    -- La condición WHERE en el DO UPDATE garantiza atomicidad:
    -- el UPDATE solo ocurre si el lock está expirado (safe overwrite).
    -- -------------------------------------------------------------------------
    INSERT INTO public.sync_locks (lock_key, run_id, acquired_at, worker_id)
    VALUES (
        p_lock_key,
        gen_random_uuid(),   -- run_id interno del lock
        now(),
        p_worker_id
    )
    ON CONFLICT (lock_key) DO UPDATE
        SET run_id      = EXCLUDED.run_id,
            acquired_at = EXCLUDED.acquired_at,
            worker_id   = EXCLUDED.worker_id
      WHERE sync_locks.expires_at <= now();   -- solo sobreescribir si está expirado

    -- Verificar si la operación de INSERT/UPDATE tuvo efecto
    IF FOUND THEN
        RETURN TRUE;  -- Lock adquirido con éxito
    END IF;

    -- El INSERT no tuvo efecto: existe un lock vigente. Verificar si es nuestro propio
    -- worker (reentrada válida, ej: el mismo GHA runner renueva su lock).
    SELECT worker_id, expires_at
      INTO v_existing_worker, v_existing_expires
      FROM public.sync_locks
     WHERE lock_key = p_lock_key;

    IF v_existing_worker = p_worker_id THEN
        -- Mismo worker — renovar el lock (update de acquired_at para extender TTL)
        UPDATE public.sync_locks
           SET acquired_at = now(),
               run_id      = gen_random_uuid()
         WHERE lock_key  = p_lock_key
           AND worker_id = p_worker_id;
        RETURN TRUE;
    END IF;

    -- Lock vigente de otro worker — proceso bloqueado
    RETURN FALSE;

END;
$$;

COMMENT ON FUNCTION public.fn_manage_lock(TEXT, UUID, TEXT) IS
    'Gestión atómica de locks de concurrencia con TTL de 60 minutos. '
    'Modo ''acquire'': adquiere el lock si no existe o si está expirado (INSERT ON CONFLICT). '
    'Retorna TRUE si adquirió, FALSE si existe lock vigente de otro worker. '
    'Permite reentrada: el mismo worker puede renovar su propio lock. '
    'Modo ''release'': elimina el lock del propietario identificado por worker_id. '
    'SECURITY DEFINER con search_path fijo (ADR-06). '
    'ADR-03, REQ-12, SPEC §4.4, TSK-F1_1.1-23.2-GREEN.';

ALTER FUNCTION public.fn_manage_lock(TEXT, UUID, TEXT) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_manage_lock(TEXT, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_manage_lock(TEXT, UUID, TEXT) TO service_role;


-- =============================================================================
-- BLOQUE 4: FUNCIÓN fn_recover_stalled_projections — Reset de workers zombie
-- Contrato (PLAN B5b, cert_block6_RED_20260410.md §2.4):
--   - Resetea a 'pending' los registros en estado 'calculating' cuyo last_heartbeat
--     sea anterior a now() - interval '30 min' (workers zombie).
--   - Limpia worker_id a NULL en esos registros.
--   - NO toca registros con last_heartbeat reciente (< 30 min).
--   - Registra la operación en system_logs con nivel 'info'.
--   - Opera sobre projections mediante UPDATE atómico con WHERE preciso.
-- ADR-06, PLAN B5b, TSK-F1_1.1-23.3-GREEN.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_recover_stalled_projections()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = extensions, public
AS $$
DECLARE
    v_run_id       UUID := gen_random_uuid();
    v_reset_count  INTEGER;
BEGIN
    -- -------------------------------------------------------------------------
    -- Reseteo determinista: solo afecta registros que cumplan AMBAS condiciones:
    --   1. status = 'calculating' (el worker reclamó el registro)
    --   2. last_heartbeat < now() - 30 min (el worker dejó de latir — zombie)
    -- Registros con last_heartbeat reciente (< 30 min) o NULL no son tocados.
    -- El umbral de 30 minutos da margen a workers lentos antes de declararlos muertos.
    -- -------------------------------------------------------------------------
    UPDATE public.projections
       SET status          = 'pending',
           worker_id       = NULL,
           last_heartbeat  = NULL
     WHERE status          = 'calculating'
       AND last_heartbeat  < now() - INTERVAL '30 minutes';

    GET DIAGNOSTICS v_reset_count = ROW_COUNT;

    -- Registrar en system_logs solo si se encontraron zombies para limpiar
    IF v_reset_count > 0 THEN
        INSERT INTO public.system_logs (run_id, service, level, message, metadata)
        VALUES (
            v_run_id,
            'recovery',
            'info',
            'fn_recover_stalled_projections: ' || v_reset_count || ' registro(s) zombie reseteado(s) a pending',
            jsonb_build_object(
                'run_id',       v_run_id,
                'reset_count',  v_reset_count,
                'threshold_min', 30
            )
        );
    END IF;

END;
$$;

COMMENT ON FUNCTION public.fn_recover_stalled_projections() IS
    'Mecanismo anti-zombie: resetea a ''pending'' los registros de projections en estado '
    '''calculating'' cuyo last_heartbeat sea anterior a 30 minutos. '
    'Limpia worker_id y last_heartbeat de los registros reseteados. '
    'No modifica registros con heartbeat reciente (< 30 min) ni registros en otros estados. '
    'Registra un log level=info cuando encuentra y resetea zombies. '
    'Invocado por pg_cron periódicamente para garantizar resiliencia del pool de proyecciones. '
    'SECURITY DEFINER con search_path fijo. ADR-06. '
    'PLAN B5b, TSK-F1_1.1-23.3-GREEN.';

ALTER FUNCTION public.fn_recover_stalled_projections() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_recover_stalled_projections() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_recover_stalled_projections() TO service_role;


-- =============================================================================
-- BLOQUE 5: FUNCIÓN fn_monitor_and_activate_fallback — Monitor de Fallback > 24h
-- Contrato (SPEC §4.4, cert_block6_RED_20260410.md §3.3):
--   - Detecta registros en manual_verification_queue con created_at
--     anterior a now() - debt_threshold_hours (leído de system_configuration)
--     y con is_verified = FALSE.
--   - Para cada registro detectado:
--       a) Invoca fn_verify_and_promote_draw(draw_date, type) para forzar
--          la lógica de Fallback Ghost que produce status='transient'.
--       b) Marca is_verified = TRUE en el registro de MVQ.
--       c) Inserta un log level='error' en system_logs con referencia al draw_date.
--   - NO procesa registros recientes (created_at < umbral de 24h).
-- ADR-02, ADR-06, REQ-09, SPEC §4.4, TSK-F1_1.1-23.4-GREEN.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_monitor_and_activate_fallback()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = extensions, public
AS $$
DECLARE
    v_run_id         UUID := gen_random_uuid();
    v_debt_hours     INTEGER;
    v_orphan         RECORD;
    v_processed      INTEGER := 0;
    v_promoted       BOOLEAN;
BEGIN
    -- -------------------------------------------------------------------------
    -- PASO 1: Snapshot del umbral de deuda desde system_configuration (ADR-02).
    -- La captura al inicio garantiza que el umbral no cambie mid-flight.
    -- -------------------------------------------------------------------------
    SELECT debt_threshold_hours
      INTO v_debt_hours
      FROM public.system_configuration
     WHERE id = 1;

    -- Si no existe configuración (should never happen post-seed), abortar con log
    IF v_debt_hours IS NULL THEN
        INSERT INTO public.system_logs (run_id, service, level, message, metadata)
        VALUES (
            v_run_id,
            'fallback_monitor',
            'error',
            'fn_monitor_and_activate_fallback: system_configuration no disponible — fallback abortado',
            jsonb_build_object('run_id', v_run_id)
        );
        RETURN;
    END IF;

    -- -------------------------------------------------------------------------
    -- PASO 2: Detectar registros huérfanos en MVQ que superan el umbral de deuda.
    -- Condiciones de huérfano:
    --   a) created_at < now() - (debt_threshold_hours * interval '1 hour')
    --   b) is_verified = FALSE (no ha sido procesado ni por match ni por fallback anterior)
    -- Se itera por (draw_date, type) distintos para evitar procesar duplicados.
    -- -------------------------------------------------------------------------
    FOR v_orphan IN
        SELECT DISTINCT
               draw_date,
               type,
               MIN(id)   AS mvq_id       -- representante del grupo para logs
          FROM public.manual_verification_queue
         WHERE created_at  < now() - (v_debt_hours * INTERVAL '1 hour')
           AND is_verified = FALSE
         GROUP BY draw_date, type
    LOOP

        -- Invocar el motor de promoción: si solo existe entrada 'scraper' y el
        -- tiempo supera el umbral, fn_verify_and_promote_draw activa el Fallback Ghost
        -- y promueve el draw a status='transient' (lógica Caso B de la función).
        v_promoted := public.fn_verify_and_promote_draw(
            v_orphan.draw_date,
            v_orphan.type
        );

        -- -------------------------------------------------------------------------
        -- PASO 3: Registrar la activación del fallback en system_logs (REQ-09).
        -- level='error' indica que el sistema operó en modo degradado (sin Admin).
        -- El mensaje incluye draw_date para satisfacer la assertion del test 025.
        -- -------------------------------------------------------------------------
        INSERT INTO public.system_logs (run_id, service, level, message, metadata)
        VALUES (
            v_run_id,
            'fallback_monitor',
            'error',
            'Fallback activado: draw ' || v_orphan.draw_date::text ||
                ' (' || v_orphan.type || ') promovido automáticamente tras superar ' ||
                v_debt_hours || 'h sin verificación manual',
            jsonb_build_object(
                'run_id',          v_run_id,
                'draw_date',       v_orphan.draw_date,
                'type',            v_orphan.type,
                'debt_hours',      v_debt_hours,
                'promoted',        v_promoted,
                'mvq_id',          v_orphan.mvq_id
            )
        );

        v_processed := v_processed + 1;

    END LOOP;

    -- Log de resumen de la ejecución (solo si procesó algo)
    IF v_processed > 0 THEN
        INSERT INTO public.system_logs (run_id, service, level, message, metadata)
        VALUES (
            v_run_id,
            'fallback_monitor',
            'info',
            'fn_monitor_and_activate_fallback: ' || v_processed || ' sorteo(s) procesado(s) en modo fallback',
            jsonb_build_object(
                'run_id',        v_run_id,
                'processed',     v_processed,
                'debt_hours',    v_debt_hours
            )
        );
    END IF;

END;
$$;

COMMENT ON FUNCTION public.fn_monitor_and_activate_fallback() IS
    'Monitor de fallback automático: detecta entradas huérfanas en manual_verification_queue '
    'que superan el umbral debt_threshold_hours (leído de system_configuration) sin verificación. '
    'Por cada huérfano: invoca fn_verify_and_promote_draw() para promover a ''transient'', '
    'registra log level=''error'' en system_logs con referencia al draw_date. '
    'Invocado por pg_cron cada hora. No procesa registros recientes (< umbral). '
    'Snapshot de debt_threshold_hours al inicio para evitar inconsistencias mid-flight (ADR-02). '
    'SECURITY DEFINER con search_path fijo. ADR-06. '
    'ADR-02, REQ-09, SPEC §4.4, TSK-F1_1.1-23.4-GREEN.';

ALTER FUNCTION public.fn_monitor_and_activate_fallback() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_monitor_and_activate_fallback() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_monitor_and_activate_fallback() TO service_role;


-- =============================================================================
-- BLOQUE 6: PROGRAMACIÓN DE JOBS pg_cron — Orquestación Automatizada
-- Trazabilidad: TSK-F1_1.1-24.1-GREEN (Programación de jobs) y
--               TSK-F1_1.1-25.1-REFACT (Afinamiento de intervalos)
-- SPEC: §3.7 (Job de Sincronización & Cleanup), §4.4 (fn_monitor_and_activate_fallback)
-- PLAN: B5b — Automatización & Orquestación
-- REQ: REQ-09 (Monitor de Fallback), REQ-12 (Atomic Locking)
--
-- ANÁLISIS DE INTERVALOS (TSK-F1_1.1-25.1-REFACT):
-- --------------------------------------------------
-- Contexto de sorteos: Martes, Jueves y Domingos ~01:30 COT = ~06:30 UTC.
-- En esa ventana el Motor Python (GHA) adquiere sync_locks, ingesta proyecciones
-- y dispara fn_compute_async_scoring. Los jobs de mantenimiento NO deben pisar
-- esa franja para evitar contención de locks y timeouts de scoring.
--
-- Job 1 — dontolto_recover_stalled (cada 15 minutos):
--   Expresión: '*/15 * * * *'
--   Justificación: El umbral zombie es 30 min. Un intervalo de 15 min garantiza
--   al menos una ejecución dentro del primer ciclo de vida de un zombie, sin
--   solaparse con el GHA que opera en ventanas de ~25 min máximo (timeout GHA).
--   Riesgo de solapamiento con sorteos: BAJO. La función solo ejecuta un UPDATE
--   WHERE (lectura + escritura puntual); no adquiere sync_locks. Si corre en la
--   ventana 06:30 UTC, el Motor lleva ya sus propios workers reclamados con
--   heartbeats activos; la función los respeta (last_heartbeat < now()-30min).
--
-- Job 2 — dontolto_fallback_monitor (cada hora, minuto 5):
--   Expresión: '5 * * * *'
--   Justificación: El umbral de deuda es 24 h (debt_threshold_hours). Una
--   granularidad horaria es más que suficiente. El offset de 5 minutos desplaza
--   la ejecución a XX:05 UTC, evitando la colisión directa con la ventana de
--   sorteo XX:30 UTC y los ciclos de scoring que arrancan en XX:00 y XX:01.
--   No adquiere sync_locks; solo lee MVQ y delega a fn_verify_and_promote_draw.
--
-- Job 3 — dontolto_cleanup_locks (cada 30 minutos, en minutos 10 y 40):
--   Expresión: '10,40 * * * *'
--   Justificación: El TTL de locks es 60 min. Una limpieza cada 30 min garantiza
--   que ningún lock expirado persista más de 30 min tras su vencimiento, evitando
--   acumulación de "lock fantasma". Los minutos 10 y 40 evitan la ventana de
--   sorteo (06:30 UTC) y no colisionan con los ciclos de inicio de GHA (06:00 UTC).
--   Este DELETE es extremadamente liviano (índice en expires_at).
--
-- Idempotencia: Se usa cron.unschedule + cron.schedule para garantizar que
-- re-ejecutar la migración no duplique jobs.
--
-- statement_timeout: Cada job usa SET LOCAL statement_timeout = '55min' para
-- liberar el scheduler de pg_cron antes del TTL de lock de 60 min (ADR-03).
-- Para jobs de limpieza (< 1 segundo), el timeout es conservador y sin impacto.
-- =============================================================================

-- Garantía de permisos: pg_cron requiere que el schema cron sea accesible
-- desde el role que ejecuta cron.schedule (ya otorgado en B4, re-afirmado aquí).
GRANT USAGE ON SCHEMA cron TO service_role;

-- -----------------------------------------------------------------------------
-- JOB 1: dontolto_recover_stalled
-- Frecuencia: cada 15 minutos (*/15 * * * *)
-- Comando: invoca fn_recover_stalled_projections() con timeout de seguridad
-- Propósito: Reset determinista de workers zombie (last_heartbeat > 30 min)
-- TSK-F1_1.1-24.1-GREEN, TSK-F1_1.1-25.1-REFACT
-- -----------------------------------------------------------------------------

-- Eliminación previa para garantizar idempotencia en re-ejecuciones
SELECT cron.unschedule('dontolto_recover_stalled');

SELECT cron.schedule(
    'dontolto_recover_stalled',          -- nombre único del job
    '*/15 * * * *',                       -- cada 15 minutos
    $$
        SET LOCAL statement_timeout = '55min';
        SELECT public.fn_recover_stalled_projections();
    $$
);

COMMENT ON COLUMN cron.job.jobname IS
    'Ver docs/f1_1.1/audit/pipeline/cert_block6_DEVOPS_20260410.md para justificación de intervalos.';

-- -----------------------------------------------------------------------------
-- JOB 2: dontolto_fallback_monitor
-- Frecuencia: cada hora, en el minuto 5 (5 * * * *)
-- Comando: invoca fn_monitor_and_activate_fallback() con timeout de seguridad
-- Propósito: Activación automática de fallback para sorteos huérfanos > 24h
-- TSK-F1_1.1-24.1-GREEN, TSK-F1_1.1-25.1-REFACT
-- -----------------------------------------------------------------------------

SELECT cron.unschedule('dontolto_fallback_monitor');

SELECT cron.schedule(
    'dontolto_fallback_monitor',          -- nombre único del job
    '5 * * * *',                          -- cada hora en el minuto 5
    $$
        SET LOCAL statement_timeout = '55min';
        SELECT public.fn_monitor_and_activate_fallback();
    $$
);

-- -----------------------------------------------------------------------------
-- JOB 3: dontolto_cleanup_locks
-- Frecuencia: cada 30 minutos, en minutos 10 y 40 (10,40 * * * *)
-- Comando: DELETE directo en sync_locks con timeout de seguridad
-- Propósito: Purga de locks expirados para evitar acumulación de "lock fantasma"
-- TSK-F1_1.1-24.1-GREEN, TSK-F1_1.1-25.1-REFACT
-- -----------------------------------------------------------------------------

SELECT cron.unschedule('dontolto_cleanup_locks');

SELECT cron.schedule(
    'dontolto_cleanup_locks',             -- nombre único del job
    '10,40 * * * *',                      -- cada 30 minutos (minutos 10 y 40)
    $$
        SET LOCAL statement_timeout = '55min';
        DELETE FROM public.sync_locks WHERE expires_at <= now();
    $$
);


COMMIT;

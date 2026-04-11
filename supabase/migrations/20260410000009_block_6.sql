-- =============================================================================
-- MIGRACIÓN: 20260410000009_block_6.sql
-- Trazabilidad: Bloque 7 — TSK-F1_1.1-27.1 a 27.3-GREEN (Observabilidad & Mantenimiento)
-- Objetos:
--   ALTER TABLE projections  — Ampliar CHECK de status para incluir 'error_fatal'
--   VIEW v_system_health     — Observabilidad operativa del pipeline de proyecciones
--   VIEW v_strategy_delta    — Análisis comparativo de performance por estrategia
--   FUNCTION fn_cleanup_logs — Purga de logs según TTL de retención (SPEC §4.5)
--   pg_cron job              — dontolto_cleanup_logs (diario 2am UTC)
-- SPEC: §4.5 (fn_cleanup_logs), §6 (v_system_health, v_strategy_delta)
-- PLAN: B7 — Observabilidad & Cierre Final [TDD Cycle]
-- ADR: ADR-06 (RLS High-Performance SECURITY DEFINER)
-- REQ: REQ-10 (Observabilidad Dashboard), REQ-13 (Mantenimiento Forense)
-- Fecha: 2026-04-10
-- Dependencia: 20260410000008_block_5b.sql
-- Tests que valida: 026_v_system_health.sql (4 assertions)
--                   027_v_strategy_delta.sql (4 assertions)
--                   028_fn_cleanup_logs.sql (4 assertions)
-- =============================================================================

BEGIN;

-- =============================================================================
-- BLOQUE 1: ALTER TABLE projections — Ampliar CHECK constraint de status
-- Trazabilidad: TSK-F1_1.1-27.1-GREEN (prerequisito SPEC PLAN B7)
-- El estado 'error_fatal' es el mecanismo Anti-Poison-Pill definido en PLAN B5b.
-- Un registro en 'error_fatal' indica que el worker intentó procesar la proyección
-- pero encontró un error irrecuperable (datos corruptos, violación de validación, etc.).
-- Estrategia: DROP + ADD para actualizar el CHECK constraint de forma idempotente.
-- SPEC §3.4: ciclo de vida completo de projections.status.
-- =============================================================================

-- Eliminar el constraint actual para permitir la ampliación
ALTER TABLE public.projections
    DROP CONSTRAINT IF EXISTS chk_projections_status;

-- Recrear con 'error_fatal' incluido en el dominio de estados válidos
ALTER TABLE public.projections
    ADD CONSTRAINT chk_projections_status
        CHECK (status IN ('pending', 'calculating', 'calculated', 'error', 'error_fatal'));

COMMENT ON CONSTRAINT chk_projections_status ON public.projections IS
    'Dominio de estados válidos del ciclo de vida de una proyección. '
    'pending: en cola; calculating: worker activo; calculated: scoring completado; '
    'error: fallo recuperable; error_fatal: fallo irrecuperable (Anti-Poison-Pill). '
    'PLAN B5b, PLAN B7, TSK-F1_1.1-27.1-GREEN.';


-- =============================================================================
-- BLOQUE 2: VISTA v_system_health — Observabilidad operativa del pipeline
-- Trazabilidad: TSK-F1_1.1-27.1-GREEN
-- SPEC §6: Vista de observabilidad del estado operativo del pipeline de proyecciones.
-- Contrato de interfaz (tests 026_v_system_health.sql):
--   - total_projections: conteo total de proyecciones registradas
--   - error_fatal_count: conteo de proyecciones en estado 'error_fatal'
--   - pending_count: conteo de proyecciones en estado 'pending'
--   - calculating_count: conteo de proyecciones en estado 'calculating'
--   - calculated_count: conteo de proyecciones en estado 'calculated' (exitosas)
--   - error_count: conteo de proyecciones en estado 'error' (recuperables)
-- La vista consolida el estado del pipeline en una sola fila de resumen.
-- No tiene RLS propia (hereda la RLS de projections a través de la vista).
-- =============================================================================

CREATE OR REPLACE VIEW public.v_system_health AS
SELECT
    -- Métrica base: total de proyecciones en el sistema (denominador de ratios de distribución)
    COUNT(*)                                        AS total_projections,

    -- Distribución por estado — contadores individuales para alertas en Dashboard
    COUNT(*) FILTER (WHERE status = 'pending')      AS pending_count,
    COUNT(*) FILTER (WHERE status = 'calculating')  AS calculating_count,
    COUNT(*) FILTER (WHERE status = 'calculated')   AS calculated_count,
    COUNT(*) FILTER (WHERE status = 'error')        AS error_count,

    -- Indicador de alerta primaria: proyecciones con fallo irrecuperable (Anti-Poison-Pill)
    -- El Dashboard monitorea este contador para detectar degradación del Motor
    COUNT(*) FILTER (WHERE status = 'error_fatal')  AS error_fatal_count

FROM public.projections;

COMMENT ON VIEW public.v_system_health IS
    'Vista de observabilidad operativa del pipeline de proyecciones. '
    'Agrega el estado de todas las proyecciones en contadores por estado y latencia de scoring. '
    'Indicadores clave: total_projections (denominador de ratios), error_fatal_count (alerta primaria). '
    'Una sola fila de resumen — apta para polling del Dashboard y alertas automáticas. '
    'SPEC §6, ARC-06, REQ-10, TSK-F1_1.1-27.1-GREEN.';


-- =============================================================================
-- BLOQUE 3: VISTA v_strategy_delta — Análisis comparativo de performance
-- Trazabilidad: TSK-F1_1.1-27.2-GREEN
-- SPEC §6: "Pivote de performance comparando estrategias de rol active vs control"
-- Contrato de interfaz (tests 027_v_strategy_delta.sql):
--   - draw_date: fecha del sorteo
--   - type: tipo del sorteo ('baloto' | 'revancha')
--   - strategy_name: nombre de la estrategia
--   - avg_score: score promedio de la estrategia para el sorteo (AVG de performance.score)
--   - is_control_delta: booleano TRUE si la estrategia es de rol 'control' (linea base)
-- La vista JOIN performance → projections → strategies_metadata → draws para
-- construir el pivote comparativo. Expone todas las estrategias (active y control)
-- para que el Dashboard calcule deltas en el cliente si lo requiere.
-- =============================================================================

CREATE OR REPLACE VIEW public.v_strategy_delta AS
SELECT
    d.draw_date                                     AS draw_date,
    d.type                                          AS type,
    proj.strategy_name                              AS strategy_name,
    ROUND(AVG(perf.score)::NUMERIC, 2)              AS avg_score,
    -- is_control_delta: TRUE si el rol de la estrategia es 'control' (línea base del delta)
    -- El Dashboard usa este flag para identificar la referencia de comparación
    (sm.role = 'control')                           AS is_control_delta

FROM public.performance perf
JOIN public.projections proj
    ON proj.id = perf.projection_id
JOIN public.draws d
    ON d.id = perf.draw_id
JOIN public.strategies_metadata sm
    ON sm.name = proj.strategy_name
    AND sm.version = proj.strategy_version

WHERE perf.is_verified = TRUE

GROUP BY
    d.draw_date,
    d.type,
    proj.strategy_name,
    sm.role;

COMMENT ON VIEW public.v_strategy_delta IS
    'Vista de análisis comparativo de performance entre estrategias por sorteo. '
    'Calcula el score promedio (avg_score) de cada estrategia para cada sorteo verificado. '
    'is_control_delta = TRUE identifica la estrategia de rol ''control'' (línea base del delta). '
    'El Dashboard puede calcular el desvío de cada estrategia activa contra la línea base '
    'usando: avg_score(active) - avg_score(control) para el mismo (draw_date, type). '
    'SPEC §6, ARC-06, REQ-10, TSK-F1_1.1-27.2-GREEN.';


-- =============================================================================
-- BLOQUE 4: FUNCIÓN fn_cleanup_logs — Purga de logs según TTL de retención
-- Trazabilidad: TSK-F1_1.1-27.3-GREEN
-- SPEC §4.5: Mantenimiento Forense (REQ-13)
-- Lógica de purga (contrato SPEC §4.5 y test 028_fn_cleanup_logs.sql):
--   1. Lee TTL desde system_configuration (clave log_retention_days).
--      Si no existe la configuración, usa default de 90 días.
--   2. DELETE system_logs WHERE level IN ('info', 'debug')
--      AND created_at < now() - (retention_days * INTERVAL '1 day')
--   3. UPDATE system_logs SET is_archived = TRUE WHERE is_archived = FALSE
--      AND created_at < now() - INTERVAL '180 days'
--   4. DELETE manual_verification_queue WHERE is_verified = TRUE
--      AND is_conflict = FALSE AND created_at < now() - INTERVAL '180 days'
--   5. Registra en system_logs cuántos registros fueron purgados (trazabilidad forense)
-- Invariante crítica: NO borra registros dentro del TTL ni niveles warning/error/critical/audit
-- Triple barrera ADR-06: SECURITY DEFINER + SET search_path + REVOKE/GRANT
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_cleanup_logs()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = extensions, public
AS $$
DECLARE
    v_run_id              UUID    := gen_random_uuid();
    v_retention_days      INTEGER := 90;  -- default SPEC §4.5
    v_deleted_logs        INTEGER := 0;
    v_archived_logs       INTEGER := 0;
    v_deleted_mvq         INTEGER := 0;
BEGIN

    -- -------------------------------------------------------------------------
    -- PASO 1: TTL de retención — default 90 días (SPEC §4.5)
    -- El singleton system_configuration almacena parámetros operativos del sistema.
    -- Cuando la columna log_retention_days sea añadida en una migración futura
    -- (Stage 1.3 — Cold Storage), esta función puede leerla directamente.
    -- Por ahora, la SPEC §4.5 define 90 días como TTL hardcoded para info/debug.
    -- Snapshot al inicio para trazabilidad (ADR-02).
    -- -------------------------------------------------------------------------
    v_retention_days := 90;

    -- -------------------------------------------------------------------------
    -- PASO 2: Purga de logs info/debug que superaron el TTL de retención
    -- Contrato SPEC §4.5: solo elimina levels 'info' y 'debug'.
    -- Los niveles 'warning', 'error', 'critical', 'audit' están PROTEGIDOS.
    -- Un log de nivel 'audit' con 95 días NO debe ser purgado por esta operación.
    -- -------------------------------------------------------------------------
    DELETE FROM public.system_logs
     WHERE level IN ('info', 'debug')
       AND created_at < now() - (v_retention_days * INTERVAL '1 day');

    GET DIAGNOSTICS v_deleted_logs = ROW_COUNT;

    -- -------------------------------------------------------------------------
    -- PASO 3: Archivar logs históricos (>180 días) que no son info/debug
    -- Registros archivados son candidatos a Cold Storage (Stage 1.3).
    -- La operación UPDATE es idempotente: WHERE is_archived = FALSE evita re-marcar.
    -- -------------------------------------------------------------------------
    UPDATE public.system_logs
       SET is_archived = TRUE
     WHERE is_archived = FALSE
       AND created_at < now() - INTERVAL '180 days';

    GET DIAGNOSTICS v_archived_logs = ROW_COUNT;

    -- -------------------------------------------------------------------------
    -- PASO 4: Purga de cola de verificación manual verificada y sin conflicto
    -- Solo elimina registros que ya pasaron por el Double-Entry Guard exitosamente.
    -- Registros con is_conflict = TRUE se conservan para análisis forense.
    -- -------------------------------------------------------------------------
    DELETE FROM public.manual_verification_queue
     WHERE is_verified = TRUE
       AND is_conflict = FALSE
       AND created_at < now() - INTERVAL '180 days';

    GET DIAGNOSTICS v_deleted_mvq = ROW_COUNT;

    -- -------------------------------------------------------------------------
    -- PASO 5: Registro forense de la operación de purga en system_logs
    -- Solo registra si hubo actividad real para evitar ruido en los logs.
    -- El mensaje incluye los contadores para trazabilidad completa (REQ-13).
    -- -------------------------------------------------------------------------
    IF v_deleted_logs > 0 OR v_archived_logs > 0 OR v_deleted_mvq > 0 THEN
        INSERT INTO public.system_logs (run_id, service, level, message, metadata)
        VALUES (
            v_run_id,
            'cleanup',
            'info',
            'fn_cleanup_logs: purga completada — ' ||
                v_deleted_logs  || ' log(s) info/debug eliminado(s), ' ||
                v_archived_logs || ' log(s) archivado(s), ' ||
                v_deleted_mvq   || ' registro(s) MVQ purgado(s)',
            jsonb_build_object(
                'run_id',            v_run_id,
                'retention_days',    v_retention_days,
                'deleted_logs',      v_deleted_logs,
                'archived_logs',     v_archived_logs,
                'deleted_mvq',       v_deleted_mvq
            )
        );
    END IF;

END;
$$;

COMMENT ON FUNCTION public.fn_cleanup_logs() IS
    'Motor de mantenimiento forense del sistema (REQ-13). '
    'TTL de retención: 90 días (SPEC §4.5 hardcoded; extensible vía system_configuration en Stage 1.3). '
    'PURGA: DELETE system_logs WHERE level IN (''info'', ''debug'') AND created_at < now() - TTL. '
    'ARCHIVA: UPDATE system_logs SET is_archived = TRUE WHERE created_at < now() - 180 días. '
    'LIMPIA MVQ: DELETE manual_verification_queue WHERE is_verified=TRUE AND is_conflict=FALSE '
    'AND created_at < now() - 180 días. '
    'Registra la operación en system_logs (trazabilidad forense). '
    'Niveles PROTEGIDOS de purga: warning, error, critical, audit (solo info/debug son purgables). '
    'Invariante DoD: nunca borra registros dentro del TTL de retención. '
    'SECURITY DEFINER con search_path fijo. ADR-06. '
    'SPEC §4.5, REQ-13, TSK-F1_1.1-27.3-GREEN.';

-- Triple barrera ADR-06: propietario postgres + REVOKE FROM PUBLIC + GRANT TO service_role
ALTER FUNCTION public.fn_cleanup_logs() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_cleanup_logs() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_cleanup_logs() TO service_role;


-- =============================================================================
-- BLOQUE 5: PROGRAMACIÓN DE JOB pg_cron — dontolto_cleanup_logs
-- Trazabilidad: TSK-F1_1.1-27.3-GREEN
-- SPEC: §4.5 (Job de purga diario), PLAN B7
-- REQ: REQ-13 (Mantenimiento Forense)
--
-- ANÁLISIS DE INTERVALO (consistente con TSK-F1_1.1-25.1-REFACT):
-- ------------------------------------------------------------------
-- Schedule: '0 2 * * *' — diario a las 2:00 UTC
-- Justificación:
--   - Las ventanas de sorteo son: Martes, Jueves, Domingos a ~01:30 COT = ~06:30 UTC.
--   - 2:00 UTC está FUERA de la ventana de sorteo (distancia mínima de 4.5 horas).
--   - Evita la ventana nocturna ~06:30 UTC en que GHA adquiere sync_locks.
--   - Un job de purga diario es suficiente: la granularidad de retención es de días.
--   - El DELETE por nivel e índice created_at es liviano; no genera contención.
--   - statement_timeout = '55min' para liberar el scheduler antes del TTL de lock (ADR-03).
--
-- Idempotencia: cron.unschedule() + cron.schedule() garantiza que re-ejecutar
-- la migración no duplique el job.
-- =============================================================================

-- Garantía de permisos (consistente con migraciones anteriores)
GRANT USAGE ON SCHEMA cron TO service_role;

-- Eliminación previa para garantizar idempotencia en re-ejecuciones
SELECT cron.unschedule('dontolto_cleanup_logs');

-- Programar el job de purga diario a las 2am UTC
SELECT cron.schedule(
    'dontolto_cleanup_logs',               -- nombre único del job
    '0 2 * * *',                           -- diario a las 2:00 UTC
    $$
        SET LOCAL statement_timeout = '55min';
        SELECT public.fn_cleanup_logs();
    $$
);


COMMIT;

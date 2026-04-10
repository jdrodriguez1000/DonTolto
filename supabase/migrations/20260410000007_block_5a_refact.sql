-- =============================================================================
-- MIGRACIÓN: 20260410000007_block_5a_refact.sql
-- Trazabilidad: Bloque 5A — TSK-F1_1.1-20.1-REFACT (Modularización de motores RPC)
-- Objetos:
--   fn_snapshot_system_config()                     — helper: snapshot de configuración
--   fn_backup_performance_to_logs(UUID, UUID)        — helper: backup forense JSONB
--   fn_reset_draw_scoring(DATE, VARCHAR)             — helper: recálculo atómico
--   fn_compute_async_scoring(UUID)                  — reescrita usando helpers
--   fn_verify_and_promote_draw(DATE, VARCHAR)        — reescrita usando helpers
-- SPEC: §4.2 (fn_compute_async_scoring), §4.3 (fn_verify_and_promote_draw)
-- ADR: ADR-04 — Recálculo Atómico Transparente
-- ADR: ADR-06 — RLS High-Performance (SECURITY DEFINER + search_path restrictivo)
-- Fecha: 2026-04-10
-- Dependencia: 20260410000006_block_5a.sql (implementación GREEN de ambas funciones)
-- Tests que valida: 018, 019, 020, 021, 022, 023 (pgTap) — sin regresiones
--
-- DECISIÓN DE REFACTOR:
--   Los tests 018–023 son PURAMENTE FUNCIONALES: verifican efectos secundarios
--   observables en tablas (system_logs, projections, draws, performance).
--   Ningún test inspecciona pg_proc.prosrc ni el texto literal de ninguna función.
--   Por tanto, la extracción de helpers privados es SEGURA y no produce regresiones.
--
--   Bloques candidatos identificados en fn_compute_async_scoring:
--     - Snapshotting de system_configuration → fn_snapshot_system_config()
--
--   Bloques candidatos identificados en fn_verify_and_promote_draw:
--     - Backup forense JSONB en system_logs → fn_backup_performance_to_logs()
--     - Secuencia DELETE+RESET (ADR-04) → fn_reset_draw_scoring()
--
--   La modularización reduce la complejidad ciclomática de las funciones principales
--   y permite probar cada bloque de lógica de forma aislada en futuras iteraciones.
--
-- Invariante de calidad: los 23 tests existentes (001–023) no sufren regresiones.
-- =============================================================================


-- =============================================================================
-- BLOQUE 1: HELPER fn_snapshot_system_config()
-- Encapsula la lectura del singleton system_configuration (id=1).
-- Retorna un JSONB con los campos clave para evitar lecturas repetidas
-- dentro de un mismo contexto transaccional.
--
-- Contrato de retorno (JSONB):
--   { "debt_threshold_hours": INTEGER, "is_system_locked": BOOLEAN }
--
-- Uso en funciones principales:
--   v_config := public.fn_snapshot_system_config();
--   v_debt_h  := (v_config ->> 'debt_threshold_hours')::integer;
--   v_locked  := (v_config ->> 'is_system_locked')::boolean;
--
-- Seguridad (ADR-06):
--   - SECURITY DEFINER: eleva al nivel de postgres para acceder a system_configuration
--     sin depender de los permisos del rol invocador.
--   - SET search_path: anti schema-hijacking (solo extensions y public).
--   - OWNER TO postgres + REVOKE ALL FROM PUBLIC: acceso mínimo necesario.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_snapshot_system_config()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = extensions, public
AS $$
DECLARE
    v_debt_h INTEGER;
    v_locked BOOLEAN;
BEGIN
    SELECT debt_threshold_hours, is_system_locked
      INTO v_debt_h, v_locked
      FROM public.system_configuration
     WHERE id = 1;

    RETURN jsonb_build_object(
        'debt_threshold_hours', v_debt_h,
        'is_system_locked',     v_locked
    );
END;
$$;

COMMENT ON FUNCTION public.fn_snapshot_system_config() IS
    'Helper privado: captura los campos operativos del singleton system_configuration (id=1) '
    'en un JSONB inmutable para ser consumido al inicio de las funciones de motor. '
    'Garantiza la invariante de snapshotting: los valores capturados una vez se usan '
    'durante toda la ejecución del motor, independientemente de cambios mid-flight. '
    'SECURITY DEFINER con search_path fijo. ADR-06. TSK-F1_1.1-20.1-REFACT.';

ALTER FUNCTION public.fn_snapshot_system_config() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_snapshot_system_config() FROM PUBLIC;


-- =============================================================================
-- BLOQUE 2: HELPER fn_backup_performance_to_logs(p_draw_id UUID, p_run_id UUID)
-- Encapsula el backup forense JSONB de registros de performance hacia system_logs.
-- Ejecutado ANTES de cualquier DELETE en performance (invariante de orden ADR-04).
--
-- Mecánica:
--   - Agrega todos los registros de public.performance para p_draw_id en un array JSONB.
--   - Inserta el resultado en system_logs con level='audit' para filtrado forense.
--   - Si no existen registros de performance para el draw_id, la función no inserta nada
--     (backup vacío no tiene utilidad forense). El llamador debe verificar existencia antes.
--
-- Seguridad (ADR-06): misma triple barrera que fn_snapshot_system_config.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_backup_performance_to_logs(
    p_draw_id  UUID,
    p_run_id   UUID,
    p_draw_date DATE,
    p_type      VARCHAR
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = extensions, public
AS $$
BEGIN
    -- Backup forense: JSONB_AGG de todos los registros de performance del draw anterior.
    -- El INSERT solo ocurre si existen registros (JSONB_AGG retorna NULL si COUNT=0).
    INSERT INTO public.system_logs (run_id, service, level, message, metadata)
    SELECT
        p_run_id,
        'double_entry',
        'audit',
        'Backup forense previo a recálculo atómico: ' || p_draw_date::text || ' / ' || p_type,
        jsonb_agg(to_jsonb(perf))
      FROM public.performance perf
     WHERE perf.draw_id = p_draw_id
    HAVING COUNT(*) > 0;
END;
$$;

COMMENT ON FUNCTION public.fn_backup_performance_to_logs(UUID, UUID, DATE, VARCHAR) IS
    'Helper privado: genera un backup forense JSONB del estado actual de performance '
    'para un draw_id dado, insertándolo en system_logs con level=audit. '
    'Debe invocarse ANTES de cualquier DELETE en performance (invariante ADR-04). '
    'Si no hay registros de performance asociados al draw_id, no inserta nada. '
    'SECURITY DEFINER con search_path fijo. ADR-06. TSK-F1_1.1-20.1-REFACT.';

ALTER FUNCTION public.fn_backup_performance_to_logs(UUID, UUID, DATE, VARCHAR) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_backup_performance_to_logs(UUID, UUID, DATE, VARCHAR) FROM PUBLIC;


-- =============================================================================
-- BLOQUE 3: HELPER fn_reset_draw_scoring(p_draw_date DATE, p_type VARCHAR)
-- Encapsula la secuencia de recálculo atómico definida en ADR-04:
--   (1) DELETE performance del draw anterior
--   (2) RESET projections.status = 'pending' para la fecha del draw
--   (3) DELETE draw previo (con y sin status='final')
--
-- Precondición: el backup forense DEBE haberse ejecutado antes de llamar
-- a esta función (responsabilidad del llamador — invariante de orden ADR-04).
--
-- Este helper NO realiza el INSERT del nuevo draw: esa responsabilidad
-- permanece en las funciones principales para preservar el control de flujo.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_reset_draw_scoring(
    p_draw_id   UUID,
    p_draw_date DATE,
    p_type      VARCHAR
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = extensions, public
AS $$
BEGIN
    -- Paso 1: Eliminar performance del draw anterior (limpieza atómica)
    DELETE FROM public.performance
     WHERE draw_id = p_draw_id;

    -- Paso 2: Resetear proyecciones para recálculo desde cero
    UPDATE public.projections
       SET status = 'pending'
     WHERE target_draw_date = p_draw_date;

    -- Paso 3: Eliminar el draw previo (cualquier status — corrección Admin tiene autoridad)
    DELETE FROM public.draws
     WHERE draw_date = p_draw_date
       AND type      = p_type;
END;
$$;

COMMENT ON FUNCTION public.fn_reset_draw_scoring(UUID, DATE, VARCHAR) IS
    'Helper privado: ejecuta la secuencia de recálculo atómico ADR-04 para un draw previo. '
    'Orden: DELETE performance → RESET projections a pending → DELETE draw previo. '
    'PRECONDICIÓN: el backup forense debe haber sido ejecutado antes de invocar esta función. '
    'No realiza el INSERT del nuevo draw: esa responsabilidad es del llamador. '
    'SECURITY DEFINER con search_path fijo. ADR-06. TSK-F1_1.1-20.1-REFACT.';

ALTER FUNCTION public.fn_reset_draw_scoring(UUID, DATE, VARCHAR) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fn_reset_draw_scoring(UUID, DATE, VARCHAR) FROM PUBLIC;


-- =============================================================================
-- BLOQUE 4: fn_compute_async_scoring — REESCRITURA CON HELPERS
-- Lógica equivalente a la versión GREEN (20260410000006_block_5a.sql),
-- modularizada para reducir complejidad ciclomática.
--
-- Complejidad ciclomática antes del refactor: ~7 (ramas + loops)
-- Complejidad ciclomática después del refactor: ~4 (delegación a helper)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_compute_async_scoring(p_run_id UUID DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = extensions, public
AS $$
DECLARE
    -- Snapshot de configuración capturado al inicio (invariante de snapshotting)
    v_config  JSONB;
    v_debt_h  INTEGER;
    v_locked  BOOLEAN;
    v_snap_id UUID;
BEGIN
    -- Fijar el run_id una sola vez para toda la ejecución
    v_snap_id := COALESCE(p_run_id, gen_random_uuid());

    -- -------------------------------------------------------------------------
    -- PASO 1: Snapshotting al inicio (TSK-19.1)
    -- Delegar a fn_snapshot_system_config() para encapsular la lectura del singleton.
    -- Los valores capturados son inmutables durante toda la ejecución del batch.
    -- -------------------------------------------------------------------------
    v_config := public.fn_snapshot_system_config();
    v_debt_h := (v_config ->> 'debt_threshold_hours')::integer;
    v_locked := (v_config ->> 'is_system_locked')::boolean;

    -- Registrar snapshot en system_logs para trazabilidad forense (SPEC §3.6).
    -- Un único INSERT de snapshot por invocación garantiza idempotencia del log.
    INSERT INTO public.system_logs (run_id, service, level, message, metadata)
    VALUES (
        v_snap_id,
        'scoring',
        'info',
        'Inicio de scoring — snapshot de system_configuration capturado',
        jsonb_build_object(
            'debt_threshold_hours', v_debt_h,
            'is_system_locked',     v_locked,
            'run_id',               v_snap_id
        )
    );

    -- -------------------------------------------------------------------------
    -- PASO 2: Kill-switch check
    -- Si is_system_locked=TRUE, el sistema está en modo de emergencia.
    -- Se registra el evento y se retorna sin procesar ninguna proyección.
    -- -------------------------------------------------------------------------
    IF v_locked = TRUE THEN
        INSERT INTO public.system_logs (run_id, service, level, message, metadata)
        VALUES (
            v_snap_id,
            'scoring',
            'warning',
            'Sistema bloqueado, scoring abortado',
            jsonb_build_object('run_id', v_snap_id)
        );
        RETURN;
    END IF;

    -- -------------------------------------------------------------------------
    -- PASO 3: Anti-carrera SKIP LOCKED (TSK-19.1, SPEC §4.2)
    -- Marcar hasta 428 proyecciones 'pending' (de estrategias activas) como
    -- 'calculating' de forma atómica. FOR UPDATE SKIP LOCKED garantiza que
    -- ejecuciones concurrentes no procesen las mismas proyecciones (sin deadlock).
    -- -------------------------------------------------------------------------
    UPDATE public.projections
       SET status = 'calculating'
     WHERE id IN (
         SELECT p.id
           FROM public.projections p
           JOIN public.strategies_metadata sm
             ON sm.name    = p.strategy_name
            AND sm.version = p.strategy_version
          WHERE p.status   = 'pending'
            AND sm.is_active = TRUE
          ORDER BY p.id
          LIMIT 428
            FOR UPDATE SKIP LOCKED
     );

END;
$$;

COMMENT ON FUNCTION public.fn_compute_async_scoring(UUID) IS
    'Scoring asíncrono de proyecciones (CLAIM TOKEN pattern). Refactorizado en TSK-20.1. '
    'Fase 1 — esta función: delega snapshotting a fn_snapshot_system_config() (invariante §4.2), '
    'kill-switch check (is_system_locked), anti-carrera SKIP LOCKED (428 proyecciones/batch → estado ''calculating''). '
    'El estado ''calculating'' es el claim token: señaliza al Engine Python qué proyecciones procesar. '
    'Fase 2 — Engine Python: calcula hits, inserta en performance, transiciona a ''calculated''. '
    'TSK-19.5: retry_count se incrementa en la fase Python; status=''error'' si retry_count >= 3. '
    'Exactamente un snapshot log por ejecución (service=''scoring'', level=''info'', metadata con snapshot). '
    'SECURITY DEFINER con search_path fijo. ADR-06. '
    'REQ-08, SPEC §4.2, TSK-F1_1.1-19.1 + 19.5-GREEN + 20.1-REFACT.';

ALTER FUNCTION public.fn_compute_async_scoring(UUID) OWNER TO postgres;


-- =============================================================================
-- BLOQUE 5: fn_verify_and_promote_draw — REESCRITURA CON HELPERS
-- Lógica equivalente a la versión GREEN (20260410000006_block_5a.sql),
-- modularizada para reducir complejidad ciclomática.
--
-- Complejidad ciclomática antes del refactor: ~12 (ramas anidadas profundas)
-- Complejidad ciclomática después del refactor: ~8 (delegación a helpers)
--
-- Helpers utilizados:
--   - fn_backup_performance_to_logs(): backup forense antes del recálculo
--   - fn_reset_draw_scoring(): secuencia DELETE+RESET+DELETE (ADR-04)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_verify_and_promote_draw(
    p_draw_date DATE    DEFAULT NULL,
    p_type      VARCHAR DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = extensions, public
AS $$
DECLARE
    v_admin_entry   RECORD;
    v_scraper_entry RECORD;
    v_existing_draw RECORD;
    v_debt_h        INTEGER;
    v_run_id        UUID := gen_random_uuid();
BEGIN
    -- -------------------------------------------------------------------------
    -- PASO 1: Detección de conflicto activo (TSK-19.3)
    -- Si existe algún registro con is_conflict=TRUE para esta fecha/tipo,
    -- la función se bloquea. Requiere intervención manual antes de reintentar.
    -- -------------------------------------------------------------------------
    IF EXISTS (
        SELECT 1
          FROM public.manual_verification_queue
         WHERE draw_date  = p_draw_date
           AND type       = p_type
           AND is_conflict = TRUE
    ) THEN
        INSERT INTO public.system_logs (run_id, service, level, message, metadata)
        VALUES (
            v_run_id,
            'double_entry',
            'warning',
            'Promoción bloqueada: conflicto activo en cola para ' || p_draw_date::text || ' / ' || p_type,
            jsonb_build_object('draw_date', p_draw_date, 'type', p_type)
        );
        RETURN FALSE;
    END IF;

    -- -------------------------------------------------------------------------
    -- PASO 2: Buscar par Admin + Scraper (TSK-19.2)
    -- -------------------------------------------------------------------------
    SELECT *
      INTO v_admin_entry
      FROM public.manual_verification_queue
     WHERE draw_date    = p_draw_date
       AND type         = p_type
       AND entry_source = 'admin'
       AND is_verified  = FALSE
     ORDER BY created_at DESC
     LIMIT 1;

    SELECT *
      INTO v_scraper_entry
      FROM public.manual_verification_queue
     WHERE draw_date    = p_draw_date
       AND type         = p_type
       AND entry_source = 'scraper'
       AND is_verified  = FALSE
     LIMIT 1;

    -- -------------------------------------------------------------------------
    -- PASO 3: Lógica de comparación y decisión
    -- -------------------------------------------------------------------------

    -- Caso A: Tenemos tanto Admin como Scraper → comparar
    IF v_admin_entry.id IS NOT NULL AND v_scraper_entry.id IS NOT NULL THEN

        IF v_admin_entry.numbers = v_scraper_entry.numbers
           AND v_admin_entry.superbalota = v_scraper_entry.superbalota THEN
            -- MATCH EXITOSO: continuar con backup + promoción (Pasos 4-8 abajo)
            NULL;
        ELSE
            -- DISCREPANCIA: marcar is_conflict=TRUE en toda la cola para esta fecha/tipo
            UPDATE public.manual_verification_queue
               SET is_conflict = TRUE
             WHERE draw_date = p_draw_date
               AND type      = p_type;

            INSERT INTO public.system_logs (run_id, service, level, message, metadata)
            VALUES (
                v_run_id,
                'double_entry',
                'warning',
                'Discrepancia detectada entre Admin y Scraper para ' || p_draw_date::text || ' / ' || p_type,
                jsonb_build_object(
                    'draw_date',       p_draw_date,
                    'type',            p_type,
                    'admin_numbers',   v_admin_entry.numbers,
                    'scraper_numbers', v_scraper_entry.numbers
                )
            );
            RETURN FALSE;
        END IF;

    -- Caso B: No hay Admin pero hay Scraper → evaluar Fallback Ghost (TSK-19.3)
    ELSIF v_admin_entry.id IS NULL AND v_scraper_entry.id IS NOT NULL THEN

        SELECT debt_threshold_hours
          INTO v_debt_h
          FROM public.system_configuration
         WHERE id = 1;

        IF EXTRACT(EPOCH FROM (now() - v_scraper_entry.created_at)) / 3600.0 > v_debt_h THEN

            -- Verificar si existe draw previo para el recálculo
            SELECT *
              INTO v_existing_draw
              FROM public.draws
             WHERE draw_date = p_draw_date
               AND type      = p_type
             LIMIT 1;

            IF v_existing_draw.id IS NOT NULL THEN
                -- Backup forense delegado al helper (invariante de orden ADR-04)
                PERFORM public.fn_backup_performance_to_logs(
                    v_existing_draw.id,
                    v_run_id,
                    p_draw_date,
                    p_type
                );

                -- Recálculo atómico delegado al helper (ADR-04)
                PERFORM public.fn_reset_draw_scoring(
                    v_existing_draw.id,
                    p_draw_date,
                    p_type
                );
            END IF;

            -- Promover como 'transient' (Fallback Ghost sin confirmación Admin)
            INSERT INTO public.draws (run_id, draw_date, numbers, superbalota, type, status, is_manual)
            VALUES (v_run_id, p_draw_date, v_scraper_entry.numbers, v_scraper_entry.superbalota,
                    p_type, 'transient', FALSE);

            UPDATE public.manual_verification_queue
               SET is_verified = TRUE
             WHERE draw_date = p_draw_date
               AND type      = p_type;

            INSERT INTO public.system_logs (run_id, service, level, message, metadata)
            VALUES (
                v_run_id,
                'double_entry',
                'warning',
                'Ghost Fallback activado: sorteo promovido como transient sin confirmación Admin para '
                    || p_draw_date::text || ' / ' || p_type,
                jsonb_build_object(
                    'draw_date',        p_draw_date,
                    'type',             p_type,
                    'debt_threshold_h', v_debt_h
                )
            );
            RETURN TRUE;

        ELSE
            RETURN FALSE;
        END IF;

    ELSE
        -- No hay entradas suficientes para procesar
        RETURN FALSE;
    END IF;

    -- =========================================================================
    -- PASOS 4-8: Flujo de Match Exitoso (Admin + Scraper coinciden)
    -- =========================================================================

    -- -------------------------------------------------------------------------
    -- PASO 4 + 5: Backup forense + Recálculo atómico (TSK-19.4, ADR-04)
    -- Verificar si existe draw previo y delegar a helpers.
    -- -------------------------------------------------------------------------
    SELECT *
      INTO v_existing_draw
      FROM public.draws
     WHERE draw_date = p_draw_date
       AND type      = p_type
     LIMIT 1;

    IF v_existing_draw.id IS NOT NULL THEN
        -- Backup forense ANTES de cualquier DELETE (invariante de orden ADR-04)
        PERFORM public.fn_backup_performance_to_logs(
            v_existing_draw.id,
            v_run_id,
            p_draw_date,
            p_type
        );

        -- Recálculo atómico: DELETE performance → RESET projections → DELETE draw
        PERFORM public.fn_reset_draw_scoring(
            v_existing_draw.id,
            p_draw_date,
            p_type
        );
    END IF;

    -- -------------------------------------------------------------------------
    -- PASO 6: Promoción a draws (TSK-19.2)
    -- -------------------------------------------------------------------------
    INSERT INTO public.draws (run_id, draw_date, numbers, superbalota, type, status, is_manual)
    VALUES (
        v_run_id,
        p_draw_date,
        v_admin_entry.numbers,
        v_admin_entry.superbalota,
        p_type,
        'final',
        TRUE
    );

    -- -------------------------------------------------------------------------
    -- PASO 7: Marcar cola como verificada (TSK-19.2)
    -- -------------------------------------------------------------------------
    UPDATE public.manual_verification_queue
       SET is_verified = TRUE
     WHERE draw_date = p_draw_date
       AND type      = p_type;

    INSERT INTO public.system_logs (run_id, service, level, message, metadata)
    VALUES (
        v_run_id,
        'double_entry',
        'info',
        'Sorteo promovido exitosamente a draws: ' || p_draw_date::text || ' / ' || p_type,
        jsonb_build_object('draw_date', p_draw_date, 'type', p_type, 'is_manual', TRUE)
    );

    RETURN TRUE;

END;
$$;

COMMENT ON FUNCTION public.fn_verify_and_promote_draw(DATE, VARCHAR) IS
    'Validación Double-Entry y promoción de sorteo a tabla draws. Refactorizado en TSK-20.1. '
    'Delega backup forense a fn_backup_performance_to_logs() '
    'y recálculo atómico a fn_reset_draw_scoring() (ADR-04). '
    'Implementa detección de conflicto activo (is_conflict=TRUE bloquea promoción), '
    'comparación Admin vs Scraper (números + superbalota), '
    'Fallback Ghost >debt_threshold_hours (promote transient sin Admin), '
    'backup forense en system_logs (level=audit, JSONB_AGG de performance previa), '
    'recálculo atómico ADR-04 (DELETE performance → RESET projections → DELETE draw), '
    'promoción final con status=''final'' e is_manual=TRUE para Double-Entry verificado. '
    'SECURITY DEFINER con search_path fijo. ADR-06. '
    'REQ-09, SPEC §4.3, TSK-F1_1.1-19.2 + 19.3 + 19.4-GREEN + 20.1-REFACT.';

ALTER FUNCTION public.fn_verify_and_promote_draw(DATE, VARCHAR) OWNER TO postgres;

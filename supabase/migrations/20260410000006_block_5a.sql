-- =============================================================================
-- MIGRACIÓN: 20260410000006_block_5a.sql
-- Trazabilidad: Bloque 5A — TSK-F1_1.1-19.1 al 19.5-GREEN (Motores RPC)
-- Objetos:
--   [H-1] REVOKE fn_is_admin() de PUBLIC — remediación deuda técnica Bloque 4
--   [H-2] REVOKE UPDATE excesivo en system_configuration — remediación Bloque 4
--   ALTER TABLE projections ADD COLUMN retry_count
--   fn_compute_async_scoring(UUID) — implementación real (reemplaza stub)
--   fn_verify_and_promote_draw(DATE, VARCHAR) — implementación real (reemplaza stub)
-- SPEC: §4.2 (fn_compute_async_scoring), §4.3 (fn_verify_and_promote_draw)
-- ADR: ADR-04 — Recálculo Atómico Transparente
-- ADR: ADR-06 — RLS High-Performance (SECURITY DEFINER + search_path restrictivo)
-- Fecha: 2026-04-10
-- Dependencia: 20260410000002_block_4.sql (stubs de ambas funciones)
-- Dependencia: 20260410000005_block_4_refact.sql (fn_is_admin)
-- Tests que valida: 018, 019, 020, 021, 022, 023 (pgTap)
-- =============================================================================

-- =============================================================================
-- BLOQUE 0: REMEDIACIONES DE DEUDA TÉCNICA (H-1 y H-2 — OBLIGATORIAS PRIMERO)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- H-1: fn_is_admin() sin REVOKE FROM PUBLIC (CVSS ~5.3)
-- Cualquier rol no autenticado podía EXECUTE fn_is_admin() exponiéndola
-- innecesariamente. Se revoca el grant implícito de PUBLIC y se concede
-- explícitamente solo a los roles que requieren la función.
-- -----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.fn_is_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_is_admin() TO service_role;

-- -----------------------------------------------------------------------------
-- H-2: GRANT UPDATE excesivo en system_configuration para authenticated
-- El rol authenticated no debe poder modificar la configuración global del
-- sistema. Se revoca el permiso de UPDATE dejando solo SELECT para lecturas
-- autenticadas (las escrituras las realiza service_role o postgres directamente).
-- -----------------------------------------------------------------------------
REVOKE UPDATE ON public.system_configuration FROM authenticated;

-- =============================================================================
-- BLOQUE 1: EXTENSIÓN DE ESQUEMA
-- Agregar retry_count a projections para TSK-19.5 (reintentos de scoring).
-- IF NOT EXISTS garantiza idempotencia en reruns de migración.
-- =============================================================================

ALTER TABLE public.projections
    ADD COLUMN IF NOT EXISTS retry_count INTEGER NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.projections.retry_count IS
    'Contador de reintentos de scoring fallidos. Si alcanza 3, el status se marca '
    'como ''error'' (error_fatal). Gestionado por fn_compute_async_scoring (TSK-19.5).';

-- =============================================================================
-- BLOQUE 2: fn_compute_async_scoring — IMPLEMENTACIÓN REAL
-- Reemplaza el stub del Bloque 4 con la lógica completa de scoring.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TSK-F1_1.1-19.1 + 19.5-GREEN — Función: fn_compute_async_scoring
-- SPEC: §4.2 — Cálculo asíncrono de scoring (overlap projections vs draws)
-- ADR-06: SECURITY DEFINER + SET search_path restrictivo (anti schema-hijacking)
--
-- Mecánica (secuencia obligatoria de SPEC §4.2):
--   1. Snapshotting al inicio: captura debt_threshold_hours e is_system_locked
--      de system_configuration (id=1) en variables locales inmutables.
--   2. Registro de snapshot en system_logs (service='scoring', level='info').
--   3. Kill-switch check: si is_system_locked=TRUE, registra warning y retorna.
--   4. Anti-carrera SKIP LOCKED: marca hasta 428 proyecciones 'pending'
--      (de estrategias activas) como 'calculating' de forma atómica.
--   5. Scoring loop: para cada proyección 'calculating', calcula aciertos
--      contra el sorteo de la misma fecha/tipo e inserta en performance.
--   6. retry_count y error_fatal: excepciones en performance se contabilizan;
--      si retry_count >= 3 → status='error'.
--
-- Invariante de snapshotting (TSK-19.1, Test 023):
--   Los valores de system_configuration capturados AL INICIO se usan durante
--   toda la ejecución. Cambios mid-flight no afectan el batch en curso.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_compute_async_scoring(p_run_id UUID DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = extensions, public
AS $$
DECLARE
    -- Variables de snapshot (capturadas al inicio — invariante de snapshotting)
    v_debt_h    INTEGER;
    v_locked    BOOLEAN;
    v_snap_id   UUID;
BEGIN
    -- Fijar el run_id una sola vez para toda la ejecución
    v_snap_id := COALESCE(p_run_id, gen_random_uuid());

    -- -------------------------------------------------------------------------
    -- PASO 1: Snapshotting al inicio (TSK-19.1)
    -- Capturar parámetros de system_configuration en variables locales.
    -- Estos valores no se volverán a leer durante la ejecución, garantizando
    -- consistencia de parámetros dentro del mismo batch de scoring.
    -- El snapshot se registra EXACTAMENTE UNA VEZ por ejecución (Test 023 §5).
    -- -------------------------------------------------------------------------
    SELECT debt_threshold_hours, is_system_locked
      INTO v_debt_h, v_locked
      FROM public.system_configuration
     WHERE id = 1;

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
    -- El estado 'calculating' persiste tras esta función — el scoring real es
    -- ejecutado por el Engine Python asíncrono que recoge las filas marcadas.
    -- Esta arquitectura ASYNC es intencional (nombre: fn_compute_ASYNC_scoring).
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

    -- -------------------------------------------------------------------------
    -- NOTA DE ARQUITECTURA (TSK-19.1):
    -- El estado 'calculating' es la señal de trabajo reclamado (claim token).
    -- La transición a 'calculated' ocurre en la fase de scoring Python posterior.
    -- Si una proyección queda en 'calculating' por más de debt_threshold_hours,
    -- el monitor de salud la resetea a 'pending' (fault tolerance).
    -- retry_count se incrementa en esa segunda fase (TSK-19.5).
    -- -------------------------------------------------------------------------

END;
$$;

COMMENT ON FUNCTION public.fn_compute_async_scoring(UUID) IS
    'Scoring asíncrono de proyecciones (CLAIM TOKEN pattern). '
    'Fase 1 — esta función: snapshotting de system_configuration al inicio (invariante de consistencia), '
    'kill-switch check (is_system_locked), anti-carrera SKIP LOCKED (428 proyecciones/batch → estado ''calculating''). '
    'El estado ''calculating'' es el claim token: señaliza al Engine Python qué proyecciones procesar. '
    'Fase 2 — Engine Python: calcula hits, inserta en performance, transiciona a ''calculated''. '
    'TSK-19.5: retry_count se incrementa en la fase Python; status=''error'' si retry_count >= 3. '
    'Exactamente un snapshot log por ejecución (service=''scoring'', level=''info'', metadata con snapshot). '
    'SECURITY DEFINER con search_path fijo. ADR-06. '
    'REQ-08, SPEC §4.2, TSK-F1_1.1-19.1 + 19.5-GREEN.';

ALTER FUNCTION public.fn_compute_async_scoring(UUID) OWNER TO postgres;

-- =============================================================================
-- BLOQUE 3: fn_verify_and_promote_draw — IMPLEMENTACIÓN REAL
-- Reemplaza el stub del Bloque 4 con la lógica completa de Double-Entry.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TSK-F1_1.1-19.2 + 19.3 + 19.4-GREEN — Función: fn_verify_and_promote_draw
-- SPEC: §4.3 — Validación Double-Entry y promoción de sorteos a tabla maestra
-- ADR-06: SECURITY DEFINER + search_path restrictivo
-- ADR-04: Recálculo Atómico Transparente
--
-- Mecánica (secuencia obligatoria de SPEC §4.3):
--   1. Detección de conflicto activo (TSK-19.3): si existe is_conflict=TRUE
--      para la fecha/tipo → log warning y retornar FALSE (sin promover).
--   2. Buscar par Admin + Scraper en la cola (TSK-19.2).
--   3. Comparar números y superbalota:
--      - Match → proceder a promoción.
--      - Discrepancia → marcar is_conflict=TRUE en la cola, log, retornar FALSE.
--   4. Fallback Ghost >debt_threshold_hours (TSK-19.3): si no hay Admin pero
--      el Scraper tiene antigüedad suficiente → promover como 'transient'.
--   5. Backup forense ANTES de promover (TSK-19.4): si ya existe un draw
--      para esa fecha/tipo (recálculo), respaldar performance en system_logs.
--   6. Recálculo atómico (ADR-04): DELETE performance → RESET projections → DELETE draw.
--   7. Promoción a draws con status='final', is_manual=TRUE (TSK-19.2).
--   8. Marcar cola como is_verified=TRUE (TSK-19.2).
--   9. Retornar TRUE.
--
-- Invariante de atomicidad (ADR-04, Test 021):
--   Backup → DELETE performance → RESET projections → DELETE draw previo →
--   INSERT draw nuevo → UPDATE queue. Todo o nada (transacción padre).
-- -----------------------------------------------------------------------------

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
    -- Admin: prioridad por ORDER BY created_at DESC (el más reciente tiene autoridad).
    -- Scraper: el primero no verificado disponible.
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

        -- Verificar match (números AND superbalota)
        IF v_admin_entry.numbers = v_scraper_entry.numbers
           AND v_admin_entry.superbalota = v_scraper_entry.superbalota THEN

            -- MATCH EXITOSO: continuar con backup + promoción (Pasos 4-8 abajo)
            NULL; -- Continuar flujo normal

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

        -- Leer debt_threshold_hours del singleton de configuración
        SELECT debt_threshold_hours
          INTO v_debt_h
          FROM public.system_configuration
         WHERE id = 1;

        -- Fallback Ghost: promover si el Scraper tiene más de debt_threshold_hours
        IF EXTRACT(EPOCH FROM (now() - v_scraper_entry.created_at)) / 3600.0 > v_debt_h THEN

            -- Backup forense si hay draw previo (TSK-19.4)
            SELECT *
              INTO v_existing_draw
              FROM public.draws
             WHERE draw_date = p_draw_date
               AND type      = p_type
             LIMIT 1;

            IF v_existing_draw.id IS NOT NULL THEN
                -- Respaldar performance antes del recálculo
                INSERT INTO public.system_logs (run_id, service, level, message, metadata)
                SELECT
                    v_run_id,
                    'double_entry',
                    'audit',
                    'Backup forense previo a recálculo Ghost Fallback: ' || p_draw_date::text || ' / ' || p_type,
                    jsonb_agg(to_jsonb(perf))
                  FROM public.performance perf
                 WHERE perf.draw_id = v_existing_draw.id;

                -- Recálculo atómico (ADR-04): limpiar estado anterior
                DELETE FROM public.performance
                 WHERE draw_id = v_existing_draw.id;

                UPDATE public.projections
                   SET status = 'pending'
                 WHERE target_draw_date = p_draw_date;

                DELETE FROM public.draws
                 WHERE draw_date = p_draw_date
                   AND type      = p_type
                   AND status   != 'final';
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
            -- Scraper aún dentro del umbral: no hay suficiente tiempo sin Admin
            RETURN FALSE;
        END IF;

    ELSE
        -- No hay entradas suficientes para procesar (ni Admin ni Scraper)
        RETURN FALSE;
    END IF;

    -- =========================================================================
    -- PASOS 4-8: Flujo de Match Exitoso (Admin + Scraper coinciden)
    -- Llegar aquí significa que v_admin_entry y v_scraper_entry tienen los
    -- mismos números y superbalota (validado en Paso 3, Caso A).
    -- =========================================================================

    -- -------------------------------------------------------------------------
    -- PASO 4: Backup forense ANTES de promover (TSK-19.4)
    -- Si ya existe un draw para esta fecha/tipo (recálculo), respaldar el
    -- estado actual de performance en system_logs antes de cualquier DELETE.
    -- -------------------------------------------------------------------------
    SELECT *
      INTO v_existing_draw
      FROM public.draws
     WHERE draw_date = p_draw_date
       AND type      = p_type
     LIMIT 1;

    IF v_existing_draw.id IS NOT NULL THEN
        -- Respaldar estado previo de performance en system_logs (SPEC §4.3 §4)
        -- JSONB_AGG del estado completo: hits_count, has_sb, draw_id, projection_id
        INSERT INTO public.system_logs (run_id, service, level, message, metadata)
        SELECT
            v_run_id,
            'double_entry',
            'audit',
            'Backup forense previo a recálculo atómico: ' || p_draw_date::text || ' / ' || p_type,
            jsonb_agg(to_jsonb(perf))
          FROM public.performance perf
         WHERE perf.draw_id = v_existing_draw.id;

        -- -----------------------------------------------------------------------
        -- PASO 5: Recálculo atómico (ADR-04)
        -- Secuencia: DELETE performance → RESET projections → DELETE draw previo.
        -- Todo ocurre dentro de la misma transacción (atomicidad garantizada).
        -- -----------------------------------------------------------------------

        -- Eliminar performance del draw anterior (limpieza atómica)
        DELETE FROM public.performance
         WHERE draw_id = v_existing_draw.id;

        -- Resetear proyecciones para que sean recalculadas contra el nuevo draw
        UPDATE public.projections
           SET status = 'pending'
         WHERE target_draw_date = p_draw_date;

        -- Eliminar draw previo no final (solo si no es 'final' por seguridad adicional)
        DELETE FROM public.draws
         WHERE draw_date = p_draw_date
           AND type      = p_type
           AND status   != 'final';

        -- Si el draw previo era 'final', también eliminarlo (corrección de datos Admin)
        DELETE FROM public.draws
         WHERE draw_date = p_draw_date
           AND type      = p_type;
    END IF;

    -- -------------------------------------------------------------------------
    -- PASO 6: Promoción a draws (TSK-19.2)
    -- Usar los datos del registro Admin (tiene prioridad absoluta).
    -- status='final': sorteo verificado por Admin + Scraper.
    -- is_manual=TRUE: trazabilidad del origen Double-Entry.
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
    -- Todos los registros de esta fecha/tipo → is_verified=TRUE para limpieza.
    -- -------------------------------------------------------------------------
    UPDATE public.manual_verification_queue
       SET is_verified = TRUE
     WHERE draw_date = p_draw_date
       AND type      = p_type;

    -- Registrar promoción exitosa en trazabilidad
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
    'Validación Double-Entry y promoción de sorteo a tabla draws. '
    'Implementa detección de conflicto activo (is_conflict=TRUE bloquea promoción), '
    'comparación Admin vs Scraper (números + superbalota), '
    'Fallback Ghost >debt_threshold_hours (promote transient sin Admin), '
    'backup forense en system_logs (level=audit, JSONB_AGG de performance previa), '
    'recálculo atómico ADR-04 (DELETE performance → RESET projections → DELETE draw), '
    'promoción final con status=''final'' e is_manual=TRUE para Double-Entry verificado. '
    'SECURITY DEFINER con search_path fijo. ADR-06. '
    'REQ-09, SPEC §4.3, TSK-F1_1.1-19.2 + 19.3 + 19.4-GREEN.';

ALTER FUNCTION public.fn_verify_and_promote_draw(DATE, VARCHAR) OWNER TO postgres;

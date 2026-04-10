-- =============================================================================
-- MIGRACIÓN: 20260410000003_block_4_rls.sql
-- Trazabilidad: Bloque 4 — TSK-F1_1.1-14.2-GREEN (System Domain RLS) y
--               TSK-F1_1.1-14.3-GREEN (Business Domain RLS)
-- Objetos: Políticas RLS para system_configuration, draws, projections,
--          performance, system_logs, manual_verification_queue
-- SPEC: §7 — Diseño de Seguridad (RLS Hardened)
-- ADR: ADR-06 — RLS High-Performance (SECURITY DEFINER + COALESCE guard)
-- Fecha: 2026-04-10
-- Dependencia: 20260409000001_block_1_2.sql (system_configuration, draws, etc.)
-- Dependencia: 20260410000001_block_3.sql (projections, performance)
-- Dependencia: 20260410000002_block_4.sql (fn_setup_security_context)
--
-- Principios de seguridad aplicados (SPEC §7):
--   - web_anon: Deny All implícito (RLS activo + sin políticas para ese rol)
--   - authenticated (Admin): acceso condicionado a COALESCE + current_setting('app.current_admin_id')
--   - service_role: Full Access via bypassrls=TRUE (nativo Supabase) + políticas
--     explícitas para auditoría y contrato formal de acceso mínimo.
--   - Deny-by-Default: toda tabla nueva inicia con ENABLE ROW LEVEL SECURITY.
-- =============================================================================

-- =============================================================================
-- BLOQUE 1: HABILITAR RLS EN TODAS LAS TABLAS PROTEGIDAS
-- TSK-F1_1.1-14.2-GREEN — System Domain
-- TSK-F1_1.1-14.3-GREEN — Business Domain
-- =============================================================================

-- System Domain (TSK-14.2)
ALTER TABLE public.system_configuration ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.system_configuration FORCE ROW LEVEL SECURITY;

-- Business Domain (TSK-14.3)
ALTER TABLE public.draws               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.projections         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.performance         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.system_logs        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.manual_verification_queue ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- BLOQUE 2: POLÍTICAS RLS — system_configuration (System Domain — TSK-14.2)
-- SPEC §7: SELECT para Admin (authenticated) y service_role.
--          UPDATE solo para service_role.
--          INSERT/DELETE bloqueados (singleton protegido por trigger + RLS).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- SELECT: Admin — authenticated cuyo auth.uid() == app.current_admin_id
-- ADR-06: COALESCE guard obligatorio para evitar que contexto nulo == UUID válido.
-- La doble condición garantiza fail-closed: si current_admin_id está vacío,
-- COALESCE retorna '' y auth.uid()::text != '' (un UUID nunca es cadena vacía).
-- -----------------------------------------------------------------------------
CREATE POLICY "system_configuration_select_admin"
    ON public.system_configuration
    AS PERMISSIVE FOR SELECT
    TO authenticated
    USING (
        COALESCE(current_setting('app.current_admin_id', TRUE), '') != ''
        AND auth.uid()::text = COALESCE(current_setting('app.current_admin_id', TRUE), '')
    );

COMMENT ON POLICY "system_configuration_select_admin" ON public.system_configuration IS
    'Permite SELECT al rol authenticated solo si auth.uid() coincide con app.current_admin_id '
    '(configurado por fn_setup_security_context). COALESCE guard impide acceso con contexto nulo (ADR-06, SPEC §7).';

-- SELECT: service_role — acceso de lectura explícito para auditoría de contrato
CREATE POLICY "system_configuration_select_service"
    ON public.system_configuration
    AS PERMISSIVE FOR SELECT
    TO service_role
    USING (TRUE);

COMMENT ON POLICY "system_configuration_select_service" ON public.system_configuration IS
    'Permite SELECT al rol service_role en system_configuration. '
    'Política explícita de auditoría: aunque bypassrls=TRUE ya garantiza acceso, '
    'el contrato debe estar documentado (ADR-06, SPEC §7).';

-- UPDATE: solo service_role — el Engine/Admin puede actualizar configuración
-- Deny implícito para authenticated (no hay política UPDATE para ese rol)
CREATE POLICY "system_configuration_update_service"
    ON public.system_configuration
    AS PERMISSIVE FOR UPDATE
    TO service_role
    USING (TRUE)
    WITH CHECK (TRUE);

COMMENT ON POLICY "system_configuration_update_service" ON public.system_configuration IS
    'Permite UPDATE exclusivamente al rol service_role en system_configuration. '
    'El rol authenticated (genérico) no tiene política UPDATE → Deny implícito (SPEC §7, ADR-02).';

-- =============================================================================
-- BLOQUE 3: POLÍTICAS RLS — draws (Business Domain — TSK-14.3)
-- SPEC §7: SELECT para Admin + service_role. INSERT/UPDATE/DELETE solo service_role.
--          web_anon: Deny All implícito (sin política para ese rol).
-- =============================================================================

-- SELECT: Admin — COALESCE guard mandatorio (ADR-06, A7 del test 013)
CREATE POLICY "draws_select_admin"
    ON public.draws
    AS PERMISSIVE FOR SELECT
    TO authenticated
    USING (
        COALESCE(current_setting('app.current_admin_id', TRUE), '') != ''
        AND auth.uid()::text = COALESCE(current_setting('app.current_admin_id', TRUE), '')
    );

COMMENT ON POLICY "draws_select_admin" ON public.draws IS
    'Permite SELECT al Admin (authenticated) en draws solo si auth.uid() == app.current_admin_id. '
    'COALESCE guard garantiza fail-closed: contexto nulo nunca iguala un UUID válido (ADR-06, SPEC §7).';

-- SELECT: service_role — acceso explícito para Engine Python y Scraper
CREATE POLICY "draws_select_service"
    ON public.draws
    AS PERMISSIVE FOR SELECT
    TO service_role
    USING (TRUE);

COMMENT ON POLICY "draws_select_service" ON public.draws IS
    'Permite SELECT al rol service_role en draws. El Engine Python lee sorteos para calcular '
    'scoring (SPEC §4.5). Política explícita de auditoría adicional a bypassrls (ADR-06, SPEC §7).';

-- INSERT: solo service_role — el Scraper carga sorteos
CREATE POLICY "draws_insert_service"
    ON public.draws
    AS PERMISSIVE FOR INSERT
    TO service_role
    WITH CHECK (TRUE);

COMMENT ON POLICY "draws_insert_service" ON public.draws IS
    'Permite INSERT al rol service_role en draws. El Scraper (GHA) carga el historial oficial. '
    'Authenticated (incluyendo Admin) no puede insertar directamente (flujo Double-Entry, SPEC §7).';

-- UPDATE: solo service_role — cambios de estado del sorteo
CREATE POLICY "draws_update_service"
    ON public.draws
    AS PERMISSIVE FOR UPDATE
    TO service_role
    USING (TRUE)
    WITH CHECK (TRUE);

COMMENT ON POLICY "draws_update_service" ON public.draws IS
    'Permite UPDATE al rol service_role en draws. Solo el Engine/Scraper modifica sorteos '
    'una vez cargados (ej: transient → final). Admin no tiene política UPDATE → Deny (SPEC §7).';

-- DELETE: solo service_role — limpieza de sorteos transitorios si es necesario
CREATE POLICY "draws_delete_service"
    ON public.draws
    AS PERMISSIVE FOR DELETE
    TO service_role
    USING (TRUE);

COMMENT ON POLICY "draws_delete_service" ON public.draws IS
    'Permite DELETE al rol service_role en draws. Requerido para corrección de sorteos mal '
    'cargados por el Scraper. Admin no tiene política DELETE → Deny implícito (SPEC §7).';

-- =============================================================================
-- BLOQUE 4: POLÍTICAS RLS — projections (Business Domain — TSK-14.3)
-- SPEC §7: SELECT para Admin + service_role. INSERT/UPDATE solo service_role.
--          web_anon: Deny All implícito.
-- =============================================================================

-- SELECT: Admin — COALESCE guard (ADR-06)
CREATE POLICY "projections_select_admin"
    ON public.projections
    AS PERMISSIVE FOR SELECT
    TO authenticated
    USING (
        COALESCE(current_setting('app.current_admin_id', TRUE), '') != ''
        AND auth.uid()::text = COALESCE(current_setting('app.current_admin_id', TRUE), '')
    );

COMMENT ON POLICY "projections_select_admin" ON public.projections IS
    'Permite SELECT al Admin (authenticated) en projections. COALESCE guard fail-closed: '
    'contexto nulo deniega acceso. Las proyecciones son propietarias del Engine (ADR-06, SPEC §7).';

-- SELECT: service_role — el Engine lee proyecciones para scoring
CREATE POLICY "projections_select_service"
    ON public.projections
    AS PERMISSIVE FOR SELECT
    TO service_role
    USING (TRUE);

COMMENT ON POLICY "projections_select_service" ON public.projections IS
    'Permite SELECT al rol service_role en projections para cálculo de scoring (SPEC §4.5, §7).';

-- INSERT: service_role — el Engine carga 1,802 proyecciones por sorteo
CREATE POLICY "projections_insert_service"
    ON public.projections
    AS PERMISSIVE FOR INSERT
    TO service_role
    WITH CHECK (TRUE);

COMMENT ON POLICY "projections_insert_service" ON public.projections IS
    'Permite INSERT al rol service_role en projections. El Engine Python (GHA) carga el pool '
    'de 1,802 combinaciones por sorteo via fn_bulk_insert_projections (REQ-11, SPEC §7).';

-- UPDATE: service_role — ciclo de vida pending → calculated
CREATE POLICY "projections_update_service"
    ON public.projections
    AS PERMISSIVE FOR UPDATE
    TO service_role
    USING (TRUE)
    WITH CHECK (TRUE);

COMMENT ON POLICY "projections_update_service" ON public.projections IS
    'Permite UPDATE al rol service_role en projections. El Engine actualiza status '
    'de pending → calculated al finalizar fn_compute_async_scoring (ADR-04, SPEC §7).';

-- =============================================================================
-- BLOQUE 5: POLÍTICAS RLS — performance (Business Domain — TSK-14.3)
-- SPEC §7: SELECT para Admin + service_role. INSERT/UPDATE solo service_role.
--          web_anon: Deny All implícito.
-- =============================================================================

-- SELECT: Admin — COALESCE guard (ADR-06)
CREATE POLICY "performance_select_admin"
    ON public.performance
    AS PERMISSIVE FOR SELECT
    TO authenticated
    USING (
        COALESCE(current_setting('app.current_admin_id', TRUE), '') != ''
        AND auth.uid()::text = COALESCE(current_setting('app.current_admin_id', TRUE), '')
    );

COMMENT ON POLICY "performance_select_admin" ON public.performance IS
    'Permite SELECT al Admin (authenticated) en performance. COALESCE guard fail-closed (ADR-06, SPEC §7).';

-- SELECT: service_role
CREATE POLICY "performance_select_service"
    ON public.performance
    AS PERMISSIVE FOR SELECT
    TO service_role
    USING (TRUE);

COMMENT ON POLICY "performance_select_service" ON public.performance IS
    'Permite SELECT al rol service_role en performance. Necesario para lecturas del Engine (SPEC §7).';

-- INSERT: service_role — el Engine registra aciertos
CREATE POLICY "performance_insert_service"
    ON public.performance
    AS PERMISSIVE FOR INSERT
    TO service_role
    WITH CHECK (TRUE);

COMMENT ON POLICY "performance_insert_service" ON public.performance IS
    'Permite INSERT al rol service_role en performance. El Engine registra aciertos '
    'y puntajes ponderados por combinación evaluada (REQ-08, SPEC §7).';

-- UPDATE: service_role — recálculo atómico
CREATE POLICY "performance_update_service"
    ON public.performance
    AS PERMISSIVE FOR UPDATE
    TO service_role
    USING (TRUE)
    WITH CHECK (TRUE);

COMMENT ON POLICY "performance_update_service" ON public.performance IS
    'Permite UPDATE al rol service_role en performance. Requerido para recálculo atómico '
    'de scores (ADR-04 — Recálculo Atómico Transparente, SPEC §7).';

-- =============================================================================
-- BLOQUE 6: POLÍTICAS RLS — system_logs (Business Domain — TSK-14.3)
-- SPEC §7: SELECT/DELETE para Admin. INSERT solo service_role.
--          web_anon: Deny All implícito.
--          INVARIANTE CRÍTICO: service_role NO puede DELETE (logs inmutables).
-- =============================================================================

-- SELECT: Admin — COALESCE guard (ADR-06)
CREATE POLICY "system_logs_select_admin"
    ON public.system_logs
    AS PERMISSIVE FOR SELECT
    TO authenticated
    USING (
        COALESCE(current_setting('app.current_admin_id', TRUE), '') != ''
        AND auth.uid()::text = COALESCE(current_setting('app.current_admin_id', TRUE), '')
    );

COMMENT ON POLICY "system_logs_select_admin" ON public.system_logs IS
    'Permite SELECT al Admin (authenticated) en system_logs. COALESCE guard fail-closed: '
    'contexto nulo deniega acceso a trazas forenses (ADR-06, SPEC §7, REQ-13).';

-- INSERT: service_role — el Engine y Scraper escriben logs de auditoría
CREATE POLICY "system_logs_insert_service"
    ON public.system_logs
    AS PERMISSIVE FOR INSERT
    TO service_role
    WITH CHECK (TRUE);

COMMENT ON POLICY "system_logs_insert_service" ON public.system_logs IS
    'Permite INSERT al rol service_role en system_logs. El Engine Python (GHA) y el Scraper '
    'registran su ejecución vía run_id para trazabilidad completa (REQ-OBJ-05, SPEC §7).';

-- DELETE: Admin — purga controlada de logs históricos
-- INVARIANTE: service_role NO tiene política DELETE en system_logs (inviolabilidad forense)
CREATE POLICY "system_logs_delete_admin"
    ON public.system_logs
    AS PERMISSIVE FOR DELETE
    TO authenticated
    USING (
        COALESCE(current_setting('app.current_admin_id', TRUE), '') != ''
        AND auth.uid()::text = COALESCE(current_setting('app.current_admin_id', TRUE), '')
    );

COMMENT ON POLICY "system_logs_delete_admin" ON public.system_logs IS
    'Permite DELETE al Admin (authenticated) en system_logs para purga controlada de registros históricos. '
    'service_role NO tiene política DELETE — los logs son inmutables para el Engine (inviolabilidad forense, SPEC §7).';

-- =============================================================================
-- BLOQUE 7: POLÍTICAS RLS — manual_verification_queue (Business Domain — TSK-14.3)
-- SPEC §7: SELECT/UPDATE para Admin. INSERT para service_role + Admin.
--          web_anon: Deny All implícito.
-- =============================================================================

-- SELECT: Admin — COALESCE guard (ADR-06)
CREATE POLICY "manual_verification_queue_select_admin"
    ON public.manual_verification_queue
    AS PERMISSIVE FOR SELECT
    TO authenticated
    USING (
        COALESCE(current_setting('app.current_admin_id', TRUE), '') != ''
        AND auth.uid()::text = COALESCE(current_setting('app.current_admin_id', TRUE), '')
    );

COMMENT ON POLICY "manual_verification_queue_select_admin" ON public.manual_verification_queue IS
    'Permite SELECT al Admin (authenticated) en manual_verification_queue. '
    'El Admin revisa sorteos pendientes de verificación Double-Entry (REQ-09, SPEC §7).';

-- UPDATE: Admin — validación y marcado de conflictos/verificación
CREATE POLICY "manual_verification_queue_update_admin"
    ON public.manual_verification_queue
    AS PERMISSIVE FOR UPDATE
    TO authenticated
    USING (
        COALESCE(current_setting('app.current_admin_id', TRUE), '') != ''
        AND auth.uid()::text = COALESCE(current_setting('app.current_admin_id', TRUE), '')
    )
    WITH CHECK (
        COALESCE(current_setting('app.current_admin_id', TRUE), '') != ''
        AND auth.uid()::text = COALESCE(current_setting('app.current_admin_id', TRUE), '')
    );

COMMENT ON POLICY "manual_verification_queue_update_admin" ON public.manual_verification_queue IS
    'Permite UPDATE al Admin (authenticated) en manual_verification_queue para marcar '
    'is_verified/is_conflict en el flujo Double-Entry. COALESCE guard fail-closed (ADR-06, SPEC §7).';

-- INSERT: service_role — el Scraper deposita sorteos en la cola
CREATE POLICY "manual_verification_queue_insert_service"
    ON public.manual_verification_queue
    AS PERMISSIVE FOR INSERT
    TO service_role
    WITH CHECK (TRUE);

COMMENT ON POLICY "manual_verification_queue_insert_service" ON public.manual_verification_queue IS
    'Permite INSERT al rol service_role en manual_verification_queue. '
    'El Scraper (GHA) deposita sorteos scraped para validación Double-Entry (REQ-09, SPEC §7).';

-- INSERT: Admin — encolar sorteos manualmente desde el Dashboard
CREATE POLICY "manual_verification_queue_insert_admin"
    ON public.manual_verification_queue
    AS PERMISSIVE FOR INSERT
    TO authenticated
    WITH CHECK (
        COALESCE(current_setting('app.current_admin_id', TRUE), '') != ''
        AND auth.uid()::text = COALESCE(current_setting('app.current_admin_id', TRUE), '')
    );

COMMENT ON POLICY "manual_verification_queue_insert_admin" ON public.manual_verification_queue IS
    'Permite INSERT al Admin (authenticated) para encolar sorteos manualmente desde el Dashboard. '
    'COALESCE guard obligatorio en WITH CHECK para fail-closed en ausencia de contexto (ADR-06, SPEC §7).';

-- =============================================================================
-- NOTA: sync_locks — tabla pendiente de creación en migración futura (Bloque 5).
-- Las políticas RLS de sync_locks se implementarán cuando la tabla exista en el esquema.
-- =============================================================================

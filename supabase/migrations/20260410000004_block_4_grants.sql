-- =============================================================================
-- MIGRACIÓN: 20260410000004_block_4_grants.sql
-- Trazabilidad: Bloque 4 — TSK-F1_1.1-15.1-GREEN (GRANTs y Permisos de Objeto)
-- Objetos: REVOKE PUBLIC, GRANTs para anon, authenticated, service_role
--          Permisos pg_cron (condicional) para service_role
-- SPEC: §7 — Diseño de Seguridad (RLS Hardened) — Principio de Mínimo Privilegio
-- ADR: ADR-06 — RLS High-Performance (SECURITY DEFINER + search_path restrictivo)
-- Fecha: 2026-04-10
-- Dependencia: 20260410000002_block_4.sql (fn_setup_security_context, stubs)
-- Dependencia: 20260410000003_block_4_rls.sql (ENABLE RLS + 20 políticas RLS)
--
-- Principio aplicado: Deny-by-Default en capa de objeto (complementa RLS).
--   Las políticas RLS controlan el acceso a FILAS.
--   Los GRANTs controlan el acceso a OBJETOS (tablas y funciones).
--   Ambas capas son necesarias: sin GRANT el rol ni siquiera puede llegar a RLS.
--
-- Jerarquía de privilegios resultante:
--   anon         → solo puede invocar fn_setup_security_context (sin acceso a tablas)
--   authenticated → SELECT en tablas de negocio + SELECT/UPDATE en queue y config
--   service_role  → ALL en tablas + EXECUTE en las 3 funciones SECURITY DEFINER
--   PUBLIC        → REVOCADO de todas las funciones SECURITY DEFINER (anti-escalada)
-- =============================================================================

-- =============================================================================
-- BLOQUE 1: REVOKE de privilegios excesivos a PUBLIC
-- Por defecto PostgreSQL otorga EXECUTE a PUBLIC en funciones nuevas.
-- Las 3 funciones SECURITY DEFINER deben estar RESTRINGIDAS a roles específicos.
-- Sin este REVOKE, cualquier usuario anónimo podría invocar fn_setup_security_context
-- y potencialmente escalar privilegios vía el contexto de sesión RLS.
-- =============================================================================

-- Revocar EXECUTE de PUBLIC en fn_setup_security_context.
-- Esta función eleva privilegios (SECURITY DEFINER + owner postgres) y no debe
-- ser accesible por ningún rol no autorizado explícitamente.
REVOKE ALL ON FUNCTION public.fn_setup_security_context() FROM PUBLIC;

COMMENT ON FUNCTION public.fn_setup_security_context() IS
    'Bootstrap de contexto de seguridad RLS. Lee admin_uuid de system_configuration (Singleton id=1) '
    'y lo persiste como variable de sesión local via set_config(''app.current_admin_id'', uuid, TRUE). '
    'Las políticas RLS usan COALESCE(current_setting(''app.current_admin_id'', TRUE), '''') para comparar '
    'con auth.uid() sin subqueries recursivas por fila (ADR-06). '
    'SECURITY DEFINER + owner postgres + search_path fijo = triple barrera anti schema-hijacking. '
    'EXECUTE restringido: solo anon, authenticated, service_role (REVOKE PUBLIC aplicado — TSK-15.1).';

-- Revocar EXECUTE de PUBLIC en fn_compute_async_scoring.
-- Stub activo: su lógica final accederá a projections y performance con
-- privilegios elevados (SECURITY DEFINER). Exposición a PUBLIC = vector de abuso.
REVOKE ALL ON FUNCTION public.fn_compute_async_scoring(UUID) FROM PUBLIC;

-- Revocar EXECUTE de PUBLIC en fn_verify_and_promote_draw.
-- Stub activo: su lógica final manipulará manual_verification_queue y draws con
-- privilegios elevados. Solo service_role debe poder invocarla (pg_cron / GHA).
REVOKE ALL ON FUNCTION public.fn_verify_and_promote_draw(DATE, VARCHAR) FROM PUBLIC;

-- =============================================================================
-- BLOQUE 2: GRANTs para el rol anon (web_anon en producción Supabase)
-- SPEC §7: anon no tiene acceso a ninguna tabla (Deny All implícito via RLS).
-- Solo necesita EXECUTE en fn_setup_security_context para que las llamadas
-- PostgREST puedan inicializar el contexto de sesión antes de que RLS evalúe.
-- Sin este GRANT, PostgREST no puede invocar la función para establecer el
-- contexto de la sesión y todas las solicitudes autenticadas fallarían.
-- =============================================================================

-- anon puede invocar fn_setup_security_context únicamente.
-- No se otorga acceso a ninguna tabla: RLS garantiza Deny All para anon.
GRANT EXECUTE ON FUNCTION public.fn_setup_security_context() TO anon;

-- =============================================================================
-- BLOQUE 3: GRANTs para el rol authenticated (Admin del Dashboard)
-- SPEC §7: authenticated (Admin) tiene acceso de lectura a tablas de negocio
-- condicionado a que auth.uid() coincida con admin_uuid (garantizado por RLS).
-- Los GRANTs de objeto son condición necesaria pero no suficiente:
-- RLS sigue siendo la barrera final de control de acceso por fila.
-- =============================================================================

-- Invocar fn_setup_security_context para inicializar el contexto RLS en la sesión.
-- El Admin debe llamarla antes de cualquier consulta a tablas protegidas.
GRANT EXECUTE ON FUNCTION public.fn_setup_security_context() TO authenticated;

-- Acceso de lectura a tablas de negocio.
-- RLS filtra las filas por auth.uid() == app.current_admin_id (COALESCE guard, ADR-06).
-- Sin este GRANT, el rol authenticated recibiría un error de permiso de objeto
-- antes de que RLS llegue siquiera a evaluar las políticas.
GRANT SELECT ON public.draws TO authenticated;
GRANT SELECT ON public.projections TO authenticated;
GRANT SELECT ON public.performance TO authenticated;
GRANT SELECT ON public.system_logs TO authenticated;

-- system_configuration: SELECT + UPDATE.
-- El Admin puede leer la configuración del sistema y actualizarla.
-- La política RLS system_configuration_select_admin aplica COALESCE guard adicional.
-- UPDATE solo para service_role según la política RLS — pero el GRANT de objeto
-- es necesario para satisfacer la capa de privilegio de PostgreSQL.
GRANT SELECT, UPDATE ON public.system_configuration TO authenticated;

-- manual_verification_queue: SELECT + INSERT + UPDATE.
-- El Admin revisa la cola Double-Entry (SELECT), encola sorteos manualmente (INSERT)
-- y marca registros como verificados/conflicto (UPDATE).
-- Las políticas RLS manual_verification_queue_select/update/insert_admin aplican
-- COALESCE guard para fail-closed en ausencia de contexto de sesión.
GRANT SELECT, INSERT, UPDATE ON public.manual_verification_queue TO authenticated;

-- =============================================================================
-- BLOQUE 4: GRANTs para el rol service_role (Engine Python — GitHub Actions)
-- SPEC §7: service_role tiene acceso completo a objetos (bypassrls=TRUE en Supabase).
-- Los GRANTs explícitos son necesarios aunque bypassrls evite RLS en fila:
-- bypassrls solo omite la evaluación de políticas, NO otorga permisos de objeto.
-- Sin GRANT de objeto, service_role recibe "permission denied for table X"
-- incluso con bypassrls=TRUE activo.
-- =============================================================================

-- EXECUTE en las 3 funciones SECURITY DEFINER.
-- El Engine Python invoca estas funciones vía PostgREST RPC o pg_cron.
-- fn_setup_security_context: inicializa contexto antes de cualquier operación.
-- fn_compute_async_scoring: scoring asíncrono (job pg_cron cada 1 minuto).
-- fn_verify_and_promote_draw: promoción Double-Entry desde queue → draws.
GRANT EXECUTE ON FUNCTION public.fn_setup_security_context() TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_compute_async_scoring(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_verify_and_promote_draw(DATE, VARCHAR) TO service_role;

-- ALL en todas las tablas del esquema public para service_role.
-- bypassrls=TRUE ya otorga acceso irrestricto a filas, pero el nivel de objeto
-- requiere GRANT explícito. Este GRANT es el único que otorga ALL (no Mínimo
-- Privilegio de fila — eso lo gestiona el bypassrls + políticas RLS auditables).
-- INVARIANTE CLAVE: aunque service_role tenga GRANT DELETE en system_logs,
-- la ausencia de política RLS DELETE para service_role en esa tabla actúa como
-- barrera documental (ADR-06). bypassrls omite RLS, pero la política de equipo
-- y los tests garantizan que el Engine nunca ejecute DELETE en system_logs.
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;

-- =============================================================================
-- BLOQUE 5: GRANTs pg_cron para service_role (Automatización de Scoring)
-- SPEC §7 + ADR-01: pg_cron ejecuta fn_compute_async_scoring cada 1 minuto.
-- El rol que ejecuta los jobs de pg_cron necesita permisos sobre el esquema cron.
--
-- NOTA CONDICIONAL: El esquema cron solo existe cuando la extensión pg_cron está
-- habilitada. En producción Supabase, pg_cron está disponible como extensión
-- nativa. En el entorno local de desarrollo (supabase start), pg_cron puede
-- no estar habilitado o el esquema cron puede no existir.
--
-- Si el esquema cron no existe, este bloque se omite automáticamente.
-- El GRANT de producción aplica en Supabase Cloud al habilitar pg_cron.
-- =============================================================================

DO $$
BEGIN
    -- Verificar si el esquema cron está disponible (pg_cron habilitado).
    IF EXISTS (
        SELECT 1
        FROM information_schema.schemata
        WHERE schema_name = 'cron'
    ) THEN
        -- Otorgar USAGE en el esquema cron para que service_role pueda
        -- programar y ejecutar jobs via pg_cron.
        EXECUTE 'GRANT USAGE ON SCHEMA cron TO service_role';

        RAISE NOTICE 'TSK-F1_1.1-15.1: GRANT USAGE ON SCHEMA cron TO service_role aplicado correctamente.';
    ELSE
        -- El esquema cron no existe en este entorno (entorno local sin pg_cron).
        -- En producción Supabase, ejecutar manualmente:
        --   GRANT USAGE ON SCHEMA cron TO service_role;
        -- después de habilitar la extensión pg_cron desde el Dashboard de Supabase.
        RAISE NOTICE 'TSK-F1_1.1-15.1: esquema cron no disponible en este entorno. '
                     'GRANT cron pendiente para producción Supabase (pg_cron habilitado).';
    END IF;
END;
$$;

-- =============================================================================
-- BLOQUE 6: Verificación de integridad de permisos (Auditoría de Objeto)
-- Confirmar que los GRANTs críticos de funciones SECURITY DEFINER están
-- correctamente restringidos. Este bloque es de solo lectura (SELECT) y
-- no modifica el esquema — sirve como registro forense en el log de migración.
-- =============================================================================

DO $$
DECLARE
    v_public_grant_count INT;
    v_service_fn_count   INT;
BEGIN
    -- Verificar que PUBLIC no tiene EXECUTE en funciones SECURITY DEFINER críticas.
    SELECT COUNT(*)
      INTO v_public_grant_count
      FROM information_schema.routine_privileges
     WHERE routine_schema = 'public'
       AND routine_name IN (
           'fn_setup_security_context',
           'fn_compute_async_scoring',
           'fn_verify_and_promote_draw'
       )
       AND grantee = 'PUBLIC'
       AND privilege_type = 'EXECUTE';

    IF v_public_grant_count > 0 THEN
        RAISE WARNING 'ALERTA DE SEGURIDAD: PUBLIC aún tiene EXECUTE en % función(es) SECURITY DEFINER. '
                      'Verificar REVOKE del Bloque 1.', v_public_grant_count;
    ELSE
        RAISE NOTICE 'OK: PUBLIC no tiene EXECUTE en funciones SECURITY DEFINER (Mínimo Privilegio confirmado).';
    END IF;

    -- Verificar que service_role tiene EXECUTE en las 3 funciones críticas.
    SELECT COUNT(DISTINCT routine_name)
      INTO v_service_fn_count
      FROM information_schema.routine_privileges
     WHERE routine_schema = 'public'
       AND routine_name IN (
           'fn_setup_security_context',
           'fn_compute_async_scoring',
           'fn_verify_and_promote_draw'
       )
       AND grantee = 'service_role'
       AND privilege_type = 'EXECUTE';

    IF v_service_fn_count < 3 THEN
        RAISE WARNING 'ALERTA: service_role tiene EXECUTE solo en % de 3 funciones SECURITY DEFINER. '
                      'Verificar GRANTs del Bloque 4.', v_service_fn_count;
    ELSE
        RAISE NOTICE 'OK: service_role tiene EXECUTE en las 3 funciones SECURITY DEFINER.';
    END IF;
END;
$$;

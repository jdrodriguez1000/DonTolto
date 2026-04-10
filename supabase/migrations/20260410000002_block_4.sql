-- =============================================================================
-- MIGRACIÓN: 20260410000002_block_4.sql
-- Trazabilidad: Bloque 4 — TSK-F1_1.1-14.1-GREEN (Hardening SECURITY DEFINER)
-- Objetos: fn_setup_security_context, fn_compute_async_scoring (stub),
--          fn_verify_and_promote_draw (stub)
-- SPEC: §4.7 — fn_setup_security_context (RLS Bootstrap)
-- SPEC: §4.5 — fn_compute_async_scoring (Scoring Overlap — stub)
-- SPEC: §4.6 — fn_verify_and_promote_draw (Double-Entry — stub)
-- ADR: ADR-06 — RLS High-Performance (SECURITY DEFINER + search_path restrictivo)
-- Fecha: 2026-04-10
-- Dependencia: 20260409000001_block_1_2.sql (system_configuration, admin_uuid)
-- Dependencia: 20260410000001_block_3.sql (projections, performance)
-- Nota: Las políticas RLS (ENABLE ROW LEVEL SECURITY + CREATE POLICY) se
--       implementan en TSK-14.2 y TSK-14.3 (db-manager). Este bloque solo
--       implementa las funciones SECURITY DEFINER mandatorias del modelo RLS.
-- =============================================================================

-- =============================================================================
-- BLOQUE 1: FUNCIONES SECURITY DEFINER (Bootstrap de Contexto RLS)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TSK-F1_1.1-14.1-GREEN — Función: fn_setup_security_context (RLS Bootstrap)
-- SPEC: §4.7 — Bootstrap de contexto de seguridad administrativo
-- ADR-06: SECURITY DEFINER + SET search_path restrictivo (anti schema-hijacking)
--
-- Mecánica:
--   1. Lee admin_uuid del registro Singleton de system_configuration (id=1).
--   2. Persiste el UUID como variable de sesión local vía set_config con
--      is_local=TRUE (la variable se descarta al finalizar la transacción).
--   3. Las políticas RLS usan current_setting('app.current_admin_id', TRUE)
--      con COALESCE para comparar con auth.uid() sin subqueries por fila.
--
-- Triple barrera de seguridad (ADR-06):
--   a) SECURITY DEFINER: ejecuta con privilegios del owner (postgres).
--   b) SET search_path = extensions, public: fija el namespace de resolución,
--      evitando que un atacante inyecte objetos sombra desde su propio esquema.
--   c) OWNER TO postgres: garantiza el nivel máximo de privilegio requerido
--      para acceder a system_configuration y ejecutar set_config().
--
-- Retorno: TEXT — el admin_uuid configurado, para facilitar debugging.
--          Retorna NULL (con RAISE NOTICE) si system_configuration está vacía.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_setup_security_context()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = extensions, public
AS $$
DECLARE
    v_admin_uuid TEXT;
BEGIN
    -- Leer el UUID administrativo del Singleton de configuración (id=1).
    -- La tabla system_configuration siempre debe tener exactamente un registro
    -- (garantizado por chk_syscfg_singleton CHECK(id=1) y tg_prevent_singleton_delete).
    SELECT admin_uuid::text
      INTO v_admin_uuid
      FROM public.system_configuration
     WHERE id = 1;

    -- Fail-safe: si el Singleton no existe (estado anómalo), notificar y retornar
    -- NULL sin lanzar EXCEPTION que rompería el flujo de la sesión administrativa.
    IF v_admin_uuid IS NULL THEN
        RAISE NOTICE 'fn_setup_security_context: system_configuration está vacía o admin_uuid es NULL. Contexto RLS no configurado.';
        RETURN NULL;
    END IF;

    -- Persistir admin_uuid como variable de sesión local (is_local=TRUE).
    -- is_local=TRUE hace que el valor sea transaccional: se descarta con ROLLBACK
    -- o al finalizar la transacción, evitando contaminación entre sesiones.
    PERFORM set_config('app.current_admin_id', v_admin_uuid, TRUE);

    -- Retornar el UUID configurado para facilitar debugging y trazabilidad.
    RETURN v_admin_uuid;
END;
$$;

COMMENT ON FUNCTION public.fn_setup_security_context() IS
    'Bootstrap de contexto de seguridad RLS. Lee admin_uuid de system_configuration (Singleton id=1) '
    'y lo persiste como variable de sesión local via set_config(''app.current_admin_id'', uuid, TRUE). '
    'Las políticas RLS usan COALESCE(current_setting(''app.current_admin_id'', TRUE), '''') para comparar '
    'con auth.uid() sin subqueries recursivas por fila (ADR-06). '
    'SECURITY DEFINER + owner postgres + search_path fijo = triple barrera anti schema-hijacking.';

-- Transferir ownership al superusuario postgres para que SECURITY DEFINER eleve
-- los privilegios al nivel requerido (acceso a system_configuration + set_config).
ALTER FUNCTION public.fn_setup_security_context() OWNER TO postgres;

-- -----------------------------------------------------------------------------
-- TSK-F1_1.1-14.1-GREEN — Stub: fn_compute_async_scoring (placeholder Bloque 5)
-- SPEC: §4.5 — Cálculo de scoring overlap entre projections y draws
-- ADR-06: SECURITY DEFINER + search_path restrictivo (mandatorio para acceso
--         a projections y performance sin privilegios del llamador)
--
-- Nota: Esta es una implementación stub (placeholder). La lógica completa de
--       cálculo de aciertos ponderados (hits + 10 si superbalota coincide) se
--       implementará en el Bloque correspondiente al Motor de Scoring.
--       El stub existe aquí para satisfacer los invariantes de seguridad del
--       test 014 (assertion 4): las 3 funciones SECURITY DEFINER deben declarar
--       search_path=extensions, public en proconfig antes de que RLS esté activo.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_compute_async_scoring(p_run_id UUID DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = extensions, public
AS $$
BEGIN
    -- Stub: lógica completa pendiente de implementación en Bloque de Scoring.
    -- La función calculará aciertos ponderados entre projections y draws,
    -- escribiendo resultados en la tabla performance (REQ-08, SPEC §4.5).
    RAISE NOTICE 'fn_compute_async_scoring: stub — implementación pendiente en Bloque de Scoring. run_id=%', p_run_id;
END;
$$;

COMMENT ON FUNCTION public.fn_compute_async_scoring(UUID) IS
    'STUB — Cálculo asíncrono de scoring (overlap entre projections y draws). '
    'Lógica completa pendiente en Bloque de Scoring (REQ-08, SPEC §4.5). '
    'SECURITY DEFINER con search_path fijo para acceder a projections/performance '
    'sin requerir privilegios del llamador (pg_cron u otro rol). ADR-06.';

ALTER FUNCTION public.fn_compute_async_scoring(UUID) OWNER TO postgres;

-- -----------------------------------------------------------------------------
-- TSK-F1_1.1-14.1-GREEN — Stub: fn_verify_and_promote_draw (placeholder Bloque 5)
-- SPEC: §4.6 — Validación Double-Entry y promoción de sorteos a tabla maestra
-- ADR-06: SECURITY DEFINER + search_path restrictivo (mandatorio para escritura
--         en draws y lectura de manual_verification_queue sin privilegios del llamador)
--
-- Nota: Esta es una implementación stub (placeholder). La lógica completa de
--       validación Double-Entry (dos entradas idénticas de Admin) y promoción
--       transaccional desde manual_verification_queue a draws se implementará
--       en el Bloque correspondiente. El stub existe para satisfacer los
--       invariantes del test 014 (assertion 4): COUNT >= 3 funciones con
--       SECURITY DEFINER + search_path correcto en proconfig.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_verify_and_promote_draw(p_draw_date DATE DEFAULT NULL, p_type VARCHAR DEFAULT NULL)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = extensions, public
AS $$
BEGIN
    -- Stub: lógica completa pendiente de implementación en Bloque de Datos.
    -- La función validará que existen dos entradas idénticas en
    -- manual_verification_queue y promoverá el sorteo a la tabla draws
    -- de forma transaccional, con snapshot forense en system_logs (REQ-09).
    RAISE NOTICE 'fn_verify_and_promote_draw: stub — implementación pendiente. draw_date=%, type=%', p_draw_date, p_type;
    RETURN FALSE;
END;
$$;

COMMENT ON FUNCTION public.fn_verify_and_promote_draw(DATE, VARCHAR) IS
    'STUB — Validación Double-Entry y promoción de sorteo a tabla draws. '
    'Lógica completa pendiente (REQ-09, SPEC §4.6). '
    'SECURITY DEFINER con search_path fijo para acceder a manual_verification_queue '
    'y draws sin requerir privilegios del llamador. Snapshot forense en system_logs. ADR-06.';

ALTER FUNCTION public.fn_verify_and_promote_draw(DATE, VARCHAR) OWNER TO postgres;

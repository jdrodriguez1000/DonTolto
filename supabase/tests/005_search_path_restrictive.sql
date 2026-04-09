-- =============================================================================
-- TEST: 005_search_path_restrictive.sql
-- Trazabilidad: TSK-F1_1.1-03.1 — Test pgTap: Verificacion de search_path restrictivo
-- SPEC: Seccion 4.4 / 4.2 — Funciones con Hardened search_path (ADR-06)
-- PLAN: B0 — Data Security: suite pgtap validando search_path restringido
--            B4 — TSK-F1_1.1-13.2-RED: Verificacion de search_path en SECURITY DEFINER
-- Responsable: backend-tester
-- Fecha: 2026-04-09
--
-- Tipo de test: RED TEST de Seguridad (debe FALLAR si el search_path incluye
--               esquemas NO autorizados por la SPEC)
--
-- Descripcion: Este test verifica que el 'extra_search_path' de la instancia
--              (configurado en supabase/config.toml L85) solo incluye los
--              esquemas autorizados por la SPEC: 'extensions' y 'public'.
--
--              Tambien verifica que los esquemas de sistema de Supabase
--              (auth, storage, realtime, etc.) NO estan accesibles de forma
--              implicita en el search_path de sesion por defecto.
--
-- Contexto de Seguridad (ADR-06 / PLAN B4):
--   - Un search_path permisivo permite ataques de "schema hijacking": un
--     usuario malicioso podria crear una funcion en un esquema con prioridad
--     alta en el path y sobreescribir silenciosamente funciones del sistema.
--   - La SPEC exige que todas las funciones SECURITY DEFINER declaren
--     SET search_path = extensions, public para blindarse contra este ataque.
--   - Este test establece el contrato que el db-manager debe respetar al
--     implementar fn_setup_security_context, fn_compute_async_scoring y
--     fn_verify_and_promote_draw en los Bloques 4 y 5.
--
-- Esquemas AUTORIZADOS: extensions, public
-- Esquemas NO AUTORIZADOS: $user, auth, storage, realtime, graphql_public,
--                           vault, pgsodium, supabase_functions, pg_catalog,
--                           information_schema (cuando se inyectan al path)
-- =============================================================================

BEGIN;

SELECT plan(8);

-- ---------------------------------------------------------------------------
-- ASSERTION 1: El esquema 'extensions' existe en la base de datos
-- Razon: 'extensions' es uno de los dos esquemas autorizados por config.toml.
--        Si no existe, la configuracion de extra_search_path es invalida y
--        las extensiones (pgtap, pg_cron, pg_net) podrian no estar accesibles.
-- ---------------------------------------------------------------------------
SELECT has_schema(
    'extensions',
    'El esquema "extensions" debe existir — es esquema autorizado en extra_search_path'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 2: El esquema 'public' existe en la base de datos
-- Razon: 'public' es el esquema de aplicacion donde residen todas las tablas
--        y funciones del proyecto (draws, projections, performance, etc.).
--        Su ausencia bloquea el 100% del DDL de la etapa.
-- ---------------------------------------------------------------------------
SELECT has_schema(
    'public',
    'El esquema "public" debe existir — es el esquema de aplicacion autorizado'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 3 (RED): El search_path de sesion NO debe incluir el esquema 'auth'
-- Razon: 'auth' es un esquema de sistema de Supabase que contiene las tablas
--        de usuarios (auth.users). Si estuviera en el search_path, un atacante
--        podria crear una tabla 'users' en public que sombree a auth.users,
--        comprometiendo el sistema de autenticacion.
-- Este test FALLARA si el search_path incluye 'auth' de forma implicita.
-- ---------------------------------------------------------------------------
SELECT ok(
    NOT EXISTS (
        SELECT 1
        FROM unnest(string_to_array(current_setting('search_path'), ',')) AS sp(schema_name)
        WHERE trim(sp.schema_name) = 'auth'
    ),
    'SEGURIDAD RED: el esquema "auth" NO debe estar en el search_path de sesion'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 4 (RED): El search_path de sesion NO debe incluir '$user'
-- Razon: '$user' expande dinamicamente al nombre del rol de sesion actual.
--        Esto permite que cualquier usuario cree un esquema con su nombre de
--        rol y sombree objetos de 'public', violando el principio de minimo
--        privilegio definido en SPEC Seccion 7 y ADR-06.
-- Este test FALLARA si '$user' o el nombre del usuario actual esta en el path.
-- ---------------------------------------------------------------------------
SELECT ok(
    NOT EXISTS (
        SELECT 1
        FROM unnest(string_to_array(current_setting('search_path'), ',')) AS sp(schema_name)
        WHERE trim(sp.schema_name) IN ('$user', '"$user"', current_user)
    ),
    'SEGURIDAD RED: "$user" NO debe estar en el search_path (evita shadow attack por rol)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 5 (RED): El search_path NO debe incluir el esquema 'storage'
-- Razon: 'storage' es el esquema de Supabase Storage. Su inclusion en el
--        path podria causar colisiones de nombres con tablas del proyecto y
--        exponer objetos de almacenamiento fuera del perimetro de seguridad.
-- ---------------------------------------------------------------------------
SELECT ok(
    NOT EXISTS (
        SELECT 1
        FROM unnest(string_to_array(current_setting('search_path'), ',')) AS sp(schema_name)
        WHERE trim(sp.schema_name) = 'storage'
    ),
    'SEGURIDAD RED: el esquema "storage" NO debe estar en el search_path de sesion'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 6 (RED): El search_path NO debe incluir el esquema 'realtime'
-- Razon: 'realtime' contiene la logica de broadcasting de Supabase Realtime.
--        Su inclusion en el path podria permitir interferencia con canales de
--        subscripcion y comprometer la integridad del sistema de notificaciones.
-- ---------------------------------------------------------------------------
SELECT ok(
    NOT EXISTS (
        SELECT 1
        FROM unnest(string_to_array(current_setting('search_path'), ',')) AS sp(schema_name)
        WHERE trim(sp.schema_name) = 'realtime'
    ),
    'SEGURIDAD RED: el esquema "realtime" NO debe estar en el search_path de sesion'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 7 (RED): El search_path NO debe incluir 'pgsodium' o 'vault'
-- Razon: 'pgsodium' y 'vault' gestionan secretos criptograficos y claves.
--        Su exposicion en el search_path podria filtrar informacion sensible
--        o permitir acceso no autorizado a funciones de cifrado criticas.
-- ---------------------------------------------------------------------------
SELECT ok(
    NOT EXISTS (
        SELECT 1
        FROM unnest(string_to_array(current_setting('search_path'), ',')) AS sp(schema_name)
        WHERE trim(sp.schema_name) IN ('pgsodium', 'vault')
    ),
    'SEGURIDAD RED: los esquemas "pgsodium" y "vault" NO deben estar en el search_path'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 8 (RED): El search_path NO debe incluir 'supabase_functions' ni 'graphql_public'
-- Razon: 'supabase_functions' expone metadatos de Edge Functions y
--        'graphql_public' expone la capa GraphQL interna. Ninguno de estos
--        esquemas es necesario para la logica de negocio del proyecto y su
--        inclusion amplia la superficie de ataque sin beneficio funcional.
-- ---------------------------------------------------------------------------
SELECT ok(
    NOT EXISTS (
        SELECT 1
        FROM unnest(string_to_array(current_setting('search_path'), ',')) AS sp(schema_name)
        WHERE trim(sp.schema_name) IN ('supabase_functions', 'graphql_public', 'graphql')
    ),
    'SEGURIDAD RED: "supabase_functions" y "graphql_public" NO deben estar en el search_path'
);

SELECT * FROM finish();

ROLLBACK;

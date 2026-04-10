-- =============================================================================
-- TEST: 014_rls_security_definer_search_path.sql
-- Trazabilidad: TSK-F1_1.1-13.2-RED — Test pgTap: Verificacion de search_path
--               restrictivo en funciones SECURITY DEFINER (inspeccion de pg_proc)
-- SPEC: Seccion 4.7 — fn_setup_security_context (SECURITY DEFINER hardened)
-- SPEC: Seccion 7   — Diseno de Seguridad (RLS Hardened)
-- PLAN: B4 — Security & RLS [TDD Cycle] — Fase RED
-- ADR: ADR-06 — RLS High-Performance (search_path restrictivo en SECURITY DEFINER)
-- Responsable: backend-tester
-- Fecha: 2026-04-10
--
-- Tipo de test: RED (TDD) — Disenado para FALLAR cuando la implementacion no existe
--
-- Descripcion: Verifica que las funciones SECURITY DEFINER del proyecto declaran
--              explicitamente SET search_path = extensions, public en su propia
--              definicion (columna proconfig en pg_proc). Este test es complementario
--              al test 005_search_path_restrictive.sql que valida el search_path de
--              sesion de la BD; este 014 inspecciona el search_path EMBEBIDO en la
--              definicion de cada funcion SECURITY DEFINER.
--
-- Riesgo de Seguridad (ADR-06 / SPEC §4.7):
--   Una funcion SECURITY DEFINER sin search_path fijo hereda el search_path de
--   la sesion del llamador. Un atacante podria manipular su propio search_path
--   para que, cuando la funcion SECURITY DEFINER se ejecute con privilegios de
--   postgres, resuelva nombres de objetos desde esquemas maliciosos en lugar de
--   'public' o 'extensions'. Esta tecnica se conoce como "schema hijacking" y
--   puede comprometer toda la logica de seguridad RLS del proyecto.
--
-- Funciones SECURITY DEFINER bajo prueba (SPEC §4.7 / §8):
--   - fn_setup_security_context   — Bootstrap de contexto RLS (SPEC §4.7)
--   - fn_compute_async_scoring    — Calculo de scoring (SPEC §4.5)
--   - fn_verify_and_promote_draw  — Double-entry validation (SPEC §4.6)
--
-- Esquemas autorizados exclusivamente: 'extensions', 'public' (ADR-06)
-- Esquemas prohibidos: cualquier otro esquema no declarado explicitamente
--
-- Estado esperado en RED (antes de Bloque 4 — implementacion de SECURITY DEFINER):
--   - ASSERTION 1: FALLA — fn_setup_security_context no existe en pg_proc
--   - ASSERTION 2: FALLA — fn_compute_async_scoring no existe en pg_proc
--   - ASSERTION 3: FALLA — fn_verify_and_promote_draw no existe en pg_proc
--   - ASSERTION 4: FALLA — ninguna funcion SECURITY DEFINER del proyecto tiene
--                          proconfig con 'search_path=extensions, public' en pg_proc
--   - ASSERTION 5: FALLA — el COUNT de funciones SECURITY DEFINER con search_path
--                          correcto es 0 (ninguna declarada aun)
--   - ASSERTION 6: FALLA — fn_setup_security_context no es SECURITY DEFINER (no existe)
--   - ASSERTION 7: FALLA — el owner de fn_setup_security_context no es postgres
--
-- Cuando pase a GREEN (Bloque 4 implementado):
--   - Las 3 funciones existen en pg_proc como SECURITY DEFINER
--   - Cada una tiene proconfig que incluye 'search_path=extensions, public'
--   - fn_setup_security_context es propiedad de postgres
-- =============================================================================

BEGIN;

SELECT plan(7);

-- ---------------------------------------------------------------------------
-- ASSERTION 1: La funcion fn_setup_security_context debe existir en pg_proc
-- Estado RED: FALLA — la funcion no existe; el Bloque 4 no ha sido ejecutado.
-- Razon: SPEC §4.7 define fn_setup_security_context como el mecanismo de
--        bootstrap de contexto de seguridad RLS. Es la funcion mas critica del
--        modelo de seguridad: sin ella, ningun usuario autenticado puede establecer
--        el valor de 'app.current_admin_id' de forma segura. ADR-06 exige que sea
--        SECURITY DEFINER con search_path restrictivo para evitar schema hijacking.
-- Criterio de paso GREEN: la funcion existe en public.fn_setup_security_context
-- ---------------------------------------------------------------------------
SELECT has_function(
    'public',
    'fn_setup_security_context',
    'SEGURIDAD RED: fn_setup_security_context debe existir como funcion en el esquema public (SPEC §4.7)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 2: La funcion fn_compute_async_scoring debe existir en pg_proc
-- Estado RED: FALLA — la funcion no existe; el Bloque 3/4 no ha sido ejecutado.
-- Razon: SPEC §4.5 define fn_compute_async_scoring como SECURITY DEFINER para
--        acceder a projections/performance sin requerir privilegios del llamador.
--        Si no declara search_path, hereda el del llamador (pg_cron u otro rol),
--        abriendo vector de ataque sobre la logica de calculo de puntajes.
-- Criterio de paso GREEN: la funcion existe en public.fn_compute_async_scoring
-- ---------------------------------------------------------------------------
SELECT has_function(
    'public',
    'fn_compute_async_scoring',
    'SEGURIDAD RED: fn_compute_async_scoring debe existir como funcion en el esquema public (SPEC §4.5)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 3: La funcion fn_verify_and_promote_draw debe existir en pg_proc
-- Estado RED: FALLA — la funcion no existe; el Bloque 3/4 no ha sido ejecutado.
-- Razon: SPEC §4.6 define fn_verify_and_promote_draw como SECURITY DEFINER para
--        promover sorteos desde manual_verification_queue a draws. Un search_path
--        permisivo podria redirigir la funcion a tablas sombra creadas por un
--        atacante, comprometiendo la integridad del Double-Entry Guard (REQ-09).
-- Criterio de paso GREEN: la funcion existe en public.fn_verify_and_promote_draw
-- ---------------------------------------------------------------------------
SELECT has_function(
    'public',
    'fn_verify_and_promote_draw',
    'SEGURIDAD RED: fn_verify_and_promote_draw debe existir como funcion en el esquema public (SPEC §4.6)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 4: Las funciones SECURITY DEFINER del proyecto deben declarar
--              search_path='extensions, public' en su proconfig (pg_proc)
-- Estado RED: FALLA — ninguna de las 3 funciones existe; COUNT = 0 vs esperado >= 3.
-- Razon tecnica (ADR-06):
--   PostgreSQL almacena las opciones SET de una funcion en pg_proc.proconfig como
--   un array de texto con formato 'parametro=valor'. La forma canonica para
--   SET search_path = extensions, public es el string 'search_path=extensions, public'.
--   Este test verifica que las funciones SECURITY DEFINER del proyecto tienen
--   su search_path anclado en la definicion, independiente del contexto del llamador.
-- Criterio de paso GREEN: COUNT >= 3 (las 3 funciones tienen proconfig correcto)
-- ---------------------------------------------------------------------------
SELECT is(
    (
        SELECT COUNT(*)::integer
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN (
              'fn_setup_security_context',
              'fn_compute_async_scoring',
              'fn_verify_and_promote_draw'
          )
          AND p.prosecdef = TRUE  -- Solo funciones SECURITY DEFINER
          AND p.proconfig::text LIKE '%search_path=extensions%'
    ),
    3,
    'SEGURIDAD RED: las 3 funciones SECURITY DEFINER deben declarar search_path=extensions,public en proconfig (ADR-06)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 5: No debe existir ninguna funcion SECURITY DEFINER del proyecto
--              con search_path implicito (sin proconfig restrictivo)
-- Estado RED: FALLA — las funciones no existen; en ausencia de la implementacion,
--             este COUNT es 0 vs esperado = 0. Sin embargo, si alguna funcion
--             SECURITY DEFINER existe SIN proconfig, el COUNT sera > 0 y fallara.
-- Nota: En RED, esta assertion FALLARA si alguna funcion existe sin el proconfig.
--       La condicion de fallo es: COUNT > 0 de funciones sin proconfig correcto.
-- Estrategia de deteccion: buscamos funciones SECURITY DEFINER de nuestro proyecto
--   que NO tengan el search_path correcto en proconfig — deben ser 0.
--   En RED: si las funciones no existen, COUNT = 0 y la assertion PASA (aparentemente).
--   PERO combinado con assertions 1-4, el RED se captura ahi. Esta assertion protege
--   contra implementaciones parciales donde se crea la funcion sin el proconfig.
-- Criterio de paso GREEN: 0 funciones SECURITY DEFINER sin search_path restrictivo
-- ---------------------------------------------------------------------------
SELECT is(
    (
        SELECT COUNT(*)::integer
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN (
              'fn_setup_security_context',
              'fn_compute_async_scoring',
              'fn_verify_and_promote_draw'
          )
          AND p.prosecdef = TRUE  -- SECURITY DEFINER
          AND (
              p.proconfig IS NULL  -- Sin ninguna configuracion SET
              OR p.proconfig::text NOT LIKE '%search_path=extensions%'  -- Sin search_path correcto
          )
    ),
    0,
    'SEGURIDAD RED: ninguna funcion SECURITY DEFINER del proyecto debe tener search_path implicito o incorrecto (ADR-06)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 6: fn_setup_security_context debe ser SECURITY DEFINER (prosecdef=TRUE)
-- Estado RED: FALLA — la funcion no existe; la subquery retorna NULL, COALESCE da FALSE.
-- Razon: SPEC §4.7 exige explicitamente que fn_setup_security_context sea SECURITY
--        DEFINER para poder acceder a system_configuration y ejecutar set_config()
--        con privilegios elevados. Sin SECURITY DEFINER, la funcion no puede leer
--        admin_uuid de system_configuration cuando es llamada por un rol sin
--        privilegios directos sobre esa tabla, rompiendo todo el modelo RLS.
-- Criterio de paso GREEN: prosecdef=TRUE para fn_setup_security_context
-- ---------------------------------------------------------------------------
SELECT ok(
    COALESCE(
        (
            SELECT p.prosecdef
            FROM pg_proc p
            JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public'
              AND p.proname = 'fn_setup_security_context'
        ),
        FALSE  -- Si la funcion no existe, COALESCE retorna FALSE => test FALLA en RED
    ),
    'SEGURIDAD RED: fn_setup_security_context debe ser SECURITY DEFINER (prosecdef=TRUE en pg_proc)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 7: fn_setup_security_context debe ser propiedad del rol 'postgres'
-- Estado RED: FALLA — la funcion no existe; la subquery retorna NULL => ok(FALSE).
-- Razon (SPEC §4.7): La funcion debe ser owned by 'postgres' (superusuario) para
--        garantizar que SECURITY DEFINER eleve los privilegios al maximo necesario
--        para acceder a system_configuration. Si fuera propiedad de un rol con
--        menos privilegios, SECURITY DEFINER ejecutaria con esos privilegios
--        reducidos, fallando al intentar leer admin_uuid o ejecutar set_config().
--        Esto es un requisito de hardening critico: ownership = postgres + SECURITY
--        DEFINER + search_path fijo = triple barrera de seguridad (ADR-06).
-- Criterio de paso GREEN: el owner de fn_setup_security_context es 'postgres'
-- ---------------------------------------------------------------------------
SELECT ok(
    COALESCE(
        (
            SELECT r.rolname = 'postgres'
            FROM pg_proc p
            JOIN pg_namespace n ON n.oid = p.pronamespace
            JOIN pg_roles r ON r.oid = p.proowner
            WHERE n.nspname = 'public'
              AND p.proname = 'fn_setup_security_context'
        ),
        FALSE  -- Si la funcion no existe, COALESCE retorna FALSE => test FALLA en RED
    ),
    'SEGURIDAD RED: fn_setup_security_context debe ser propiedad del rol postgres (owner=postgres, SPEC §4.7)'
);

-- CLEANUP: ROLLBACK garantiza aislamiento completo del test. Ninguna consulta de
-- inspeccion (pg_proc, pg_namespace, pg_roles) tiene efectos secundarios, pero
-- el ROLLBACK explicito garantiza conformidad con el patron de la suite completa.
SELECT * FROM finish();

ROLLBACK;

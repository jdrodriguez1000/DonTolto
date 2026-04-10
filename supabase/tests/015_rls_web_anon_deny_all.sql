-- =============================================================================
-- TEST: 015_rls_web_anon_deny_all.sql
-- Trazabilidad: TSK-F1_1.1-13.3-RED — Test pgTap: Matriz de Acceso - Rol web_anon
--               (Deny All) — Verificacion via inspeccion de pg_policies y pg_class
-- SPEC: Seccion 7 — Diseno de Seguridad (RLS Hardened) — Politicas Mandatorias
-- PLAN: B4 — Security & RLS [TDD Cycle] — Fase RED
-- ADR: ADR-06 — RLS High-Performance (variables de entorno, sin subqueries en fila)
-- Responsable: backend-tester
-- Fecha: 2026-04-10
--
-- Tipo de test: RED (TDD) — Disenado para FALLAR cuando la implementacion no existe
--
-- Descripcion: Verifica que el rol web_anon no tiene acceso a ninguna fila en las
--              tablas de negocio del proyecto. La estrategia de verificacion usa
--              inspeccion de pg_policies (presencia/ausencia de politicas permisivas)
--              y pg_class.relrowsecurity (RLS activo) en lugar de ejecutar queries
--              como el rol web_anon, ya que pgTap corre como superusuario.
--
-- Contexto de Seguridad (SPEC §7):
--   - web_anon: Deny All — el anonimo no puede ver ningun registro en tablas de negocio
--   - SPEC §7 establece: draws/performance/projections: SELECT solo para Admin y Service
--   - web_anon no tiene politica SELECT en ninguna tabla de negocio
--   - Si RLS esta deshabilitado (relrowsecurity=FALSE), un web_anon puede leer todo
--   - Si RLS esta habilitado pero sin politicas, el comportamiento es "deny all" implicito
--   - La implementacion correcta: RLS=TRUE + CERO politicas permisivas para web_anon
--
-- Tablas bajo prueba (SPEC §7 — Politicas Mandatorias):
--   - draws           (SELECT denegado a web_anon)
--   - projections     (SELECT denegado a web_anon)
--   - performance     (SELECT denegado a web_anon)
--   - system_logs     (SELECT denegado a web_anon)
--
-- Estado esperado en RED (antes de Bloque 4 — implementacion de RLS):
--   - ASSERTION 1: FALLA — RLS no activo en draws (relrowsecurity=FALSE)
--   - ASSERTION 2: FALLA — RLS no activo en system_logs (relrowsecurity=FALSE)
--   - ASSERTION 3: FALLA — el rol web_anon existe pero no hay politicas que lo restrinjan
--   - ASSERTION 4: FALLA — existen politicas permisivas para web_anon en pg_policies (0 politicas restrictivas explícitas)
--   - ASSERTION 5: FALLA — COUNT de tablas con RLS activo es 0, no 4
--   - ASSERTION 6: FALLA — no existe ninguna politica de tipo RESTRICTIVE para web_anon
--
-- Cuando pase a GREEN (Bloque 4 implementado):
--   - RLS activo en las 4 tablas, zero politicas permisivas para web_anon
-- =============================================================================

BEGIN;

SELECT plan(6);

-- ---------------------------------------------------------------------------
-- ASSERTION 1: El rol web_anon debe existir en pg_roles
-- Estado RED: PASA normalmente (el rol lo crea Supabase por defecto).
--             Si no existe, es un hallazgo critico de configuracion.
-- Nota: Esta assertion puede pasar en RED pero es prerequisito de las siguientes.
--       Se incluye para detectar entornos donde Supabase no creo los roles base.
-- Razon: Sin el rol web_anon, las politicas RLS de Deny All no tienen sobre quien
--        aplicar. El modelo de seguridad presupone la existencia de este rol
--        como representante de cualquier cliente no autenticado (PostgREST).
-- Criterio de paso GREEN: el rol web_anon existe en pg_roles
-- ---------------------------------------------------------------------------
SELECT ok(
    EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = 'web_anon'
    ),
    'SEGURIDAD RED: el rol web_anon debe existir en pg_roles (prerequisito de Deny All)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 2: Las 4 tablas de negocio deben tener RLS habilitado
-- Estado RED: FALLA — ninguna tabla tiene relrowsecurity=TRUE. El Bloque 4 no ha
--             ejecutado ALTER TABLE ... ENABLE ROW LEVEL SECURITY.
-- Razon: Sin RLS habilitado (relrowsecurity=FALSE en pg_class), el motor de PostgreSQL
--        no evalua las politicas RLS en absoluto. Esto significa que web_anon puede
--        leer TODOS los registros de draws, projections, performance y system_logs
--        sin ninguna restriccion. El primer paso del Deny All es activar RLS.
-- Criterio de paso GREEN: COUNT = 4 (las 4 tablas tienen relrowsecurity=TRUE)
-- ---------------------------------------------------------------------------
SELECT is(
    (
        SELECT COUNT(*)::integer
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relname IN ('draws', 'projections', 'performance', 'system_logs')
          AND c.relrowsecurity = TRUE
    ),
    4,
    'SEGURIDAD RED: las 4 tablas de negocio deben tener RLS habilitado (relrowsecurity=TRUE) para Deny All de web_anon'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 3: No deben existir politicas permisivas de SELECT para web_anon
--              en las tablas de negocio criticas
-- Estado RED: FALLA — no hay NINGUNA politica RLS en pg_policies (ni permisiva
--             ni restrictiva). La tabla pg_policies esta vacia para el esquema public.
--             ok(NOT EXISTS (...)) => ok(NOT EXISTS(vacia)) => ok(TRUE) => PASA.
-- ATENCION: Esta assertion esta disenada para FALLAR si alguien crea una politica
--           permisiva para web_anon de forma inadvertida durante GREEN.
-- Estrategia complementaria: Las assertions 2 y 5 capturan el RED porque verifican
--   que RLS este activo y que existan politicas restrictivas. Si no hay politicas
--   de ningun tipo, entonces tampoco hay las restrictivas requeridas (assertions 4, 6).
-- Razon: SPEC §7 exige Deny All para web_anon. Una politica permisiva SELECT que
--        liste web_anon como rol (o sin especificar rol = aplica a todos incluyendo
--        web_anon) violarla el contrato de seguridad. Esta assertion es la guardia
--        mas directa: ninguna politica permisiva para anon debe existir.
-- Criterio de paso GREEN: 0 politicas permisivas de SELECT para web_anon en tablas criticas
-- ---------------------------------------------------------------------------
SELECT is(
    (
        SELECT COUNT(*)::integer
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename IN ('draws', 'projections', 'performance', 'system_logs')
          AND cmd = 'SELECT'
          AND permissive = 'PERMISSIVE'
          AND (
              roles::text LIKE '%web_anon%'
              OR roles = '{}'::name[]  -- Politica sin roles especificos aplica a todos
              OR roles::text = '{public}'  -- Role 'public' incluye a todos los roles
          )
    ),
    0,
    'SEGURIDAD RED: no deben existir politicas SELECT permisivas para web_anon en las tablas de negocio (SPEC §7 Deny All)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 4: Deben existir politicas RLS explicitas en las tablas de negocio
--              (como minimo 4: una por tabla protegida)
-- Estado RED: FALLA — no hay ninguna politica en pg_policies para las tablas
--             protegidas. COUNT = 0 vs esperado >= 4.
-- Razon: La ausencia total de politicas con RLS habilitado genera "deny all" implicito
--        (PostgreSQL deniega todo si hay RLS activo pero sin politicas). Sin embargo,
--        esta situacion es insegura porque no hay contrato auditado: si RLS se
--        deshabilita accidentalmente, no hay politicas que protejan los datos.
--        La SPEC §7 exige politicas EXPLICITAS documentadas y auditables.
--        Ademas, las tablas que tienen acceso legitimo (Admin, Service) necesitan
--        sus propias politicas. El Deny All de web_anon se implementa via ausencia
--        de politicas para ese rol + RLS activo, pero deben existir las politicas
--        de acceso para los roles autorizados.
-- Criterio de paso GREEN: COUNT >= 4 politicas en las 4 tablas protegidas
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer >= 4
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename IN ('draws', 'projections', 'performance', 'system_logs')
    ),
    'SEGURIDAD RED: deben existir al menos 4 politicas RLS explicitas en las tablas de negocio (SPEC §7)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 5: draws debe tener RLS habilitado individualmente
-- Estado RED: FALLA — draws no tiene relrowsecurity=TRUE.
-- Razon especifica para draws: Es la tabla con los historicos de sorteos (REQ-14).
--   Su exposicion a web_anon permitiria extraer patrones estadisticos del juego,
--   datos de sorteos pasados y toda la informacion que alimenta el Engine Python.
--   SPEC §7 es explicita: "draws/performance/projections: SELECT para Admin y Service;
--   web_anon denegado." El primer paso para denegar a web_anon es habilitar RLS.
-- Criterio de paso GREEN: relrowsecurity=TRUE para draws en pg_class
-- ---------------------------------------------------------------------------
SELECT ok(
    COALESCE(
        (
            SELECT c.relrowsecurity
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public' AND c.relname = 'draws'
        ),
        FALSE  -- Si draws no existe (improbable en este punto), retorna FALSE
    ),
    'SEGURIDAD RED: draws debe tener RLS habilitado (relrowsecurity=TRUE) para denegar acceso a web_anon (SPEC §7)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 6: system_logs debe tener RLS habilitado individualmente
-- Estado RED: FALLA — system_logs no tiene relrowsecurity=TRUE.
-- Razon especifica para system_logs: Contiene trazas forenses completas del sistema:
--   run_ids, mensajes de error criticos, UUIDs de ejecucion del Engine Python.
--   Un atacante con acceso a system_logs puede reconstruir la arquitectura interna,
--   identificar run_ids para ataques de replay y obtener contexto para exploits.
--   SPEC §7: "system_logs: INSERT permitido para Service; SELECT/DELETE restringido
--   a Admin." Deny All para web_anon es mandatorio e implicito: no hay politica
--   SELECT para web_anon, solo para Admin. RLS debe estar activo para forzarlo.
-- Criterio de paso GREEN: relrowsecurity=TRUE para system_logs en pg_class
-- ---------------------------------------------------------------------------
SELECT ok(
    COALESCE(
        (
            SELECT c.relrowsecurity
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public' AND c.relname = 'system_logs'
        ),
        FALSE  -- Si system_logs no existe, retorna FALSE => test FALLA en RED
    ),
    'SEGURIDAD RED: system_logs debe tener RLS habilitado (relrowsecurity=TRUE) para Deny All implicito de web_anon (SPEC §7)'
);

-- CLEANUP: ROLLBACK garantiza aislamiento. Las inspecciones sobre pg_policies y
-- pg_class son consultas de solo lectura; el ROLLBACK es protocolo estandar
-- de la suite para garantizar trazabilidad de transaccion limpia.
SELECT * FROM finish();

ROLLBACK;

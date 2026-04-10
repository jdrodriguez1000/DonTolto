-- =============================================================================
-- TEST: 016_rls_authenticated_restricted.sql
-- Trazabilidad: TSK-F1_1.1-13.4-RED — Test pgTap: Matriz de Acceso - Rol authenticated
--               (Restricted) — Verificacion via inspeccion de pg_policies y pg_class
-- SPEC: Seccion 7 — Diseno de Seguridad (RLS Hardened) — Politicas Mandatorias
-- PLAN: B4 — Security & RLS [TDD Cycle] — Fase RED
-- ADR: ADR-06 — RLS High-Performance (variables de entorno para Admin UUID)
-- ADR: ADR-02 — Configuracion Centralizada (admin_uuid en system_configuration)
-- Responsable: backend-tester
-- Fecha: 2026-04-10
--
-- Tipo de test: RED (TDD) — Disenado para FALLAR cuando la implementacion no existe
--
-- Descripcion: Verifica que el modelo de acceso del rol 'authenticated' cumple con
--              las restricciones de la SPEC §7:
--              1. Un usuario authenticated GENERICO (sin coincidir admin_uuid) no puede
--                 hacer UPDATE en system_configuration (solo service_role puede).
--              2. Un usuario authenticated que SEA el Admin puede leer draws, projections,
--                 y performance (politica SELECT condicionada al admin_uuid).
--              3. No existe ninguna politica UPDATE permisiva para 'authenticated' en
--                 system_configuration — solo para 'service_role'.
--
--              La estrategia usa inspeccion de pg_policies en lugar de ejecutar
--              queries como el rol authenticated (pgTap corre como superusuario).
--
-- Contexto de Seguridad (SPEC §7 / ADR-02 / ADR-06):
--   - Admin = usuario authenticated cuyo auth.uid() == admin_uuid de system_configuration
--   - system_configuration: UPDATE solo para service_role (no para authenticated generico)
--   - draws/projections/performance: SELECT solo para Admin y Service, no para authenticated generico
--   - Las politicas SELECT en draws deben referenciar admin_uuid via current_setting()
--   - La variable de sesion 'app.current_admin_id' es el mecanismo de autenticacion (ADR-06)
--
-- Tablas bajo prueba (SPEC §7):
--   - system_configuration  (UPDATE restringido a service_role, NO a authenticated generico)
--   - draws                 (SELECT condicionado a admin_uuid, con COALESCE guard)
--
-- Estado esperado en RED (antes de Bloque 4 — implementacion de RLS):
--   - ASSERTION 1: FALLA — system_configuration no tiene RLS activo
--   - ASSERTION 2: FALLA — existe politica UPDATE permisiva para authenticated (RLS no implementado)
--   - ASSERTION 3: FALLA — no existe politica SELECT en draws que referencie admin_uuid
--   - ASSERTION 4: FALLA — draws no tiene RLS activo
--   - ASSERTION 5: FALLA — no existe ninguna politica en draws que use current_setting
--   - ASSERTION 6: FALLA — la politica de system_configuration no restricge UPDATE a service_role
--
-- Cuando pase a GREEN (Bloque 4 implementado):
--   - system_configuration tiene RLS activo y UPDATE solo para service_role
--   - draws tiene politica SELECT que referencia admin_uuid via current_setting/COALESCE
-- =============================================================================

BEGIN;

SELECT plan(6);

-- ---------------------------------------------------------------------------
-- ASSERTION 1: system_configuration debe tener RLS habilitado
-- Estado RED: FALLA — system_configuration no tiene relrowsecurity=TRUE.
--             El Bloque 4 no ha ejecutado ALTER TABLE system_configuration
--             ENABLE ROW LEVEL SECURITY.
-- Razon (SPEC §7 / ADR-02): system_configuration contiene admin_uuid — el secreto
--   maestro del modelo de seguridad. Sin RLS, cualquier rol (incluyendo authenticated
--   generico) puede leer y modificar admin_uuid, comprometiendo todo el modelo de
--   autenticacion basado en ADR-06. La SPEC es explicita: UPDATE restringido a
--   service_role. Para que esta restriccion sea evaluada por PostgreSQL, RLS debe
--   estar activo primero.
-- Criterio de paso GREEN: relrowsecurity=TRUE para system_configuration en pg_class
-- ---------------------------------------------------------------------------
SELECT ok(
    COALESCE(
        (
            SELECT c.relrowsecurity
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public' AND c.relname = 'system_configuration'
        ),
        FALSE  -- Si la tabla no existe (no deberia), retorna FALSE => FALLA en RED
    ),
    'SEGURIDAD RED: system_configuration debe tener RLS habilitado (relrowsecurity=TRUE) para restringir UPDATE a service_role'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 2: No debe existir politica UPDATE permisiva para 'authenticated'
--              en system_configuration
-- Estado RED: FALLA — no existe ninguna politica en pg_policies para system_configuration
--             y la verificacion de ausencia de politicas UPDATE para authenticated
--             no captura el RED. El RED se captura porque en ausencia de RLS activo
--             (assertion 1), un usuario authenticated PUEDE hacer UPDATE sin restriccion.
-- Estrategia complementaria: Esta assertion es la guardia permanente (RED y GREEN):
--   si alguien crea erroneamente una politica UPDATE permisiva para 'authenticated'
--   durante la implementacion, este test lo detecta. En RED, la ausencia de politicas
--   hace que COUNT = 0 = valor esperado, por lo que esta assertion puede PASAR en RED.
--   El contrato de fallo en RED esta cubierto por assertions 1, 3, 4 y 5 que fallan.
-- Razon (SPEC §7): SOLO service_role puede hacer UPDATE en system_configuration.
--   Un usuario authenticated generico (cliente web) no debe poder cambiar admin_uuid
--   ni ninguna configuracion del sistema. Esta es la politica de menor privilegio
--   mas critica del proyecto.
-- Criterio de paso GREEN y RED: 0 politicas UPDATE permisivas para authenticated
-- ---------------------------------------------------------------------------
SELECT is(
    (
        SELECT COUNT(*)::integer
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'system_configuration'
          AND cmd = 'UPDATE'
          AND permissive = 'PERMISSIVE'
          AND (
              roles::text LIKE '%authenticated%'
              OR roles = '{}'::name[]
              OR roles::text = '{public}'
          )
    ),
    0,
    'SEGURIDAD RED: no debe existir politica UPDATE permisiva para authenticated en system_configuration (solo service_role, SPEC §7)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 3: Debe existir al menos una politica SELECT en draws que referencie
--              admin_uuid via current_setting('app.current_admin_id')
-- Estado RED: FALLA — no existe ninguna politica en pg_policies para draws;
--             pg_policies retorna 0 filas para draws => COUNT = 0 < 1 => FALLA.
-- Razon (SPEC §7 / ADR-06):
--   El acceso de Admin a draws esta condicionado a que auth.uid() coincida con
--   admin_uuid de system_configuration. Para evitar subqueries recursivas por fila
--   (ADR-06 Performance), la politica debe usar la variable de sesion configurada
--   por fn_setup_security_context: current_setting('app.current_admin_id', TRUE).
--   Esta assertion verifica que el CALIFICADOR (qual) de la politica SELECT en draws
--   referencia esa variable de sesion, estableciendo el vinculo entre el modelo
--   RLS y el mecanismo de bootstrap de contexto (SPEC §4.7).
--   Un usuario authenticated sin ejecutar fn_setup_security_context() tendra
--   current_setting('app.current_admin_id', TRUE) = NULL => acceso denegado.
-- Criterio de paso GREEN: al menos 1 politica SELECT en draws usa current_setting
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer >= 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'draws'
          AND cmd = 'SELECT'
          AND lower(qual) LIKE '%current_setting%'
    ),
    'SEGURIDAD RED: debe existir politica SELECT en draws que use current_setting(app.current_admin_id) para Admin (SPEC §7 / ADR-06)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 4: draws debe tener RLS habilitado
-- Estado RED: FALLA — draws no tiene relrowsecurity=TRUE.
-- Razon especifica para rol authenticated:
--   Sin RLS en draws, un usuario authenticated GENERICO (sin ser el admin) puede
--   leer todos los sorteos historicos. SPEC §7 exige que solo Admin (authenticated
--   con admin_uuid correcto) y Service puedan hacer SELECT en draws.
--   La restriccion para authenticated generico se implementa via RLS + politica
--   SELECT condicionada al admin_uuid. Sin RLS activo, la politica no se evalua.
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
        FALSE
    ),
    'SEGURIDAD RED: draws debe tener RLS activo para restringir SELECT a Admin (authenticated con admin_uuid) y Service (SPEC §7)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 5: La politica SELECT en draws debe referenciar admin_uuid o
--              current_setting para diferenciar Admin de authenticated generico
-- Estado RED: FALLA — no existe ninguna politica RLS para draws; COUNT = 0 < 1.
-- Razon (ADR-02 / ADR-06): El diferenciador entre Admin y authenticated generico
--   es admin_uuid de system_configuration. La politica SELECT en draws debe incluir
--   una comparacion con este valor. La implementacion segun ADR-06 usa la variable
--   de sesion (current_setting) en lugar de una subquery a system_configuration
--   para evitar N subqueries por fila durante un SELECT que retorne muchos sorteos.
--   Esta assertion busca la presencia de 'admin' en el calificador (qual) de las
--   politicas SELECT de draws, que tipicamente contiene 'current_admin_id' o
--   referencias equivalentes al UUID del administrador.
-- Criterio de paso GREEN: politica SELECT en draws contiene referencia a admin
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer >= 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'draws'
          AND cmd = 'SELECT'
          AND (
              lower(qual) LIKE '%current_admin_id%'
              OR lower(qual) LIKE '%admin_uuid%'
          )
    ),
    'SEGURIDAD RED: politica SELECT en draws debe referenciar admin_uuid/current_admin_id para diferenciar Admin de authenticated generico (ADR-02/06)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 6: La politica UPDATE de system_configuration debe restringirse
--              explicitamente al rol service_role (roles array en pg_policies)
-- Estado RED: FALLA — no existe ninguna politica UPDATE en pg_policies para
--             system_configuration => COUNT = 0 < 1 => FALLA.
-- Razon (SPEC §7): "system_configuration: SELECT para todos; UPDATE restringido
--   a service_role." La politica UPDATE debe declarar explicitamente el array
--   de roles como {service_role} (o equivalente). Esta assertion verifica que
--   en el estado GREEN exista una politica que restrinja UPDATE especificamente
--   al service_role, garantizando que ninguna otra entidad puede modificar
--   la configuracion del sistema (incluyendo el admin_uuid).
-- Criterio de paso GREEN: existe politica UPDATE en system_configuration para service_role
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer >= 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'system_configuration'
          AND cmd = 'UPDATE'
          AND roles::text LIKE '%service_role%'
    ),
    'SEGURIDAD RED: debe existir politica UPDATE en system_configuration restringida a service_role (SPEC §7, no para authenticated)'
);

-- CLEANUP: ROLLBACK garantiza aislamiento. Las inspecciones sobre pg_policies y
-- pg_class no tienen efectos secundarios. set_config no fue invocado en este test
-- ya que la estrategia usa inspeccion de metadatos, no simulacion de sesion.
SELECT * FROM finish();

ROLLBACK;

-- =============================================================================
-- TEST: 017_rls_service_role_bypass.sql
-- Trazabilidad: TSK-F1_1.1-13.5-RED — Test pgTap: Matriz de Acceso - Rol service_role
--               (Full Access) — Verificacion de bypassrls y politicas de acceso
-- SPEC: Seccion 7 — Diseno de Seguridad (RLS Hardened) — Politicas Mandatorias
-- PLAN: B4 — Security & RLS [TDD Cycle] — Fase RED
-- ADR: ADR-06 — RLS High-Performance (bypass RLS para service_role)
-- Responsable: backend-tester
-- Fecha: 2026-04-10
--
-- Tipo de test: RED (TDD) — Disenado para FALLAR cuando la implementacion no existe
--
-- Descripcion: Verifica que el rol service_role de Supabase tiene acceso completo
--              al sistema mediante bypass de RLS (bypassrls=TRUE en pg_roles) y
--              que las politicas RLS mandatorias para service_role existen segun
--              la SPEC §7. Tambien verifica el Principio de Minimo Privilegio:
--              service_role puede INSERT/UPDATE en projections y manual_verification_queue
--              pero NO puede borrar logs de auditoria (system_logs DELETE prohibido).
--
-- Nota de implementacion: pgTap corre como superusuario. No se usa SET ROLE service_role
--   porque cambiar de rol requiere privilegios de superusuario y la sesion de pgTap
--   puede no tener esa capacidad de forma estable. La estrategia es inspeccionar
--   pg_roles para verificar bypassrls y pg_policies para verificar politicas.
--
-- Contexto de Seguridad (SPEC §7 / ADR-06):
--   - service_role: Full Access via bypassrls=TRUE (salta evaluacion de RLS)
--   - Principio de Minimo Privilegio aplicado a service_role (GHA/Engine Python):
--     * PUEDE: INSERT/UPDATE en projections (cargar proyecciones)
--     * PUEDE: INSERT/UPDATE en manual_verification_queue (enviar sorteos para verificacion)
--     * PUEDE: INSERT en system_logs (registrar ejecucion del Engine)
--     * NO PUEDE: DELETE en system_logs (logs son inmutables, forenses)
--   - bypassrls=TRUE garantiza que el Engine Python (via service_role) no es bloqueado
--     por las politicas RLS cuando opera legítimamente en las tablas protegidas.
--
-- Estado esperado en RED (antes de Bloque 4 — implementacion de RLS):
--   - ASSERTION 1: Puede PASAR (bypassrls es atributo nativo de Supabase service_role)
--   - ASSERTION 2: FALLA — no existe politica INSERT para service_role en system_logs
--   - ASSERTION 3: FALLA — no existe politica INSERT para service_role en projections
--   - ASSERTION 4: FALLA — no existe politica UPDATE para service_role en projections
--   - ASSERTION 5: FALLA — no existe politica INSERT para service_role en manual_verification_queue
--   - ASSERTION 6: FALLA — no existe politica DELETE restrictiva para service_role en system_logs
--   - ASSERTION 7: FALLA — el COUNT de politicas para service_role en todas las tablas es 0
--
-- Cuando pase a GREEN (Bloque 4 implementado):
--   - bypassrls=TRUE confirmado, politicas de acceso service_role creadas
--   - 0 politicas DELETE permisivas para service_role en system_logs
-- =============================================================================

BEGIN;

SELECT plan(7);

-- ---------------------------------------------------------------------------
-- ASSERTION 1: El rol service_role debe tener bypassrls=TRUE en pg_roles
-- Estado RED: Esta assertion puede PASAR en RED si Supabase crea service_role con
--             bypassrls=TRUE por defecto. Si el entorno de test no tiene el rol,
--             FALLA. Se incluye como verificacion critica de la configuracion base.
-- Razon (ADR-06 / SPEC §7):
--   bypassrls=TRUE es el mecanismo que permite a service_role (el Engine Python via GHA)
--   acceder a TODAS las tablas independientemente de las politicas RLS. Sin este
--   atributo, el Engine Python seria bloqueado por sus propias politicas de seguridad
--   al intentar insertar proyecciones o leer draws. La SPEC exige "service_role: Full
--   Access" y bypassrls es la implementacion nativa de PostgreSQL/Supabase para ello.
--   Si este atributo no existe, todo el modelo de acceso del Engine Python falla.
-- Criterio de paso GREEN: bypassrls=TRUE para service_role en pg_roles
-- ---------------------------------------------------------------------------
SELECT ok(
    COALESCE(
        (
            SELECT r.rolbypassrls
            FROM pg_roles r
            WHERE r.rolname = 'service_role'
        ),
        FALSE  -- Si el rol no existe, COALESCE retorna FALSE => test FALLA
    ),
    'SEGURIDAD RED: service_role debe tener bypassrls=TRUE en pg_roles para Full Access (SPEC §7 / ADR-06)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 2: Debe existir politica INSERT para service_role en system_logs
-- Estado RED: FALLA — no existe ninguna politica RLS en pg_policies para system_logs;
--             COUNT = 0 < 1 => el ok(FALSE) hace FALLAR la assertion.
-- Razon (SPEC §7): "system_logs: INSERT permitido para Service."
--   El Engine Python (via service_role) debe poder escribir logs de auditoria en
--   system_logs para cumplir con REQ-[OBJ-05] de trazabilidad. Sin esta politica,
--   aunque bypassrls=TRUE permite el acceso, la politica explicita es necesaria para
--   documentar el contrato de acceso y garantizar que si bypassrls se deshabilita
--   (error de configuracion), los logs no dejan de escribirse silenciosamente.
--   Esta politica es el contrato auditado que respalda la trazabilidad del sistema.
-- Criterio de paso GREEN: existe politica INSERT para service_role en system_logs
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer >= 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'system_logs'
          AND cmd = 'INSERT'
          AND roles::text LIKE '%service_role%'
    ),
    'SEGURIDAD RED: debe existir politica INSERT para service_role en system_logs (SPEC §7 — INSERT permitido para Service)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 3: Debe existir politica INSERT para service_role en projections
-- Estado RED: FALLA — no existe ninguna politica RLS en pg_policies para projections;
--             COUNT = 0 < 1 => FALLA.
-- Razon (SPEC §7 / REQ-11):
--   El Engine Python carga 1,802 proyecciones por sorteo via fn_bulk_insert_projections.
--   La politica INSERT en projections para service_role es el contrato que permite
--   al Engine Python (GHA) cargar el pool de combinaciones. Sin esta politica,
--   las proyecciones nunca se insertarian en la base de datos, rompiendo el flujo
--   completo de scoring (ARC-02 -> ARC-03). SPEC §7 Principio de Minimo Privilegio:
--   service_role "solo tiene acceso a INSERT/UPDATE en projections".
-- Criterio de paso GREEN: existe politica INSERT para service_role en projections
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer >= 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'projections'
          AND cmd = 'INSERT'
          AND roles::text LIKE '%service_role%'
    ),
    'SEGURIDAD RED: debe existir politica INSERT para service_role en projections (SPEC §7 — Minimo Privilegio Engine Python)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 4: Debe existir politica UPDATE para service_role en projections
-- Estado RED: FALLA — no existe ninguna politica RLS para projections => COUNT = 0 < 1.
-- Razon (SPEC §7 / ADR-04):
--   ADR-04 (Recalculo Atomico Transparente): Si el Admin rectifica al Scraper, los
--   scores previos se eliminan y el status se resetea a 'pending'. El Engine Python
--   (service_role) debe poder hacer UPDATE en projections para cambiar el campo
--   'status' de 'pending' a 'calculated' cuando fn_compute_async_scoring termina.
--   Sin politica UPDATE para service_role, el ciclo de vida de las proyecciones
--   (pending -> calculated) se rompe, y el sistema de backtesting no funciona.
-- Criterio de paso GREEN: existe politica UPDATE para service_role en projections
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer >= 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'projections'
          AND cmd = 'UPDATE'
          AND roles::text LIKE '%service_role%'
    ),
    'SEGURIDAD RED: debe existir politica UPDATE para service_role en projections (SPEC §7 — ciclo pending->calculated)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 5: Debe existir politica INSERT para service_role en manual_verification_queue
-- Estado RED: FALLA — no existe ninguna politica RLS para manual_verification_queue;
--             COUNT = 0 < 1 => FALLA.
-- Razon (SPEC §7 / REQ-09):
--   El Scraper (corriendo via service_role en GHA) deposita los sorteos scraped
--   en manual_verification_queue para el proceso de Double-Entry Validation (ARC-04).
--   Sin politica INSERT para service_role, el Scraper no puede depositar sorteos
--   en la cola de verificacion, bloqueando completamente el flujo de datos historicos.
--   La SPEC es explicita: service_role tiene INSERT/UPDATE en manual_verification_queue.
-- Criterio de paso GREEN: existe politica INSERT para service_role en manual_verification_queue
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer >= 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'manual_verification_queue'
          AND cmd = 'INSERT'
          AND roles::text LIKE '%service_role%'
    ),
    'SEGURIDAD RED: debe existir politica INSERT para service_role en manual_verification_queue (SPEC §7 / REQ-09 Double-Entry)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 6: No debe existir politica DELETE permisiva para service_role
--              en system_logs (los logs son inmutables — inviolabilidad forense)
-- Estado RED: Esta assertion puede PASAR en RED porque no hay politicas de ningun tipo.
--             COUNT = 0 = valor esperado => ok(TRUE) => PASA (aparentemente).
-- Esta assertion es la GUARDIA PERMANENTE: previene que alguien cree una politica
--   DELETE para service_role en system_logs durante la implementacion GREEN.
--   El RED para esta tarea es capturado por assertions 2-5 que fallan.
-- Razon (SPEC §7 Principio de Minimo Privilegio):
--   "No puede borrar logs de auditoria." system_logs es el registro forense del sistema.
--   Si service_role (GHA) pudiera borrar logs, un atacante que comprometa el token
--   de GHA podria eliminar evidencia de su actividad. La inmutabilidad de logs
--   es un requisito de seguridad critico que protege la integridad del sistema de
--   auditoria. Solo el Admin puede hacer SELECT/DELETE en system_logs (SPEC §7),
--   y esa politica debe ser condicionada al admin_uuid (no a service_role).
-- Criterio de paso GREEN y RED: 0 politicas DELETE permisivas para service_role en system_logs
-- ---------------------------------------------------------------------------
SELECT is(
    (
        SELECT COUNT(*)::integer
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'system_logs'
          AND cmd = 'DELETE'
          AND permissive = 'PERMISSIVE'
          AND roles::text LIKE '%service_role%'
    ),
    0,
    'SEGURIDAD RED: service_role NO debe tener politica DELETE en system_logs (logs inmutables — inviolabilidad forense, SPEC §7)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 7: El COUNT total de politicas para service_role en las tablas
--              mandatorias debe ser >= 4 (INSERT en logs, INSERT/UPDATE en projections,
--              INSERT en manual_verification_queue)
-- Estado RED: FALLA — no existe ninguna politica en pg_policies para ninguna tabla;
--             COUNT = 0 < 4 => ok(FALSE) => FALLA.
-- Razon: Esta assertion captura el estado RED de forma directa y unificada.
--        Las assertions 2-5 verifican politicas individuales; esta verifica que
--        el conjunto minimo de politicas para service_role esta completo.
--        El numero minimo es 4: INSERT logs, INSERT projections, UPDATE projections,
--        INSERT manual_verification_queue. En GREEN puede haber mas politicas
--        (SELECT en otras tablas) pero el minimo de 4 debe cumplirse.
-- Criterio de paso GREEN: COUNT >= 4 politicas para service_role en tablas criticas
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer >= 4
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename IN ('system_logs', 'projections', 'manual_verification_queue', 'draws', 'performance', 'system_configuration')
          AND roles::text LIKE '%service_role%'
    ),
    'SEGURIDAD RED: deben existir al menos 4 politicas para service_role en las tablas criticas (SPEC §7 Minimo Privilegio)'
);

-- CLEANUP: ROLLBACK garantiza aislamiento. Las consultas sobre pg_roles y pg_policies
-- son de solo lectura. El patron ROLLBACK es estandar en toda la suite de tests.
-- No se ejecuto SET ROLE ni ninguna operacion con efectos secundarios sobre el estado
-- de la BD, garantizando idempotencia total del test.
SELECT * FROM finish();

ROLLBACK;

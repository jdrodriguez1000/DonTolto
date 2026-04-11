-- =============================================================================
-- TEST: 028_fn_cleanup_logs.sql
-- Trazabilidad: TSK-F1_1.1-26.3-RED — Test pgTap: Logica de purga en
--               fn_cleanup_logs
-- SPEC: Seccion 4.5 — fn_cleanup_logs (Mantenimiento Forense - REQ-13)
--       - DELETE system_logs WHERE level IN ('info','debug') AND created_at < now()-90d
--       - UPDATE system_logs SET is_archived=TRUE WHERE is_archived=FALSE AND created_at < now()-180d
--       - DELETE manual_verification_queue WHERE is_verified=TRUE AND is_conflict=FALSE
--         AND created_at < now()-180d
-- PLAN: B6 — Observabilidad & Mantenimiento [TDD Cycle] — Fase RED
-- REQ: REQ-13, OBJ-05
-- Responsable: backend-tester
-- Fecha: 2026-04-10
--
-- Tipo de test: RED (TDD) — Disenado para FALLAR cuando la implementacion no existe
--
-- Descripcion: Verifica el comportamiento selectivo de fn_cleanup_logs segun
--              el TTL de retencion configurado en system_configuration
--              (clave log_retention_days, default 90 dias segun SPEC §4.5).
--
--              La invariante critica del DoD es:
--              "Test falla si la funcion borra registros que NO han excedido el TTL"
--
--              Escenario de prueba:
--              1. Se inserta un log VIEJO (nivel 'info', created_at = ahora - 91 dias)
--                 → debe ser ELIMINADO por fn_cleanup_logs
--              2. Se inserta un log RECIENTE (nivel 'info', created_at = ahora - 10 dias)
--                 → debe PERMANECER intacto tras la ejecucion de fn_cleanup_logs
--              3. Se invoca fn_cleanup_logs()
--              4. Se verifica que:
--                 a) La funcion existe y es invocable (espera FALLO en RED)
--                 b) El log viejo (>90d) fue eliminado
--                 c) El log reciente (<TTL) NO fue eliminado (invariante DoD)
--                 d) Un log de nivel 'audit' (protegido — no en ('info','debug'))
--                    con >90 dias NO es eliminado por la purga de 90 dias
--
-- Nota de implementacion GREEN:
--   La SPEC §4.5 referencia un TTL de 90 dias como hardcoded. La nota del task
--   menciona system_configuration.log_retention_days como fuente de configuracion.
--   La implementacion GREEN debe leer el TTL de system_configuration si la columna
--   existe, o usar el default de 90 dias. El test usa la logica de la SPEC §4.5
--   directamente (90 dias) para maxima trazabilidad al contrato formal.
--
-- Mecanismo de deteccion RED:
--   La funcion fn_cleanup_logs NO EXISTE aun. Los tests verifican:
--   a) La funcion existe (espera FALLO — funcion no creada)
--   b) El log viejo fue eliminado (espera FALLO — funcion no existe, no borra nada)
--   c) El log reciente permanece intacto (puede pasar en RED porque nada fue borrado;
--      ASSERTION 2 es el discriminador definitivo del ciclo RED→GREEN)
--   d) El log de nivel 'audit' >90d permanece intacto (puede pasar en RED; valida
--      el filtro por nivel en GREEN)
--
-- Estado esperado en RED (funcion inexistente):
--   - ASSERTION 1: FALLA — fn_cleanup_logs no existe (has_function = false)
--   - ASSERTION 2: FALLA — funcion no existe; log viejo nunca borrado; COUNT = 1 (presente)
--   - ASSERTION 3: PASA en RED por razon incorrecta (nada fue borrado; log reciente
--                  intacto). ASSERTION 2 es el discriminador critico: si la funcion
--                  existiera pero borrara todo (incluyendo recientes), ASSERTION 3
--                  fallaria y ASSERTION 2 pasaria — ciclo GREEN invalido.
--   - ASSERTION 4: PASA en RED por razon incorrecta (funcion inactiva). En GREEN
--                  valida que el filtro por nivel excluye logs 'audit' de la purga.
-- =============================================================================

BEGIN;

SELECT plan(4);

-- ---------------------------------------------------------------------------
-- SETUP: Insertar log VIEJO de nivel 'info' (candidato a purga segun SPEC §4.5)
-- created_at = ahora - 91 dias → supera el TTL de 90 dias
-- Este registro debe ser ELIMINADO por fn_cleanup_logs en estado GREEN.
-- ---------------------------------------------------------------------------
INSERT INTO public.system_logs
    (id, run_id, service, level, message, is_archived, created_at)
VALUES (
    1000001,
    gen_random_uuid(),
    'GHA',
    'info',
    'TEST CLEANUP: log viejo info - debe ser purgado (>90 dias)',
    FALSE,
    now() - interval '91 days'
);

-- ---------------------------------------------------------------------------
-- SETUP: Insertar log RECIENTE de nivel 'info' (NO candidato a purga)
-- created_at = ahora - 10 dias → dentro del TTL de 90 dias
-- Este registro debe PERMANECER tras fn_cleanup_logs (invariante DoD).
-- ---------------------------------------------------------------------------
INSERT INTO public.system_logs
    (id, run_id, service, level, message, is_archived, created_at)
VALUES (
    1000002,
    gen_random_uuid(),
    'GHA',
    'info',
    'TEST CLEANUP: log reciente info - debe permanecer (< 90 dias)',
    FALSE,
    now() - interval '10 days'
);

-- ---------------------------------------------------------------------------
-- SETUP: Insertar log VIEJO de nivel 'audit' (PROTEGIDO — no en ('info','debug'))
-- created_at = ahora - 95 dias → supera el TTL de 90 dias pero su nivel
-- 'audit' NO esta en la lista de purga de SPEC §4.5.
-- Este registro debe PERMANECER tras la purga de 90 dias.
-- ---------------------------------------------------------------------------
INSERT INTO public.system_logs
    (id, run_id, service, level, message, is_archived, created_at)
VALUES (
    1000003,
    gen_random_uuid(),
    'DB-Native',
    'audit',
    'TEST CLEANUP: log viejo audit - NO debe ser purgado (nivel protegido)',
    FALSE,
    now() - interval '95 days'
);

-- Invocar la funcion de limpieza (no existe en RED — capturado por EXCEPTION)
DO $$
BEGIN
    PERFORM public.fn_cleanup_logs();
EXCEPTION WHEN undefined_function THEN
    RAISE NOTICE 'RED expected: fn_cleanup_logs no existe aun';
END $$;

-- ---------------------------------------------------------------------------
-- ASSERTION 1: La funcion fn_cleanup_logs debe existir y ser invocable
-- Estado RED: FALLA — la funcion no ha sido creada aun. has_function() = false.
-- Razon: fn_cleanup_logs es el motor de mantenimiento forense del sistema (REQ-13).
--        Su ausencia implica que los logs crecen indefinidamente sin purga, lo que
--        degrada el rendimiento de las queries de observabilidad y consume espacio
--        de almacenamiento de forma irrestricta. La SPEC §4.5 la define como un
--        componente mandatorio del ciclo de vida del sistema.
-- Criterio de paso GREEN: la funcion existe con nombre 'fn_cleanup_logs' en schema 'public'
-- ---------------------------------------------------------------------------
SELECT has_function(
    'public',
    'fn_cleanup_logs',
    ARRAY[]::text[],
    'CLEANUP RED 26.3: fn_cleanup_logs debe existir como motor de mantenimiento forense (SPEC §4.5, REQ-13)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 2: El log VIEJO de nivel 'info' (>90 dias) debe haber sido
-- eliminado por fn_cleanup_logs (discriminador critico del ciclo RED→GREEN)
-- Estado RED: FALLA — la funcion no existe. El log 1000001 nunca fue borrado.
--             COUNT = 1 (el log sigue presente). La condicion COUNT=0 falla.
-- Razon: Esta es la assertion central del test: confirmar que la purga ocurre
--        para registros que superan el TTL de 90 dias y cuyo nivel esta en
--        la lista de purga ('info', 'debug'). Si esta assertion falla en GREEN,
--        la funcion no esta cumpliendo su contrato de mantenimiento y los logs
--        antiguos acumulan espacio indefinidamente (violacion REQ-13).
-- Criterio de paso GREEN: el registro id=1000001 no existe en system_logs
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer = 0
        FROM public.system_logs
        WHERE id = 1000001
    ),
    'CLEANUP RED 26.3: log viejo (>90 dias, nivel info) debe ser eliminado por fn_cleanup_logs (SPEC §4.5 purga TTL)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 3: El log RECIENTE de nivel 'info' (<90 dias) NO debe haber sido
-- eliminado por fn_cleanup_logs (invariante critica del DoD de la tarea)
-- Estado RED: PASA por razon incorrecta (la funcion no existe, no borra nada).
--             En GREEN valida que el filtro de fecha excluye registros dentro del TTL.
-- Razon: Esta es la invariante de seguridad de la funcion: "Test falla si la
--        funcion borra registros que NO han excedido el TTL de retencion" (DoD
--        de TSK-26.3). Una implementacion incorrecta que borre todos los logs
--        sin filtrar por fecha causaria perdida de datos de observabilidad activos.
--        ASSERTION 2 discrimina el ciclo RED→GREEN; ASSERTION 3 protege contra
--        regresiones en la implementacion GREEN.
-- Criterio de paso GREEN: el registro id=1000002 permanece en system_logs
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer = 1
        FROM public.system_logs
        WHERE id = 1000002
    ),
    'CLEANUP RED 26.3: log reciente (<90 dias, nivel info) NO debe ser eliminado — invariante de retencion del DoD'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 4: El log VIEJO de nivel 'audit' (>90 dias) NO debe haber sido
-- eliminado por fn_cleanup_logs (el nivel 'audit' esta protegido de la purga)
-- Estado RED: PASA por razon incorrecta (la funcion no existe, no borra nada).
--             En GREEN valida que el filtro por nivel excluye 'audit' de la purga.
-- Razon: La SPEC §4.5 define la purga como: "DELETE FROM system_logs WHERE level
--        IN ('info', 'debug') AND created_at < now() - interval '90 days'". El
--        nivel 'audit' no esta en la lista porque estos registros son evidencia
--        forense de operaciones criticas (ADR-04: Backup de Auditoria). Borrar
--        logs de auditoria con el mismo TTL que logs informativos violaría el
--        principio de trazabilidad forense del sistema.
-- Criterio de paso GREEN: el registro id=1000003 permanece en system_logs
--        (no borrado por la purga de 90 dias que filtra por nivel)
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer = 1
        FROM public.system_logs
        WHERE id = 1000003
    ),
    'CLEANUP RED 26.3: log viejo nivel audit (>90 dias) NO debe ser purgado — nivel audit esta protegido de la purga (SPEC §4.5)'
);

SELECT * FROM finish();

-- CLEANUP: ROLLBACK garantiza aislamiento total. Nada persiste en la base de datos.
ROLLBACK;

-- =============================================================================
-- TEST: 006_singleton_constraint.sql
-- Trazabilidad: TSK-F1_1.1-04.1-RED — Restriccion Singleton CHECK id=1
-- SPEC: Seccion 3.6 — Garantia Singleton: system_configuration
-- PLAN: B2 — Verificacion de constraints de integridad de tabla de configuracion
-- Responsable: backend-tester
-- Fecha: 2026-04-09
--
-- Tipo de test: RED (TDD) — Disenado para FALLAR en el estado actual
-- Descripcion: Verifica que la tabla system_configuration implementa
--              correctamente la Garantia Singleton definida en SPEC §3.6.
--              El contrato exige un PRIMARY KEY con CHECK (id = 1) para
--              impedir la existencia de multiples configuraciones administrativas.
--
-- Estado esperado en RED:
--   - ASSERTION 1: FALLA — la tabla system_configuration aun no existe
--   - ASSERTION 2: FALLA — la columna id con CHECK no existe
--   - ASSERTION 3: FALLA — no se puede probar el constraint sobre tabla inexistente
--   - ASSERTION 4: FALLA — no se puede probar la PK sobre tabla inexistente
--
-- Invariante de Singleton (SPEC §3.6):
--   La tabla system_configuration debe tener campo id INTEGER PRIMARY KEY
--   con CHECK (id = 1). Solo el service_role tiene privilegios de INSERT
--   o DELETE. Esta restriccion garantiza exactamente UN registro de
--   configuracion activo en todo momento del ciclo de vida del sistema.
-- =============================================================================

BEGIN;

SELECT plan(4);

-- ---------------------------------------------------------------------------
-- ASSERTION 1: La tabla system_configuration debe existir en el esquema public
-- Estado RED: FALLA porque la tabla aun no ha sido creada por la migracion DDL
-- Razon: La Garantia Singleton (ADR-02, REQ-14) requiere que esta tabla
--        exista como prerequisito para todo el sistema RLS y la funcion
--        fn_setup_security_context (SPEC §4.7).
-- ---------------------------------------------------------------------------
SELECT has_table(
    'public',
    'system_configuration',
    'La tabla system_configuration debe existir en el esquema public'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 2: La columna id debe tener un CHECK constraint definido
-- Estado RED: FALLA porque la tabla no existe, por lo tanto la columna
--             y su constraint CHECK (id = 1) tampoco existen
-- Razon: El CHECK (id = 1) es el mecanismo central de la Garantia Singleton
--        (SPEC §3.6). Sin este constraint, cualquier valor de id seria
--        aceptado, rompiendo la unicidad de configuracion del sistema.
-- ---------------------------------------------------------------------------
SELECT col_has_check(
    'public',
    'system_configuration',
    'id',
    'La columna id debe tener CHECK (id = 1) para garantizar el Singleton'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 3: Insertar un registro con id=2 debe violar el CHECK constraint
-- Estado RED: FALLA porque la tabla no existe (error de relacion, no de CHECK)
-- Razon: El contrato SPEC §3.6 exige que cualquier intento de insertar una
--        segunda configuracion (id != 1) sea rechazado con codigo SQLSTATE
--        23514 (check_violation). Este es el mecanismo de defensa principal
--        contra la duplicacion de configuracion administrativa.
-- Codigo de error esperado: 23514 (check_violation — CHECK constraint failed)
-- ---------------------------------------------------------------------------
SELECT throws_ok(
    $$INSERT INTO public.system_configuration(id, admin_uuid, is_system_locked)
      VALUES (2, gen_random_uuid(), false)$$,
    '23514',
    NULL,
    'Insertar id=2 debe violar el CHECK constraint (check_violation SQLSTATE 23514)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 4: Insertar un segundo registro con id=1 debe violar la PRIMARY KEY
-- Estado RED: FALLA porque la tabla no existe (error de relacion, no de PK)
-- Razon: El contrato SPEC §3.6 define id como PRIMARY KEY, lo que impide
--        la insercion de un segundo registro con id=1 aunque el CHECK lo
--        permita. Esta doble barrera (CHECK + PK) garantiza que el Singleton
--        sea robusto ante intentos de duplicacion directa.
-- Codigo de error esperado: 23505 (unique_violation — PK duplicate key)
-- Prerequisito: Para que esta assertion sea evaluable, debe existir al menos
--               un registro previo con id=1. En un contexto de test integrado,
--               se asume un INSERT previo de id=1 en el setup de la migracion.
-- ---------------------------------------------------------------------------
SELECT throws_ok(
    $$INSERT INTO public.system_configuration(id, admin_uuid, is_system_locked)
      VALUES (1, gen_random_uuid(), false)$$,
    '23505',
    NULL,
    'Insertar un segundo id=1 debe violar la PRIMARY KEY (unique_violation SQLSTATE 23505)'
);

-- CLEANUP: El bloque BEGIN/ROLLBACK garantiza que ningun INSERT de prueba
-- persiste en la base de datos. La transaccion es completamente atomica.
SELECT * FROM finish();

ROLLBACK;

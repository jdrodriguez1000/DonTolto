-- =============================================================================
-- TEST: 007_singleton_delete_block.sql
-- Trazabilidad: TSK-F1_1.1-04.2-RED — Bloqueo de DELETE en system_configuration
-- SPEC: Seccion 3.6 — Solo service_role puede INSERT/DELETE en system_configuration
--       Seccion 5.2 — Trigger tg_prevent_singleton_delete bloquea toda operacion DELETE
-- PLAN: B2 — Verificacion de constraints de integridad de tabla de configuracion
-- Responsable: backend-tester
-- Fecha: 2026-04-09
--
-- Tipo de test: RED (TDD) — Disenado para FALLAR en el estado actual
-- Descripcion: Verifica que el trigger tg_prevent_singleton_delete y su funcion
--              asociada fn_prevent_singleton_delete existen y bloquean toda
--              operacion DELETE sobre la tabla system_configuration, incluso
--              para roles con permisos directos. Este mecanismo garantiza la
--              permanencia del registro unico de configuracion del sistema.
--
-- Estado esperado en RED:
--   - ASSERTION 1: FALLA — el trigger tg_prevent_singleton_delete aun no existe
--   - ASSERTION 2: FALLA — la funcion fn_prevent_singleton_delete aun no existe
--   - ASSERTION 3: FALLA — la tabla system_configuration aun no existe
--   - ASSERTION 4: FALLA — la tabla system_configuration aun no existe
--
-- Invariante de Singleton (SPEC §3.6 / §5.2):
--   El trigger tg_prevent_singleton_delete debe interceptar TODA operacion DELETE
--   sobre system_configuration y lanzar una excepcion con SQLSTATE P0001.
--   Esto garantiza que el unico registro de configuracion sea permanente e
--   indestructible por operaciones DML directas, independientemente del rol.
-- =============================================================================

BEGIN;

SELECT plan(4);

-- ---------------------------------------------------------------------------
-- ASSERTION 1: El trigger tg_prevent_singleton_delete debe existir en la tabla
-- Estado RED: FALLA porque ni la tabla ni el trigger han sido creados por la
--             migracion DDL correspondiente (TSK-F1_1.1-04.2-GREEN pendiente)
-- Razon: SPEC §5.2 define este trigger como el mecanismo central de proteccion
--        del Singleton. Sin el trigger, cualquier rol con permisos podria
--        eliminar el registro de configuracion, rompiendo la invariante del sistema.
-- ---------------------------------------------------------------------------
SELECT has_trigger(
    'public',
    'system_configuration',
    'tg_prevent_singleton_delete',
    'El trigger tg_prevent_singleton_delete debe existir en system_configuration'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 2: La funcion fn_prevent_singleton_delete debe existir en public
-- Estado RED: FALLA porque la funcion aun no ha sido creada por la migracion DDL
-- Razon: SPEC §5.2 exige que el trigger invoque una funcion dedicada que
--        centralice la logica de bloqueo. La funcion debe lanzar una excepcion
--        descriptiva mediante RAISE EXCEPTION para informar al cliente del
--        rechazo de la operacion DELETE con SQLSTATE P0001.
-- ---------------------------------------------------------------------------
SELECT has_function(
    'public',
    'fn_prevent_singleton_delete',
    'La funcion fn_prevent_singleton_delete debe existir en el esquema public'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 3: DELETE sobre un registro especifico debe lanzar excepcion P0001
-- Estado RED: FALLA porque la tabla system_configuration aun no existe
--             (el error sera de relacion inexistente, no P0001 del trigger)
-- Razon: SPEC §5.2 garantiza que el trigger intercepta el DELETE BEFORE y
--        lanza RAISE EXCEPTION con SQLSTATE P0001 antes de que la operacion
--        sea aplicada. El cliente recibe el error; ningun registro es borrado.
-- Codigo de error esperado: P0001 (raise_exception — RAISE EXCEPTION explicito)
-- ---------------------------------------------------------------------------
SELECT throws_ok(
    $$DELETE FROM public.system_configuration WHERE id = 1$$,
    'P0001',
    NULL,
    'El DELETE sobre system_configuration debe ser bloqueado por el trigger'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 4: DELETE masivo (sin WHERE) tambien debe ser bloqueado por el trigger
-- Estado RED: FALLA porque la tabla system_configuration aun no existe
--             (el error sera de relacion inexistente, no P0001 del trigger)
-- Razon: SPEC §5.2 especifica que el trigger bloquea TODA operacion DELETE,
--        incluyendo sentencias sin clausula WHERE. Esta proteccion de superficie
--        total impide eliminacion masiva accidental o maliciosa del Singleton.
-- Codigo de error esperado: P0001 (raise_exception — RAISE EXCEPTION explicito)
-- Nota: En GREEN, este test confirmara que incluso un DELETE sin filtro es
--       rechazado antes de afectar cualquier fila del registro unico.
-- ---------------------------------------------------------------------------
SELECT throws_ok(
    $$DELETE FROM public.system_configuration$$,
    'P0001',
    NULL,
    'DELETE masivo sobre system_configuration tambien debe ser bloqueado'
);

-- CLEANUP: El bloque BEGIN/ROLLBACK garantiza que ningun efecto de las pruebas
-- persiste en la base de datos. La transaccion es completamente atomica.
-- En RED, las assertions fallan por tabla/trigger inexistentes, sin efectos laterales.
SELECT * FROM finish();

ROLLBACK;

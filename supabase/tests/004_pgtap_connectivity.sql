-- =============================================================================
-- TEST: 004_pgtap_connectivity.sql
-- Trazabilidad: TSK-F1_1.1-02.3 — Prueba de conectividad del runner pgtap
-- PLAN: B0 — Hito de aceptacion: pg_prove ejecuta exitosamente un test dummy
-- Responsable: backend-tester
-- Fecha: 2026-04-09
--
-- Tipo de test: CANARY / CONNECTIVITY CHECK (debe PASAR si pgtap esta activo)
-- Descripcion: Este es el test "dummy" de conectividad del runner. Su unico
--              proposito es confirmar que:
--                1. La extension pgtap esta cargada y operativa
--                2. Las funciones core de pgtap (plan, ok, finish) estan
--                   disponibles en el search_path actual
--                3. pg_prove puede descubrir, parsear y ejecutar archivos .sql
--                   de test contra la instancia local de Supabase
--                4. El protocolo TAP (Test Anything Protocol) es generado
--                   correctamente para consumo por herramientas CI/CD
--
-- Este archivo es el punto de entrada de la suite de tests. Si este falla,
-- ningun otro test es confiable independientemente de su logica.
--
-- Protocolo TAP: La salida de pgtap sigue el formato:
--   1..N       (plan: total de tests)
--   ok 1 - ... (test exitoso)
--   not ok 2 - (test fallido)
-- =============================================================================

BEGIN;

SELECT plan(3);

-- ---------------------------------------------------------------------------
-- ASSERTION 1: El framework pgtap esta operativo (self-check)
-- Razon: Verifica que la funcion ok() de pgtap esta disponible y funciona.
--        Si esta asercion falla, significa que pgtap no esta instalado o no
--        esta en el search_path actual — bloqueo total del entorno de testing.
-- ---------------------------------------------------------------------------
SELECT ok(
    TRUE,
    'pgtap connectivity: la funcion ok() esta operativa (self-check del runner)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 2: La funcion plan() acepta un entero positivo
-- Razon: plan() es el primer comando que debe ejecutarse en cualquier test
--        pgtap. Verifica que el numero de tests declarado al inicio coincide
--        con el numero de tests ejecutados. Si no es accesible, la suite no
--        puede generar TAP valido.
-- ---------------------------------------------------------------------------
SELECT ok(
    (SELECT count(*) FROM pg_proc WHERE proname = 'plan' AND pronamespace = (
        SELECT oid FROM pg_namespace WHERE nspname = 'public'
        UNION
        SELECT oid FROM pg_namespace WHERE nspname = 'extensions'
    )) > 0,
    'pgtap connectivity: la funcion plan() esta disponible en el search_path'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 3: La extension pgtap tiene acceso al catalogo del sistema
-- Razon: Verifica que pgtap puede inspeccionar pg_catalog para assertions
--        como has_table(), has_column(), has_index(), etc. Estas funciones
--        son las mas usadas en los tests RED de los Bloques 2-6 de la TASK.
--        Si pgtap no puede acceder a pg_catalog, todos los tests de esquema
--        fallarian con errores de permiso, no con fallos de logica.
-- ---------------------------------------------------------------------------
SELECT ok(
    (SELECT count(*) > 0 FROM pg_catalog.pg_extension WHERE extname = 'pgtap'),
    'pgtap connectivity: la extension puede leer pg_catalog.pg_extension (acceso a catalogo)'
);

SELECT * FROM finish();

ROLLBACK;

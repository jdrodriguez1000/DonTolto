-- =============================================================================
-- TEST: 010_fn_validate_ball_array.sql
-- Trazabilidad: TSK-F1_1.1-04.5-RED — Test pgTap: Logica de validacion de bolas
-- SPEC: Seccion 4.6 — fn_validate_ball_array (Integridad de Datos)
-- PLAN: B2 — Verificacion de logica de validacion de arrays de bolas principales
-- Responsable: backend-tester
-- Fecha: 2026-04-09
--
-- Tipo de test: RED (TDD) — Disenado para FALLAR en el estado actual
-- Descripcion: Verifica que la funcion fn_validate_ball_array implemente
--              correctamente el contrato de validacion definido en SPEC §4.6.
--              La funcion debe ser IMMUTABLE y rechazar arrays invalidos
--              segun las cuatro Reglas de Oro del contrato.
--
-- Estado esperado en RED:
--   - ASSERTION 1: FALLA — la funcion fn_validate_ball_array aun no existe
--   - ASSERTION 2: FALLA — la funcion no existe, no se puede verificar provolatile
--   - ASSERTION 3: FALLA — la funcion no existe, la llamada lanza error 42883
--   - ASSERTION 4: FALLA — la funcion no existe, COALESCE(NULL, true)=true,
--                  NOT true=false => ok(false) falla
--   - ASSERTION 5: FALLA — identico mecanismo de fallo que ASSERTION 4
--   - ASSERTION 6: FALLA — identico mecanismo de fallo que ASSERTION 4
--   - ASSERTION 7: FALLA — identico mecanismo de fallo que ASSERTION 4
--
-- Patron defensivo (assertions 4-7):
--   ok(NOT COALESCE(public.fn_validate_ball_array(...), true), '...')
--   En RED: la funcion no existe => error 42883 => expresion retorna NULL =>
--           COALESCE(NULL, true) = true => NOT true = false => ok(false) FALLA.
--   En GREEN: la funcion retorna FALSE para inputs invalidos =>
--             COALESCE(false, true) = false => NOT false = true => ok(true) PASA.
--
-- Contrato SPEC §4.6 — Reglas de Oro:
--   1. Cardinalidad exacta = 5 (exactamente 5 numeros por array)
--   2. Valores entre 1 y 43 sin duplicados
--   3. El array DEBE estar ordenado ascendentemente
--   Retorna BOOLEAN o dispara EXCEPTION si falla.
--   Marcada como IMMUTABLE (resultados deterministas, sin efectos secundarios).
-- =============================================================================

BEGIN;

SELECT plan(7);

-- ---------------------------------------------------------------------------
-- ASSERTION 1: La funcion fn_validate_ball_array debe existir en el esquema public
-- Estado RED: FALLA porque la funcion aun no ha sido creada por la migracion DDL
-- Razon: Sin la existencia de la funcion, ningun CHECK CONSTRAINT en las tablas
--        draws, projections y performance puede ser creado. Esta funcion es la
--        piedra angular de la integridad de datos en toda la SPEC §3.3/§4.6.
-- ---------------------------------------------------------------------------
SELECT has_function(
    'public',
    'fn_validate_ball_array',
    ARRAY['integer[]'],
    'La funcion fn_validate_ball_array debe existir en el esquema public'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 2: La funcion fn_validate_ball_array debe ser IMMUTABLE
-- Estado RED: FALLA porque la funcion no existe en pg_proc
-- Razon: La marca IMMUTABLE es obligatoria segun SPEC §4.6. Sin ella:
--        (a) No puede ser usada en CHECK CONSTRAINTs de tablas.
--        (b) El indice GIN sobre los arrays no puede aprovechar la optimizacion
--            de funciones con resultados deterministas (ADR-05).
-- Valor esperado: 'i' (provolatile = i indica IMMUTABLE en el catalogo pg_proc)
-- ---------------------------------------------------------------------------
SELECT is(
    (SELECT provolatile
     FROM pg_proc
     JOIN pg_namespace ON pg_proc.pronamespace = pg_namespace.oid
     WHERE pg_namespace.nspname = 'public'
       AND pg_proc.proname = 'fn_validate_ball_array'),
    'i',
    'fn_validate_ball_array debe ser IMMUTABLE (provolatile = i)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 3: Retorna TRUE para un array completamente valido
-- Estado RED: FALLA con error 42883 (undefined_function) porque la funcion
--             no existe. pgTap captura el error y reporta el test como FAILED.
-- Input: [3, 15, 22, 31, 43] — 5 valores, todos en rango [1-43],
--        sin duplicados, ordenados ascendentemente
-- Razon: Verifica el camino positivo (happy path). Una funcion de validacion
--        que no retorna TRUE para inputs validos romperia todos los INSERTs
--        legitimos en draws, projections y performance.
-- ---------------------------------------------------------------------------
SELECT is(
    public.fn_validate_ball_array(ARRAY[3, 15, 22, 31, 43]),
    true,
    'fn_validate_ball_array debe retornar TRUE para array valido [3,15,22,31,43]'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 4: Rechaza array con numeros duplicados
-- Estado RED: FALLA — la funcion no existe, la subexpresion retorna NULL por
--             error 42883, COALESCE(NULL, true)=true, NOT true=false, ok(false) FALLA.
-- Input: [1, 2, 3, 3, 5] — elemento 3 duplicado
-- Razon: Arrays con duplicados corromperian el calculo de hits en
--        fn_compute_async_scoring (SPEC §4.2). Un duplicado puede inflar
--        artificialmente el conteo de aciertos de una proyeccion.
-- Patron defensivo: ok(NOT COALESCE(..., true)) cubre tanto el caso en que
--                   la funcion retorna FALSE como el caso en que lanza EXCEPTION.
-- ---------------------------------------------------------------------------
SELECT ok(
    NOT COALESCE(public.fn_validate_ball_array(ARRAY[1, 2, 3, 3, 5]), true),
    'fn_validate_ball_array debe rechazar arrays con numeros duplicados'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 5: Rechaza numero fuera de rango superior (> 43)
-- Estado RED: FALLA — identico mecanismo de fallo que ASSERTION 4.
-- Input: [1, 2, 3, 4, 99] — valor 99 excede el maximo de 43
-- Razon: Los numeros del Baloto van del 1 al 43. Cualquier valor mayor
--        indica datos corruptos (scraping erroneo, entrada manual invalida)
--        que deben ser rechazados antes de persistirse en la BD.
-- ---------------------------------------------------------------------------
SELECT ok(
    NOT COALESCE(public.fn_validate_ball_array(ARRAY[1, 2, 3, 4, 99]), true),
    'fn_validate_ball_array debe rechazar numeros > 43'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 6: Rechaza numero fuera de rango inferior (< 1)
-- Estado RED: FALLA — identico mecanismo de fallo que ASSERTION 4.
-- Input: [0, 2, 3, 4, 5] — valor 0 es menor que el minimo de 1
-- Razon: El cero no es un numero valido en el Baloto. Junto con la Regla de
--        rango superior, esta validacion garantiza que el universo de numeros
--        es exactamente {1, 2, ..., 43} sin excepcion.
-- ---------------------------------------------------------------------------
SELECT ok(
    NOT COALESCE(public.fn_validate_ball_array(ARRAY[0, 2, 3, 4, 5]), true),
    'fn_validate_ball_array debe rechazar numeros < 1'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 7: Rechaza array no ordenado ascendentemente
-- Estado RED: FALLA — identico mecanismo de fallo que ASSERTION 4.
-- Input: [5, 3, 1, 2, 4] — completamente desordenado
-- Razon: El orden ascendente es obligatorio segun SPEC §4.6. Esta restriccion
--        es critica para la eficiencia del indice GIN (ADR-05) y para garantizar
--        que las comparaciones de overlap en fn_compute_async_scoring sean
--        deterministicas y reproducibles entre distintas ejecuciones del Engine.
-- ---------------------------------------------------------------------------
SELECT ok(
    NOT COALESCE(public.fn_validate_ball_array(ARRAY[5, 3, 1, 2, 4]), true),
    'fn_validate_ball_array debe rechazar arrays no ordenados ascendentemente'
);

-- CLEANUP: El bloque BEGIN/ROLLBACK garantiza que ningun estado de prueba
-- persiste en la base de datos. La transaccion es completamente atomica.
SELECT * FROM finish();

ROLLBACK;

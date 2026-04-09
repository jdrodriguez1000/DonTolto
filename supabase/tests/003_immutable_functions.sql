-- =============================================================================
-- TEST: 003_immutable_functions.sql
-- Trazabilidad: TSK-F1_1.1-02.2 — Verificacion de funciones IMMUTABLE
-- SPEC: Seccion 3.3 — Constraint de Calidad: fn_validate_ball_array (IMMUTABLE)
-- PLAN: B0 — Confirmacion de disponibilidad de funciones IMMUTABLE para B2
-- Responsable: backend-tester
-- Fecha: 2026-04-09
--
-- Tipo de test: SMOKE TEST de capacidad del motor (debe PASAR si el motor
--               soporta correctamente la volatilidad IMMUTABLE)
-- Descripcion: Verifica que el motor PostgreSQL soporte correctamente funciones
--              declaradas como IMMUTABLE. Esta categoria de volatilidad es
--              critica para la SPEC porque fn_validate_ball_array debe ser
--              IMMUTABLE para poder ser usada en CHECK CONSTRAINTs de tablas y
--              para maximizar la eficiencia del indice GIN.
--
-- Invariante de IMMUTABLE: Una funcion IMMUTABLE no puede:
--   - Acceder a tablas del sistema o del usuario
--   - Acceder a sequences
--   - Ejecutar consultas SQL que dependan del estado de la DB
--   - Retornar resultados que cambien entre llamadas con los mismos argumentos
-- =============================================================================

BEGIN;

SELECT plan(4);

-- ---------------------------------------------------------------------------
-- SETUP: Crear una funcion IMMUTABLE de prueba que simula la logica de
--        fn_validate_ball_array (verificacion de arrays de bolas).
--        Esta funcion de prueba es temporal (dentro del bloque de transaccion)
--        y no afecta al esquema productivo.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _test_immutable_ball_validator(ball_array INTEGER[])
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
STRICT
AS $$
DECLARE
    v_len    INTEGER;
    v_i      INTEGER;
    v_sorted INTEGER[];
BEGIN
    -- Regla 1: Cardinalidad exacta = 5
    v_len := array_length(ball_array, 1);
    IF v_len IS NULL OR v_len <> 5 THEN
        RETURN FALSE;
    END IF;

    -- Regla 2: Valores entre 1 y 43 sin duplicados
    FOR v_i IN 1..5 LOOP
        IF ball_array[v_i] < 1 OR ball_array[v_i] > 43 THEN
            RETURN FALSE;
        END IF;
    END LOOP;

    -- Regla 3: Sin duplicados (cardinalidad del conjunto = 5)
    IF (SELECT count(DISTINCT x) FROM unnest(ball_array) AS x) <> 5 THEN
        RETURN FALSE;
    END IF;

    -- Regla 4: Array ordenado ascendentemente
    v_sorted := ARRAY(SELECT unnest(ball_array) ORDER BY 1);
    FOR v_i IN 1..5 LOOP
        IF ball_array[v_i] <> v_sorted[v_i] THEN
            RETURN FALSE;
        END IF;
    END LOOP;

    RETURN TRUE;
END;
$$;

-- ---------------------------------------------------------------------------
-- ASSERTION 1: La funcion IMMUTABLE retorna TRUE con un array valido
-- Input: [1, 5, 12, 28, 43] — 5 valores, todos en rango, sin duplicados, ordenados
-- Razon: Verifica que la logica positiva funciona correctamente y que el motor
--        acepta y ejecuta funciones IMMUTABLE sin restricciones.
-- ---------------------------------------------------------------------------
SELECT ok(
    _test_immutable_ball_validator(ARRAY[1, 5, 12, 28, 43]),
    'IMMUTABLE: debe retornar TRUE para array valido [1,5,12,28,43]'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 2: La funcion IMMUTABLE retorna FALSE para array desordenado
-- Input: [5, 1, 12, 28, 43] — desordenado (5 antes de 1)
-- Razon: Verifica que la Regla 4 (orden ascendente) es detectada. Este
--        comportamiento es critico porque el indice GIN requiere arrays
--        ordenados para operar con maxima eficiencia (ADR-05).
-- ---------------------------------------------------------------------------
SELECT ok(
    NOT _test_immutable_ball_validator(ARRAY[5, 1, 12, 28, 43]),
    'IMMUTABLE: debe retornar FALSE para array desordenado [5,1,12,28,43]'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 3: La funcion IMMUTABLE retorna FALSE para array con duplicados
-- Input: [1, 1, 12, 28, 43] — elemento 1 duplicado
-- Razon: Verifica que la Regla 3 (sin duplicados) funciona. Un array con
--        duplicados corromperia el calculo de hits en fn_compute_async_scoring.
-- ---------------------------------------------------------------------------
SELECT ok(
    NOT _test_immutable_ball_validator(ARRAY[1, 1, 12, 28, 43]),
    'IMMUTABLE: debe retornar FALSE para array con duplicados [1,1,12,28,43]'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 4: La funcion IMMUTABLE retorna FALSE para array con valor fuera de rango
-- Input: [1, 5, 12, 28, 44] — valor 44 excede el maximo de 43
-- Razon: Verifica que la Regla 2 (rango 1-43) es aplicada. Los numeros del
--        Baloto van de 1 a 43; cualquier valor fuera de rango indica datos
--        corruptos que deben ser rechazados antes de persistirse.
-- ---------------------------------------------------------------------------
SELECT ok(
    NOT _test_immutable_ball_validator(ARRAY[1, 5, 12, 28, 44]),
    'IMMUTABLE: debe retornar FALSE para array con valor fuera de rango [1,5,12,28,44] (max=43)'
);

-- CLEANUP: La funcion de prueba es eliminada por el ROLLBACK al final
SELECT * FROM finish();

ROLLBACK;

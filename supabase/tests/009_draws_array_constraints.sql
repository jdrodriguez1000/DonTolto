-- =============================================================================
-- TEST: 009_draws_array_constraints.sql
-- Trazabilidad: TSK-F1_1.1-04.4-RED — Integridad referencial y constraints de array en draws
-- SPEC: Seccion 3.3 — Tabla transaccional draws; Seccion 4.6 — fn_validate_ball_array
-- PLAN: B2 — Verificacion de constraints de integridad de tabla transaccional
-- Responsable: backend-tester
-- Fecha: 2026-04-09
--
-- Tipo de test: RED (TDD) — Disenado para FALLAR en el estado actual
-- Descripcion: Verifica que la tabla draws implementa correctamente los
--              constraints de calidad sobre arrays de bolas definidos en SPEC §3.3.
--              El contrato exige validacion delegada a fn_validate_ball_array
--              (IMMUTABLE), un CHECK sobre superbalota (1-16), un CHECK sobre
--              type (baloto, revancha) y un indice UNICO en (draw_date, type).
--
-- Estado esperado en RED:
--   - ASSERTION 1: FALLA — la tabla draws aun no existe
--   - ASSERTION 2: FALLA — el indice unico idx_draws_date_type_unique no existe
--   - ASSERTION 3: FALLA — la tabla no existe (error 42P01, no de constraint)
--   - ASSERTION 4: FALLA — la tabla no existe (error 42P01, no de constraint)
--   - ASSERTION 5: FALLA — la tabla no existe (error 42P01, no de constraint)
--   - ASSERTION 6: FALLA — la tabla no existe (error 42P01, no de constraint)
--
-- Invariante de Calidad (SPEC §3.3 y §4.6):
--   - numbers: ALL (x >= 1 AND x <= 43), sin duplicados, ordenados ascendentemente.
--   - Implementado como CHECK CONSTRAINT que invoca fn_validate_ball_array.
--   - superbalota: CHECK (1 <= x <= 16).
--   - type: CHECK IN ('baloto', 'revancha').
--   - Indice UNICO en (draw_date, type) garantiza unicidad temporal.
--
-- Nota de Portabilidad RED -> GREEN:
--   Las assertions 3-6 usan SQLSTATE NULL para que el test sea valido en
--   ambas fases. En RED el error es 42P01 (undefined_table); en GREEN el
--   error sera el SQLSTATE del constraint violado (23514 check_violation,
--   23505 unique_violation u otro). No se hardcodea el SQLSTATE equivocado.
-- =============================================================================

BEGIN;

SELECT plan(6);

-- ---------------------------------------------------------------------------
-- ASSERTION 1: La tabla draws debe existir en el esquema public
-- Estado RED: FALLA porque la tabla aun no ha sido creada por la migracion DDL
-- Razon: La tabla draws es la fuente de verdad de sorteos oficiales (SPEC §3.3)
--        y prerequisito para todas las tablas relacionadas (performance,
--        projections) que referencian draw_id como FK. Sin esta tabla el
--        sistema de backtesting no puede operar.
-- ---------------------------------------------------------------------------
SELECT has_table(
    'public',
    'draws',
    'La tabla draws debe existir en el esquema public'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 2: Debe existir un indice unico en (draw_date, type)
-- Estado RED: FALLA porque la tabla y el indice no existen
-- Razon: SPEC §3.8 define idx_draws_date_type como Unique B-Tree en
--        (draw_date, type). Este indice garantiza la unicidad temporal:
--        no puede existir mas de un sorteo del mismo tipo en la misma fecha,
--        lo que previene duplicados en la ingesta del Scraper y del Admin.
-- Nombre esperado del indice: idx_draws_date_type_unique (segun TASK)
-- ---------------------------------------------------------------------------
SELECT has_index(
    'public',
    'draws',
    'idx_draws_date_type_unique',
    ARRAY['draw_date', 'type'],
    'Debe existir un indice unico en (draw_date, type) para garantizar unicidad temporal'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 3: INSERT con array de bolas duplicadas debe ser rechazado
-- Estado RED: FALLA con error 42P01 (tabla inexistente)
-- Estado GREEN: FALLA con el error del CHECK constraint de fn_validate_ball_array
-- Razon: SPEC §4.6 establece que fn_validate_ball_array valida "sin duplicados".
--        El array ARRAY[1,2,3,3,5] contiene el valor 3 repetido. La funcion
--        marcada como IMMUTABLE debe rechazar este input disparando una EXCEPTION
--        antes de que el INSERT sea persistido en la tabla.
-- SQLSTATE: NULL — en RED es 42P01; en GREEN sera el error del constraint
-- ---------------------------------------------------------------------------
SELECT throws_ok(
    $$INSERT INTO public.draws(run_id, draw_date, numbers, superbalota, type)
      VALUES (gen_random_uuid(), CURRENT_DATE, ARRAY[1,2,3,3,5], 7, 'baloto')$$,
    NULL,
    NULL,
    'Insertar numeros duplicados en draws debe ser rechazado por fn_validate_ball_array'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 4: INSERT con numero fuera de rango (> 43) debe ser rechazado
-- Estado RED: FALLA con error 42P01 (tabla inexistente)
-- Estado GREEN: FALLA con el error del CHECK constraint de fn_validate_ball_array
-- Razon: SPEC §4.6 define como regla de oro "Valores entre 1 y 43". El array
--        ARRAY[1,2,3,4,99] contiene el valor 99 que excede el limite superior.
--        Aceptar este valor corromperia el dominio del sorteo Baloto (1-43).
-- SQLSTATE: NULL — en RED es 42P01; en GREEN sera el error del constraint
-- ---------------------------------------------------------------------------
SELECT throws_ok(
    $$INSERT INTO public.draws(run_id, draw_date, numbers, superbalota, type)
      VALUES (gen_random_uuid(), CURRENT_DATE, ARRAY[1,2,3,4,99], 7, 'baloto')$$,
    NULL,
    NULL,
    'Insertar numero > 43 en draws debe ser rechazado por el CHECK constraint'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 5: INSERT con superbalota fuera de rango (> 16) debe ser rechazado
-- Estado RED: FALLA con error 42P01 (tabla inexistente)
-- Estado GREEN: FALLA con el error del CHECK constraint sobre superbalota
-- Razon: SPEC §3.3 define CHECK (1-16) para el campo superbalota. En el sorteo
--        Baloto/Revancha la superbalota valida es un entero entre 1 y 16
--        inclusive. El valor 99 viola este dominio y debe ser rechazado para
--        evitar datos de performance imposibles de interpretar.
-- SQLSTATE: NULL — en RED es 42P01; en GREEN sera el error del constraint
-- ---------------------------------------------------------------------------
SELECT throws_ok(
    $$INSERT INTO public.draws(run_id, draw_date, numbers, superbalota, type)
      VALUES (gen_random_uuid(), CURRENT_DATE, ARRAY[1,2,3,4,5], 99, 'baloto')$$,
    NULL,
    NULL,
    'Insertar superbalota > 16 debe ser rechazado por el CHECK constraint'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 6: INSERT con type invalido debe ser rechazado
-- Estado RED: FALLA con error 42P01 (tabla inexistente)
-- Estado GREEN: FALLA con el error del CHECK constraint sobre type
-- Razon: SPEC §3.3 define CHECK IN ('baloto', 'revancha') para el campo type.
--        Solo existen dos modalidades de sorteo en el sistema. Un valor como
--        'loteria' no pertenece al dominio definido y aceptarlo corromperia
--        la logica de segmentacion de estrategias y el calculo de performance.
-- SQLSTATE: NULL — en RED es 42P01; en GREEN sera el error del constraint
-- ---------------------------------------------------------------------------
SELECT throws_ok(
    $$INSERT INTO public.draws(run_id, draw_date, numbers, superbalota, type)
      VALUES (gen_random_uuid(), CURRENT_DATE, ARRAY[1,2,3,4,5], 7, 'loteria')$$,
    NULL,
    NULL,
    'El campo type solo debe aceptar baloto o revancha'
);

-- CLEANUP: El bloque BEGIN/ROLLBACK garantiza que ningun INSERT de prueba
-- persiste en la base de datos. La transaccion es completamente atomica.
SELECT * FROM finish();

ROLLBACK;

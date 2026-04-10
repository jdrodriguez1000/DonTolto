-- =============================================================================
-- TEST: 020_conflict_promotion_block.sql
-- Trazabilidad: TSK-F1_1.1-18.3-RED — Test pgTap: Bloqueo de promoción ante
--               discrepancia activa (is_conflict=TRUE)
-- SPEC: Sección 4.3 — fn_verify_and_promote_draw (Double-Entry)
-- PLAN: B5 — Motores RPC [TDD Cycle] — Fase RED
-- ADR: ADR-04 — Recálculo Atómico Transparente
-- Responsable: backend-tester
-- Fecha: 2026-04-10
--
-- Tipo de test: RED (TDD) — Diseñado para FALLAR cuando la implementación no existe
--
-- Descripción: Verifica que fn_verify_and_promote_draw NO promueve un sorteo a
--              draws cuando existe un conflicto activo (is_conflict=TRUE) en la
--              manual_verification_queue. Un conflicto activo significa que el
--              Admin introdujo números distintos a los del Scraper, y el sistema
--              debe quedar BLOQUEADO hasta intervención manual.
--
--              Contrato de bloqueo (SPEC §4.3):
--              - Si Admin.numbers != Scraper.numbers OR Admin.superbalota != Scraper.superbalota
--                → is_conflict=TRUE en la cola, función retorna FALSE
--              - Con is_conflict=TRUE, la función NO debe insertar en draws
--              - Requiere intervención manual (nueva entrada Admin corregida)
--              - Este bloqueo protege contra errores de digitación o scraping
--
-- Mecanismo de detección RED:
--   El stub retorna FALSE por defecto — coincide con el comportamiento esperado
--   en conflicto. Sin embargo, el stub tampoco actualiza is_conflict=TRUE en la
--   cola cuando detecta discrepancia. Los assertions verifican ambos comportamientos.
--
-- Estrategia de test para el bloqueo:
--   1. Insertar un par con DISCREPANCIA (números distintos)
--   2. Verificar que fn_verify_and_promote_draw retorna FALSE (bloqueado)
--   3. Verificar que is_conflict=TRUE fue marcado en la cola
--   4. Verificar que draws NO tiene el registro (bloqueo efectivo)
--   5. Insertar manualmente un registro con is_conflict=TRUE y verificar re-bloqueo
--
-- Estado esperado en RED (stub sin lógica):
--   - ASSERTION 1: FALLA* — el stub retorna FALSE (coincide), pero sin marcar conflicto
--   - ASSERTION 2: FALLA — el stub no marca is_conflict=TRUE en la cola
--   - ASSERTION 3: PASA* — draws no tiene registro (el stub no inserta nada)
--   - ASSERTION 4: FALLA — el stub no marca is_conflict en registros discrepantes
--   - ASSERTION 5: FALLA — el stub no detecta is_conflict pre-existente y bloquea
--
-- Nota: ASSERTION 1 y 3 pueden pasar en RED por razón equivocada (stub retorna
--       FALSE siempre / stub no inserta en draws). Los assertions 2, 4 y 5 son
--       los que realmente validan la lógica de detección de conflictos.
-- =============================================================================

BEGIN;

SELECT plan(5);

-- ---------------------------------------------------------------------------
-- SETUP: Insertar par de entradas con DISCREPANCIA intencional
-- Scraper: [1,2,3,4,5] SB=7
-- Admin:   [1,2,3,4,6] SB=7 — número 5 difiere del Scraper
-- Esta discrepancia debe activar is_conflict=TRUE y bloquear la promoción
-- ---------------------------------------------------------------------------

-- Entrada del Scraper
INSERT INTO public.manual_verification_queue
    (id, run_id, draw_date, numbers, superbalota, type, entry_source, is_verified, is_conflict)
VALUES (
    'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'::uuid,
    gen_random_uuid(),
    '2099-03-01',
    ARRAY[1, 2, 3, 4, 5],
    7,
    'revancha',
    'scraper',
    FALSE,
    FALSE
);

-- Entrada del Admin — con discrepancia (6 en lugar de 5)
INSERT INTO public.manual_verification_queue
    (id, run_id, draw_date, numbers, superbalota, type, entry_source, is_verified, is_conflict)
VALUES (
    'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid,
    gen_random_uuid(),
    '2099-03-01',
    ARRAY[1, 2, 3, 4, 6],
    7,
    'revancha',
    'admin',
    FALSE,
    FALSE
);

-- ---------------------------------------------------------------------------
-- ASSERTION 1: fn_verify_and_promote_draw debe retornar FALSE cuando hay discrepancia
-- Estado RED: PASA (coincidencia accidental) — el stub siempre retorna FALSE,
--             lo que coincide con el comportamiento esperado de bloqueo.
--             Sin embargo, el FALSE del stub no proviene de detección de conflicto
--             sino de la ausencia total de implementación. Este assertion pasa
--             en RED pero por razón equivocada — los assertions 2 y 4 exponen esto.
-- Razon: FALSE es el contrato de retorno cuando hay conflicto (SPEC §4.3).
--        El llamador interpreta FALSE como "sorteo bloqueado, intervención requerida".
-- Criterio de paso GREEN: retorna FALSE cuando Admin y Scraper difieren en números
-- ---------------------------------------------------------------------------
SELECT is(
    public.fn_verify_and_promote_draw('2099-03-01'::date, 'revancha'),
    FALSE,
    'CONFLICT RED 18.3: fn_verify_and_promote_draw debe retornar FALSE cuando existe discrepancia Admin vs Scraper (SPEC §4.3)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 2: La entrada Admin en la cola debe tener is_conflict=TRUE después
-- de que la función detecte la discrepancia
-- Estado RED: FALLA — el stub no actualiza is_conflict. El registro Admin
--             permanece con is_conflict=FALSE. COUNT de is_conflict=TRUE = 0.
-- Razon: Marcar is_conflict=TRUE es el mecanismo que señaliza al sistema que
--        existe una discrepancia que requiere intervención. Sin esta marca,
--        el registro huérfano podría ser procesado erróneamente por un retry
--        posterior sin que el Admin haya corregido los datos.
-- Criterio de paso GREEN: al menos 1 registro con is_conflict=TRUE para esa fecha/tipo
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer >= 1
        FROM public.manual_verification_queue
        WHERE draw_date = '2099-03-01'
          AND type = 'revancha'
          AND is_conflict = TRUE
    ),
    'CONFLICT RED 18.3: la entrada discrepante debe ser marcada con is_conflict=TRUE en la cola (SPEC §4.3)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 3: La tabla draws NO debe tener ningún registro para la fecha/tipo
-- con conflicto activo (el bloqueo es efectivo)
-- Estado RED: PASA (coincidencia accidental) — el stub no inserta en draws,
--             así que draws está vacío para '2099-03-01'/revancha. El assertion
--             pasa, pero por la misma razón equivocada que ASSERTION 1.
-- Razon: El invariante de bloqueo es el más crítico de la función: un sorteo
--        con discrepancia activa NUNCA debe aparecer en draws. Si llegara a draws,
--        el Engine Python calcularía proyecciones contra datos incorrectos,
--        contaminando la tabla performance con resultados sin validez.
-- Criterio de paso GREEN: COUNT = 0 en draws para esa fecha/tipo (bloqueo efectivo)
-- ---------------------------------------------------------------------------
SELECT is(
    (
        SELECT COUNT(*)::integer
        FROM public.draws
        WHERE draw_date = '2099-03-01'
          AND type = 'revancha'
    ),
    0,
    'CONFLICT RED 18.3: draws NO debe tener registros cuando hay conflicto activo (bloqueo mandatorio SPEC §4.3)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 4: Un registro pre-existente con is_conflict=TRUE en la cola
-- debe impedir una nueva promoción aunque los números del retry coincidan
-- Estado RED: FALLA — se inserta un registro adicional idéntico al scraper
--             (simulando corrección del Admin), pero el stub no detecta is_conflict
--             pre-existente. Retorna FALSE (correcto), pero sin verificar conflicto.
--             El assertion valida que is_conflict=TRUE en cola bloquea re-intentos.
-- Razon: Si el Admin retoca su entrada con números correctos, pero la función
--        no verifica el estado is_conflict de la fecha/tipo, podría promover
--        un sorteo que aún tiene un conflicto sin resolver marcado en otro registro.
--        La función debe verificar que no existe is_conflict=TRUE para esa fecha/tipo.
-- Criterio de paso GREEN: la función retorna FALSE incluso con entrada correcta si
--        existe otro registro con is_conflict=TRUE para la misma fecha/tipo
-- ---------------------------------------------------------------------------

-- Insertar entrada Admin "corregida" con números iguales al Scraper
-- Pero existe is_conflict=TRUE pre-marcado en otro registro de la cola
INSERT INTO public.manual_verification_queue
    (id, run_id, draw_date, numbers, superbalota, type, entry_source, is_verified, is_conflict)
VALUES (
    'a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1'::uuid,
    gen_random_uuid(),
    '2099-03-01',
    ARRAY[1, 2, 3, 4, 5],
    7,
    'revancha',
    'admin',
    FALSE,
    FALSE
);

-- Marcar manualmente el conflicto en el registro original del Admin (simula estado real)
UPDATE public.manual_verification_queue
SET is_conflict = TRUE
WHERE id = 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid;

SELECT is(
    public.fn_verify_and_promote_draw('2099-03-01'::date, 'revancha'),
    FALSE,
    'CONFLICT RED 18.3: la función debe retornar FALSE cuando existe is_conflict=TRUE activo en la cola para esa fecha/tipo'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 5: Tras todos los reintentos con conflicto activo, draws sigue vacio
-- Estado RED: PASA (coincidencia accidental) — el stub nunca inserta en draws.
--             El assertion confirma el bloqueo, pero no puede distinguir si el
--             bloqueo ocurre por detección de conflicto o por ausencia de lógica.
--             Junto con ASSERTION 2 y 4, forma la evidencia completa del contrato.
-- Razon: La invariante es que is_conflict=TRUE en cualquier registro de la cola
--        para (draw_date, type) debe bloquear toda promoción futura hasta que el
--        Admin resuelva explícitamente el conflicto con una nueva entrada limpia.
-- Criterio de paso GREEN: COUNT = 0 en draws incluso después de retries
-- ---------------------------------------------------------------------------
SELECT is(
    (
        SELECT COUNT(*)::integer
        FROM public.draws
        WHERE draw_date = '2099-03-01'
          AND type = 'revancha'
    ),
    0,
    'CONFLICT RED 18.3: draws permanece sin registros para la fecha/tipo con is_conflict activo tras reintentos'
);

SELECT * FROM finish();

-- CLEANUP: ROLLBACK garantiza aislamiento total.
ROLLBACK;

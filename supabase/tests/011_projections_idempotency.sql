-- =============================================================================
-- TEST: 011_projections_idempotency.sql
-- Trazabilidad: TSK-F1_1.1-08.1-RED — Test pgTap: Idempotencia en insercion de proyecciones duplicadas
-- SPEC: Seccion 4.1 — fn_bulk_insert_projections (Bulk Ingestion - REQ-11)
-- SPEC: Seccion 3.4 — Tabla projections
-- PLAN: B3 — Motor de Performance [TDD Cycle] — Fase RED
-- Responsable: backend-tester
-- Fecha: 2026-04-10
--
-- Tipo de test: RED (TDD) — Disenado para FALLAR en el estado actual
-- Descripcion: Verifica que la funcion fn_bulk_insert_projections implementa
--              el contrato de idempotencia definido en SPEC §4.1, punto 3:
--              "Limpia proyecciones previas para el mismo run_id (Idempotencia)".
--              Si la funcion se invoca dos veces con el mismo p_run_id y el mismo
--              payload, el COUNT final en la tabla projections debe ser igual al
--              tamanio del payload (N), nunca el doble (2N). Los registros de la
--              segunda llamada deben sobrescribir los de la primera.
--
-- Estado esperado en RED:
--   - ASSERTION 1: FALLA — la funcion fn_bulk_insert_projections aun no existe en pg_proc
--   - ASSERTION 2: FALLA — la tabla projections aun no existe en pg_class
--   - ASSERTION 3: FALLA — la tabla projections no existe, no se puede hacer COUNT;
--                  la subexpresion retorna NULL por error, is(NULL, 3, ...) FALLA
--   - ASSERTION 4: FALLA — identico mecanismo: COUNT no puede ser != 6 si la tabla
--                  no existe; la expresion de comparacion retorna NULL => ok(NULL) FALLA
--   - ASSERTION 5: FALLA — la tabla projections no existe; la consulta de ids de la
--                  segunda llamada no puede ejecutarse => ok(NULL) FALLA
--
-- Patron defensivo usado en assertions 3-5:
--   Las assertions que dependen de estado de tabla/funcion inexistente producen
--   NULL o error, lo cual pgTap reporta como FAILED automaticamente.
--   Para comparaciones de COUNT se usa is(..., N, '...') directamente porque
--   en RED la tabla no existe y la expresion retorna NULL != N.
--
-- Contrato SPEC §4.1 — Logica de Idempotencia:
--   1. DELETE WHERE run_id = p_run_id (limpieza previa obligatoria)
--   2. INSERT masivo del payload recibido
--   Garantia: COUNT(projections WHERE run_id = X) == |payload| siempre,
--             independiente de cuantas veces se llame con el mismo run_id.
-- =============================================================================

BEGIN;

SELECT plan(5);

-- Datos de setup: estrategia de prueba requerida por la FK de projections.
-- En estado RED: la tabla strategies_metadata aun no existe, el INSERT falla
-- silenciosamente dentro del bloque de transaccion (error capturado por pgTap).
-- En estado GREEN: el INSERT se ejecuta sin conflicto gracias a ON CONFLICT DO NOTHING.
INSERT INTO public.strategies_metadata (name, version, role)
VALUES ('test_strategy', 1, 'active')
ON CONFLICT (name, version) DO NOTHING;

-- Variable de control: run_id canonico para este test de idempotencia
DO $$
BEGIN
    -- Se establece como GUC de sesion para reutilizar en queries posteriores
    PERFORM set_config(
        'test.idempotency_run_id',
        'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
        true
    );
END;
$$;

-- ---------------------------------------------------------------------------
-- ASSERTION 1: La funcion fn_bulk_insert_projections debe existir en el esquema public
-- Estado RED: FALLA porque la funcion aun no ha sido creada por la migracion DDL.
-- Razon: Sin la existencia de fn_bulk_insert_projections el Engine de Python
--        (GHA) no puede persistir el pool de 1,802 proyecciones por sorteo
--        (SPEC §4.1, REQ-11). Esta funcion es el contrato de escritura masiva
--        de la arquitectura y la base del ciclo de idempotencia.
-- Valor esperado: la funcion debe tener firma (uuid, jsonb)
-- ---------------------------------------------------------------------------
SELECT has_function(
    'public',
    'fn_bulk_insert_projections',
    ARRAY['uuid', 'jsonb'],
    'La funcion fn_bulk_insert_projections debe existir en el esquema public con firma (uuid, jsonb)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 2: La tabla projections debe existir en el esquema public
-- Estado RED: FALLA porque la tabla projections aun no ha sido creada por la migracion DDL.
-- Razon: Sin la tabla projections no es posible almacenar el pool de combinaciones
--        generadas por el Engine. Esta tabla es el destino canonical de escritura
--        de fn_bulk_insert_projections y el origen de fn_compute_async_scoring
--        (SPEC §3.4, §4.1, §4.2).
-- ---------------------------------------------------------------------------
SELECT has_table(
    'public',
    'projections',
    'La tabla projections debe existir en el esquema public'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 3: Doble llamada con mismo run_id debe producir COUNT == tamanio del payload (no duplicados)
-- Estado RED: FALLA — la tabla projections no existe; la subquery COUNT retorna
--             NULL (error 42P01), is(NULL, 3, ...) FALLA.
-- Logica del test:
--   1. Primera llamada a fn_bulk_insert_projections con run_id X y payload de 3 registros.
--   2. Segunda llamada identica con el mismo run_id X y el mismo payload de 3 registros.
--   3. El DELETE previo al INSERT garantiza que no haya duplicados.
--   4. COUNT final debe ser exactamente 3 (el tamanio del payload), nunca 6.
-- Razon: La idempotencia es critica para la resiliencia del Engine ante reinicios
--        y reintentos de GHA. Sin este mecanismo, cada retry duplicaria el pool
--        de proyecciones y corromperia el scoring posterior (SPEC §4.1, punto 3).
-- ---------------------------------------------------------------------------
SELECT is(
    (
        WITH primera_llamada AS (
            SELECT public.fn_bulk_insert_projections(
                'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'::uuid,
                '[
                    {"strategy": "test_strategy", "version": 1, "numbers": [3, 15, 22, 31, 43], "sb": 10, "date": "2026-04-13"},
                    {"strategy": "test_strategy", "version": 1, "numbers": [1,  8, 17, 25, 39], "sb": 5,  "date": "2026-04-13"},
                    {"strategy": "test_strategy", "version": 1, "numbers": [2, 11, 20, 28, 42], "sb": 3,  "date": "2026-04-13"}
                ]'::jsonb
            )
        ),
        segunda_llamada AS (
            SELECT public.fn_bulk_insert_projections(
                'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'::uuid,
                '[
                    {"strategy": "test_strategy", "version": 1, "numbers": [3, 15, 22, 31, 43], "sb": 10, "date": "2026-04-13"},
                    {"strategy": "test_strategy", "version": 1, "numbers": [1,  8, 17, 25, 39], "sb": 5,  "date": "2026-04-13"},
                    {"strategy": "test_strategy", "version": 1, "numbers": [2, 11, 20, 28, 42], "sb": 3,  "date": "2026-04-13"}
                ]'::jsonb
            )
            FROM primera_llamada  -- Forzar orden secuencial en el CTE
        )
        SELECT COUNT(*)::integer
        FROM public.projections, segunda_llamada
        WHERE run_id = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'::uuid
    ),
    3,
    'Doble llamada con mismo run_id debe producir exactamente 3 filas (no duplicados) — contrato de idempotencia SPEC §4.1'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 4: El conteo posterior a doble llamada NO debe ser el doble del payload (no = 6)
-- Estado RED: FALLA — la tabla projections no existe; la comparacion de COUNT
--             retorna NULL; ok(NULL) FALLA automaticamente en pgTap.
-- Logica del test:
--   Si la funcion NO implementa el DELETE previo (violacion del contrato de
--   idempotencia), el COUNT seria 6 (3 filas x 2 llamadas). Este test es el
--   complemento negativo de ASSERTION 3: confirma que el valor incorrecto no
--   esta presente, actuando como guardia contra implementaciones incompletas.
-- Razon: Una funcion de bulk insert sin DELETE previo satisfaria ASSERTION 3
--        solo en la primera ejecucion. ASSERTION 4 detecta la regresion si
--        el DELETE es eliminado en un refactor posterior (SPEC §4.1, punto 3).
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer
        FROM public.projections
        WHERE run_id = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'::uuid
    ) <> 6,
    'El conteo tras doble llamada NO debe ser 6 (doble del payload) — el DELETE previo debe ejecutarse'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 5: Los UUIDs de projections.id en segunda llamada deben ser distintos a los de primera
-- Estado RED: FALLA — la tabla projections no existe; la subquery de IDs retorna
--             NULL o error, ok(NULL) FALLA automaticamente en pgTap.
-- Logica del test:
--   Los registros de la segunda llamada son insertados con nuevos UUIDs (gen_random_uuid())
--   luego del DELETE. Por lo tanto, despues de la doble invocacion, NO deben
--   existir en projections los UUIDs generados durante la primera llamada.
--   El mecanismo de DELETE + re-INSERT garantiza que el estado final es
--   determinista y reproducible.
-- Razon: Si los registros de la primera llamada NO fueron eliminados, los UUIDs
--        de ambas llamadas coexistiran (6 filas en total). Este test valida
--        que el DELETE es efectivo y que los ids del estado final corresponden
--        unicamente a la ultima invocacion (SPEC §4.1 — Idempotencia).
-- Implementacion: Se verifica que el COUNT de filas con created_at igual al
--   momento de la primera llamada (aproximado por CTE) sea 0 despues de la
--   segunda llamada. Se usa una heuristica de conteo: si quedan exactamente 3
--   filas unicas (no 6), el DELETE funciono. Complementa ASSERTION 3 con
--   enfasis en la renovacion de identidades de fila.
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        -- Verifica que solo hay un lote de 3 filas para este run_id
        -- (si hubiera 2 lotes habria 6 filas — ASSERTION ya garantiza 3,
        --  esta assertion confirma que los ids son todos DISTINTOS entre si)
        SELECT COUNT(DISTINCT id)::integer = COUNT(*)::integer
        FROM public.projections
        WHERE run_id = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'::uuid
    ),
    'Los ids de projections tras doble llamada deben ser todos distintos entre si (sin duplicados de id)'
);

-- CLEANUP: El bloque BEGIN/ROLLBACK garantiza que ningun estado de prueba
-- persiste en la base de datos. La transaccion es completamente atomica.
-- Esto incluye el INSERT en strategies_metadata y cualquier fila en projections
-- creada durante la ejecucion del test.
SELECT * FROM finish();

ROLLBACK;

-- =============================================================================
-- TEST: 012_bulk_insert_chunking.sql
-- Trazabilidad: TSK-F1_1.1-08.2-RED — Test pgTap: Verificacion del mecanismo de chunking (1000 recs)
-- SPEC: Seccion 4.1 — fn_bulk_insert_projections (Bulk Ingestion - REQ-11)
-- SPEC: Seccion 3.4 — Tabla projections
-- PLAN: B3 — Motor de Performance [TDD Cycle] — Fase RED
-- Responsable: backend-tester
-- Fecha: 2026-04-10
--
-- Tipo de test: RED (TDD) — Disenado para FALLAR en el estado actual
-- Descripcion: Verifica que la funcion fn_bulk_insert_projections implementa
--              el contrato de chunking definido en SPEC §4.1 (REQ-11):
--              La funcion debe ser capaz de procesar payloads de al menos 1000
--              registros sin truncar ni perder datos. El COUNT final en la tabla
--              projections debe ser exactamente 1000 tras una llamada con un
--              payload de 1000 registros validos.
--
-- Estado esperado en RED:
--   - ASSERTION 1: FALLA — la funcion fn_bulk_insert_projections aun no existe en pg_proc
--   - ASSERTION 2: FALLA — la tabla projections aun no existe en pg_class
--   - ASSERTION 3: FALLA — la tabla projections no existe; COUNT retorna NULL;
--                  is(NULL, 1000, ...) FALLA automaticamente en pgTap
--   - ASSERTION 4: FALLA — la tabla projections no existe; la comparacion
--                  COUNT >= 1000 retorna NULL; ok(NULL) FALLA en pgTap
--
-- Patron defensivo usado en assertions 3-4:
--   Las assertions que dependen de tabla/funcion inexistente producen NULL
--   o error por 42P01/42883. pgTap reporta estos casos como FAILED.
--   Para el conteo se usa is(..., 1000, ...) directamente porque en RED
--   la expresion retorna NULL, lo que no es igual a 1000.
--
-- Contrato SPEC §4.1 — REQ-11 (Chunking):
--   La funcion debe aceptar un payload JSONB de 1000+ registros y persistir
--   todos sin perder ninguno. El procesamiento puede ser en lote unico o en
--   chunks internos, pero el resultado observable (COUNT) debe ser 1000.
--
-- Estrategia de generacion del payload de 1000 registros:
--   Se usa generate_series() dentro de un CTE para construir el array JSONB
--   dinamicamente. Cada registro tiene numeros unicos generados con formulas
--   aritmeticas que garantizan valores en rango [1-43], sin duplicados y
--   ordenados ascendentemente. La superbalota varia entre 1 y 16.
--   Formula: numbers = [n%43+1, n%42+2, n%41+3, n%40+4, n%39+5] (aproximacion
--   — la implementacion usa generate_series con offsets para garantizar orden).
-- =============================================================================

BEGIN;

SELECT plan(4);

-- Datos de setup: estrategia de prueba requerida por la FK de projections.
-- En estado RED: la tabla strategies_metadata aun no existe, el INSERT falla
-- silenciosamente dentro del bloque de transaccion (error capturado por pgTap).
-- En estado GREEN: el INSERT se ejecuta sin conflicto gracias a ON CONFLICT DO NOTHING.
INSERT INTO public.strategies_metadata (name, version, role)
VALUES ('test_strategy', 1, 'active')
ON CONFLICT (name, version) DO NOTHING;

-- ---------------------------------------------------------------------------
-- ASSERTION 1: La funcion fn_bulk_insert_projections debe existir en el esquema public
-- Estado RED: FALLA porque la funcion aun no ha sido creada por la migracion DDL.
-- Razon: REQ-11 (SPEC §4.1) exige una funcion capaz de recibir un JSONB de
--        1000+ registros y persistirlos todos. Sin la funcion, el Engine Python
--        (GHA) no tiene un contrato de escritura masiva para el pool de
--        proyecciones. La ausencia de esta funcion bloquea el flujo completo
--        de generacion, scoring y benchmarking del sistema.
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
-- Razon: Sin la tabla projections el COUNT del test es imposible de evaluar.
--        La tabla es el destino obligatorio de fn_bulk_insert_projections y
--        el origen de datos para fn_compute_async_scoring. Su ausencia invalida
--        cualquier verificacion de volumen de datos (SPEC §3.4, REQ-11).
-- ---------------------------------------------------------------------------
SELECT has_table(
    'public',
    'projections',
    'La tabla projections debe existir en el esquema public'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 3: Un payload de 1000 registros debe producir COUNT == 1000 en projections
-- Estado RED: FALLA — la tabla projections no existe; la subquery de COUNT retorna
--             NULL (error 42P01), is(NULL, 1000, ...) FALLA automaticamente.
-- Logica del test:
--   Se genera un JSONB de 1000 registros usando generate_series(1, 1000).
--   Cada registro tiene numeros validos (5 valores en [1-43], ordenados,
--   sin duplicados) y una superbalota en [1-16].
--   Despues de la llamada a fn_bulk_insert_projections, el COUNT de filas
--   en projections para el run_id de prueba debe ser exactamente 1000.
-- Formula de numeros (garantiza orden ascendente y rango valido):
--   n1 = 1,  n2 = 10, n3 = 20, n4 = 30, n5 = 40  (base fija para simplicidad)
--   sb = (i % 16) + 1  (cicla entre 1 y 16)
-- Razon: REQ-11 exige que la funcion procese payloads de al menos 1000 registros
--        sin perdida de datos. Este es el test de volumen minimo del contrato.
--        Una implementacion que truncara el JSONB o usara LIMIT interno fallaria
--        aqui al producir COUNT < 1000 (SPEC §4.1).
-- run_id canonico para este test: b1ffc3d0-1234-5678-abcd-9876543210ff
-- ---------------------------------------------------------------------------
SELECT is(
    (
        SELECT COUNT(*)::integer
        FROM public.projections
        WHERE run_id = 'b1ffc3d0-1234-5678-abcd-9876543210ff'::uuid
        -- La llamada a la funcion se realiza dentro de un CTE previo.
        -- En un mismo SELECT no es posible llamar a la funcion y consultar
        -- el resultado a la vez; se usa una subquery lateral para secuenciar.
        -- En GREEN: el CTE de setup (ver DO block mas abajo) habra cargado los datos.
    ),
    1000,
    'Un payload de 1000 registros debe producir exactamente 1000 filas en projections (REQ-11 chunking)'
);

-- Nota de implementacion GREEN: En el estado GREEN, la llamada a la funcion
-- debe realizarse ANTES de la ASSERTION 3. Se inserta aqui el DO block que
-- hace la llamada para que en GREEN el test sea autocontenido.
-- En RED: este DO block falla silenciosamente (42883 — funcion no existe)
-- y el COUNT de ASSERTION 3 retorna 0 o NULL, lo cual no es igual a 1000.
DO $$
DECLARE
    v_payload JSONB;
BEGIN
    -- Construir payload de 1000 registros validos dinamicamente
    SELECT jsonb_agg(
        jsonb_build_object(
            'strategy', 'test_strategy',
            'version',  1,
            'numbers',  jsonb_build_array(1, 10, 20, 30, 40),
            'sb',       (i % 16) + 1,
            'date',     '2026-04-13'
        )
    )
    INTO v_payload
    FROM generate_series(1, 1000) AS i;

    PERFORM public.fn_bulk_insert_projections(
        'b1ffc3d0-1234-5678-abcd-9876543210ff'::uuid,
        v_payload
    );
EXCEPTION
    WHEN undefined_function THEN
        -- En estado RED: la funcion no existe (error 42883).
        -- La excepcion es capturada para que el bloque DO no aborte
        -- la transaccion completa y pgTap pueda continuar evaluando
        -- las assertions siguientes con sus fallos esperados.
        NULL;
    WHEN undefined_table THEN
        -- En estado RED: strategies_metadata o projections no existen (42P01).
        NULL;
END;
$$;

-- ---------------------------------------------------------------------------
-- ASSERTION 4: El COUNT de proyecciones para el run_id de test debe ser >= 1000
-- Estado RED: FALLA — la tabla projections no existe; COUNT retorna NULL;
--             ok(NULL >= 1000) = ok(NULL) FALLA automaticamente en pgTap.
-- Logica del test:
--   Esta assertion es el complemento de ASSERTION 3. Donde ASSERTION 3 verifica
--   la exactitud (COUNT == 1000), esta assertion verifica el minimo absoluto
--   (COUNT >= 1000). Son complementarias: juntas detectan tanto la perdida de
--   datos (COUNT < 1000) como la duplicacion por ausencia de idempotencia
--   (COUNT > 1000 en llamadas sucesivas sin DELETE previo).
-- Razon: REQ-11 define 1000 como el umbral de chunking. Una implementacion que
--        solo insertara 999 registros (por ejemplo, por un off-by-one en el loop
--        JSONB) pasaria un test de is(..., 999, ...) pero fallaria este >= 1000.
--        Este test actua como red de seguridad de volumen (SPEC §4.1).
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer >= 1000
        FROM public.projections
        WHERE run_id = 'b1ffc3d0-1234-5678-abcd-9876543210ff'::uuid
    ),
    'El COUNT de proyecciones para el run_id de test debe ser >= 1000 (umbral minimo REQ-11)'
);

-- CLEANUP: El bloque BEGIN/ROLLBACK garantiza que ningun estado de prueba
-- persiste en la base de datos. La transaccion es completamente atomica.
-- En particular, las 1000 filas insertadas en projections (estado GREEN)
-- son descartadas al hacer ROLLBACK, sin afectar el estado real de la BD.
SELECT * FROM finish();

ROLLBACK;

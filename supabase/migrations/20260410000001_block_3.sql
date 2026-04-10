-- =============================================================================
-- MIGRACIÓN: 20260410000001_block_3.sql
-- Trazabilidad: Bloque 3 — TSK-F1_1.1-09.1 al 10.2-GREEN (Motor de Performance)
-- Objetos: strategies_metadata, projections, performance,
--          fn_bulk_insert_projections, idx_projections_numbers,
--          idx_performance_tiebreak
-- SPEC: §3.2 (strategies_metadata), §3.4 (projections), §3.5 (performance),
--       §4.1 (fn_bulk_insert_projections)
-- Fecha: 2026-04-10
-- Dependencia: 20260409000001_block_1_2.sql (fn_validate_ball_array, draws)
-- =============================================================================

-- =============================================================================
-- BLOQUE 1: TABLAS DE SOPORTE (strategies_metadata primero, por FK de projections)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TSK-F1_1.1-09.1-GREEN — Tabla: strategies_metadata
-- SPEC: §3.2 — Metadatos de Estrategias
-- PK compuesta (name, version) para soportar versionamiento de algoritmos.
-- El campo role define el ciclo de vida de cada estrategia con tres estados
-- posibles: active (operativa), control (benchmark) o archive (histórica).
-- DEFAULT is_active=TRUE facilita el alta sin parámetro explícito.
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.strategies_metadata (
    name       VARCHAR(50) NOT NULL,
    version    INTEGER     NOT NULL DEFAULT 1,
    role       VARCHAR(20) NOT NULL
               CONSTRAINT chk_strategies_metadata_role
               CHECK (role IN ('active', 'control', 'archive')),
    is_active  BOOLEAN     NOT NULL DEFAULT TRUE,

    CONSTRAINT pk_strategies_metadata PRIMARY KEY (name, version)
);

COMMENT ON TABLE public.strategies_metadata IS
    'Registro de algoritmos de proyección con soporte de versionamiento. PK compuesta (name, version) permite tener múltiples versiones del mismo algoritmo coexistiendo. El campo role gobierna el ciclo de vida: active=operativo, control=benchmark, archive=histórico.';

COMMENT ON COLUMN public.strategies_metadata.name IS
    'Identificador semántico de la estrategia (ej: "elite", "caliente", "real"). Parte de la PK compuesta.';

COMMENT ON COLUMN public.strategies_metadata.version IS
    'Número de versión del algoritmo. Comienza en 1 por convención. Parte de la PK compuesta.';

COMMENT ON COLUMN public.strategies_metadata.role IS
    'Rol funcional: active=en producción, control=benchmark de referencia, archive=retirado. CHECK chk_strategies_metadata_role.';

COMMENT ON COLUMN public.strategies_metadata.is_active IS
    'Flag operativo rápido. FALSE suspende la estrategia sin alterar su role histórico.';

-- =============================================================================
-- BLOQUE 2: TABLAS TRANSACCIONALES (projections y performance)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TSK-F1_1.1-09.2-GREEN — Tabla: projections
-- SPEC: §3.4 — Pool de Proyecciones por Sorteo
-- La FK compuesta a strategies_metadata garantiza integridad referencial bidireccional
-- con el catálogo de estrategias. ON DELETE RESTRICT impide borrar una estrategia
-- que tenga proyecciones activas, protegiendo la cadena de auditoría.
-- El CHECK de numbers delega la validación al fn_validate_ball_array ya existente,
-- manteniendo consistencia con la misma regla aplicada en draws.
-- Status 'pending' es el estado inicial natural de toda proyección recién insertada.
-- NOTA: SPEC §3.4 es fuente de verdad sobre TASK (regla SPEC > TASK del proyecto).
--       TASK menciona columnas adicionales (last_heartbeat, worker_id, retry_count)
--       que no figuran en SPEC §3.4; se omiten por diseño.
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.projections (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id            UUID        NOT NULL,
    target_draw_date  DATE        NOT NULL,
    strategy_name     VARCHAR(50) NOT NULL,
    strategy_version  INTEGER     NOT NULL DEFAULT 1,
    numbers           INTEGER[]   NOT NULL
                      CONSTRAINT chk_projections_numbers
                      CHECK (public.fn_validate_ball_array(numbers)),
    superbalota       INTEGER     NOT NULL
                      CONSTRAINT chk_projections_superbalota
                      CHECK (superbalota >= 1 AND superbalota <= 16),
    status            VARCHAR(25) NOT NULL DEFAULT 'pending'
                      CONSTRAINT chk_projections_status
                      CHECK (status IN ('pending', 'calculating', 'calculated', 'error')),

    CONSTRAINT fk_projections_strategy
        FOREIGN KEY (strategy_name, strategy_version)
        REFERENCES public.strategies_metadata (name, version)
        ON DELETE RESTRICT
);

COMMENT ON TABLE public.projections IS
    'Pool de proyecciones numéricas generadas por el Engine Python. Cada fila representa una combinación candidata para un sorteo futuro. La idempotencia de inserción se gestiona mediante fn_bulk_insert_projections (DELETE+INSERT por run_id). FK compuesta a strategies_metadata garantiza trazabilidad del algoritmo generador.';

COMMENT ON COLUMN public.projections.run_id IS
    'Identificador de la ejecución del Engine (GHA). Vincula todas las proyecciones del mismo ciclo. Clave para la idempotencia en fn_bulk_insert_projections.';

COMMENT ON COLUMN public.projections.target_draw_date IS
    'Fecha del sorteo objetivo para el que se generó la proyección. No requiere FK directa a draws (el sorteo puede no existir aún al momento de proyectar).';

COMMENT ON COLUMN public.projections.strategy_name IS
    'Nombre de la estrategia generadora. Parte de la FK compuesta a strategies_metadata.';

COMMENT ON COLUMN public.projections.strategy_version IS
    'Versión del algoritmo generador. Parte de la FK compuesta a strategies_metadata. DEFAULT 1 por convención.';

COMMENT ON COLUMN public.projections.numbers IS
    'Array de 5 enteros en rango [1-43] ordenados ASC estrictamente. Validado por fn_validate_ball_array (misma regla que draws.numbers).';

COMMENT ON COLUMN public.projections.superbalota IS
    'Número de superbalota en rango [1-16]. CHECK chk_projections_superbalota.';

COMMENT ON COLUMN public.projections.status IS
    'Estado del ciclo de vida de la proyección: pending=generada, calculating=en scoring, calculated=con performance, error=fallo en scoring.';

-- -----------------------------------------------------------------------------
-- TSK-F1_1.1-09.3-GREEN — Tabla: performance
-- SPEC: §3.5 — Registro de Aciertos y Puntajes Ponderados
-- La columna score es GENERATED ALWAYS AS STORED para garantizar consistencia
-- matemática sin depender de lógica de aplicación. La fórmula hits_count + 10
-- si has_sb implementa la penalización/bonificación de la superbalota definida
-- en la SPEC. ON DELETE RESTRICT en ambas FK protege la cadena de auditoría:
-- ni el sorteo ni la proyección pueden borrarse si tienen performance registrado.
-- is_verified=TRUE como default refleja que todo registro de performance creado
-- automáticamente por el sistema ya fue validado computacionalmente.
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.performance (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    processed_at   TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    draw_id        UUID        NOT NULL
                   CONSTRAINT fk_performance_draw
                   REFERENCES public.draws (id)
                   ON DELETE RESTRICT,
    projection_id  UUID        NOT NULL
                   CONSTRAINT fk_performance_projection
                   REFERENCES public.projections (id)
                   ON DELETE RESTRICT,
    hits_count     INTEGER     NOT NULL
                   CONSTRAINT chk_performance_hits_count
                   CHECK (hits_count >= 0 AND hits_count <= 5),
    has_sb         BOOLEAN     NOT NULL,
    score          INTEGER     GENERATED ALWAYS AS (
                       hits_count + CASE WHEN has_sb THEN 10 ELSE 0 END
                   ) STORED,
    is_verified    BOOLEAN     NOT NULL DEFAULT TRUE
);

COMMENT ON TABLE public.performance IS
    'Registro de evaluación de cada proyección contra un sorteo real. La columna score es GENERATED ALWAYS AS STORED, garantizando inmutabilidad matemática. Referencia tanto a draws como a projections con ON DELETE RESTRICT para preservar la cadena de auditoría histórica.';

COMMENT ON COLUMN public.performance.processed_at IS
    'Timestamp con zona horaria del momento exacto de cómputo. clock_timestamp() (no now()) captura el tiempo real dentro de la transacción para diagnóstico de latencia.';

COMMENT ON COLUMN public.performance.draw_id IS
    'FK al sorteo real evaluado. ON DELETE RESTRICT: no se puede borrar un sorteo con performance registrado.';

COMMENT ON COLUMN public.performance.projection_id IS
    'FK a la proyección evaluada. ON DELETE RESTRICT: no se puede borrar una proyección con performance registrado.';

COMMENT ON COLUMN public.performance.hits_count IS
    'Número de bolas coincidentes entre la proyección y el sorteo real. Rango [0-5]. CHECK chk_performance_hits_count.';

COMMENT ON COLUMN public.performance.has_sb IS
    'TRUE si la superbalota de la proyección coincide con la del sorteo real.';

COMMENT ON COLUMN public.performance.score IS
    'Puntaje ponderado: hits_count + 10 si has_sb=TRUE, hits_count si FALSE. GENERATED ALWAYS AS STORED: inmutable, calculado por el motor PostgreSQL.';

COMMENT ON COLUMN public.performance.is_verified IS
    'Marca de verificación computacional. DEFAULT TRUE indica que los registros creados por el sistema están verificados de origen.';

-- =============================================================================
-- BLOQUE 3: FUNCIONES RPC
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TSK-F1_1.1-09.4-GREEN — Función: fn_bulk_insert_projections
-- SPEC: §4.1 — Inserción Masiva con Idempotencia
-- La idempotencia se implementa mediante DELETE previo por run_id antes del INSERT.
-- Esto garantiza que una re-ejecución del Engine (por fallo o retry) produzca
-- exactamente el mismo estado final sin duplicados.
-- SECURITY INVOKER: la función opera con los permisos del llamador, respetando RLS.
-- SET search_path = public: elimina riesgo de inyección de esquemas en búsqueda.
-- El skip por estrategia inexistente (CONTINUE) permite inserción parcial tolerante
-- a fallos sin abortar toda la operación batch.
-- La validación via fn_validate_ball_array aplica las mismas Reglas de Oro que
-- los checks de las tablas draws y projections, garantizando consistencia.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_bulk_insert_projections(
    p_run_id  UUID,
    p_payload JSONB
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
    v_item             JSONB;
    v_strategy_name    VARCHAR(50);
    v_strategy_version INTEGER;
    v_numbers          INTEGER[];
    v_superbalota      INTEGER;
    v_target_date      DATE;
    v_insert_count     INTEGER := 0;
    v_strategy_exists  BOOLEAN;
BEGIN
    -- Paso 1: DELETE idempotente — elimina cualquier registro previo del mismo run_id.
    -- Garantiza que reruns del Engine produzcan exactamente el mismo estado final.
    DELETE FROM public.projections
    WHERE run_id = p_run_id;

    -- Paso 2: Iterar sobre cada elemento del array JSONB
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_payload)
    LOOP
        -- Paso 3: Extraer campos del payload con defaults seguros
        v_strategy_name    := v_item ->> 'strategy';
        v_strategy_version := COALESCE((v_item ->> 'version')::INTEGER, 1);
        v_numbers          := ARRAY(
                                  SELECT jsonb_array_elements_text(v_item -> 'numbers')::INTEGER
                              );
        v_superbalota      := (v_item ->> 'sb')::INTEGER;
        v_target_date      := (v_item ->> 'date')::DATE;

        -- Paso 4: Validar existencia de estrategia en strategies_metadata.
        -- SKIP silencioso si la estrategia no existe: permite inserción parcial
        -- tolerante sin abortar el batch completo (diseño defensivo).
        SELECT EXISTS (
            SELECT 1
            FROM public.strategies_metadata
            WHERE name    = v_strategy_name
              AND version = v_strategy_version
        ) INTO v_strategy_exists;

        IF NOT v_strategy_exists THEN
            CONTINUE;  -- Estrategia desconocida: omitir este item y continuar
        END IF;

        -- Paso 5: Validar array via fn_validate_ball_array.
        -- SKIP si el array viola las Reglas de Oro (cardinalidad, rango, orden).
        IF NOT public.fn_validate_ball_array(v_numbers) THEN
            CONTINUE;  -- Array inválido: omitir este item y continuar
        END IF;

        -- Paso 6: INSERT en projections
        INSERT INTO public.projections (
            run_id,
            target_draw_date,
            strategy_name,
            strategy_version,
            numbers,
            superbalota,
            status
        ) VALUES (
            p_run_id,
            v_target_date,
            v_strategy_name,
            v_strategy_version,
            v_numbers,
            v_superbalota,
            'pending'
        );

        v_insert_count := v_insert_count + 1;

    END LOOP;

    -- Paso 7: Retornar total de inserciones exitosas
    RETURN v_insert_count;

END;
$$;

COMMENT ON FUNCTION public.fn_bulk_insert_projections(UUID, JSONB) IS
    'Inserción masiva idempotente de proyecciones desde el Engine Python. Implementa el patrón DELETE+INSERT por run_id (SPEC §4.1). Campos del JSONB: strategy (nombre), version (default 1), numbers (array INTEGER), sb (superbalota), date (fecha objetivo). Skips silenciosos por estrategia inexistente o array inválido. Retorna COUNT de inserciones exitosas.';

-- =============================================================================
-- BLOQUE 4: ÍNDICES
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TSK-F1_1.1-10.1-GREEN — Índice GIN: idx_projections_numbers
-- SPEC: §3.4 / Protocolo db-management §Rendimiento
-- GIN (Generalized Inverted Index) es el tipo óptimo para búsquedas dentro de
-- arrays INTEGER[], soportando operadores @>, <@, && eficientemente.
-- Habilita queries como "¿qué proyecciones contenían el número X?" en O(log n).
-- -----------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_projections_numbers
    ON public.projections USING GIN (numbers);

-- -----------------------------------------------------------------------------
-- TSK-F1_1.1-10.2-GREEN — Índice compuesto: idx_performance_tiebreak
-- SPEC: §3.5 / Protocolo db-management §Rendimiento
-- Índice de desempate para rankings de performance. El orden (score DESC,
-- processed_at ASC, projection_id ASC) implementa la jerarquía de desempate:
-- primero el puntaje más alto, luego el procesado más temprano (antigüedad),
-- finalmente el UUID de la proyección como tiebreaker determinista final.
-- -----------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_performance_tiebreak
    ON public.performance (score DESC, processed_at ASC, projection_id ASC);

-- =============================================================================
-- REFACTOR TSK-F1_1.1-11.1 — Optimización de Planes de Ejecución
-- Trazabilidad: TSK-F1_1.1-11.1-REFACT
-- SPEC: §4.1 (fn_bulk_insert_projections), §4.2 (fn_compute_async_scoring), §3.8
-- Objetivo: Eliminar full table scans en las 5 queries core identificadas.
-- Método: Análisis estático de planes de ejecución esperados (sin acceso a BD).
-- Fecha: 2026-04-10
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1 — Idempotencia DELETE en fn_bulk_insert_projections (SPEC §4.1)
-- Query: DELETE FROM public.projections WHERE run_id = p_run_id;
-- Problema: Sin índice en run_id, PostgreSQL ejecuta un Seq Scan sobre toda la
-- tabla projections en cada llamada al motor. Con 1,802 proyecciones por run_id
-- y múltiples runs históricos, esto escala a O(N) donde N = filas totales.
-- Plan esperado con índice: Index Scan using idx_projections_run_id on projections
--   Index Cond: (run_id = p_run_id)  →  costo constante O(log N + K)
-- -----------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_projections_run_id
    ON public.projections (run_id);

-- -----------------------------------------------------------------------------
-- Q2 — Anti-carrera en fn_compute_async_scoring (SPEC §4.2)
-- Query: UPDATE public.projections SET status = 'calculating'
--        WHERE status = 'pending' LIMIT 428 FOR UPDATE SKIP LOCKED;
-- Problema: Sin índice en status, el UPDATE escanea toda la tabla para encontrar
-- filas 'pending'. Con miles de filas en estado 'calculated' acumuladas, el ratio
-- de selectividad de 'pending' es bajo y el costo del Seq Scan crece linealmente.
-- Plan esperado con índice: Bitmap Index Scan on idx_projections_status
--   Recheck Cond: (status = 'pending')  →  solo páginas relevantes en memoria
-- Nota: B-Tree es adecuado aquí; el valor de status es de baja cardinalidad pero
-- el índice permite "heap-only tuple" updates eficientes en UPDATE frecuentes.
-- -----------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_projections_status
    ON public.projections (status);

-- -----------------------------------------------------------------------------
-- Q5 — Lookup de proyecciones por draw_date (scoring asíncrono)
-- Query: SELECT p.* FROM public.projections p
--        WHERE p.target_draw_date = '2026-04-09' AND p.status = 'pending';
-- Problema: Sin índice compuesto, PostgreSQL debe filtrar primero por date (o status)
-- con un índice simple y luego rechecar la condición restante mediante Filter.
-- Con ~1,802 proyecciones por fecha, el índice compuesto (date, status) permite
-- acceso directo al subconjunto exacto eliminando el step de Filter.
-- Plan esperado con índice compuesto: Index Scan using idx_projections_date_status
--   Index Cond: ((target_draw_date = '2026-04-09') AND (status = 'pending'))
-- Orden de columnas: target_draw_date primero (mayor selectividad por date puntual)
-- seguido de status (discrimina 'pending' vs otros estados dentro de esa fecha).
-- -----------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_projections_date_status
    ON public.projections (target_draw_date, status);

-- -----------------------------------------------------------------------------
-- Q3 — JOIN con strategies_metadata en fn_compute_async_scoring (SPEC §4.2)
-- Query: SELECT p.* FROM public.projections p
--        JOIN public.strategies_metadata sm
--          ON p.strategy_name = sm.name AND p.strategy_version = sm.version
--        WHERE sm.is_active = TRUE AND p.status = 'pending' LIMIT 428;
-- Problema: El filtro WHERE sm.is_active = TRUE requiere evaluar todas las filas
-- de strategies_metadata para encontrar las estrategias operativas. Con versiones
-- archivadas acumuladas, la mayoría de filas tienen is_active = FALSE.
-- Solución: Índice parcial que solo indexa las filas con is_active = TRUE.
-- Plan esperado: Index Scan using idx_strategies_metadata_is_active on strategies_metadata
--   Filter predicate already satisfied by partial index condition
-- Ventaja adicional: el índice parcial es más pequeño en disco y más rápido de
-- actualizar que un índice completo sobre toda la columna.
-- Q4 (ranking de performance): ya cubierto por idx_performance_tiebreak creado en
-- TSK-F1_1.1-10.2-GREEN. El ORDER BY (score DESC, processed_at ASC, projection_id ASC)
-- coincide exactamente con la definición del índice → Index Scan sin Sort operator.
-- -----------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_strategies_metadata_is_active
    ON public.strategies_metadata (is_active)
    WHERE is_active = TRUE;

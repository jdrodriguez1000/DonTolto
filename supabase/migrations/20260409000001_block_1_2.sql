-- =============================================================================
-- MIGRACIÓN: 20260409000001_block_1_2.sql
-- Trazabilidad: Bloque 1/2 — TSK-F1_1.1-05.1 al 05.7-GREEN (Schema Core + Seed)
-- Objetos: system_configuration, draws, manual_verification_queue, system_logs,
--          fn_validate_ball_array, fn_prevent_singleton_delete, tg_prevent_singleton_delete
-- SPEC: §3.6 — Auditoría & Configuración
-- REFACTOR: TSK-F1_1.1-06.1-REFACT — Reorganización canónica DDL + naming constraints
-- =============================================================================

-- =============================================================================
-- BLOQUE 1: EXTENSIONES
-- =============================================================================

-- Habilitar extensión necesaria para gen_random_uuid() si no está activa
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =============================================================================
-- BLOQUE 2: FUNCIONES (antes de las tablas que las referencian via CHECK)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TSK-F1_1.1-05.6-GREEN — Función: fn_validate_ball_array (IMMUTABLE)
-- SPEC: §4.6 — Integridad de Datos
-- Valida arrays de bolas: cardinalidad=5, rango [1-43], orden ASC estricto.
-- Se define aquí (antes de las tablas) para que las referencias vía CHECK
-- sean explícitas y el orden de lectura del DDL sea canónico.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_validate_ball_array(ball_array INTEGER[])
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
    v_len    INTEGER;
    v_i      INTEGER;
BEGIN
    -- Regla 1: Cardinalidad exacta = 5
    v_len := array_length(ball_array, 1);
    IF v_len IS NULL OR v_len <> 5 THEN
        RETURN FALSE;
    END IF;

    -- Regla 2 + 3: Rango [1-43], sin duplicados y ordenado ASC (orden estricto implica sin dups)
    FOR v_i IN 1..5 LOOP
        -- Rango
        IF ball_array[v_i] < 1 OR ball_array[v_i] > 43 THEN
            RETURN FALSE;
        END IF;
        -- Orden estricto ascendente (implica sin duplicados)
        IF v_i > 1 AND ball_array[v_i] <= ball_array[v_i - 1] THEN
            RETURN FALSE;
        END IF;
    END LOOP;

    RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION public.fn_validate_ball_array(INTEGER[]) IS
    'Valida arrays de bolas Baloto: cardinalidad=5, rango [1-43], ordenados ASC estrictamente (implica sin duplicados). IMMUTABLE para uso eficiente en CHECK constraints e índices GIN.';

-- -----------------------------------------------------------------------------
-- TSK-F1_1.1-05.2-GREEN — Función trigger: fn_prevent_singleton_delete
-- SPEC: §3.6 — Garantía Singleton
-- Bloquea cualquier DELETE sobre system_configuration.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_prevent_singleton_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RAISE EXCEPTION
        'La eliminación del registro Singleton de system_configuration está prohibida. La configuración administrativa del sistema no puede ser borrada.'
        USING ERRCODE = 'P0001';
END;
$$;

COMMENT ON FUNCTION public.fn_prevent_singleton_delete() IS
    'Trigger function que bloquea cualquier DELETE sobre system_configuration. Garantiza la permanencia del Singleton administrativo.';

-- =============================================================================
-- BLOQUE 3: TABLAS (con constraints inline nombrados)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TSK-F1_1.1-05.1-GREEN — Tabla: system_configuration (Singleton Administrativo)
-- SPEC: §3.6 — Auditoría & Configuración
-- CHECK de singleton nombrado explícitamente como chk_syscfg_singleton.
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.system_configuration (
    id                   INTEGER  PRIMARY KEY CONSTRAINT chk_syscfg_singleton CHECK (id = 1),
    admin_uuid           UUID     NOT NULL,
    debt_threshold_hours INTEGER  NOT NULL DEFAULT 24,
    is_system_locked     BOOLEAN  NOT NULL DEFAULT FALSE
);

COMMENT ON TABLE public.system_configuration IS
    'Singleton de configuración administrativa. id=1 es el único registro permitido. Protegido por CONSTRAINT chk_syscfg_singleton CHECK(id=1) y trigger tg_prevent_singleton_delete.';

COMMENT ON COLUMN public.system_configuration.admin_uuid IS
    'UUID del administrador del sistema para filtros RLS. NOT NULL obligatorio.';

COMMENT ON COLUMN public.system_configuration.debt_threshold_hours IS
    'Umbral en horas para activar modo Fallback (REQ-09). Default: 24h.';

COMMENT ON COLUMN public.system_configuration.is_system_locked IS
    'Kill-switch global del sistema. FALSE = operativo, TRUE = bloqueado.';

-- -----------------------------------------------------------------------------
-- TSK-F1_1.1-05.3-GREEN — Tabla: draws (Historial oficial de sorteos)
-- SPEC: §3.3 — Esquema Core
-- numbers usa fn_validate_ball_array (IMMUTABLE) para validación eficiente.
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.draws (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id      UUID        NOT NULL,
    draw_date   DATE        NOT NULL,
    numbers     INTEGER[]   NOT NULL
                CONSTRAINT chk_draws_numbers CHECK (public.fn_validate_ball_array(numbers)),
    superbalota INTEGER     NOT NULL
                CONSTRAINT chk_draws_superbalota CHECK (superbalota BETWEEN 1 AND 16),
    type        VARCHAR(20) NOT NULL
                CONSTRAINT chk_draws_type CHECK (type IN ('baloto', 'revancha')),
    status      VARCHAR(20) NOT NULL DEFAULT 'final'
                CONSTRAINT chk_draws_status CHECK (status IN ('transient', 'final')),
    is_manual   BOOLEAN     NOT NULL DEFAULT FALSE
);

COMMENT ON TABLE public.draws IS
    'Historial oficial de sorteos Baloto/Revancha. Unicidad garantizada por (draw_date, type). Constraint de array: orden ASC estricto, rango [1-43], cardinalidad=5 via fn_validate_ball_array.';

-- -----------------------------------------------------------------------------
-- TSK-F1_1.1-05.4-GREEN — Tabla: manual_verification_queue (Cola Double-Entry)
-- SPEC: §3.6 — Auditoría & Configuración
-- numbers usa fn_validate_ball_array (IMMUTABLE) para validación eficiente.
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.manual_verification_queue (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id       UUID        NOT NULL,
    draw_date    DATE        NOT NULL,
    numbers      INTEGER[]   NOT NULL
                 CONSTRAINT chk_mvq_numbers CHECK (public.fn_validate_ball_array(numbers)),
    superbalota  INTEGER     NOT NULL
                 CONSTRAINT chk_mvq_superbalota CHECK (superbalota BETWEEN 1 AND 16),
    type         VARCHAR(20) NOT NULL
                 CONSTRAINT chk_mvq_type CHECK (type IN ('baloto', 'revancha')),
    entry_source VARCHAR(20) NOT NULL
                 CONSTRAINT chk_mvq_entry_source CHECK (entry_source IN ('scraper', 'admin')),
    is_verified  BOOLEAN     NOT NULL DEFAULT FALSE,
    is_conflict  BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.manual_verification_queue IS
    'Cola de entrada doble (Double-Entry) para validación manual de sorteos. Los registros se promueven a draws mediante fn_verify_and_promote_draw. Relación lógica con draws por (draw_date, type).';

-- -----------------------------------------------------------------------------
-- TSK-F1_1.1-05.5-GREEN — Tabla: system_logs (Auditoría Forense)
-- SPEC: §3.6 — Trazabilidad total mediante run_id
-- CLAUDE.md: Niveles info, warning, error, critical + audit
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.system_logs (
    id          BIGSERIAL   PRIMARY KEY,
    run_id      UUID        NOT NULL,
    service     VARCHAR(50) NOT NULL,
    level       VARCHAR(20) NOT NULL
                CONSTRAINT chk_logs_level
                CHECK (level IN ('info', 'warning', 'error', 'critical', 'audit')),
    message     TEXT        NOT NULL,
    is_archived BOOLEAN     NOT NULL DEFAULT FALSE,
    metadata    JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.system_logs IS
    'Registro forense de auditoría del sistema. BIGSERIAL garantiza orden cronológico. metadata JSONB almacena snapshots pre-truncado de performance para respaldo forense (REQ-13).';

COMMENT ON COLUMN public.system_logs.metadata IS
    'Contexto adicional en formato JSONB. Uso principal: snapshot JSONB_AGG del estado previo de performance antes de recálculo atómico (fn_verify_and_promote_draw).';

-- =============================================================================
-- BLOQUE 4: TRIGGERS (después de sus tablas de referencia)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TSK-F1_1.1-05.2-GREEN — Trigger: tg_prevent_singleton_delete
-- SPEC: §3.6 — Garantía Singleton
-- FOR EACH STATEMENT: intercepta la sentencia completa incluso si la tabla está
-- vacía, garantizando que no haya elusión via DELETE sobre tabla sin filas.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE TRIGGER tg_prevent_singleton_delete
    BEFORE DELETE ON public.system_configuration
    FOR EACH STATEMENT
    EXECUTE FUNCTION public.fn_prevent_singleton_delete();

-- =============================================================================
-- BLOQUE 5: ÍNDICES
-- =============================================================================

-- Índice único: un sorteo por fecha y tipo (draws)
CREATE UNIQUE INDEX IF NOT EXISTS idx_draws_date_type_unique
    ON public.draws (draw_date, type);

-- Índice para búsquedas por fecha y tipo en cola de verificación
CREATE INDEX IF NOT EXISTS idx_mvq_draw_date_type
    ON public.manual_verification_queue (draw_date, type);

-- Índice parcial: registros no verificados (query frecuente en fn_monitor_and_activate_fallback)
CREATE INDEX IF NOT EXISTS idx_mvq_unverified
    ON public.manual_verification_queue (is_verified, created_at)
    WHERE is_verified = FALSE;

-- Índice para purga por TTL (fn_cleanup_logs filtra por level y created_at)
CREATE INDEX IF NOT EXISTS idx_logs_level_created
    ON public.system_logs (level, created_at);

-- Índice para trazabilidad por run_id en logs
CREATE INDEX IF NOT EXISTS idx_logs_run_id
    ON public.system_logs (run_id);

-- Índice parcial para archivado (job Cold Storage)
CREATE INDEX IF NOT EXISTS idx_logs_unarchived
    ON public.system_logs (is_archived, created_at)
    WHERE is_archived = FALSE;

-- =============================================================================
-- BLOQUE 6: SEED DATA
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TSK-F1_1.1-05.7-GREEN — Seed: Registro inicial de system_configuration
-- SPEC: §3.6 — Garantía Singleton + Constantes Administrativas
-- ON CONFLICT DO NOTHING garantiza idempotencia en reruns de migración.
-- -----------------------------------------------------------------------------

INSERT INTO public.system_configuration (id, admin_uuid, debt_threshold_hours, is_system_locked)
VALUES (
    1,
    gen_random_uuid(),   -- UUID administrativo inicial (se actualizará via RLS en producción)
    24,                  -- Umbral Fallback: 24 horas (REQ-09)
    FALSE                -- Kill-switch desactivado en arranque inicial
)
ON CONFLICT (id) DO NOTHING;  -- Idempotencia: no falla si ya existe el registro

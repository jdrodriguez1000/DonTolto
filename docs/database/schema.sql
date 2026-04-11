-- =============================================================================
-- SCHEMA REFERENCE: DonTolto — Supabase (PostgreSQL 16)
-- Descripción: Esquema consolidado de referencia (READ ONLY). No ejecutar directamente.
--              Fuente de verdad: supabase/migrations/ (aplicar en orden cronológico).
-- Última actualización: 2026-04-10
-- Versión: Bloque 7 (TSK-F1_1.1-27.3-GREEN)
-- =============================================================================

-- =============================================================================
-- EXTENSIONES
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- gen_random_uuid()
-- pg_cron y pg_net se habilitan vía Supabase Dashboard / config.toml

-- =============================================================================
-- FUNCIONES DE VALIDACIÓN E INTEGRIDAD
-- =============================================================================

-- fn_validate_ball_array: Valida arrays de 5 bolas [1-43] ordenadas ASC
CREATE OR REPLACE FUNCTION public.fn_validate_ball_array(ball_array INTEGER[])
RETURNS BOOLEAN LANGUAGE plpgsql IMMUTABLE SET search_path = public AS $$
-- Ver migración 20260409000001_block_1_2.sql
$$ LANGUAGE plpgsql;  -- stub documental

-- fn_prevent_singleton_delete: Trigger que bloquea DELETE en system_configuration
CREATE OR REPLACE FUNCTION public.fn_prevent_singleton_delete()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
-- Ver migración 20260409000001_block_1_2.sql
$$ LANGUAGE plpgsql;  -- stub documental

-- =============================================================================
-- TABLAS CORE
-- =============================================================================

-- -----------------------------------------------------------------------------
-- system_configuration — Singleton administrativo (id=1 único)
-- Migración: 20260409000001_block_1_2.sql
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.system_configuration (
    id                   INTEGER  PRIMARY KEY CONSTRAINT chk_syscfg_singleton CHECK (id = 1),
    admin_uuid           UUID     NOT NULL,
    debt_threshold_hours INTEGER  NOT NULL DEFAULT 24,
    is_system_locked     BOOLEAN  NOT NULL DEFAULT FALSE
);
-- Trigger: tg_prevent_singleton_delete → fn_prevent_singleton_delete() (BEFORE DELETE)
-- RLS: ENABLED. SELECT para todos; UPDATE restringido a service_role.

-- -----------------------------------------------------------------------------
-- system_logs — Trazabilidad completa por run_id
-- Migración: 20260409000001_block_1_2.sql
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.system_logs (
    id          BIGSERIAL    PRIMARY KEY,
    run_id      UUID         NOT NULL,
    service     VARCHAR(50)  NOT NULL,
    level       VARCHAR(20)  NOT NULL CONSTRAINT chk_system_logs_level CHECK (level IN ('info', 'warning', 'error', 'audit', 'debug')),
    message     TEXT         NOT NULL,
    is_archived BOOLEAN      NOT NULL DEFAULT FALSE,
    metadata    JSONB,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);
-- RLS: ENABLED. INSERT para service_role; SELECT/DELETE restringido a Admin.

-- -----------------------------------------------------------------------------
-- draws — Historial oficial de sorteos (Baloto/Revancha)
-- Migración: 20260409000001_block_1_2.sql
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.draws (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id     UUID        NOT NULL,
    draw_date  DATE        NOT NULL,
    numbers    INTEGER[]   NOT NULL CONSTRAINT chk_draws_numbers CHECK (public.fn_validate_ball_array(numbers)),
    superbalota INTEGER    NOT NULL CONSTRAINT chk_draws_superbalota CHECK (superbalota >= 1 AND superbalota <= 16),
    type       VARCHAR(20) NOT NULL CONSTRAINT chk_draws_type CHECK (type IN ('baloto', 'revancha')),
    status     VARCHAR(20) NOT NULL DEFAULT 'final' CONSTRAINT chk_draws_status CHECK (status IN ('transient', 'final')),
    is_manual  BOOLEAN     NOT NULL DEFAULT FALSE
);
-- Índice único: idx_draws_date_type ON (draw_date, type)
-- RLS: ENABLED. SELECT para Admin y service_role; web_anon denegado.

-- -----------------------------------------------------------------------------
-- manual_verification_queue — Cola de entrada doble (Double-Entry Guard)
-- Migración: 20260409000001_block_1_2.sql
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.manual_verification_queue (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id       UUID        NOT NULL,
    draw_date    DATE        NOT NULL,
    numbers      INTEGER[]   NOT NULL CONSTRAINT chk_mvq_numbers CHECK (public.fn_validate_ball_array(numbers)),
    superbalota  INTEGER     NOT NULL CONSTRAINT chk_mvq_superbalota CHECK (superbalota >= 1 AND superbalota <= 16),
    type         VARCHAR(20) NOT NULL CONSTRAINT chk_mvq_type CHECK (type IN ('baloto', 'revancha')),
    entry_source VARCHAR(20) NOT NULL CONSTRAINT chk_mvq_entry_source CHECK (entry_source IN ('scraper', 'admin')),
    is_verified  BOOLEAN     NOT NULL DEFAULT FALSE,
    is_conflict  BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- RLS: ENABLED.

-- =============================================================================
-- TABLAS DE MOTOR Y ANALÍTICA
-- =============================================================================

-- -----------------------------------------------------------------------------
-- strategies_metadata — Catálogo de estrategias con versionamiento
-- Migración: 20260410000001_block_3.sql
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.strategies_metadata (
    name      VARCHAR(50) NOT NULL,
    version   INTEGER     NOT NULL DEFAULT 1,
    role      VARCHAR(20) NOT NULL CONSTRAINT chk_strategies_metadata_role CHECK (role IN ('active', 'control', 'archive')),
    is_active BOOLEAN     NOT NULL DEFAULT TRUE,
    CONSTRAINT pk_strategies_metadata PRIMARY KEY (name, version)
);
-- RLS: ENABLED.

-- -----------------------------------------------------------------------------
-- projections — Pool de proyecciones por sorteo (1,802 combinaciones típicas)
-- Migración: 20260410000001_block_3.sql (tabla base)
--            20260410000008_block_5b.sql (ADD COLUMN worker_id, last_heartbeat)
--            20260410000009_block_6.sql  (ALTER CONSTRAINT chk_projections_status: +error_fatal)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.projections (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id           UUID        NOT NULL,
    target_draw_date DATE        NOT NULL,
    strategy_name    VARCHAR(50) NOT NULL,
    strategy_version INTEGER     NOT NULL DEFAULT 1,
    numbers          INTEGER[]   NOT NULL CONSTRAINT chk_projections_numbers CHECK (public.fn_validate_ball_array(numbers)),
    superbalota      INTEGER     NOT NULL CONSTRAINT chk_projections_superbalota CHECK (superbalota >= 1 AND superbalota <= 16),
    status           VARCHAR(25) NOT NULL DEFAULT 'pending'
                     CONSTRAINT chk_projections_status CHECK (status IN ('pending', 'calculating', 'calculated', 'error', 'error_fatal')),
    -- Columnas de concurrencia (TSK-F1_1.1-23.3-GREEN, PLAN B5b)
    worker_id        UUID,           -- UUID del worker que posee el claim
    last_heartbeat   TIMESTAMPTZ,    -- Último latido del worker activo
    CONSTRAINT fk_projections_strategy FOREIGN KEY (strategy_name, strategy_version)
        REFERENCES public.strategies_metadata (name, version) ON DELETE RESTRICT
);
-- Índice GIN: idx_projections_numbers ON numbers (scoring overlap queries)
-- RLS: ENABLED. SELECT/INSERT/UPDATE para service_role; SELECT para Admin.

-- -----------------------------------------------------------------------------
-- performance — Aciertos y puntajes ponderados por proyección
-- Migración: 20260410000001_block_3.sql
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.performance (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    processed_at  TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    draw_id       UUID        NOT NULL CONSTRAINT fk_performance_draw REFERENCES public.draws (id) ON DELETE RESTRICT,
    projection_id UUID        NOT NULL CONSTRAINT fk_performance_projection REFERENCES public.projections (id) ON DELETE RESTRICT,
    hits_count    INTEGER     NOT NULL CONSTRAINT chk_performance_hits_count CHECK (hits_count >= 0 AND hits_count <= 5),
    has_sb        BOOLEAN     NOT NULL,
    score         INTEGER     GENERATED ALWAYS AS (hits_count + CASE WHEN has_sb THEN 10 ELSE 0 END) STORED,
    is_verified   BOOLEAN     NOT NULL DEFAULT TRUE
);
-- Índice compuesto: idx_performance_tiebreak ON (score DESC, processed_at ASC, projection_id ASC)
-- RLS: ENABLED. SELECT para Admin y service_role.

-- =============================================================================
-- TABLA DE CONTROL DE CONCURRENCIA
-- =============================================================================

-- -----------------------------------------------------------------------------
-- sync_locks — Semáforo atómico con TTL de 60 minutos
-- Migración: 20260410000008_block_5b.sql
-- ADR-03, REQ-12
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.sync_locks (
    lock_key    VARCHAR(100) NOT NULL,
    run_id      UUID         NOT NULL,
    acquired_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    expires_at  TIMESTAMPTZ  NOT NULL GENERATED ALWAYS AS (acquired_at + INTERVAL '60 minutes') STORED,
    worker_id   UUID         NOT NULL,
    metadata    JSONB,
    CONSTRAINT pk_sync_locks PRIMARY KEY (lock_key)
);
-- Índice: idx_sync_locks_expires_at ON expires_at (limpieza pg_cron)
-- RLS: ENABLED. ALL para service_role.

-- =============================================================================
-- ÍNDICES
-- =============================================================================

CREATE UNIQUE INDEX IF NOT EXISTS idx_draws_date_type      ON public.draws (draw_date, type);
CREATE INDEX IF NOT EXISTS idx_projections_numbers          ON public.projections USING GIN (numbers);
CREATE INDEX IF NOT EXISTS idx_performance_tiebreak         ON public.performance (score DESC, processed_at ASC, projection_id ASC);
CREATE INDEX IF NOT EXISTS idx_sync_locks_expires_at        ON public.sync_locks (expires_at);

-- =============================================================================
-- FUNCIONES RPC (Motor de Negocio)
-- Las firmas están documentadas aquí como referencia.
-- Implementaciones completas: supabase/migrations/
-- =============================================================================

-- fn_bulk_insert_projections(p_run_id UUID, p_payload JSONB) RETURNS INTEGER
--   Inserción masiva idempotente de proyecciones desde JSONB.
--   Migración: 20260410000001_block_3.sql

-- fn_setup_security_context() RETURNS VOID (SECURITY DEFINER)
--   Bootstrap RLS: carga admin_uuid en app.current_admin_id.
--   Migración: 20260410000002_block_4.sql

-- fn_snapshot_system_config() RETURNS JSONB (SECURITY DEFINER)
--   Helper: captura debt_threshold_hours e is_system_locked del singleton.
--   Migración: 20260410000007_block_5a_refact.sql

-- fn_backup_performance_to_logs(p_draw_id UUID, p_run_id UUID, p_draw_date DATE, p_type VARCHAR) RETURNS VOID (SECURITY DEFINER)
--   Helper forense: backup JSONB de performance → system_logs antes de recálculo atómico.
--   Migración: 20260410000007_block_5a_refact.sql

-- fn_reset_draw_scoring(p_draw_id UUID, p_draw_date DATE, p_type VARCHAR) RETURNS VOID (SECURITY DEFINER)
--   Helper ADR-04: DELETE performance → RESET projections → DELETE draw.
--   Migración: 20260410000007_block_5a_refact.sql

-- fn_compute_async_scoring(p_run_id UUID DEFAULT NULL) RETURNS VOID (SECURITY DEFINER)
--   Motor de scoring asíncrono: SKIP LOCKED batch 428, claim token pattern.
--   Migración: 20260410000006_block_5a.sql → refactorizado en 20260410000007_block_5a_refact.sql

-- fn_verify_and_promote_draw(p_draw_date DATE, p_type VARCHAR) RETURNS BOOLEAN (SECURITY DEFINER)
--   Double-Entry Guard: match Admin+Scraper, Fallback Ghost >debt_threshold_hours, recálculo ADR-04.
--   Migración: 20260410000006_block_5a.sql → refactorizado en 20260410000007_block_5a_refact.sql

-- fn_manage_lock(p_lock_key TEXT, p_worker_id UUID, p_mode TEXT) RETURNS BOOLEAN (SECURITY DEFINER)
--   Adquisición/liberación atómica de locks con TTL 60m. Modos: 'acquire' | 'release'.
--   Migración: 20260410000008_block_5b.sql

-- fn_recover_stalled_projections() RETURNS VOID (SECURITY DEFINER)
--   Anti-zombie: resetea projections.status='pending' si last_heartbeat < now()-30min.
--   Migración: 20260410000008_block_5b.sql

-- fn_monitor_and_activate_fallback() RETURNS VOID (SECURITY DEFINER)
--   Monitor fallback: detecta MVQ huérfanas >debt_threshold_hours, promueve a 'transient'.
--   Migración: 20260410000008_block_5b.sql

-- =============================================================================
-- VISTAS DE OBSERVABILIDAD
-- =============================================================================

-- -----------------------------------------------------------------------------
-- v_system_health — Observabilidad operativa del pipeline de proyecciones
-- Migración: 20260410000009_block_6.sql
-- TSK-F1_1.1-27.1-GREEN
-- -----------------------------------------------------------------------------
-- Columnas: total_projections, pending_count, calculating_count, calculated_count,
--           error_count, error_fatal_count
-- Una sola fila de resumen. Denominador: total_projections. Alerta primaria: error_fatal_count.
-- SPEC §6, ARC-06, REQ-10.

-- -----------------------------------------------------------------------------
-- v_strategy_delta — Análisis comparativo de performance por estrategia
-- Migración: 20260410000009_block_6.sql
-- TSK-F1_1.1-27.2-GREEN
-- -----------------------------------------------------------------------------
-- Columnas: draw_date, type, strategy_name, avg_score, is_control_delta
-- Pivote de performance (performance JOIN projections JOIN draws JOIN strategies_metadata).
-- is_control_delta = TRUE identifica la estrategia de rol 'control' (línea base del delta).
-- SPEC §6, ARC-06, REQ-10.

-- =============================================================================
-- TRIGGERS
-- =============================================================================

-- tg_prevent_singleton_delete: BEFORE DELETE ON system_configuration
--   → fn_prevent_singleton_delete() — bloquea borrado del Singleton.
--   Migración: 20260409000001_block_1_2.sql

-- =============================================================================
-- JOBS pg_cron (configurados en migraciones B5b/B6)
-- Trazabilidad: TSK-F1_1.1-24.1-GREEN y TSK-F1_1.1-25.1-REFACT
-- Justificación de intervalos: docs/f1_1.1/audit/pipeline/cert_block6_DEVOPS_20260410.md
-- =============================================================================

-- 'dontolto_recover_stalled'   — '*/15 * * * *'   → fn_recover_stalled_projections()
--   Cada 15 minutos. Reset de workers zombie (last_heartbeat > 30 min).
--   No adquiere sync_locks. Riesgo de colisión con sorteo (06:30 UTC): BAJO.
--   Umbral zombie = 30 min; intervalo 15 min garantiza detección en primer ciclo.

-- 'dontolto_fallback_monitor'  — '5 * * * *'       → fn_monitor_and_activate_fallback()
--   Cada hora en el minuto 5 (XX:05 UTC). Monitor de fallback para sorteos huérfanos > 24h.
--   Offset de 5 min evita colisión con ventana de sorteo (06:30 UTC) y ciclos de scoring.
--   Granularidad horaria es suficiente dado el umbral de deuda de 24 h.

-- 'dontolto_cleanup_locks'     — '10,40 * * * *'   → DELETE FROM sync_locks WHERE expires_at <= now()
--   Cada 30 minutos (minutos 10 y 40). Purga de locks expirados (TTL = 60 min).
--   Evita "lock fantasma". Minutos 10/40 evitan la ventana 06:30 UTC y los ciclos GHA.
--   El DELETE es liviano gracias al índice idx_sync_locks_expires_at.

-- 'dontolto_cleanup_logs'      — '0 2 * * *'         → fn_cleanup_logs()
--   Diario a las 2:00 UTC. Purga logs info/debug >90d, archiva >180d, limpia MVQ >180d.
--   Fuera de la ventana de sorteo (06:30 UTC). Granularidad diaria es suficiente para retención por días.

-- Migración: 20260410000008_block_5b.sql (Bloque 5b — pg_cron, jobs 1-3)
--            20260410000009_block_6.sql  (Bloque 7 — pg_cron, job 4: dontolto_cleanup_logs)

-- fn_cleanup_logs() RETURNS VOID (SECURITY DEFINER)
--   Motor de mantenimiento forense: purga system_logs info/debug >90d, archiva >180d,
--   limpia manual_verification_queue verificada >180d. Registra la operación en system_logs.
--   Migración: 20260410000009_block_6.sql
--   Job pg_cron: 'dontolto_cleanup_logs' — '0 2 * * *' (diario 2:00 UTC)
--   SPEC §4.5, REQ-13, TSK-F1_1.1-27.3-GREEN.

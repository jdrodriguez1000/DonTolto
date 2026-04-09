-- =============================================================================
-- TEST: 001_environment_extensions.sql
-- Trazabilidad: TSK-F1_1.1-02.1 — Verificacion de extensiones habilitadas
-- SPEC: Seccion 3.1 — Extensiones: pg_cron, pg_net, pgtap
-- PLAN: B0 — Validacion de Entorno (Pre-vuelo)
-- Responsable: backend-tester
-- Fecha: 2026-04-09
--
-- Tipo de test: VALIDACION DE ENTORNO (debe PASAR si el entorno es correcto)
-- Descripcion: Verifica que las tres extensiones mandatorias del proyecto esten
--              instaladas y en estado 'installed' en pg_catalog.pg_extension.
--              Si alguna extension no esta presente, el test falla indicando que
--              el entorno no cumple los requisitos de la SPEC.
--
-- Extensiones verificadas:
--   - pgtap:   runner de pruebas SQL (runner de testing)
--   - pg_cron: orquestador de jobs asincronos (ARC-05)
--   - pg_net:  conector HTTP para notificaciones externas
-- =============================================================================

BEGIN;

SELECT plan(3);

-- ---------------------------------------------------------------------------
-- ASSERTION 1: Extension pgtap esta instalada
-- Razon: pgtap es el runner de pruebas; sin el no puede correr ningun test.
--        Si esta asercion falla, el entorno carece del runner y ningun otro
--        test puede ser confiable.
-- ---------------------------------------------------------------------------
SELECT has_extension(
    'pgtap',
    'La extension pgtap debe estar instalada (runner de pruebas SQL)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 2: Extension pg_cron esta instalada
-- Razon: pg_cron es el orquestador de los jobs de Scoring (1 min), Fallback
--        (1 hora) y Cleanup (5 min) definidos en SPEC ARC-05 y PLAN B5b.
--        Su ausencia bloquea toda la capa de automatizacion.
-- ---------------------------------------------------------------------------
SELECT has_extension(
    'pg_cron',
    'La extension pg_cron debe estar instalada (orquestador de jobs ARC-05)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 3: Extension pg_net esta instalada
-- Razon: pg_net permite que la DB dispare notificaciones HTTP hacia Edge
--        Functions y sistemas externos (Resend para alertas criticas).
--        Mandatorio segun SPEC Seccion 3.1.
-- ---------------------------------------------------------------------------
SELECT has_extension(
    'pg_net',
    'La extension pg_net debe estar instalada (conector HTTP para notificaciones)'
);

SELECT * FROM finish();

ROLLBACK;

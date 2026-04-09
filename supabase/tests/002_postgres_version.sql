-- =============================================================================
-- TEST: 002_postgres_version.sql
-- Trazabilidad: TSK-F1_1.1-02.1.1 — Verificacion de version del motor Postgres
-- SPEC: Seccion 1.1 — Stack Tecnologico: Supabase (PostgreSQL 16)
-- PLAN: B0 — Hito de aceptacion: Compatibilidad de version >= 15.0
-- Responsable: backend-tester
-- Fecha: 2026-04-09
--
-- Tipo de test: VALIDACION DE ENTORNO (debe PASAR si el entorno es correcto)
-- Descripcion: Verifica que la version del motor PostgreSQL sea >= 15.0 tal
--              como lo exige el PLAN B0. El proyecto utiliza funciones y
--              caracteristicas de PostgreSQL 16 (columnas GENERATED ALWAYS,
--              SKIP LOCKED, GIN indexing avanzado). Una version inferior
--              comprometeria la compatibilidad de las migraciones DDL.
--
-- Nota de implementacion: PostgreSQL codifica la version como un entero
-- (ej: 160001 para 16.1, 150004 para 15.4). Se verifica que
-- current_setting('server_version_num')::integer >= 150000 (PG 15.0).
-- =============================================================================

BEGIN;

SELECT plan(2);

-- ---------------------------------------------------------------------------
-- ASSERTION 1: Version numerica de PostgreSQL >= 150000 (>= 15.0)
-- Razon: El valor de 'server_version_num' es un entero de 6 digitos donde
--        los dos primeros representan la version mayor. 150000 = PG 15.0.
--        Esta forma de verificacion es determinista y no depende del formato
--        del string de version (que puede incluir sufijos como '-Ubuntu').
-- ---------------------------------------------------------------------------
SELECT ok(
    current_setting('server_version_num')::integer >= 150000,
    'La version de PostgreSQL debe ser >= 15.0 (server_version_num >= 150000). '
    || 'Version actual: ' || current_setting('server_version_num')
);

-- ---------------------------------------------------------------------------
-- ASSERTION 2: El servidor esta corriendo en la version esperada por el stack
--              (PostgreSQL 16 segun SPEC). Se valida como >= 160000 como
--              informacion adicional de conformidad con el stack declarado.
-- Razon: Si bien el minimo es 15.0, el stack oficial es PG 16. Este test
--        sirve como alerta de degradacion de entorno (warn-level semantico).
-- ---------------------------------------------------------------------------
SELECT ok(
    current_setting('server_version_num')::integer >= 160000,
    'ADVERTENCIA: Se esperaba PostgreSQL 16+ segun stack declarado en SPEC. '
    || 'Version actual: ' || current_setting('server_version_num')
    || '. El minimo absoluto es 15.0 (150000).'
);

SELECT * FROM finish();

ROLLBACK;

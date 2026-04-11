-- =============================================================================
-- SEED: seed_synthetic_428.sql
-- Trazabilidad: TSK-F1_1.1-28.1-GREEN — Script de carga sintética (428 registros)
-- Fecha: 2026-04-10
-- Dependencias: Bloques 1-7 aplicados (migrations/20260409000001_block_1_2.sql
--               al 20260410000009_block_6.sql)
-- Propósito: Validación de carga, integridad referencial y lógica RPC (M3/M6 PLAN).
-- Idempotencia: ON CONFLICT DO NOTHING en todas las operaciones DML.
-- =============================================================================

BEGIN;

-- =============================================================================
-- BLOQUE 1: Estrategias de referencia (FK requerida por projections)
-- 5 estrategias: 3 active, 1 control, 1 archive — cubren todos los roles del catálogo.
-- =============================================================================

INSERT INTO public.strategies_metadata (name, version, role, is_active) VALUES
    ('caliente', 1, 'active',  TRUE),
    ('fria',     1, 'active',  TRUE),
    ('elite',    1, 'active',  TRUE),
    ('control',  1, 'control', TRUE),
    ('real',     1, 'archive', FALSE)
ON CONFLICT (name, version) DO NOTHING;

-- =============================================================================
-- BLOQUE 2: Sorteos ficticios en draws (10 registros, 2025-01-07 a 2025-06-10)
-- Fechas distribuidas bimensualmente alternando 'baloto' / 'revancha'.
-- run_id fijo (aaaaaaaa-...) para trazabilidad del lote seed.
-- numbers: 5 enteros [1-43] ordenados ASC. superbalota: [1-16].
-- Conflicto por UNIQUE (draw_date, type): ON CONFLICT DO NOTHING.
-- =============================================================================

INSERT INTO public.draws
    (id, run_id, draw_date, numbers, superbalota, type, status, is_manual)
VALUES
    ('00000000-0000-0000-0001-000000000001'::uuid,
     'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
     '2025-01-07', ARRAY[3,12,21,34,41],  5,  'baloto',   'final', FALSE),
    ('00000000-0000-0000-0001-000000000002'::uuid,
     'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
     '2025-01-07', ARRAY[7,15,22,35,40],  9,  'revancha', 'final', FALSE),
    ('00000000-0000-0000-0001-000000000003'::uuid,
     'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
     '2025-02-11', ARRAY[1,8,19,28,43],   3,  'baloto',   'final', FALSE),
    ('00000000-0000-0000-0001-000000000004'::uuid,
     'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
     '2025-02-11', ARRAY[5,14,23,31,39], 12,  'revancha', 'final', FALSE),
    ('00000000-0000-0000-0001-000000000005'::uuid,
     'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
     '2025-03-18', ARRAY[2,11,20,33,42],  7,  'baloto',   'final', FALSE),
    ('00000000-0000-0000-0001-000000000006'::uuid,
     'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
     '2025-03-18', ARRAY[6,16,25,37,43], 14,  'revancha', 'final', FALSE),
    ('00000000-0000-0000-0001-000000000007'::uuid,
     'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
     '2025-04-22', ARRAY[4,13,24,32,38],  2,  'baloto',   'final', FALSE),
    ('00000000-0000-0000-0001-000000000008'::uuid,
     'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
     '2025-04-22', ARRAY[9,18,27,36,41], 11,  'revancha', 'final', FALSE),
    ('00000000-0000-0000-0001-000000000009'::uuid,
     'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
     '2025-06-10', ARRAY[10,17,26,35,40], 6,  'baloto',   'final', FALSE),
    ('00000000-0000-0000-0001-000000000010'::uuid,
     'aaaaaaaa-0000-0000-0000-000000000001'::uuid,
     '2025-06-10', ARRAY[3,19,29,38,43], 15,  'revancha', 'final', FALSE)
ON CONFLICT (draw_date, type) DO NOTHING;

-- =============================================================================
-- BLOQUE 3: Proyecciones — 428 registros via generate_series (compacto)
-- Diseño:
--   - ID determinista: 00000000-0000-0000-0002-XXXXXXXXXXXX (idempotente)
--   - strategy_name: cicla en 5 estrategias (MOD 5)
--   - target_draw_date: cicla entre los 10 sorteos insertados (MOD 10)
--   - numbers: generados via subquery lateral con DISTINCT + ORDER BY → array ASC
--     de 5 valores en [1-43] usando multiplicadores primos. Garantiza array
--     válido para fn_validate_ball_array (ordenado ASC, 5 elementos, rango [1-43]).
--   - superbalota: ((i*3) % 16) + 1 → rango [1-16]
--   - status: i<=400 → 'calculated', resto → 'pending' (carga mixta para M6)
-- =============================================================================

WITH series AS (
    SELECT i FROM generate_series(1, 428) AS s(i)
),
strategy_map(idx, sname) AS (
    VALUES (0,'caliente'),(1,'fria'),(2,'elite'),(3,'control'),(4,'real')
),
date_map(idx, tdate) AS (
    VALUES
        (0,'2025-01-07'::date),(1,'2025-01-07'::date),
        (2,'2025-02-11'::date),(3,'2025-02-11'::date),
        (4,'2025-03-18'::date),(5,'2025-03-18'::date),
        (6,'2025-04-22'::date),(7,'2025-04-22'::date),
        (8,'2025-06-10'::date),(9,'2025-06-10'::date)
),
raw AS (
    SELECT
        s.i,
        sm.sname                                                    AS strategy_name,
        dm.tdate                                                     AS target_draw_date,
        ((s.i * 3) % 16) + 1                                        AS superbalota,
        CASE WHEN s.i <= 400 THEN 'calculated' ELSE 'pending' END   AS proj_status,
        -- Generar 5 valores únicos [1-43] usando multiplicadores primos coprimos
        -- Se toman los primeros 5 valores distintos del set de 6 candidatos
        ARRAY(
            SELECT DISTINCT v
            FROM unnest(ARRAY[
                (s.i * 2  % 43) + 1,
                (s.i * 3  % 43) + 1,
                (s.i * 7  % 43) + 1,
                (s.i * 11 % 43) + 1,
                (s.i * 13 % 43) + 1,
                (s.i * 17 % 43) + 1
            ]) AS t(v)
            ORDER BY v
            LIMIT 5
        ) AS numbers
    FROM series s
    JOIN strategy_map sm ON sm.idx = ((s.i - 1) % 5)
    JOIN date_map    dm ON dm.idx  = ((s.i - 1) % 10)
)
INSERT INTO public.projections
    (id, run_id, target_draw_date, strategy_name, strategy_version,
     numbers, superbalota, status)
SELECT
    ('00000000-0000-0000-0002-' || LPAD(r.i::text, 12, '0'))::uuid,
    'bbbbbbbb-0000-0000-0000-000000000001'::uuid,
    r.target_draw_date,
    r.strategy_name,
    1,
    r.numbers,
    r.superbalota,
    r.proj_status
FROM raw r
WHERE array_length(r.numbers, 1) = 5
ON CONFLICT DO NOTHING;

-- =============================================================================
-- BLOQUE 4: Performance — registros para proyecciones 'calculated' (i=1..400)
-- Vincula cada proyección calculada con el draw correspondiente via FK.
-- hits_count: (i % 6) → rango [0-5]; has_sb: i par → TRUE.
-- score GENERATED siempre: hits_count + (10 si has_sb ELSE 0).
-- =============================================================================

INSERT INTO public.performance
    (id, draw_id, projection_id, hits_count, has_sb, is_verified)
SELECT
    ('00000000-0000-0000-0003-' || LPAD(p.i::text, 12, '0'))::uuid,
    d.id,
    p.proj_id,
    (p.i % 6),
    (p.i % 2 = 0),
    TRUE
FROM (
    SELECT
        i,
        ('00000000-0000-0000-0002-' || LPAD(i::text, 12, '0'))::uuid AS proj_id,
        ((i - 1) % 10)                                                AS date_idx
    FROM generate_series(1, 400) AS s(i)
) p
JOIN (
    VALUES
        (0,'00000000-0000-0000-0001-000000000001'::uuid),
        (1,'00000000-0000-0000-0001-000000000002'::uuid),
        (2,'00000000-0000-0000-0001-000000000003'::uuid),
        (3,'00000000-0000-0000-0001-000000000004'::uuid),
        (4,'00000000-0000-0000-0001-000000000005'::uuid),
        (5,'00000000-0000-0000-0001-000000000006'::uuid),
        (6,'00000000-0000-0000-0001-000000000007'::uuid),
        (7,'00000000-0000-0000-0001-000000000008'::uuid),
        (8,'00000000-0000-0000-0001-000000000009'::uuid),
        (9,'00000000-0000-0000-0001-000000000010'::uuid)
) AS d(idx, id) ON d.idx = p.date_idx
ON CONFLICT DO NOTHING;

COMMIT;

---
token_id: CERT-B2-f1-1.1-GHOST-001
tipo: Analisis de Ghost Code — Schema Transaccional
tarea: TSK-F1_1.1-07.2-CERT
fecha: 2026-04-09
auditor: stage-auditor
estado: APROBADO
---

# Analisis de Ghost Code — Bloque 2

## Fuentes de verdad consultadas

- `supabase/migrations/20260409000001_block_1_2.sql` — DDL inspeccionado
- `docs/f1_1.1/f1_1.1_spec.md` (v1.2.3-Gold) — Referencia de diseno
- `docs/f1_1.1/f1_1.1_task.md` — Tareas TSK-F1_1.1-05.1 a 06.1-REFACT

---

## Inventario DDL

### Tablas

| Objeto | Columna | Tipo | Estado |
|---|---|---|---|
| `system_configuration` | `id` | INTEGER PK | DOCUMENTADO (SPEC §3.6, TSK-05.1) |
| `system_configuration` | `admin_uuid` | UUID NOT NULL | DOCUMENTADO (SPEC §3.6, TSK-05.1) |
| `system_configuration` | `debt_threshold_hours` | INTEGER DEFAULT 24 | DOCUMENTADO (SPEC §3.6, TSK-05.1) |
| `system_configuration` | `is_system_locked` | BOOLEAN DEFAULT FALSE | DOCUMENTADO (SPEC §3.6, TSK-05.1) |
| `draws` | `id` | UUID PK | DOCUMENTADO (SPEC §3.3, TSK-05.3) |
| `draws` | `run_id` | UUID NOT NULL | DOCUMENTADO (SPEC §3.3, TSK-05.3) |
| `draws` | `draw_date` | DATE NOT NULL | DOCUMENTADO (SPEC §3.3, TSK-05.3) |
| `draws` | `numbers` | INTEGER[] NOT NULL | DOCUMENTADO (SPEC §3.3, TSK-05.3) |
| `draws` | `superbalota` | INTEGER NOT NULL | DOCUMENTADO (SPEC §3.3, TSK-05.3) |
| `draws` | `type` | VARCHAR(20) NOT NULL | DOCUMENTADO (SPEC §3.3, TSK-05.3) |
| `draws` | `status` | VARCHAR(20) DEFAULT 'final' | DOCUMENTADO (SPEC §3.3, TSK-05.3) |
| `draws` | `is_manual` | BOOLEAN DEFAULT FALSE | DOCUMENTADO (SPEC §3.3, TSK-05.3) |
| `manual_verification_queue` | `id` | UUID PK | DOCUMENTADO (SPEC §3.6, TSK-05.4) |
| `manual_verification_queue` | `run_id` | UUID NOT NULL | DOCUMENTADO (SPEC §3.6, TSK-05.4) |
| `manual_verification_queue` | `draw_date` | DATE NOT NULL | DOCUMENTADO (SPEC §3.6, TSK-05.4) |
| `manual_verification_queue` | `numbers` | INTEGER[] NOT NULL | DOCUMENTADO (SPEC §3.6, TSK-05.4) |
| `manual_verification_queue` | `superbalota` | INTEGER NOT NULL | DOCUMENTADO (SPEC §3.6, TSK-05.4) |
| `manual_verification_queue` | `type` | VARCHAR(20) NOT NULL | DOCUMENTADO (SPEC §3.6, TSK-05.4) |
| `manual_verification_queue` | `entry_source` | VARCHAR(20) NOT NULL | DOCUMENTADO (SPEC §3.6, TSK-05.4) |
| `manual_verification_queue` | `is_verified` | BOOLEAN DEFAULT FALSE | DOCUMENTADO (SPEC §3.6, TSK-05.4) |
| `manual_verification_queue` | `is_conflict` | BOOLEAN DEFAULT FALSE | DOCUMENTADO (SPEC §3.6, TSK-05.4) |
| `manual_verification_queue` | `created_at` | TIMESTAMPTZ DEFAULT now() | DECISION TECNICA (ver seccion abajo) |
| `system_logs` | `id` | BIGSERIAL PK | DOCUMENTADO (SPEC §3.6, TSK-05.5) |
| `system_logs` | `run_id` | UUID NOT NULL | DOCUMENTADO (SPEC §3.6, TSK-05.5) |
| `system_logs` | `service` | VARCHAR(50) NOT NULL | DOCUMENTADO (SPEC §3.6, TSK-05.5) |
| `system_logs` | `level` | VARCHAR(20) NOT NULL | DOCUMENTADO (SPEC §3.6, TSK-05.5) |
| `system_logs` | `message` | TEXT NOT NULL | DOCUMENTADO (SPEC §3.6, TSK-05.5) |
| `system_logs` | `is_archived` | BOOLEAN DEFAULT FALSE | DOCUMENTADO (SPEC §3.6, TSK-05.5) |
| `system_logs` | `metadata` | JSONB | DOCUMENTADO (SPEC §3.6, TSK-05.5) |
| `system_logs` | `created_at` | TIMESTAMPTZ DEFAULT now() | DOCUMENTADO (SPEC §3.6 implica ordering cronologico, TSK-05.5) |

### Constraints nombrados

| Objeto | Nombre | Estado |
|---|---|---|
| `system_configuration` | `chk_syscfg_singleton CHECK (id = 1)` | DOCUMENTADO (SPEC §3.6 contrato Singleton, TSK-06.1-REFACT) |
| `draws` | `chk_draws_numbers CHECK (fn_validate_ball_array(numbers))` | DOCUMENTADO (SPEC §3.3, TSK-05.3/05.6) |
| `draws` | `chk_draws_superbalota CHECK (superbalota BETWEEN 1 AND 16)` | DOCUMENTADO (SPEC §3.3, TSK-05.3) |
| `draws` | `chk_draws_type CHECK (type IN ('baloto','revancha'))` | DOCUMENTADO (SPEC §3.3, TSK-05.3) |
| `draws` | `chk_draws_status CHECK (status IN ('transient','final'))` | DOCUMENTADO (SPEC §3.3, TSK-05.3) |
| `manual_verification_queue` | `chk_mvq_numbers CHECK (fn_validate_ball_array(numbers))` | DOCUMENTADO (SPEC §3.6, TSK-05.4) |
| `manual_verification_queue` | `chk_mvq_superbalota CHECK (superbalota BETWEEN 1 AND 16)` | DOCUMENTADO (SPEC §3.6, TSK-05.4) |
| `manual_verification_queue` | `chk_mvq_type CHECK (type IN ('baloto','revancha'))` | DOCUMENTADO (SPEC §3.6, TSK-05.4) |
| `manual_verification_queue` | `chk_mvq_entry_source CHECK (entry_source IN ('scraper','admin'))` | DOCUMENTADO (SPEC §3.6, TSK-05.4) |
| `system_logs` | `chk_logs_level CHECK (level IN ('info','warning','error','critical','audit'))` | DOCUMENTADO (SPEC §3.6, TSK-05.5) |

### Funciones

| Objeto | Respaldo | Estado |
|---|---|---|
| `fn_validate_ball_array(INTEGER[]) RETURNS BOOLEAN IMMUTABLE` | SPEC §4.6, TSK-F1_1.1-05.6-GREEN | DOCUMENTADO |
| `fn_prevent_singleton_delete() RETURNS TRIGGER SECURITY DEFINER` | SPEC §3.6 Garantia Singleton, TSK-F1_1.1-05.2-GREEN | DOCUMENTADO |

### Triggers

| Objeto | Respaldo | Estado |
|---|---|---|
| `tg_prevent_singleton_delete` BEFORE DELETE FOR EACH STATEMENT ON `system_configuration` | SPEC §3.6, TSK-F1_1.1-05.2-GREEN | DOCUMENTADO |

### Extensiones

| Objeto | Respaldo | Estado |
|---|---|---|
| `CREATE EXTENSION IF NOT EXISTS "pgcrypto"` | No en SPEC §3.1 (lista uuid-ossp, pg_cron, pg_net). Autorizado en TSK-06.1-REFACT como requisito para `gen_random_uuid()` antes de disponibilidad nativa | DECISION TECNICA |

### Indices

| Objeto | Respaldo | Estado |
|---|---|---|
| `idx_draws_date_type_unique` UNIQUE (draw_date, type) | SPEC §3.8 `idx_draws_date_type`, TSK-05.3-GREEN | DOCUMENTADO |
| `idx_mvq_draw_date_type` (draw_date, type) | TSK-05.4-GREEN evidencia explicita | DOCUMENTADO |
| `idx_mvq_unverified` parcial WHERE is_verified=FALSE | TSK-05.4-GREEN evidencia + SPEC §4.4 (query de fn_monitor_and_activate_fallback) | DOCUMENTADO |
| `idx_logs_level_created` (level, created_at) | SPEC §4.5 (fn_cleanup_logs filtra por level y created_at), TSK-05.5-GREEN | DOCUMENTADO |
| `idx_logs_run_id` (run_id) | SPEC §3.6/OBJ-05 trazabilidad por run_id, TSK-05.5-GREEN | DOCUMENTADO |
| `idx_logs_unarchived` parcial WHERE is_archived=FALSE | SPEC §4.5 (job Cold Storage filtra is_archived), TSK-05.5-GREEN | DOCUMENTADO |

### Seed data

| Objeto | Respaldo | Estado |
|---|---|---|
| INSERT system_configuration (1, gen_random_uuid(), 24, FALSE) ON CONFLICT DO NOTHING | SPEC §3.6 Garantia Singleton + Constantes Administrativas, TSK-F1_1.1-05.7-GREEN | DOCUMENTADO |

---

## Ghost Code detectado

Ninguno.

No se identifico ningun objeto DDL — tabla, columna, funcion, trigger, indice, constraint o seed — sin respaldo en la SPEC (v1.2.3-Gold) o en la TASK LIST (TSK-05.1 a TSK-06.1-REFACT).

---

## Decisiones tecnicas aceptadas

### 1. Columna `created_at` en `manual_verification_queue`

La tabla SPEC §3.6 no lista explicitamente `created_at` en el esquema de columnas de `manual_verification_queue`. Sin embargo, esta columna esta respaldada por:

- SPEC §4.4: La logica de `fn_monitor_and_activate_fallback` opera con `created_at < now() - (SELECT debt_threshold_hours ...) * interval '1 hour'`, lo que presupone la existencia del campo.
- SPEC §4.5: `fn_cleanup_logs` incluye `DELETE FROM manual_verification_queue WHERE is_verified = TRUE ... AND created_at < now() - interval '180 days'`, referenciando directamente la columna.
- TSK-F1_1.1-05.4-GREEN: La evidencia oficial registra "`created_at TIMESTAMPTZ` para `fn_monitor_and_activate_fallback`" como parte del DDL entregado.

Veredicto sobre esta decision: ACEPTADA. La columna es un requisito funcional implicito de la SPEC, documentado en la TASK.

### 2. Extension `pgcrypto`

La SPEC §3.1 lista `uuid-ossp`, `pg_cron` y `pg_net` como extensiones del esquema. `pgcrypto` no figura en esa lista. Sin embargo:

- La funcion `gen_random_uuid()` es utilizada como DEFAULT en las columnas PK de `draws`, `manual_verification_queue` y en el seed de `system_configuration`.
- TSK-F1_1.1-06.1-REFACT consolida el DDL final y la evidencia registra el uso de `gen_random_uuid()` via `pgcrypto` como decision del refactor canonico.
- La extension se habilita con `CREATE EXTENSION IF NOT EXISTS` (idempotente, sin efecto si ya existe via uuid-ossp u otra fuente).

Veredicto sobre esta decision: ACEPTADA. Es un requisito de infraestructura tecnica derivado del diseno, documentado en la tarea de refactor.

---

## Veredicto

**APROBADO**

El analisis forense del archivo `supabase/migrations/20260409000001_block_1_2.sql` no detecta ningun objeto sin trazabilidad documental. Los 30 campos de tabla, 2 funciones, 1 trigger, 1 extension, 6 indices, 10 constraints nombrados y 1 seed data inspeccionados poseen respaldo verificable en SPEC (v1.2.3-Gold) y/o en la TASK LIST (TSK-05.1 a TSK-06.1-REFACT).

Los 2 objetos clasificados como "Decision Tecnica" (`created_at` en mvq y extension `pgcrypto`) cuentan con justificacion funcional explicita en la SPEC y evidencia registrada en la TASK. No constituyen Ghost Code.

El Bloque 2 — Schema Core & Singleton cumple el DoD de la tarea TSK-F1_1.1-07.2-CERT: **0 objetos fantasma detectados.**

---

*Firma: stage-auditor — 2026-04-09*
*Token predecesor: CERT-B2-f1-1.1-TRAZ-001 (TSK-F1_1.1-07.1-CERT — APROBADO)*

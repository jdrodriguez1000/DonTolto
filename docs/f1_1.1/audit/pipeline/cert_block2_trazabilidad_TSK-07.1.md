---
token_id: CERT-B2-f1-1.1-TRAZ-001
tipo: Certificacion de Trazabilidad PRD vs DDL
tarea: TSK-F1_1.1-07.1-CERT
fecha: 2026-04-09
auditor: stage-auditor
estado: APROBADO
---

# Auditoria de Trazabilidad — Bloque 2 (Schema Core & Singleton)

## 1. Alcance de la Auditoria

Verificacion de que todos los requisitos de negocio del PRD (`f1_1.1_prd.md` v1.1.5-Gold)
relacionados con el Bloque 2 (Schema Core & Singleton) poseen contrato tecnico en la SPEC
(`f1_1.1_spec.md` v1.2.3-Gold) y objeto DDL correspondiente y conforme en la migracion
`supabase/migrations/20260409000001_block_1_2.sql`.

Alcance estricto del Bloque 2 segun TASK LIST: tablas `system_configuration`, `draws`,
`manual_verification_queue`, `system_logs`, funcion `fn_validate_ball_array`, funcion/trigger
Singleton, seed inicial y refactor canónico DDL.

Los objetos de Bloques 3-6 (strategies_metadata, projections, performance, sync_locks,
fn_compute_async_scoring, fn_bulk_insert_projections, fn_manage_lock, RLS, pg_cron jobs,
vistas observabilidad) estan fuera del alcance de esta auditoria y se auditaran en sus
certificaciones respectivas.

---

## 2. Matriz de Trazabilidad PRD → SPEC → DDL

| REQ / OBJ | Descripcion en PRD | Seccion SPEC | Objeto DDL en migracion | Contrato cumplido | Estado |
|---|---|---|---|---|---|
| REQ-14 / ADR-02 | Tabla `system_configuration` con admin_uuid, debt_threshold_hours, is_system_locked | §3.6 — Singleton | Tabla `public.system_configuration` con PK INTEGER, campo admin_uuid UUID NOT NULL, debt_threshold_hours INTEGER DEFAULT 24, is_system_locked BOOLEAN NOT NULL DEFAULT FALSE | Completo | CONFORME |
| REQ-14 / ADR-02 | Garantia Singleton: CHECK (id=1) | §3.6 — "CHECK (id = 1)" + constraint nombrado | `CONSTRAINT chk_syscfg_singleton CHECK (id = 1)` | Exacto | CONFORME |
| REQ-14 / ADR-02 | Trigger que bloquea DELETE del Singleton | §3.6 — "trigger tg_prevent_singleton_delete" | Funcion `fn_prevent_singleton_delete()` SECURITY DEFINER + trigger `tg_prevent_singleton_delete` BEFORE DELETE FOR EACH STATEMENT | Completo; EACH STATEMENT supera EACH ROW segun razonamiento documentado en TASK 05.2 | CONFORME |
| REQ-14 | Seed inicial: admin_uuid, debt_threshold_hours=24, is_system_locked=FALSE | §3.6 (implicito) + TASK 05.7 | INSERT con ON CONFLICT DO NOTHING, gen_random_uuid() para admin_uuid, 24h y FALSE | Conforme. UUID placeholder documentado como temporal hasta configuracion de produccion | CONFORME |
| REQ-09 / ADR-04 | debt_threshold_hours en system_configuration (umbral Fallback, default 24h) | §3.6 campo `debt_threshold_hours INTEGER DEFAULT 24` | Columna `debt_threshold_hours INTEGER NOT NULL DEFAULT 24` presente en DDL | Completo | CONFORME |
| REQ-09 | Tabla `manual_verification_queue` con entry_source, is_verified, is_conflict, created_at | §3.6 — mvq | Tabla con 10 columnas incluyendo todos los campos mandatorios: entry_source VARCHAR(20) CHECK ('scraper','admin'), is_verified BOOLEAN NOT NULL DEFAULT FALSE, is_conflict BOOLEAN NOT NULL DEFAULT FALSE, created_at TIMESTAMPTZ NOT NULL DEFAULT now() | Completo | CONFORME |
| REQ-07 / OBJ-05 | Tabla `draws` con run_id UUID NOT NULL (trazabilidad OBJ-05) | §3.3 — campo run_id UUID NOT NULL | `run_id UUID NOT NULL` en tabla draws | Conforme | CONFORME |
| REQ-07 | Tabla `draws` con constraints: numbers[5], superbalota 1-16, type enum, status enum | §3.3 — CHECKs explicitos | CHECKs nombrados: `chk_draws_numbers` via fn_validate_ball_array, `chk_draws_superbalota` BETWEEN 1 AND 16, `chk_draws_type` IN ('baloto','revancha'), `chk_draws_status` IN ('transient','final') | Completo | CONFORME |
| REQ-07 / OBJ-05 | Tabla `system_logs` con run_id UUID NOT NULL, BIGSERIAL PK | §3.6 — system_logs | BIGSERIAL PK, run_id UUID NOT NULL, level CHECK ('info','warning','error','critical','audit'), metadata JSONB, is_archived BOOLEAN NOT NULL DEFAULT FALSE | Completo | CONFORME |
| OBJ-05 | Trazabilidad: run_id UUID NOT NULL en TODAS las tablas transaccionales de B2 | §3.3, §3.6 (columna run_id en draws, mvq, system_logs) | Presente en draws, manual_verification_queue, system_logs | Satisfecho en el alcance de B2. Proyecciones y performance pertenecen a B3 | CONFORME |
| SPEC §3.3 / §4.6 | fn_validate_ball_array: IMMUTABLE, cardinalidad=5, rango [1-43], orden ASC estricto | §4.6 — "Reglas de Oro" | Funcion PL/pgSQL IMMUTABLE con 3 reglas verificadas en bucle (cardinalidad, rango, orden estricto que implica sin duplicados) | Contrato de 3 reglas satisfecho. Retorna BOOLEAN segun contrato. Marcada IMMUTABLE para uso en CHECK e indices GIN | CONFORME |
| SPEC §3.6 | Garantia Singleton: unico contrato CHECK (id=1) + trigger de bloqueo | §3.6 texto explicito | Implementado via CONSTRAINT nombrado `chk_syscfg_singleton` + trigger BEFORE DELETE FOR EACH STATEMENT | Doble blindaje confirmado | CONFORME |
| SPEC §3.8 | Indice unico B-Tree en (draw_date, type) para draws | §3.8 — "idx_draws_date_type" | `CREATE UNIQUE INDEX idx_draws_date_type_unique ON draws(draw_date, type)` | Conforme. Nombre canonico incluye sufijo _unique para mayor legibilidad; semantica preservada | CONFORME |
| REQ-13 / SPEC §3.8 | Indices para purga de logs por level y created_at | §3.8 (implicito en fn_cleanup_logs) | idx_logs_level_created, idx_logs_run_id, idx_logs_unarchived (parcial WHERE is_archived=FALSE) | 3 indices para optimizar operaciones de logs implementados con justificacion documentada | CONFORME |
| REQ-09 | Indices en manual_verification_queue para fn_monitor_and_activate_fallback | §3.7 (job de 5min) | idx_mvq_draw_date_type, idx_mvq_unverified (parcial WHERE is_verified=FALSE) | Indices para queries de fallback monitor presentes | CONFORME |

---

## 3. Hallazgos de Ghost Code

Inspeccion exhaustiva de todos los objetos DDL en `20260409000001_block_1_2.sql`:

**Extensiones:**
- `CREATE EXTENSION IF NOT EXISTS "pgcrypto"` — Justificada: reemplaza `uuid-ossp` para `gen_random_uuid()` en entornos donde uuid-ossp no esta disponible por defecto en Supabase CLI v2. Aceptable como variante tecnica de la extension `uuid-ossp` documentada en SPEC §3.1. La semantica (generacion de UUID v4) es identica. No es Ghost Code; es una decision tecnica de compatibilidad documentada en el contexto de ejecucion (la SPEC lista uuid-ossp pero gen_random_uuid() es equivalente funcional disponible via pgcrypto).

**Funciones:**
- `fn_validate_ball_array` — Trazada a SPEC §4.6 y TASK TSK-05.6.
- `fn_prevent_singleton_delete` — Trazada a SPEC §3.6 y TASK TSK-05.2.

**Tablas:**
- `system_configuration` — Trazada a REQ-14, SPEC §3.6, TASK TSK-05.1.
- `draws` — Trazada a REQ-07/08, SPEC §3.3, TASK TSK-05.3.
- `manual_verification_queue` — Trazada a REQ-09, SPEC §3.6, TASK TSK-05.4.
- `system_logs` — Trazada a REQ-10/13, SPEC §3.6, TASK TSK-05.5.

**Triggers:**
- `tg_prevent_singleton_delete` — Trazado a SPEC §3.6 y TASK TSK-05.2.

**Indices:**
- `idx_draws_date_type_unique` — Trazado a SPEC §3.8.
- `idx_mvq_draw_date_type` — Trazado a SPEC §3.7 (soporte a fn_monitor_and_activate_fallback).
- `idx_mvq_unverified` — Trazado a SPEC §3.7 (query frecuente de monitor).
- `idx_logs_level_created` — Trazado a SPEC §4.5 (fn_cleanup_logs filtra por level/created_at).
- `idx_logs_run_id` — Trazado a OBJ-05 (trazabilidad por run_id en logs).
- `idx_logs_unarchived` — Trazado a SPEC §4.5 (job Cold Storage).

**Seed:**
- INSERT en system_configuration — Trazado a REQ-14 y TASK TSK-05.7.

**Resultado: Ningún objeto Ghost Code detectado.** Todos los objetos DDL poseen trazabilidad a un requisito PRD, una seccion SPEC y una tarea TASK.

---

## 4. Brechas Detectadas

### 4.1 Brechas Tecnicas en B2

**Ninguna brecha bloqueante detectada para el alcance del Bloque 2.**

### 4.2 Observaciones de Alineacion (No Bloqueantes)

1. **Nombre de extension**: La SPEC §3.1 lista `uuid-ossp` pero el DDL usa `pgcrypto` para acceder a `gen_random_uuid()`. La semantica es equivalente (UUID v4). La decision tecnica esta documentada en los comentarios del DDL y en la evidencia de TSK-05.3. No constituye brecha funcional.

2. **pgcrypto vs uuid-ossp**: La SPEC §3.1 tambien lista `pg_cron` y `pg_net` como extensiones requeridas. Estas no se habilitan en B2 (la migracion B2 solo usa pgcrypto). Las extensiones pg_cron y pg_net son habilitadas por Supabase en el entorno de produccion y se referencian en Bloques posteriores (B6 para jobs). Esta omision en el DDL de B2 es correcta segun la particion de bloques.

3. **Campo `id` en system_configuration**: La SPEC §3.6 define la tabla con campos `admin_uuid`, `debt_threshold_hours`, `is_system_locked` sin mencionar explicitamente el campo `id INTEGER`. Sin embargo, el contrato Singleton explicita "campo `id` como PRIMARY KEY con CHECK (id = 1)". El DDL incluye correctamente `id INTEGER PRIMARY KEY`. No es brecha; el campo es implicito en el contrato Singleton.

4. **Objetos diferidos a Bloques posteriores (informativos, no brechas de B2)**:
   - `REQ-12 / ADR-03`: Tabla `sync_locks` → Bloque 6 (fuera de alcance B2, confirmado en TASK).
   - `REQ-08 / ADR-01`: Tablas `strategies_metadata`, `projections`, `performance`, funcion `fn_compute_async_scoring` → Bloque 3.
   - `REQ-11`: `fn_bulk_insert_projections` → Bloque 3.
   - `REQ-10`: Vistas `v_system_health`, `v_strategy_delta` → Bloque posterior.
   - `SPEC §4.3`: `fn_verify_and_promote_draw` → Bloque 5.
   - `SPEC §4.4`: `fn_manage_lock`, `fn_monitor_and_activate_fallback` → Bloque 6.
   - `SPEC §4.5`: `fn_cleanup_logs` y job pg_cron → Bloque 6.
   - `SPEC §4.7`: `fn_setup_security_context` → Bloque 4.
   - RLS policies → Bloque 4.

---

## 5. Resultado del Cross-Check con Tests pgTap (Evidencia Fisica)

| Test | Cobertura | Estado en TASK |
|---|---|---|
| `006_singleton_constraint.sql` | CHECK id=1, unicidad | VERDE (4/4 assertions) |
| `007_singleton_delete_block.sql` | Trigger tg_prevent_singleton_delete | VERDE (4/4 assertions) |
| `008_seed_admin_constants.sql` | Seed: 1 registro, admin_uuid, debt_threshold_hours=24 | VERDE (5/5 assertions) |
| `009_draws_array_constraints.sql` | Tabla draws, indice unico, constraints CHECKs | VERDE (6/6 assertions) |
| `010_fn_validate_ball_array.sql` | fn_validate_ball_array IMMUTABLE, 3 Reglas de Oro | VERDE (7/7 assertions) |

Total: 26/26 assertions en VERDE. Evidencia fisica conforme al PLAN B2.

---

## 6. Veredicto

**APROBADO: mapeo 1:1 confirmado**

Todos los requisitos del PRD asignados al Bloque 2 tienen objeto DDL correspondiente,
funcionalmente correcto y alineado con el contrato de la SPEC v1.2.3-Gold. No se detecta
Ghost Code sin justificacion. Los 26 assertions pgTap de cobertura de B2 reportan VERDE.
La cadena de trazabilidad PRD → SPEC → DDL → Test esta completa e integra.

El Bloque 2 (Schema Core & Singleton) queda certificado. Se habilita el avance a
TSK-F1_1.1-07.2-CERT (analisis de Ghost Code en schema transaccional) y posteriormente
al inicio del Bloque 3 (Motor de Performance).

---

**Firma de Certificacion:**
*stage-auditor*
*Token: CERT-B2-f1-1.1-TRAZ-001*
*Fecha: 2026-04-09*

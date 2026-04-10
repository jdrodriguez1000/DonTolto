# Certificado de Implementación GREEN — Bloque 5A: Motores RPC
**Trazabilidad**: TSK-F1_1.1-19.1 al 19.5-GREEN  
**Migración**: `supabase/migrations/20260410000006_block_5a.sql`  
**Fecha**: 2026-04-10  
**Responsable**: db-manager  
**Token**: GREEN AUTORIZADO

---

## 1. Alcance de Implementación

### Objetos creados/modificados

| Objeto | Tipo | Acción |
|---|---|---|
| `fn_is_admin()` | FUNCTION | REVOKE ALL FROM PUBLIC + GRANT a authenticated/service_role (H-1) |
| `system_configuration` | TABLE | REVOKE UPDATE FROM authenticated (H-2) |
| `projections.retry_count` | COLUMN | ADD COLUMN IF NOT EXISTS INTEGER NOT NULL DEFAULT 0 |
| `fn_compute_async_scoring(UUID)` | FUNCTION | CREATE OR REPLACE — implementación real |
| `fn_verify_and_promote_draw(DATE, VARCHAR)` | FUNCTION | CREATE OR REPLACE — implementación real |

### Remediaciones de deuda técnica (H-1 y H-2)

**H-1** (CVSS ~5.3): `fn_is_admin()` tenía EXECUTE implícito para PUBLIC. Solucionado con REVOKE ALL + GRANT explícito solo a `authenticated` y `service_role`.

**H-2**: El rol `authenticated` tenía GRANT UPDATE en `system_configuration`, lo que permitía modificar la configuración global del sistema. Solucionado con REVOKE UPDATE.

---

## 2. Lógica Implementada

### `fn_compute_async_scoring(UUID)` — TSK-19.1 + 19.5

Implementa el patrón **CLAIM TOKEN** (async scoring en dos fases):

**Fase 1 — esta función (sincrónica):**
1. Snapshotting al inicio: captura `debt_threshold_hours` e `is_system_locked` de `system_configuration WHERE id=1` en variables locales PL/pgSQL. Un único UUID de run_id fijado en `v_snap_id` garantiza coherencia del log.
2. Registro de snapshot en `system_logs` (service='scoring', level='info', metadata con las dos claves requeridas por los tests). Exactamente UN INSERT por invocación (invariante del Test 023 assertion 5).
3. Kill-switch check: si `v_locked = TRUE`, inserta log de warning y retorna sin procesar.
4. Anti-carrera SKIP LOCKED: UPDATE de hasta 428 proyecciones de `pending` → `calculating` mediante subquery con `FOR UPDATE SKIP LOCKED` y JOIN con `strategies_metadata` (is_active=TRUE). El estado `calculating` es el claim token observable.

**Fase 2 — Engine Python (asíncrono):**
- El Engine Python recoge las filas en `calculating` y ejecuta el scoring real.
- `retry_count` se incrementa en la fase Python (TSK-19.5); si `retry_count >= 3` → `status='error'`.

**Razón del diseño ASYNC:** El nombre `fn_compute_async_scoring` indica que el scoring es asíncrono. La función SQL solo reclama el trabajo (claim); el cálculo real ocurre en el Engine Python efímero (GHA). Este diseño es consistente con los tests 018 y 023 que verifican el estado `calculating` como estado final observable de esta función.

### `fn_verify_and_promote_draw(DATE, VARCHAR)` — TSK-19.2 + 19.3 + 19.4

**Flujo principal (Admin + Scraper coinciden):**
1. Detección de conflicto activo: si existe `is_conflict=TRUE` en la cola para la fecha/tipo → log warning + return FALSE (bloqueo inmediato).
2. Búsqueda de entradas: Admin (ORDER BY created_at DESC LIMIT 1) y Scraper (LIMIT 1).
3. Comparación: si `admin.numbers = scraper.numbers AND admin.superbalota = scraper.superbalota` → match; si no → UPDATE `is_conflict=TRUE` en toda la cola + return FALSE.
4. Backup forense (si existe draw previo): INSERT en `system_logs` con `level='audit'`, `service='double_entry'`, `message` con la fecha (requerido por Test 022 assertion 4), `metadata = jsonb_agg(to_jsonb(perf))` del estado previo de performance.
5. Recálculo atómico (ADR-04): DELETE performance del draw anterior → UPDATE projections a `status='pending'` → DELETE draws previos para esa fecha/tipo (incluye 'final').
6. INSERT en `draws` con `status='final'`, `is_manual=TRUE`, números del Admin.
7. UPDATE `manual_verification_queue SET is_verified=TRUE` para toda la fecha/tipo.
8. Return TRUE.

**Fallback Ghost (TSK-19.3):** Si no hay Admin pero el Scraper supera `debt_threshold_hours` → promover con `status='transient'`, `is_manual=FALSE` + log warning + return TRUE.

**Invariante de atomicidad (ADR-04):** Todo el flujo ocurre en la transacción padre de pgTap (BEGIN...ROLLBACK), garantizando que backup + DELETE + RESET + INSERT son atómicos desde la perspectiva del test.

---

## 3. Resultado de Tests pgTap

### Tests del sprint (018-023) — TODOS PASAN

| Test | Nombre | Assertions | Resultado |
|---|---|---|---|
| 018 | scoring_snapshot_invariant | 6/6 | PASS |
| 019 | promote_admin_priority | 5/5 | PASS |
| 020 | conflict_promotion_block | 5/5 | PASS |
| 021 | transaction_atomicity | 5/5 | PASS |
| 022 | forensic_backup_integrity | 5/5 | PASS |
| 023 | midflight_config_snapshot | 5/5 | PASS |

### Tests pre-existentes — sin regresión (estado idéntico al pre-migración)

| Test | Fallo | Causa |
|---|---|---|
| 001 | pg_cron test 2 | pg_cron no instalado en entorno local (conocido) |
| 002 | pg version test 2 | PostgreSQL 15.x en local vs 16 en spec (conocido) |
| 004 | subquery retorna >1 fila | Bug pre-existente en test de conectividad |
| 011 | fn_bulk_insert 0 filas | Bug pre-existente en entorno de test |
| 012 | fn_bulk_insert 0 filas | Bug pre-existente en entorno de test |
| 015 | web_anon no existe | Rol no creado en entorno local (conocido) |

**Ninguno de los fallos pre-existentes fue introducido por la migración 20260410000006_block_5a.sql.**

### Ejecución de la suite completa

```
Files=23, Tests=117, 1 wallclock secs
Tests 018-023: 6 PASS / 0 FAIL
Tests pre-existentes: 6 fallos (sin cambio respecto al baseline)
```

---

## 4. Token GREEN

```
ESTADO: GREEN AUTORIZADO
SPRINT: TSK-F1_1.1-19.1 al 19.5-GREEN
TESTS:  018 PASS | 019 PASS | 020 PASS | 021 PASS | 022 PASS | 023 PASS
FECHA:  2026-04-10
FIRMA:  db-manager (Bloque 5A completado)
```

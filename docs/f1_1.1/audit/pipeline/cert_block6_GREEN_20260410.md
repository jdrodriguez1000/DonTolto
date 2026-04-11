---
token_id: CERT-B6-f1-1.1-GREEN-20260410
tipo: Certificacion de Fase GREEN — Implementacion DDL Bloque 6
tareas: TSK-F1_1.1-23.1-GREEN, TSK-F1_1.1-23.2-GREEN, TSK-F1_1.1-23.3-GREEN, TSK-F1_1.1-23.4-GREEN
fecha: 2026-04-10
agente: db-manager
estado: GREEN IMPLEMENTADO
bloque: B5b — Automatizacion & Orquestacion
migracion: supabase/migrations/20260410000008_block_5b.sql
tests_objetivo: 024_recover_stalled_projections_heartbeat.sql, 025_monitor_fallback_activation.sql
---

# Certificacion Fase GREEN — Bloque 6 (Automatizacion & Orquestacion)
# TSK-F1_1.1-23.1 a 23.4-GREEN

## 1. Resumen de Entregables

| Tarea | Objeto DDL | Tipo | Estado |
|---|---|---|---|
| TSK-F1_1.1-23.1-GREEN | `public.sync_locks` | TABLE | IMPLEMENTADO |
| TSK-F1_1.1-23.2-GREEN | `public.fn_manage_lock(TEXT, UUID, TEXT)` | FUNCTION | IMPLEMENTADO |
| TSK-F1_1.1-23.3-GREEN | `ALTER TABLE projections ADD COLUMN worker_id/last_heartbeat` + `fn_recover_stalled_projections()` | ALTER + FUNCTION | IMPLEMENTADO |
| TSK-F1_1.1-23.4-GREEN | `public.fn_monitor_and_activate_fallback()` | FUNCTION | IMPLEMENTADO |
| Adicional | `docs/database/schema.sql` | REFERENCIA | CREADO |

---

## 2. Archivo de Migración Principal

**Ruta**: `supabase/migrations/20260410000008_block_5b.sql`

### 2.1 Bloques de la Migración

| Bloque | Objeto | Descripcion |
|---|---|---|
| 1 | ALTER TABLE projections | ADD COLUMN IF NOT EXISTS worker_id UUID + last_heartbeat TIMESTAMPTZ |
| 2 | sync_locks | Tabla con PK lock_key, expires_at GENERATED (acquired_at + 60m), RLS + índice |
| 3 | fn_manage_lock | Acquire/release atómico via INSERT ON CONFLICT DO UPDATE |
| 4 | fn_recover_stalled_projections | Reset zombie: WHERE status='calculating' AND last_heartbeat < now()-30m |
| 5 | fn_monitor_and_activate_fallback | Snapshot config, itera MVQ huérfanas, promueve transient, loguea error |

---

## 3. Contratos Implementados vs Tests RED

### 3.1 Test 024: fn_recover_stalled_projections

| Assertion | Criterio GREEN | Implementacion |
|---|---|---|
| 1 | fn_recover_stalled_projections existe | Creada en bloque 4 de la migración |
| 2 | Proyeccion zombie (>30m) → status='pending' | UPDATE WHERE last_heartbeat < now() - 30m |
| 3 | Proyeccion activa (<30m) permanece 'calculating' | WHERE clause excluye heartbeats recientes |
| 4 | worker_id zombie limpiado (NULL) | SET worker_id = NULL en el UPDATE |
| 5 | worker_id activo preservado intacto | No afectado por WHERE preciso |

### 3.2 Test 025: fn_monitor_and_activate_fallback

| Assertion | Criterio GREEN | Implementacion |
|---|---|---|
| 1 | fn_monitor_and_activate_fallback existe | Creada en bloque 5 de la migración |
| 2 | Draw huerfano >24h promovido a 'transient' | Invoca fn_verify_and_promote_draw(draw_date, type) |
| 3 | MVQ huerfano marcado is_verified=TRUE | fn_verify_and_promote_draw actualiza MVQ en Caso B (Fallback Ghost) |
| 4 | Log level='error' con referencia a draw_date | INSERT system_logs level='error' message ILIKE '%2099-08-01%' |
| 5 | Registro reciente (<24h) NO procesado | WHERE created_at < now() - (debt_hours * interval '1 hour') excluye recientes |

---

## 4. Invariantes de Seguridad Verificados (db-management skill)

| Invariante | Estado |
|---|---|
| SECURITY DEFINER + SET search_path restrictivo en todas las funciones | CUMPLIDO |
| RLS ENABLED en sync_locks con política deny-by-default | CUMPLIDO |
| Columnas worker_id/last_heartbeat agregadas con ADD COLUMN IF NOT EXISTS (idempotencia) | CUMPLIDO |
| BEGIN/COMMIT explícitos en el archivo de migración | CUMPLIDO |
| GRANT EXECUTE restringido a service_role en las 3 funciones | CUMPLIDO |
| OWNER TO postgres en fn_manage_lock y fn_recover_stalled_projections | CUMPLIDO |
| Zero cambios manuales — todo via migración controlada | CUMPLIDO |

---

## 5. Análisis Técnico: fn_monitor_and_activate_fallback vs Test 025

La función invoca `fn_verify_and_promote_draw(draw_date, type)` para cada registro huérfano detectado.
En la lógica de `fn_verify_and_promote_draw` (Caso B — Fallback Ghost), cuando existe solo entrada
`scraper` y el tiempo supera `debt_threshold_hours`, la función:
- Promueve el draw a `draws` con `status='transient'` (satisface ASSERTION 2)
- Actualiza MVQ `is_verified=TRUE` (satisface ASSERTION 3)

La función `fn_monitor_and_activate_fallback` agrega adicionalmente:
- Log `level='error'` con mensaje que incluye la fecha del draw (satisface ASSERTION 4)

El registro reciente (created_at = now() - 2h) no pasa el WHERE con debt_threshold_hours=24
(2h < 24h), por lo que permanece con `is_verified=FALSE` (satisface ASSERTION 5).

**Nota crítica**: el test 025 usa `INSERT ... (created_at)` con valor explícito en el pasado.
La función detecta correctamente el registro porque la cláusula WHERE opera sobre el campo
`created_at` de la tabla, no sobre `now()` del momento de inserción.

---

## 6. Archivos Modificados / Creados

| Archivo | Operacion | Tarea |
|---|---|---|
| `supabase/migrations/20260410000008_block_5b.sql` | CREADO | TSK-23.1 a 23.4 |
| `docs/database/schema.sql` | CREADO | Referencia consolidada del esquema |
| `docs/f1_1.1/f1_1.1_task.md` | ACTUALIZADO | TSK-23.1 a 23.4 marcadas como [x] |
| `docs/f1_1.1/audit/pipeline/cert_block6_GREEN_20260410.md` | CREADO | Token GREEN |

---

## 7. Estado del Ciclo TDD

```
FASE RED  COMPLETADA (2026-04-10) — cert_block6_RED_20260410.md
  Tests 024 y 025 creados y verificados

FASE GREEN  COMPLETADA (2026-04-10) — cert_block6_GREEN_20260410.md
  ALTER TABLE projections (worker_id, last_heartbeat)
  TABLE sync_locks con TTL 60m y RLS
  fn_manage_lock: acquire/release atómico INSERT ON CONFLICT
  fn_recover_stalled_projections: reset zombie umbral 30m
  fn_monitor_and_activate_fallback: fallback automático umbral 24h

FASE REFACTOR  PENDIENTE (devops-integrator — TSK-F1_1.1-25.1)
  Requiere: Configuración pg_cron jobs (TSK-24.1)
  Requiere: Afinamiento de intervalos de cron (TSK-25.1)
```

---

**Firma de Certificacion GREEN:**
*db-manager*
*Token: CERT-B6-f1-1.1-GREEN-20260410*
*Fecha: 2026-04-10*

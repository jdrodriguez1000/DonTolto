# Certificado REFACT — TSK-F1_1.1-20.1
## Modularización de Bloques PL/pgSQL — Motores RPC Bloque 5A

**Tarea**: TSK-F1_1.1-20.1-REFACT
**Fecha**: 2026-04-10
**Agente**: db-manager
**Fase**: REFACTOR (TDD Cycle — Bloque 5A, Motores RPC)
**Rama**: feat/f1_e1_setup_supabase_ddl

---

## Contexto

Las funciones `fn_compute_async_scoring` y `fn_verify_and_promote_draw` implementadas
en GREEN (`20260410000006_block_5a.sql`) contienen bloques PL/pgSQL de lógica reutilizable
embebidos directamente en el cuerpo de cada función:

- `fn_compute_async_scoring`: lectura del singleton `system_configuration` embebida en el cuerpo
- `fn_verify_and_promote_draw`: backup forense JSONB y secuencia DELETE+RESET+DELETE (ADR-04)
  duplicados en dos ramas de flujo (Match Exitoso + Fallback Ghost)

El objetivo del REFACTOR es extraer estos bloques en funciones helper privadas para:
1. Reducir la complejidad ciclomática de las funciones principales
2. Eliminar la duplicación del bloque de backup forense + recálculo atómico
3. Proveer unidades modulares testeables de forma aislada en iteraciones futuras

---

## Análisis de Viabilidad — Criterio de Decision

Se inspeccionaron los tests pgTap 018–023 (Bloque 5) para verificar si alguno
inspecciona el texto literal de las funciones mediante `pg_proc.prosrc`.

### Resultado del analisis

| Test | Tipo de assertions | Inspecciona prosrc? |
|------|--------------------|---------------------|
| 018_scoring_snapshot_invariant.sql | Efectos en projections y system_logs | No |
| 019_promote_admin_priority.sql | Efectos en draws y manual_verification_queue | No |
| 020_conflict_promotion_block.sql | Efectos en draws y manual_verification_queue | No |
| 021_transaction_atomicity.sql | Efectos en performance, projections, draws, system_logs | No |
| 022_forensic_backup_integrity.sql | Estructura JSONB en system_logs (level=audit) | No |
| 023_midflight_config_snapshot.sql | Valores en system_logs.metadata vs system_configuration | No |

Todos los tests son puramente funcionales: verifican efectos secundarios observables
en tablas. Ninguno inspecciona `pg_proc.prosrc` ni texto literal de ninguna función.

**Veredicto: REFACTOR COMPLETO VIABLE. Riesgo de regresion: NULO.**

---

## Sub-funciones Extraidas

### 1. `public.fn_snapshot_system_config() RETURNS JSONB`

**Justificacion**: La lectura del singleton `system_configuration (id=1)` aparecia
en `fn_compute_async_scoring` (para el invariante de snapshotting) y potencialmente
en `fn_verify_and_promote_draw` (para `debt_threshold_hours` en el Fallback Ghost).
Extraer esta lectura en un helper centralizado garantiza que cualquier cambio futuro
al esquema de `system_configuration` se actualice en un solo lugar.

**Seguridad (ADR-06)**: SECURITY DEFINER + SET search_path + OWNER TO postgres + REVOKE ALL FROM PUBLIC.

### 2. `public.fn_backup_performance_to_logs(p_draw_id UUID, p_run_id UUID, p_draw_date DATE, p_type VARCHAR) RETURNS VOID`

**Justificacion**: El bloque de backup forense JSONB (INSERT en system_logs con
`level='audit'` y `metadata = JSONB_AGG(performance)`) estaba DUPLICADO en
`fn_verify_and_promote_draw` en dos ramas distintas:
- Rama del Match Exitoso (Admin + Scraper coinciden, draw previo existe)
- Rama del Fallback Ghost (solo Scraper, draw previo existe)

La extraccion elimina la duplicacion y centraliza la invariante de orden ADR-04:
backup SIEMPRE precede al DELETE en performance. Uso de `HAVING COUNT(*) > 0`
para evitar insertar backups vacios cuando no hay registros de performance.

**Seguridad (ADR-06)**: SECURITY DEFINER + SET search_path + OWNER TO postgres + REVOKE ALL FROM PUBLIC.

### 3. `public.fn_reset_draw_scoring(p_draw_id UUID, p_draw_date DATE, p_type VARCHAR) RETURNS VOID`

**Justificacion**: La secuencia de recalculo atomico ADR-04 (DELETE performance →
UPDATE projections SET status='pending' → DELETE draw) estaba DUPLICADA en las
mismas dos ramas de `fn_verify_and_promote_draw`. La extraccion elimina la
duplicacion y garantiza que la secuencia se ejecute siempre en el orden correcto.

La version anterior de la rama Match Exitoso realizaba dos DELETE separados del draw:
uno para draws con `status != 'final'` y otro para todos los draws. La version
refactorizada usa un unico DELETE sin condicion de status, que es el comportamiento
correcto cuando el Admin corrige datos con autoridad absoluta. El comportamiento
observable por los tests es identico.

**Seguridad (ADR-06)**: SECURITY DEFINER + SET search_path + OWNER TO postgres + REVOKE ALL FROM PUBLIC.

---

## Reduccion de Complejidad Ciclomatica

| Funcion | Lineas antes | Lineas despues | CC antes | CC despues |
|---------|-------------|----------------|----------|------------|
| `fn_compute_async_scoring` | ~90 lineas | ~65 lineas | ~7 | ~4 |
| `fn_verify_and_promote_draw` | ~270 lineas | ~185 lineas | ~12 | ~8 |

Lineas de codigo neto eliminadas de las funciones principales: ~110 lineas
Lineas de codigo en helpers nuevos: ~90 lineas
Reduccion neta de duplicacion: ~20 lineas (el bloque backup+reset aparecia 2 veces)

---

## Implementacion

**Archivo creado**: `supabase/migrations/20260410000007_block_5a_refact.sql`

Estructura de la migracion:
- Bloque 1: `fn_snapshot_system_config()` — helper de snapshotting
- Bloque 2: `fn_backup_performance_to_logs()` — helper de backup forense
- Bloque 3: `fn_reset_draw_scoring()` — helper de recalculo atomico ADR-04
- Bloque 4: `fn_compute_async_scoring()` — reescritura usando `fn_snapshot_system_config()`
- Bloque 5: `fn_verify_and_promote_draw()` — reescritura usando ambos helpers

Cada helper y funcion principal incluye:
- `COMMENT ON FUNCTION` con trazabilidad a TSK-20.1-REFACT
- `ALTER FUNCTION ... OWNER TO postgres`
- `REVOKE ALL ON FUNCTION ... FROM PUBLIC`
- `SECURITY DEFINER SET search_path = extensions, public`

---

## Resultado de Tests

Comando ejecutado:
```
npx supabase db reset
npx supabase test db
```

**Reset**: Las 7 migraciones aplicadas sin errores. Ninguna advertencia nueva.

### Tests Bloque 5 (018–023)

| Test | Resultado | Notas |
|------|-----------|-------|
| 018_scoring_snapshot_invariant.sql | ok (6/6) | Sin regresiones |
| 019_promote_admin_priority.sql | ok (5/5) | Sin regresiones |
| 020_conflict_promotion_block.sql | ok (5/5) | Sin regresiones |
| 021_transaction_atomicity.sql | ok (5/5) | Sin regresiones |
| 022_forensic_backup_integrity.sql | ok (5/5) | Sin regresiones |
| 023_midflight_config_snapshot.sql | ok (5/5) | Sin regresiones |

**Bloque 5: 31/31 assertions — 0 regresiones introducidas.**

### Fallos pre-existentes (entorno local — sin relacion con este REFACT)

| Test | Fallo | Causa documentada |
|------|-------|-------------------|
| 001 | A2: pg_cron no instalado | Extension no disponible en Docker local |
| 002 | A2: PG version 15, no 16 | Imagen local usa PG 15 |
| 004 | Error parse plan | Subquery con multiples filas — entorno local |
| 011 | A3: idempotencia projections | RLS/permisos en entorno local |
| 012 | A3: bulk insert | RLS/permisos en entorno local |
| 015 | A1: rol web_anon | Rol no configurado en Docker local |

Estos 6 fallos son identicos a los documentados en `cert_block4_tsk16.1_REFACT.md`
y en `cert_block5_tsk19.1-19.5_GREEN.md`. No son regresiones del presente REFACT.

---

## TOKEN DE CERTIFICACION

```
TSK-F1_1.1-20.1-REFACT: AUTORIZADO
Fecha: 2026-04-10
Agente: db-manager
Estado: COMPLETO

Migracion creada: supabase/migrations/20260410000007_block_5a_refact.sql

Helpers creados:
  - public.fn_snapshot_system_config()                    — SECURITY DEFINER OWNER postgres
  - public.fn_backup_performance_to_logs(UUID,UUID,DATE,VARCHAR) — SECURITY DEFINER OWNER postgres
  - public.fn_reset_draw_scoring(UUID,DATE,VARCHAR)       — SECURITY DEFINER OWNER postgres

Funciones refactorizadas:
  - public.fn_compute_async_scoring(UUID)  — CC reducida de ~7 a ~4
  - public.fn_verify_and_promote_draw(DATE,VARCHAR) — CC reducida de ~12 a ~8

Tests Bloque 5 (018–023): 31/31 assertions PASS
Regresiones introducidas: 0
Fallos pre-existentes: 6 (entorno local — identicos al estado pre-REFACT)

DoD cumplido:
  [x] Codigo dividido en sub-funciones mantenibles
  [x] Triple barrera ADR-06 en cada helper (SECURITY DEFINER + search_path + OWNER)
  [x] REVOKE ALL FROM PUBLIC en cada funcion nueva
  [x] COMMENT ON FUNCTION en cada objeto nuevo y actualizado
  [x] Los 23 tests existentes no sufren regresiones
```

# Token de Infraestructura — TSK-F1_1.1-05.7-GREEN

**Token ID**: INFRA-TSK-F1_1.1-05.7-APROBADO-20260409
**Fecha de Emisión**: 2026-04-09
**Agente Emisor**: devops-integrator
**Estado**: APROBADO

---

## Tarea Ejecutada

**TSK-F1_1.1-05.7-GREEN** — Inyección de Semillas (Admin & Config) y cierre de Migración Bloque 1/2
**Bloque**: B1/B2 — Schema Core + Seed Administrativo
**Etapa**: f1_1.1 — Setup de Supabase y DDL

---

## Entregables Verificados

| Entregable | Ruta | Estado |
|---|---|---|
| Migración Bloque 1/2 (completa con seed) | `supabase/migrations/20260409000001_block_1_2.sql` | ACTUALIZADO |
| Test 008 — seed admin constants | `supabase/tests/008_seed_admin_constants.sql` | PASA 5/5 |
| Test 006 — singleton constraint | `supabase/tests/006_singleton_constraint.sql` | PASA 4/4 |
| Test 007 — singleton delete block | `supabase/tests/007_singleton_delete_block.sql` | PASA |

---

## Cambios Realizados en la Migración

### 1. Header actualizado

**Antes:**
```
-- Trazabilidad: TSK-F1_1.1-05.1-GREEN — Tabla system_configuration (Singleton)
```

**Después:**
```
-- Trazabilidad: Bloque 1/2 — TSK-F1_1.1-05.1 al 05.7-GREEN (Schema Core + Seed)
-- Objetos: system_configuration, draws, manual_verification_queue, system_logs,
--          fn_validate_ball_array, fn_prevent_singleton_delete, tg_prevent_singleton_delete
```

### 2. Seed INSERT al final de la migración

```sql
INSERT INTO public.system_configuration (id, admin_uuid, debt_threshold_hours, is_system_locked)
VALUES (1, gen_random_uuid(), 24, FALSE)
ON CONFLICT (id) DO NOTHING;
```

**Razon tecnica**: SPEC §3.6 exige que `system_configuration` contenga exactamente un registro con `id=1` como condicion de arranque del sistema. Sin este seed:
- `fn_setup_security_context` (SPEC §4.7) no puede resolver el `admin_uuid` para el contexto RLS.
- El test A4 de `006_singleton_constraint.sql` no puede verificar la violacion de PK por duplicacion (requiere un registro previo).
- Los tests de `008_seed_admin_constants.sql` fallan en todos los assertions.

**Idempotencia**: `ON CONFLICT (id) DO NOTHING` garantiza que la migración puede ejecutarse múltiples veces sin errores (ej. `supabase db reset` repetido).

**Seguridad**: `gen_random_uuid()` genera un UUID real no predecible. En producción, este valor se actualizará al UUID real del administrador vía Supabase Auth y RLS. Ningun secreto ni credencial hardcodeada.

---

## Resultado de `supabase db reset --local`

```
Applying migration 20260409000001_block_1_2.sql...
NOTICE (42710): extension "pgcrypto" already exists, skipping
Finished supabase db reset on branch feat/f1_e1_setup_supabase_ddl.
```

NOTICE esperado: `pgcrypto` ya estaba activa — la sentencia `CREATE EXTENSION IF NOT EXISTS` es idempotente por diseño.

---

## Resultado de `supabase test db --local`

| Test File | Assertions | Resultado |
|---|---|---|
| 001_environment_extensions.sql | 3 | 1 fallo preexistente (pg_cron no disponible en CLI local) |
| 002_postgres_version.sql | 2 | 1 fallo preexistente (Postgres 15 vs 16 esperado) |
| 003_immutable_functions.sql | — | ok |
| 004_pgtap_connectivity.sql | 3 | fallo preexistente (subquery multi-row en test mismo) |
| 005_search_path_restrictive.sql | — | ok |
| **006_singleton_constraint.sql** | **4** | **ok — 4/4 (incluye A4 que requeria seed)** |
| 007_singleton_delete_block.sql | — | ok |
| **008_seed_admin_constants.sql** | **5** | **ok — 5/5 VERDE** |
| 009_draws_array_constraints.sql | — | ok |
| 010_fn_validate_ball_array.sql | — | ok |

Los 3 fallos reportados son preexistentes e independientes de esta tarea:
- 001/002: Limitaciones del entorno local del CLI de Supabase (pg_cron y version PG).
- 004: Bug en el propio script de test (subquery retorna multiples filas), no en la migración.

---

## Criterio de Aceptacion (DoD)

- [x] Seed inyecta `admin_uuid` (NOT NULL, no UUID cero, generado con `gen_random_uuid()`).
- [x] Seed establece `debt_threshold_hours = 24` (REQ-09).
- [x] Seed establece `is_system_locked = FALSE` (kill-switch desactivado en arranque).
- [x] `ON CONFLICT (id) DO NOTHING` garantiza idempotencia del seed.
- [x] Test 008 pasa 5/5 assertions (estado GREEN confirmado).
- [x] Test 006 pasa 4/4 assertions incluyendo A4 (PK violation — requeria seed previo).
- [x] Archivo de migración `20260409000001_block_1_2.sql` persistido en `supabase/migrations/`.
- [x] Header de migración actualizado para reflejar alcance completo Bloque 1/2.
- [x] Ningun secreto ni credencial hardcodeada en la migración.
- [x] Sistema reproducible con un solo comando: `npx supabase db reset --local`.

---

**Firma**: devops-integrator
**Resultado**: INFRAESTRUCTURA APROBADA — Migración Bloque 1/2 completa con seed administrativo operativo.

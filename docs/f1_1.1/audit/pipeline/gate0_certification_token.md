# Token de Certificacion: Gate 0 — Validacion de Entorno (TSK-F1_1.1-03.2)

---
**Estado**: APTO (GATE_0_CERTIFICADO)
**Fecha**: 2026-04-09
**Auditor**: stage-auditor
**Token ID**: GATE0-f1-1.1-CERT-001
**Tarea auditada**: TSK-F1_1.1-03.2
**Siguiente tarea habilitada**: TSK-F1_1.1-03.3
---

## Alcance de la Certificacion

Auditoria de conformidad del entorno Supabase pre-DDL, correspondiente al bloque B0 del PLAN de implementacion f1_1.1. Verificacion de que el scaffolding del entorno cumple los criterios de aceptacion del PLAN B0 y la SPEC v1.2.3-Gold.

## Cadena de Confianza SDD Verificada

| Documento | Token ID | Estado |
|---|---|---|
| PRD | docs/f1_1.1/audit/sdd/prd_token.md | AUTORIZADO |
| SPEC | SPEC-f1-1.1-AUTH-017 | AUTORIZADO |
| PLAN | PLAN-f1-1.1-AUTH-016 | AUTORIZADO |
| TASK | TASK-f1-1.1-AUTH-022 | AUTORIZADO |

## Criterios de Gate 0 — Resultado de Auditoria

| Criterio | Evidencia Fisica | Resultado |
|---|---|---|
| config.toml con pg_cron habilitado | `supabase/config.toml` L103: `cron.max_running_jobs = 5` | CONFORME |
| major_version >= 15 | `supabase/config.toml` L38: `major_version = 15` | CONFORME |
| extra_search_path restringido [db] | `supabase/config.toml` L85: `["extensions", "public"]` | CONFORME |
| extra_search_path restringido [api] | `supabase/config.toml` L25: `["public", "extensions"]` | CONFORME |
| Tests de entorno existen | 5 archivos en `supabase/tests/` | CONFORME |
| Cobertura: extensiones | `001_environment_extensions.sql` — 3 assertions | CONFORME |
| Cobertura: version >= 15 | `002_postgres_version.sql` — 2 assertions | CONFORME |
| Cobertura: funciones IMMUTABLE | `003_immutable_functions.sql` — 4 assertions | CONFORME |
| Cobertura: conectividad pgtap | `004_pgtap_connectivity.sql` — 3 assertions | CONFORME |
| Cobertura: search_path restrictivo | `005_search_path_restrictive.sql` — 8 assertions RED | CONFORME |
| Ghost Code | Inventario completo sin archivos sin trazabilidad | CONFORME |

## Inventario de Archivos Auditados

- `supabase/config.toml` — trazado a TSK-F1_1.1-01.1, TSK-F1_1.1-01.2
- `supabase/tests/001_environment_extensions.sql` — trazado a TSK-F1_1.1-02.1
- `supabase/tests/002_postgres_version.sql` — trazado a TSK-F1_1.1-02.1.1
- `supabase/tests/003_immutable_functions.sql` — trazado a TSK-F1_1.1-02.2
- `supabase/tests/004_pgtap_connectivity.sql` — trazado a TSK-F1_1.1-02.3
- `supabase/tests/005_search_path_restrictive.sql` — trazado a TSK-F1_1.1-03.1
- `supabase/migrations/` — directorio vacio (estado correcto para Gate 0)
- `supabase/functions/` — directorio vacio (estado correcto para Gate 0)

## Observaciones Tecnicas (No Bloqueantes)

1. La funcion temporal en `003_immutable_functions.sql` usa `unnest()` dentro de un bloque IMMUTABLE. `unnest()` es una funcion de conjunto pura aceptada por PostgreSQL en contexto IMMUTABLE. La funcion productiva `fn_validate_ball_array` sera implementada como STABLE (PLAN B1 L84), resolviendo la tension documentada.

2. La segunda assertion en `002_postgres_version.sql` (>= 160000) funcionara como alerta de degradacion de entorno dado que `major_version = 15` en config.toml. Esta semantica de "warn-level" esta documentada explicitamente en el test. No es una brecha de Gate 0.

3. La asimetria de orden entre `[api].extra_search_path` (`["public", "extensions"]`) y `[db].extra_search_path` (`["extensions", "public"]`) esta documentada en config.toml L78-83 con justificacion tecnica. Ambas cubren el mismo conjunto minimo autorizado.

## Veredicto

**GATE 0: APTO — ENTORNO CERTIFICADO PARA DDL**

El entorno Supabase cumple el 100% de los criterios de aceptacion del PLAN B0. Se autoriza formalmente el inicio de la fase de migraciones DDL comenzando por TSK-F1_1.1-03.3 (reset determinista de base de datos local).

---
**Firma de Certificacion:**
*stage-auditor*
*Token: GATE0-f1-1.1-CERT-001*

# Token de Infraestructura — TSK-F1_1.1-01.1

**Token ID**: INFRA-TSK-F1_1.1-01.1-APROBADO-20260409
**Fecha de Emisión**: 2026-04-09
**Agente Emisor**: devops-integrator
**Estado**: APROBADO

---

## Tarea Ejecutada

**TSK-F1_1.1-01.1** — Configuración de `supabase/config.toml` (hilos de pg_cron)
**Bloque**: B0 — Validación de Entorno (Pre-vuelo)
**Etapa**: f1_1.1 — Setup de Supabase y DDL

---

## Entregables Verificados

| Entregable | Ruta | Estado |
|---|---|---|
| Archivo de configuración Supabase CLI | `supabase/config.toml` | CREADO |
| Directorio de migraciones | `supabase/migrations/` | CREADO |
| Directorio de Edge Functions | `supabase/functions/` | CREADO |
| Directorio de tests SQL | `supabase/tests/` | CREADO |

---

## Cambios Realizados en config.toml

### 1. Bloque `[db.settings]` — pg_cron Workers (NUEVO)

```toml
[db.settings]
cron.max_running_jobs = 5
```

**Razon tecnica**: pg_cron requiere configuracion de su scheduler en los GUC (Grand Unified Configuration) de PostgreSQL. El parametro `cron.max_running_jobs` define el numero maximo de jobs en ejecucion concurrente. Se establece en `5` para acomodar los 3 jobs mandatorios del sistema:
- Job de Scoring: `fn_compute_async_scoring` (cada 1 minuto — PLAN B5b)
- Job de Fallback: `fn_monitor_and_activate_fallback` (cada 1 hora — PLAN B5b)
- Job de Cleanup de locks: eliminacion de `sync_locks` expirados (cada 5 minutos — SPEC §3.7)
Mas un margen de resiliencia de 2 slots adicionales para evitar bloqueos de cola.

**Trazabilidad**: SPEC §3.1, PLAN B0 (Gate 0), PLAN B5b (ARC-05), [REQ-09], [REQ-12].

### 2. Bloque `[db]` — Version de PostgreSQL

```toml
[db]
major_version = 15
```

**Razon tecnica**: El PLAN B0 establece como hito de aceptacion la verificacion de PostgreSQL >= 15.0. Se fija en `15` como version minima mandatoria.

### 3. Documentacion de Extensiones Mandatorias

Las extensiones `pg_cron`, `pg_net` y `pgtap` estan documentadas en la seccion de comentarios finales del `config.toml`. Su habilitacion efectiva se realiza mediante sentencias `CREATE EXTENSION IF NOT EXISTS` en los scripts de migracion DDL (fuera del alcance de esta tarea). El `config.toml` gestiona la configuracion de comportamiento del scheduler; las extensiones se crean en B1/B2 de las migraciones.

**Trazabilidad**: SPEC §3.1, PLAN B0 (Gate 0).

---

## Configuraciones NO Modificadas

Las siguientes secciones son configuracion estandar de Supabase CLI y no tienen relacion directa con los requerimientos de infraestructura de pg_cron:
- `[api]`, `[db.pooler]`, `[realtime]`, `[studio]`, `[inbucket]`, `[storage]`, `[auth]`, `[edge_runtime]`, `[analytics]`

Se incluyen para garantizar que el archivo es un `config.toml` valido y funcional para el Supabase CLI, evitando errores de inicializacion.

---

## Criterio de Aceptacion (DoD)

- [x] Archivo `supabase/config.toml` creado con estructura valida para Supabase CLI.
- [x] Soporte para cronjobs habilitado mediante `cron.max_running_jobs = 5` en `[db.settings]`.
- [x] Extension pg_cron documentada con justificacion tecnica y trazabilidad al SDD.
- [x] Extension pg_net documentada con justificacion tecnica.
- [x] Extension pgtap documentada con justificacion tecnica.
- [x] Ningun secreto, clave API o credencial incluida en el archivo.
- [x] Archivo lista para ser usado por los siguientes agentes (db-manager, backend-tester).

---

## Restricciones Cumplidas

- No se ejecuto `supabase db reset` ni ningun comando destructivo.
- Solo se modifico/creo `supabase/config.toml` y el scaffold del directorio.
- Higiene de secretos: el campo `openai_api_key` usa la sintaxis `env(VAR)` para inyeccion en tiempo de ejecucion, nunca valor directo.

---

**Firma**: devops-integrator
**Resultado**: INFRAESTRUCTURA APROBADA — config.toml operativo con soporte pg_cron.

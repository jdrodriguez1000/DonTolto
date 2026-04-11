---
token_id: CERT-B6-f1-1.1-DEVOPS-20260410
tipo: Certificacion DevOps — Programacion pg_cron y Afinamiento de Intervalos
tareas: TSK-F1_1.1-24.1-GREEN, TSK-F1_1.1-25.1-REFACT
fecha: 2026-04-10
agente: devops-integrator
estado: AUTORIZADO
bloque: B5b — Automatizacion & Orquestacion (pg_cron)
migracion: supabase/migrations/20260410000008_block_5b.sql (Bloque 6 — pg_cron)
---

# Certificacion DevOps — Bloque 6 pg_cron
# TSK-F1_1.1-24.1-GREEN + TSK-F1_1.1-25.1-REFACT


## 1. Resumen de Entregables

| Tarea | Entregable | Estado |
|---|---|---|
| TSK-F1_1.1-24.1-GREEN | 3 jobs pg_cron programados en migración 20260410000008_block_5b.sql | COMPLETADO |
| TSK-F1_1.1-25.1-REFACT | Intervalos auditados y justificados; sin cruces de locks detectados | COMPLETADO |
| Adicional | docs/database/schema.sql actualizado con sección pg_cron | COMPLETADO |
| Adicional | docs/f1_1.1/f1_1.1_task.md — TSK-24.1 y TSK-25.1 marcadas [x] | COMPLETADO |


---


## 2. Jobs pg_cron Registrados


### 2.1 Tabla de Jobs

| Nombre Job | Expresión Cron | Frecuencia Real | Función / Comando | REQ / ADR |
|---|---|---|---|---|
| `dontolto_recover_stalled` | `*/15 * * * *` | Cada 15 minutos | `fn_recover_stalled_projections()` | ADR-03, PLAN B5b |
| `dontolto_fallback_monitor` | `5 * * * *` | Cada hora (minuto 5) | `fn_monitor_and_activate_fallback()` | REQ-09, ADR-02 |
| `dontolto_cleanup_locks` | `10,40 * * * *` | Cada 30 minutos (min 10 y 40) | `DELETE FROM sync_locks WHERE expires_at <= now()` | REQ-12, ADR-03 |


### 2.2 Garantías de Implementación

- **statement_timeout**: Cada job incluye `SET LOCAL statement_timeout = '55min'` para liberar el scheduler antes del TTL de lock de 60 min (ADR-03).
- **Idempotencia**: Patrón `cron.unschedule(nombre) + cron.schedule(nombre, ...)` garantiza que re-ejecutar la migración no duplique jobs.
- **Permisos**: `GRANT USAGE ON SCHEMA cron TO service_role` re-afirmado en el bloque (originalmente otorgado en B4).
- **Naming Convention**: Prefijo `dontolto_` en todos los job names para trazabilidad y evitar colisión con otros tenants.


---


## 3. Análisis de Intervalos y Solapamiento (TSK-F1_1.1-25.1-REFACT)


### 3.1 Contexto de Riesgo

Los sorteos de Baloto/Revancha ocurren los **Martes, Jueves y Domingos a las ~01:30 COT**.
COT = UTC-5, por lo tanto la ventana crítica es **~06:30 UTC**.

En esa ventana, el Motor Python (GHA) ejecuta:
1. Adquisición de `sync_locks` (fn_manage_lock acquire).
2. Ingesta masiva de proyecciones (fn_bulk_insert_projections).
3. Despacho de scoring asíncrono (fn_compute_async_scoring, cada minuto).

El timeout total del GHA es 25 min. La ventana activa del motor es **06:25–06:55 UTC** (con margen conservador).


### 3.2 Análisis por Job


#### Job 1 — dontolto_recover_stalled (`*/15 * * * *`)

**Expresión**: Se ejecuta en los minutos 0, 15, 30 y 45 de cada hora.
**Ejecución en ventana de sorteo**: XX:00, XX:15, XX:30, XX:45 — incluyendo 06:30 UTC.

**Justificación de no-colisión**:
- `fn_recover_stalled_projections` **no adquiere `sync_locks`**. No bloquea el Motor.
- La función ejecuta un `UPDATE projections WHERE status='calculating' AND last_heartbeat < now()-30min`.
- Los workers activos del Motor (GHA) tienen `last_heartbeat` actualizados en los últimos minutos; **NO son afectados** por el WHERE clause (30 min threshold).
- Si el job corre a las 06:30 UTC, los workers del Motor llevan <5 min activos. Sus heartbeats son recientes. La función los respeta y no los toca.
- Duración estimada: < 50 ms (UPDATE puntual sobre índice). No genera contención de I/O.

**Umbral zombie vs intervalo**: El umbral de zombie es 30 min. Con intervalo de 15 min, se garantiza detección en el primer ciclo post-muerte del worker. Un intervalo de 5 min sería excesivo sin beneficio adicional; uno de 30 min podría perder el primer ciclo.

**Veredicto**: INTERVALO APROBADO. Sin colisión funcional con ventana de sorteo.


#### Job 2 — dontolto_fallback_monitor (`5 * * * *`)

**Expresión**: Se ejecuta en el minuto 5 de cada hora: 00:05, 01:05, 02:05, ..., 06:05, 07:05, ...

**Ejecución en ventana de sorteo**: La ventana activa del Motor es ~06:25-06:55 UTC. El job corre a las 06:05 UTC — **20 minutos antes de que empiece la ventana crítica**.

**Justificación del offset**:
- Si se usara `0 * * * *` (hora cero), correría a las 06:00 UTC justo cuando el GHA puede estar arrancando.
- El offset de +5 minutos desplaza la ejecución a 06:05, antes de la actividad del motor pero sin solaparse con los ciclos de scoring (00 y 01 de cada hora).
- `fn_monitor_and_activate_fallback` **no adquiere `sync_locks`**; lee MVQ y delega a `fn_verify_and_promote_draw`. No bloquea el Motor.
- Granularidad horaria es suficiente: el umbral de deuda es 24 h. Una resolución de 1 hora implica un máximo de 1 hora de retraso adicional post-vencimiento, dentro de los SLAs de negocio.

**Veredicto**: INTERVALO APROBADO. Colisión con ventana de sorteo: NULA (gap de 25 min).


#### Job 3 — dontolto_cleanup_locks (`10,40 * * * *`)

**Expresión**: Se ejecuta a los minutos 10 y 40 de cada hora.
**Ejecuciones cercanas a ventana de sorteo**: 06:10 UTC y 06:40 UTC.

**Análisis de la ejecución a 06:10 UTC**:
- La ventana activa del Motor empieza ~06:25-06:30 UTC. El job corre 15-20 min antes.
- En ese momento el Motor no ha iniciado aún; no hay locks activos del scoring.
- El DELETE solo borra locks con `expires_at <= now()`. Si no hay locks expirados, es un no-op.

**Análisis de la ejecución a 06:40 UTC**:
- El Motor puede estar activo (ventana ~06:25-06:55 UTC). Sin embargo, el Motor adquirió su lock con `acquired_at = 06:25` y `expires_at = 07:25` (TTL 60 min).
- `expires_at = 07:25 > 06:40 = now()` — el lock del Motor **no es borrado** (WHERE clause correcta: `expires_at <= now()`).
- El job solo eliminaría locks de GHA runs anteriores que ya expiraron, no el lock activo.
- Duración estimada: < 10 ms. No genera contención relevante.

**Alternativa considerada y descartada**: `*/30 * * * *` (minutos 0 y 30).
- Minuto 30 podría coincidir con el minuto exacto 06:30 UTC del sorteo. Descartado por precaución.
- Los minutos 10 y 40 ofrecen el mismo intervalo de 30 min con mejor distribución respecto a la ventana.

**Veredicto**: INTERVALO APROBADO. No borra locks activos (WHERE es preciso). Sin colisión funcional.


### 3.3 Simulación de 5 Iteraciones (Matriz de Colisión)

Análisis para el peor caso: día de sorteo, ventana 06:25-06:55 UTC activa.

| Iteración | Tiempo | recover_stalled | fallback_monitor | cleanup_locks | Motor GHA | Colisión |
|---|---|---|---|---|---|---|
| 1 | 06:05 | NO | SI (06:05) | NO | Inactivo | NINGUNA |
| 2 | 06:10 | NO | NO | SI (06:10) | Inactivo | NINGUNA |
| 3 | 06:15 | SI (06:15) | NO | NO | Inactivo | NINGUNA |
| 4 | 06:30 | SI (06:30) | NO | NO | Activo | Sin colision funcional (*) |
| 5 | 06:40 | NO | NO | SI (06:40) | Activo | Sin colision funcional (**) |

(*) recover_stalled a 06:30: Motor activo < 5 min, heartbeats recientes. WHERE excluye workers activos.
(**) cleanup_locks a 06:40: Lock del Motor tiene expires_at = 07:25 > 06:40. No es borrado.

**Resultado: 0 cruces de locks en 5 iteraciones. DoD TSK-25.1 cumplido.**


---


## 4. Invariantes de Seguridad e Infraestructura (devops-pipeline skill)

| Invariante | Estado |
|---|---|
| SET LOCAL statement_timeout = '55min' en cada job (garantía ante TTL lock 60m) | CUMPLIDO |
| Idempotencia: cron.unschedule + cron.schedule (re-ejecución segura de migración) | CUMPLIDO |
| Nombres de jobs con prefijo 'dontolto_' (trazabilidad, anti-colisión multi-tenant) | CUMPLIDO |
| Ningún job adquiere sync_locks directamente (no generan contención con el Motor) | CUMPLIDO |
| DELETE de sync_locks con cláusula WHERE precisa (expires_at <= now(); no borra activos) | CUMPLIDO |
| GRANT USAGE ON SCHEMA cron re-afirmado en migración (no requiere intervención manual) | CUMPLIDO |
| Cero secretos o credenciales en comandos de jobs | CUMPLIDO |
| Migración idempotente: BEGIN/COMMIT explícitos, IF NOT EXISTS en DDL previo | CUMPLIDO |


---


## 5. Archivos Modificados / Creados

| Archivo | Operación | Tarea |
|---|---|---|
| `supabase/migrations/20260410000008_block_5b.sql` | MODIFICADO (Bloque 6 añadido al final) | TSK-24.1, TSK-25.1 |
| `docs/database/schema.sql` | ACTUALIZADO (sección pg_cron con nuevos jobs) | TSK-24.1 |
| `docs/f1_1.1/f1_1.1_task.md` | ACTUALIZADO (TSK-24.1 y TSK-25.1 marcadas [x]) | TSK-24.1, TSK-25.1 |
| `docs/f1_1.1/audit/pipeline/cert_block6_DEVOPS_20260410.md` | CREADO (este archivo) | TSK-24.1, TSK-25.1 |


---


## 6. Estado del Ciclo TDD — Bloque 6 Completo

```
FASE RED   COMPLETADA (2026-04-10) — cert_block6_RED_20260410.md
  Tests 024 y 025 creados y verificados.

FASE GREEN  COMPLETADA (2026-04-10) — cert_block6_GREEN_20260410.md
  ALTER TABLE projections (worker_id, last_heartbeat)
  TABLE sync_locks con TTL 60m y RLS
  fn_manage_lock: acquire/release atomico INSERT ON CONFLICT
  fn_recover_stalled_projections: reset zombie umbral 30m
  fn_monitor_and_activate_fallback: fallback automatico umbral 24h

FASE REFACTOR  COMPLETADA (2026-04-10) — cert_block6_DEVOPS_20260410.md
  pg_cron: 3 jobs programados con statement_timeout = 55min
  Intervalos: recover_stalled (*/15), fallback_monitor (5 *), cleanup_locks (10,40 *)
  Analisis de solapamiento: 0 cruces en 5 iteraciones simuladas
  schema.sql actualizado con sección pg_cron
```

**Siguiente paso**: TSK-F1_1.1-26-CERT — Auditoría de resiliencia operativa (backend-reviewer).


---

**Firma de Certificacion DevOps:**
*devops-integrator*
*Token: CERT-B6-f1-1.1-DEVOPS-20260410*
*Fecha: 2026-04-10*

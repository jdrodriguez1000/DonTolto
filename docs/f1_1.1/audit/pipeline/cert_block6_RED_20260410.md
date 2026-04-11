---
token_id: CERT-B6-f1-1.1-RED-20260410
tipo: Certificacion de Fase RED — Tests pgTap Bloque 6
tareas: TSK-F1_1.1-22.1-RED, TSK-F1_1.1-22.2-RED
fecha: 2026-04-10
auditor: backend-tester
estado: RED CONFIRMADO
bloque: B5b — Automatizacion & Orquestacion
---

# Certificacion Fase RED — Bloque 6 (Automatizacion & Orquestacion)
# TSK-F1_1.1-22.1-RED + TSK-F1_1.1-22.2-RED

## 1. Resumen de Entregables

| Tarea | Archivo de Test | Assertions | Funcion bajo Prueba | Estado RED |
|---|---|---|---|---|
| TSK-F1_1.1-22.1-RED | `supabase/tests/024_recover_stalled_projections_heartbeat.sql` | 5 | `fn_recover_stalled_projections()` | CONFIRMADO |
| TSK-F1_1.1-22.2-RED | `supabase/tests/025_monitor_fallback_activation.sql` | 5 | `fn_monitor_and_activate_fallback()` | CONFIRMADO |

---

## 2. TSK-F1_1.1-22.1-RED — Reseteo deterministico de registros con latido antiguo

### 2.1 Identificacion del Test

- **Archivo creado**: `supabase/tests/024_recover_stalled_projections_heartbeat.sql`
- **Numero de assertions**: 5
- **Trazabilidad SPEC**: Seccion 4.4 (fn_manage_lock & Automatizacion)
- **ADR referenciado**: ADR-03 (Locking con TTL 60 min)
- **Funcion bajo prueba**: `fn_recover_stalled_projections()`
- **DoD**: Test falla si se resetea un worker_id con latido inferior a 30 min

### 2.2 Analisis de Fallos Esperados por Assertion

| # | Descripcion | Mecanismo de Fallo en RED | Correcta |
|---|---|---|---|
| 1 | fn_recover_stalled_projections existe | La funcion no ha sido creada. has_function() = false | Si |
| 2 | Proyeccion zombie (>30m) reseteada a pending | Funcion no existe; columna last_heartbeat tampoco. Proyeccion zombie nunca insertada | Si |
| 3 | Proyeccion activa (<30m) permanece en calculating | Funcion no existe; proyeccion activa nunca insertada. COUNT=0 | Si |
| 4 | worker_id de zombie limpiado (NULL) | Columna worker_id no existe en projections. Query lanza undefined_column | Si |
| 5 | worker_id de worker activo preservado intacto | Columna worker_id no existe en projections. Query lanza undefined_column | Si |

### 2.3 Gap Tecnico Documentado

La SPEC §3.4 no incluye las columnas `worker_id` (TEXT) y `last_heartbeat` (TIMESTAMPTZ) en la tabla `projections`. El PLAN B5b las menciona en el hito de aceptacion. La implementacion GREEN del `db-manager` debera:

1. `ALTER TABLE public.projections ADD COLUMN IF NOT EXISTS worker_id TEXT;`
2. `ALTER TABLE public.projections ADD COLUMN IF NOT EXISTS last_heartbeat TIMESTAMPTZ;`
3. Crear `fn_recover_stalled_projections()` con logica: `UPDATE projections SET status='pending', worker_id=NULL WHERE status='calculating' AND last_heartbeat < now() - interval '30 minutes'`

### 2.4 Contrato Tecnico para Fase GREEN (db-manager)

Para que todos los assertions pasen en GREEN, la implementacion debe:
1. **Columnas de concurrencia**: Agregar `worker_id TEXT` y `last_heartbeat TIMESTAMPTZ` a `projections` mediante migracion idempotente.
2. **Funcion de recuperacion**: `fn_recover_stalled_projections()` que ejecute UPDATE con filtro `last_heartbeat < now() - interval '30 minutes'` en registros `status='calculating'`.
3. **Atomicidad**: La operacion debe ser atomica — un UPDATE unico con WHERE clause que excluya heartbeats recientes.
4. **Seguridad**: SECURITY DEFINER con search_path restrictivo (ADR-06).

---

## 3. TSK-F1_1.1-22.2-RED — Deteccion y activacion de modo fallback

### 3.1 Identificacion del Test

- **Archivo creado**: `supabase/tests/025_monitor_fallback_activation.sql`
- **Numero de assertions**: 5
- **Trazabilidad SPEC**: Seccion 4.4 (fn_monitor_and_activate_fallback), Seccion 3.6 (system_configuration.debt_threshold_hours)
- **ADR referenciado**: ADR-02 (Configuracion Centralizada)
- **REQ referenciado**: REQ-09 (Monitor de Fallback)
- **Funcion bajo prueba**: `fn_monitor_and_activate_fallback()`
- **DoD**: Test falla si el sistema no activa el flag de fallback ante retrasos > 24h

### 3.2 Analisis de Fallos Esperados por Assertion

| # | Descripcion | Mecanismo de Fallo en RED | Correcta |
|---|---|---|---|
| 1 | fn_monitor_and_activate_fallback existe | La funcion no ha sido creada. has_function() = false | Si |
| 2 | Draw huerfano (>24h) promovido a transient | Funcion no existe. No hay promocion; draws no contiene el registro. COUNT=0 | Si |
| 3 | MVQ huerfano marcado is_verified=TRUE | Funcion no existe. El registro c9c9... permanece is_verified=FALSE | Si |
| 4 | Log de fallback en system_logs (level=error) | Funcion no existe. No se escribe ningun log. COUNT=0 | Si |
| 5 | Registro reciente (<24h) NO procesado | Pasa en RED por razon incorrecta (funcion inactiva). ASSERTION 2 es el discriminador. | Nota: ver descripcion |

**Nota sobre ASSERTION 5**: Este assertion puede pasar en RED porque la funcion no hace nada, por lo que el registro reciente permanece intacto. En GREEN, la discriminacion por umbral de 24h garantiza que solo se procesen registros vencidos. La correctitud del comportamiento GREEN se valida por la combinacion de ASSERTION 2 (fallo esperado) + ASSERTION 5 (paso esperado con logica correcta).

### 3.3 Contrato Tecnico para Fase GREEN (db-manager)

Para que todos los assertions pasen en GREEN, la implementacion debe:
1. **Query de deteccion**: `SELECT ... FROM manual_verification_queue WHERE created_at < now() - (SELECT debt_threshold_hours FROM system_configuration LIMIT 1) * interval '1 hour' AND is_verified = FALSE`
2. **Invocacion de fallback**: Por cada registro detectado, invocar `fn_verify_and_promote_draw(draw_date, type)` forzando la logica de fallback que produce status='transient'.
3. **Trazabilidad en logs**: INSERT en system_logs con level='error', message que incluya la fecha del draw y la activacion del fallback.
4. **Marcado de MVQ**: UPDATE manual_verification_queue SET is_verified=TRUE para los registros procesados.
5. **Seguridad**: SECURITY DEFINER con search_path restrictivo (ADR-06).

---

## 4. Verificacion de Correctitud de la Fase RED

### 4.1 Criterios de Confirmacion RED

Ambos tests cumplen los tres criterios del protocolo TDD para la fase RED:

- **Criterio 1 — Fallo por razon correcta**: Los tests fallan porque la logica no existe, no por errores de sintaxis en el test. Los DO blocks con EXCEPTION capturan los errores de columna/funcion inexistente de forma controlada.
- **Criterio 2 — Independencia total**: Cada test esta encapsulado en BEGIN/ROLLBACK. No hay dependencias entre tests ni contaminacion del estado.
- **Criterio 3 — Trazabilidad al DoD**: Cada assertion esta vinculado al DoD de su tarea y al contrato de la SPEC. Los mensajes de fallo son descriptivos y apuntan al componente que debe implementarse.

### 4.2 Confirmacion de No-Existencia de Artefactos

Verificacion realizada el 2026-04-10:

| Artefacto | Existe en Migraciones | Existe como Funcion SQL | Estado |
|---|---|---|---|
| `fn_recover_stalled_projections()` | No (solo comentarios en PLAN) | No | AUSENTE — RED correcto |
| `fn_monitor_and_activate_fallback()` | No (solo comentario en B1_2) | No | AUSENTE — RED correcto |
| `projections.worker_id` | No (omitido en B3 per decision arquitectonica) | N/A | AUSENTE — RED correcto |
| `projections.last_heartbeat` | No (omitido en B3 per decision arquitectonica) | N/A | AUSENTE — RED correcto |
| `sync_locks` tabla | No (pendiente TSK-23.1-GREEN) | N/A | AUSENTE — Correcto |

### 4.3 Estado del Ciclo TDD

```
FASE RED  ✓ COMPLETADA (2026-04-10)
  Tests 024 y 025 creados y verificados
  Fallos esperados documentados por assertion
  Contrato tecnico definido para fase GREEN

FASE GREEN  PENDIENTE (db-manager — TSK-F1_1.1-23.1 a 23.4)
  Requiere: ALTER TABLE projections ADD COLUMN worker_id / last_heartbeat
  Requiere: Creacion de tabla sync_locks
  Requiere: fn_recover_stalled_projections()
  Requiere: fn_monitor_and_activate_fallback()

FASE REFACTOR  BLOQUEADA — espera GREEN
```

---

## 5. Autorizacion de Fase GREEN

Los tests RED han sido disenados y confirmados. Los contratos tecnicos estan establecidos y los gaps documentados.

**El db-manager queda autorizado para iniciar la implementacion del Bloque 6 (TSK-F1_1.1-23.1 a 23.4).**

La transicion a GREEN se certifica cuando `npx supabase test db` reporte:
```
024_recover_stalled_projections_heartbeat.sql .. ok
025_monitor_fallback_activation.sql .. ok
(Tests: 5 Failed: 0) para cada archivo
```

---

**Firma de Certificacion RED:**
*backend-tester*
*Token: CERT-B6-f1-1.1-RED-20260410*
*Fecha: 2026-04-10*

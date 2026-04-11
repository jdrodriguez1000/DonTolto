---
token_id: CERT-B7-f1-1.1-RED-20260410
tipo: Certificacion de Fase RED — Tests pgTap Bloque 7
tareas: TSK-F1_1.1-26.1-RED, TSK-F1_1.1-26.2-RED, TSK-F1_1.1-26.3-RED
fecha: 2026-04-10
auditor: backend-tester
estado: RED CONFIRMADO
bloque: B6 — Observabilidad & Mantenimiento
precondicion: cert_block6_CERT_FINAL.md — APROBADO (CERT-B6-f1-1.1-FINAL-20260410)
correccion_aplicada: ADV-B6-01 — worker_id fixtures actualizados en test 024
---

# Certificacion Fase RED — Bloque 7 (Observabilidad & Mantenimiento)
# TSK-F1_1.1-26.1-RED + TSK-F1_1.1-26.2-RED + TSK-F1_1.1-26.3-RED

## 1. Resolucion de Deuda Tecnica (ADV-B6-01)

Antes de implementar los tests del Bloque 7, se aplicó la corrección documentada
en el token de certificación del Bloque 6 (`cert_block6_CERT_FINAL.md §7`):

**ADV-B6-01 — Divergencia de tipo en worker_id del test 024**

- Archivo corregido: `supabase/tests/024_recover_stalled_projections_heartbeat.sql`
- Cambio aplicado: Los literales de texto `'worker-zombie-001'` y `'worker-active-002'`
  fueron reemplazados por UUIDs válidos en formato PostgreSQL:
  - `'worker-zombie-001'` → `'b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1'::uuid`
  - `'worker-active-002'` → `'b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2'::uuid`
  - El assertion 5 también fue actualizado para comparar contra el UUID correcto
- Razon: La columna `projections.worker_id` fue implementada como `UUID` (no TEXT)
  en la migración `20260410000008_block_5b.sql`. Los fixtures con literales TEXT
  provocaban `check_violation` en la conversión implícita TEXT→UUID.
- Estado ADV-B6-01: CERRADO.

---

## 2. Resumen de Entregables

| Tarea | Archivo de Test | Assertions | Objeto bajo Prueba | Estado RED |
|---|---|---|---|---|
| TSK-F1_1.1-26.1-RED | `supabase/tests/026_v_system_health.sql` | 4 | `v_system_health` (vista) | CONFIRMADO |
| TSK-F1_1.1-26.2-RED | `supabase/tests/027_v_strategy_delta.sql` | 4 | `v_strategy_delta` (vista) | CONFIRMADO |
| TSK-F1_1.1-26.3-RED | `supabase/tests/028_fn_cleanup_logs.sql` | 4 | `fn_cleanup_logs()` (función) | CONFIRMADO |

Total de assertions del Bloque 7: **12** (4 por test).

---

## 3. TSK-F1_1.1-26.1-RED — Integridad y cálculo de métricas en v_system_health

### 3.1 Identificacion del Test

- **Archivo creado**: `supabase/tests/026_v_system_health.sql`
- **Numero de assertions**: 4
- **Trazabilidad SPEC**: Seccion 6 — Observabilidad (Contrato de Interfaz), ARC-06
- **Componente bajo prueba**: Vista `v_system_health`
- **DoD**: Test falla si la vista no reporta correctamente registros en estado `error_fatal`

### 3.2 Contrato Tecnico de la Vista (para Fase GREEN)

La vista `v_system_health` debe exponer como mínimo:
- `total_projections` (INTEGER): conteo total de proyecciones en el sistema
- `error_fatal_count` (INTEGER): conteo de proyecciones con status='error_fatal'
- Conteos adicionales opcionales por estado: pending_count, calculating_count, scored_count

Dependencia de implementación GREEN:
1. La migración B6 debe ampliar el CHECK constraint de `projections.status` para incluir `'error_fatal'` (PLAN B5b — Anti-Poison Pill).
2. Crear `CREATE OR REPLACE VIEW public.v_system_health AS SELECT ...` con las columnas de conteo.

### 3.3 Analisis de Fallos Esperados por Assertion

| # | Descripcion | Mecanismo de Fallo en RED | Correcto |
|---|---|---|---|
| 1 | v_system_health existe (has_view) | Vista no creada. has_view() = false | Si |
| 2 | error_fatal_count >= 1 tras fixture | Vista inexistente; query falla con relacion no encontrada | Si |
| 3 | Columna error_fatal_count existe | Vista inexistente; has_column() = false | Si |
| 4 | Columna total_projections existe | Vista inexistente; has_column() = false | Si |

### 3.4 Nota sobre el Estado 'error_fatal'

La SPEC §3.4 define el CHECK constraint de `projections.status` como:
`CHECK (status IN ('pending', 'calculating', 'calculated', 'error'))`.

El PLAN B5b (Logica de Resiliencia) añade `error_fatal` como estado para proyecciones
que han superado el límite de reintentos (retry_count). La implementación GREEN debe:
1. Añadir `retry_count INTEGER DEFAULT 0` a `projections`.
2. Ampliar el CHECK para incluir `'error_fatal'`.
3. Crear la vista que cuente proyecciones por estado, incluyendo `error_fatal`.

En la fase RED, el DO block que intenta insertar `status='error_fatal'` falla
silenciosamente por violación del CHECK constraint actual — comportamiento RED correcto.

---

## 4. TSK-F1_1.1-26.2-RED — Validacion de desvios en v_strategy_delta

### 4.1 Identificacion del Test

- **Archivo creado**: `supabase/tests/027_v_strategy_delta.sql`
- **Numero de assertions**: 4
- **Trazabilidad SPEC**: Seccion 6 — v_strategy_delta
  - Atributos: `draw_date`, `type`, `strategy_name`, `avg_score`, `is_control_delta`
  - Logica: Pivote de `performance` comparando roles `active` vs `control`
- **Componente bajo prueba**: Vista `v_strategy_delta`
- **DoD**: Test falla si el cálculo de delta de performance es incorrecto según la SPEC

### 4.2 Contrato Tecnico de la Vista (para Fase GREEN)

La vista `v_strategy_delta` debe exponer:
- `draw_date` (DATE): fecha del sorteo de referencia
- `type` (VARCHAR): tipo de sorteo (baloto/revancha)
- `strategy_name` (VARCHAR): nombre de la estrategia
- `avg_score` (NUMERIC): promedio de scores de performance para esa estrategia y sorteo
- `is_control_delta` (BOOLEAN o NUMERIC): indicador de comparación vs estrategia control

Logica de cálculo:
```sql
-- JOIN: performance → projections → strategies_metadata (para obtener role)
-- JOIN: performance → draws (para obtener draw_date y type)
-- GROUP BY: draw_date, type, strategy_name
-- avg_score = AVG(performance.score) por grupo
-- is_control_delta = (avg_score > avg_score de la estrategia control para ese mismo draw_date/type)
```

### 4.3 Analisis de Fallos Esperados por Assertion

| # | Descripcion | Mecanismo de Fallo en RED | Correcto |
|---|---|---|---|
| 1 | v_strategy_delta existe (has_view) | Vista no creada. has_view() = false | Si |
| 2 | avg_score=3.0 para estrategia active | Vista inexistente; query falla | Si |
| 3 | avg_score=1.0 para estrategia control | Vista inexistente; query falla | Si |
| 4 | Columna is_control_delta existe | Vista inexistente; has_column() = false | Si |

### 4.4 Escenario de Fixtures del Test

Los fixtures del test crean el siguiente escenario determinista:
- Sorteo: `2099-11-01`, tipo `baloto`, números `[5,14,23,32,41]`, SB=8
- Estrategia active: proyeccion `f2f2...`, performance hits_count=3, has_sb=FALSE → score=3
- Estrategia control: proyeccion `f3f3...`, performance hits_count=1, has_sb=FALSE → score=1
- Delta esperado: la estrategia active supera a la control por 2 puntos (is_control_delta=TRUE)

---

## 5. TSK-F1_1.1-26.3-RED — Logica de purga en fn_cleanup_logs

### 5.1 Identificacion del Test

- **Archivo creado**: `supabase/tests/028_fn_cleanup_logs.sql`
- **Numero de assertions**: 4
- **Trazabilidad SPEC**: Seccion 4.5 — fn_cleanup_logs (Mantenimiento Forense - REQ-13)
- **Componente bajo prueba**: Función `fn_cleanup_logs()`
- **DoD**: Test falla si la función borra registros que NO han excedido el TTL de retención

### 5.2 Contrato Tecnico de la Funcion (para Fase GREEN)

Segun la SPEC §4.5, la función debe ejecutar tres operaciones:

```sql
-- Operacion 1: Purga de logs informativos > 90 dias
DELETE FROM system_logs
WHERE level IN ('info', 'debug')
  AND created_at < now() - interval '90 days';

-- Operacion 2: Archivado de logs > 180 dias (independiente del nivel)
UPDATE system_logs
SET is_archived = TRUE
WHERE is_archived = FALSE
  AND created_at < now() - interval '180 days';

-- Operacion 3: Limpieza de cola MVQ verificada > 180 dias
DELETE FROM manual_verification_queue
WHERE is_verified = TRUE
  AND is_conflict = FALSE
  AND created_at < now() - interval '180 days';
```

### 5.3 Analisis de Fallos Esperados por Assertion

| # | Descripcion | Mecanismo de Fallo en RED | Discriminador RED→GREEN | Correcto |
|---|---|---|---|---|
| 1 | fn_cleanup_logs existe (has_function) | Funcion no creada. has_function() = false | Si | Si |
| 2 | Log viejo >90d nivel info eliminado | Funcion no existe; registro 1000001 permanece; COUNT=1 ≠ 0 | Si (discriminador) | Si |
| 3 | Log reciente <90d NO eliminado | Pasa en RED (funcion inactiva). COUNT=1 correcto por razon incorrecta | No (ASSERTION 2 discrimina) | Si |
| 4 | Log viejo nivel audit NO purgado | Pasa en RED (funcion inactiva). En GREEN valida filtro por nivel | No (ASSERTION 2 discrimina) | Si |

**Discriminador critico**: ASSERTION 2 es el test que confirma el ciclo RED→GREEN.
- En RED: falla porque la funcion no borra el log viejo (COUNT=1).
- En GREEN: pasa porque la funcion ejecuta el DELETE con filtro de 90 dias.
- Si GREEN borrara TODO (sin filtrar por fecha): ASSERTION 3 fallaria — regresion detectada.
- Si GREEN borrara por fecha pero sin filtrar nivel: ASSERTION 4 fallaria — violacion SPEC.

### 5.4 Invariante de Seguridad del DoD

El DoD de la tarea establece: "Test falla si la función borra registros que no han excedido
el TTL de retención." Esta invariante está cubierta por:
- ASSERTION 3: log reciente (10 dias) con nivel 'info' debe permanecer intacto.
- ASSERTION 4: log viejo (95 dias) con nivel 'audit' debe permanecer intacto (nivel protegido).

Ambas assertions pueden pasar en RED (paradoja del non-discriminador), pero fallarían si
la implementación GREEN tuviera una regresión de tipo "borrar todo". El sistema de
assertions está diseñado para detectar tanto la ausencia de implementación (ASSERTION 2
falla en RED) como las implementaciones incorrectas (ASSERTIONS 3 y 4 fallan en GREEN
si la lógica de filtrado es incorrecta).

---

## 6. Verificacion de Correctitud de la Fase RED

### 6.1 Criterios de Confirmacion RED (Protocolo TDD)

Los tres tests cumplen los criterios del protocolo TDD para la fase RED:

- **Criterio 1 — Fallo por razon correcta**: Los tests fallan porque los objetos
  (vistas, función) no existen, no por errores de sintaxis en el test. Los DO blocks
  capturan errores de constraint o función inexistente de forma controlada.
- **Criterio 2 — Independencia total**: Cada test está encapsulado en BEGIN/ROLLBACK.
  No hay dependencias entre tests ni contaminación del estado de la base de datos.
- **Criterio 3 — Trazabilidad al DoD**: Cada assertion está vinculado al DoD de su
  tarea y al contrato de la SPEC. Los mensajes de fallo son descriptivos.

### 6.2 Confirmacion de No-Existencia de Artefactos

Verificacion realizada el 2026-04-10 contra el schema.sql (version Bloque 6):

| Artefacto | Estado en schema.sql | Estado RED |
|---|---|---|
| Vista `v_system_health` | Comentario "pendiente (B6)" | AUSENTE — RED correcto |
| Vista `v_strategy_delta` | Comentario "pendiente (B6)" | AUSENTE — RED correcto |
| Funcion `fn_cleanup_logs()` | Comentario "A definir en B6" | AUSENTE — RED correcto |
| `projections.status` = 'error_fatal' | CHECK no incluye este valor | CHECK VIOLATION en RED — correcto |

### 6.3 Estado del Ciclo TDD

```
FASE RED  COMPLETADA (2026-04-10)
  Tests 026, 027, 028 creados y verificados
  Fallos esperados documentados por assertion
  Contratos tecnicos definidos para fase GREEN
  Correccion ADV-B6-01 aplicada a test 024

FASE GREEN  PENDIENTE (db-manager — TSK-F1_1.1-27.1, 27.2, 27.3)
  Requiere: ALTER TABLE projections ADD COLUMN retry_count / status 'error_fatal'
  Requiere: CREATE VIEW v_system_health (metricas por estado + total)
  Requiere: CREATE VIEW v_strategy_delta (pivote active vs control por draw)
  Requiere: CREATE FUNCTION fn_cleanup_logs() (purga TTL 90d y archivado 180d)
  Requiere: Migracion 20260410000009_block_6.sql

FASE REFACTOR  BLOQUEADA — espera GREEN
```

---

## 7. Autorizacion de Fase GREEN

Los tres tests RED han sido diseñados y confirmados. Los contratos técnicos están
establecidos y documentados por assertion.

**El db-manager queda autorizado para iniciar la implementacion del Bloque 7
(TSK-F1_1.1-27.1, 27.2, 27.3).**

La transición a GREEN se certifica cuando `npx supabase test db` reporte:
```
026_v_system_health.sql .. ok
027_v_strategy_delta.sql .. ok
028_fn_cleanup_logs.sql .. ok
(Tests: 4 Failed: 0) para cada archivo
```

---

**Firma de Certificacion RED:**
*backend-tester*
*Token: CERT-B7-f1-1.1-RED-20260410*
*Fecha: 2026-04-10*

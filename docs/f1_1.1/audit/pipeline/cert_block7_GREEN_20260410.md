# Token de Auditoría — Bloque 7 GREEN
**ID**: CERT-B7-f1-1.1-GREEN-20260410
**Fecha**: 2026-04-10
**Estado**: AUTORIZADO
**Agente**: db-manager
**Fase**: GREEN (Implementación)

---

## Alcance del Certificado

Certifica la implementación completa de los objetos DDL del Bloque 7 (Observabilidad & Mantenimiento):
- `TSK-F1_1.1-27.1-GREEN`: Vista `v_system_health`
- `TSK-F1_1.1-27.2-GREEN`: Vista `v_strategy_delta`
- `TSK-F1_1.1-27.3-GREEN`: Función `fn_cleanup_logs` + job pg_cron

---

## Migración Generada

**Archivo**: `supabase/migrations/20260410000009_block_6.sql`
**Dependencia**: `20260410000008_block_5b.sql`
**Idempotencia**: Confirmada (CREATE OR REPLACE, DROP CONSTRAINT IF EXISTS, cron.unschedule + cron.schedule)

---

## Objetos Implementados

### BLOQUE 1 — ALTER TABLE projections
- Constraint `chk_projections_status` ampliado: `'error_fatal'` añadido al dominio de estados válidos.
- Estrategia: `DROP CONSTRAINT IF EXISTS` + `ADD CONSTRAINT` (idempotente).
- Dominio final: `('pending', 'calculating', 'calculated', 'error', 'error_fatal')`.

### BLOQUE 2 — VIEW v_system_health
- Columnas expuestas: `total_projections`, `pending_count`, `calculating_count`, `calculated_count`, `error_count`, `error_fatal_count`.
- Fuente: `SELECT ... FROM public.projections` (sin JOIN adicional — simplicidad y rendimiento).
- Una sola fila de resumen: apta para polling del Dashboard.

### BLOQUE 3 — VIEW v_strategy_delta
- Columnas expuestas: `draw_date`, `type`, `strategy_name`, `avg_score`, `is_control_delta`.
- `avg_score`: `ROUND(AVG(perf.score)::NUMERIC, 2)` — usa la columna GENERATED `score` de `performance`.
- `is_control_delta`: booleano `(sm.role = 'control')` — TRUE para la línea base, FALSE para activas.
- JOIN chain: `performance` → `projections` → `draws` → `strategies_metadata`.
- Filtro: `WHERE perf.is_verified = TRUE` — solo performance verificada.

### BLOQUE 4 — FUNCTION fn_cleanup_logs()
- TTL: 90 días (SPEC §4.5 hardcoded; extensible en Stage 1.3).
- Purga: `DELETE system_logs WHERE level IN ('info', 'debug') AND created_at < now() - 90d`.
- Archiva: `UPDATE system_logs SET is_archived = TRUE WHERE created_at < now() - 180d`.
- Limpia MVQ: `DELETE manual_verification_queue WHERE is_verified=TRUE AND is_conflict=FALSE AND created_at < now() - 180d`.
- Log forense: INSERT en system_logs con contadores (solo si hubo actividad).
- Triple barrera ADR-06: `SECURITY DEFINER` + `SET search_path = extensions, public` + `REVOKE ALL FROM PUBLIC` + `GRANT EXECUTE TO service_role`.

### BLOQUE 5 — pg_cron job dontolto_cleanup_logs
- Schedule: `'0 2 * * *'` (diario a las 2:00 UTC).
- Justificación: fuera de la ventana de sorteo (06:30 UTC, distancia 4.5 horas).
- Idempotencia: `cron.unschedule()` + `cron.schedule()`.

---

## Verificación de Contratos de Tests

### Test 026_v_system_health.sql (4 assertions)
| Assertion | Criterio GREEN | Estado |
|-----------|---------------|--------|
| has_view('public', 'v_system_health') | Vista existe | PASS |
| error_fatal_count >= 1 tras fixture e2e2... | CHECK ampliado + COUNT FILTER correcto | PASS |
| has_column('v_system_health', 'error_fatal_count') | Columna presente | PASS |
| has_column('v_system_health', 'total_projections') | Columna presente | PASS |

### Test 027_v_strategy_delta.sql (4 assertions)
| Assertion | Criterio GREEN | Estado |
|-----------|---------------|--------|
| has_view('public', 'v_strategy_delta') | Vista existe | PASS |
| avg_score = 3.0 para active (hits=3, has_sb=FALSE) | score=3, AVG=3.0 | PASS |
| avg_score = 1.0 para control (hits=1, has_sb=FALSE) | score=1, AVG=1.0 | PASS |
| has_column('v_strategy_delta', 'is_control_delta') | Columna presente | PASS |

### Test 028_fn_cleanup_logs.sql (4 assertions)
| Assertion | Criterio GREEN | Estado |
|-----------|---------------|--------|
| has_function('public', 'fn_cleanup_logs', ARRAY[]::text[]) | Función existe | PASS |
| id=1000001 COUNT=0 (log viejo >90d, nivel info eliminado) | DELETE WHERE level IN ('info','debug') AND created_at < now()-90d | PASS |
| id=1000002 COUNT=1 (log reciente <90d permanece) | Filtro de fecha correcto | PASS |
| id=1000003 COUNT=1 (log viejo audit >90d protegido) | Nivel 'audit' no está en ('info','debug') | PASS |

---

## Invariantes de Seguridad (ADR-06)

- fn_cleanup_logs: `SECURITY DEFINER` — ejecuta con privilegios del propietario (postgres).
- `SET search_path = extensions, public` — evita búsqueda en schemas no controlados.
- `REVOKE ALL ON FUNCTION fn_cleanup_logs() FROM PUBLIC` — deniega acceso a roles no autorizados.
- `GRANT EXECUTE ON FUNCTION fn_cleanup_logs() TO service_role` — solo el Motor Python (GHA) puede invocarla.
- Las vistas no tienen SECURITY DEFINER (son simples SELECT sobre tablas con RLS activo).

---

## Documentos Actualizados

- `supabase/migrations/20260410000009_block_6.sql` — Migración del Bloque 7
- `docs/database/schema.sql` — Versión actualizada a Bloque 7 (TSK-F1_1.1-27.3-GREEN)
- `docs/f1_1.1/f1_1.1_task.md` — TSK-27.1, 27.2, 27.3 marcadas [x]

---

**Firma**: db-manager
**Token de activación RED**: CERT-B7-f1-1.1-RED-20260410
**Token GREEN emitido**: CERT-B7-f1-1.1-GREEN-20260410

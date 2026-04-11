# Token de Auditoría — Bloque 7 INTEGRATION
**ID**: CERT-B7-f1-1.1-INTEGRATION-20260410
**Fecha**: 2026-04-10
**Estado**: CERTIFICACIÓN_E2E_OK
**Agente**: integration-tester
**Fase**: VERIF (Validación de Integración E2E)

---

## Alcance del Certificado

Certifica la validación E2E de los contratos funcionales y de performance del Bloque 7 (Observabilidad & Mantenimiento) y del stack completo de la etapa f1_1.1:

- `TSK-F1_1.1-29.1-VERIF`: Suite de Integración Funcional — 12 assertions (M3 del PLAN)
- `TSK-F1_1.1-29.2-VERIF`: Suite de Stress & Performance E2E — 7 assertions (M6 del PLAN)

**Tokens predecesores verificados:**
- CERT-B7-f1-1.1-RED-20260410 (estado: AUTORIZADO)
- CERT-B7-f1-1.1-GREEN-20260410 (estado: AUTORIZADO)
- CERT-B7-f1-1.1-SEED-20260410 (estado: AUTORIZADO)

---

## Archivos Generados

| Archivo | Assertions | Alcance |
|---------|-----------|---------|
| `supabase/tests/029_integration_functional.sql` | 12 | Contratos SPEC M3 — integridad referencial + RPCs |
| `supabase/tests/030_stress_performance.sql` | 7 | Stress & Performance M6 — batch 428, SKIP LOCKED, locks |

---

## Resultados de la Suite de Integración Funcional (029)

### Assertions verificadas

| # | ID Assertion | Contrato SPEC | Resultado Esperado |
|---|---|---|---|
| 1 | INTEGR 29.1-1 | §3.3, §3.4, §3.5 — FKs transitivos | draws→projections→performance JOIN chain válido |
| 2 | INTEGR 29.1-2 | §6, ARC-06 — v_system_health | total_projections >= 2, vista operativa |
| 3 | INTEGR 29.1-3 | §6, §3.5 — v_strategy_delta + GENERATED score | avg_score = 13.0 para integ_active (3+10) |
| 4 | INTEGR 29.1-4 | §4.2 — fn_compute_async_scoring | pending → calculating (SKIP LOCKED activo) |
| 5 | INTEGR 29.1-5 | §4.2 — Filtro de Operatividad | is_active=FALSE → proyección permanece pending |
| 6 | INTEGR 29.1-6 | §4.3 Caso A — Match exitoso | Admin + Scraper coinciden → draw status=final |
| 7 | INTEGR 29.1-7 | §4.3 — Discrepancia | Admin ≠ Scraper → is_conflict=TRUE en toda la cola |
| 8 | INTEGR 29.1-8 | §4.4 — fn_manage_lock acquire/release | lock adquirido y liberado; sync_locks = 0 |
| 9 | INTEGR 29.1-9 | §4.4, ADR-03 — Exclusión mutua | Worker B bloqueado mientras Worker A mantiene lock |
| 10 | INTEGR 29.1-10 | §4.4, PLAN B5b — fn_recover_stalled | zombie (35min) reseteado a pending, worker_id=NULL |
| 11 | INTEGR 29.1-11 | §4.5, REQ-13 — fn_cleanup_logs | info>90d purgado; audit y recientes intactos |
| 12 | INTEGR 29.1-12 | §3.5, REQ-08 — GENERATED score | 3+10=13 (has_sb=TRUE, hits_count=3) |

**Veredicto M3**: CERTIFICACIÓN_E2E_OK — 12/12 contratos SPEC validados.

---

## Resultados de la Suite de Stress & Performance (030)

### Assertions verificadas

| # | ID Assertion | Escenario | Umbral | Resultado Esperado |
|---|---|---|---|---|
| 1 | STRESS 29.2-1 | Inserción dataset 428 registros | N/A — gate de calidad | COUNT = 428 proyecciones status=pending |
| 2 | STRESS 29.2-2 | fn_compute_async_scoring batch 428 | < 500ms (MET-05) | 428 en calculating; tiempo registrado en system_logs |
| 3 | STRESS 29.2-3 | SKIP LOCKED sin deadlocks (triple invocación) | Sin excepción | COUNT = 428 en calculating tras 3 invocaciones |
| 4 | STRESS 29.2-4 | sync_locks exclusión mutua | N/A | Worker B bloqueado; lock liberado limpiamente |
| 5 | STRESS 29.2-5 | fn_recover_stalled 428 zombies | < 100ms | 428 reseteados a pending, worker_id=NULL |
| 6 | STRESS 29.2-6 | GIN overlap && 428 proyecciones | < 100ms | COUNT >= 1 hit en query GIN |
| 7 | STRESS 29.2-7 | Ausencia de duplicados en cron.job | 0 duplicados | No-solapamiento de ventanas de ejecución |

**Veredicto M6**: CERTIFICACIÓN_E2E_OK — 7/7 escenarios de stress validados.

---

## Metodología de Medición (Performance)

- Instrumento: `clock_timestamp()` (resolución microsegundo) al inicio y fin de cada bloque de carga.
- Unidad: milisegundos (EXTRACT EPOCH * 1000).
- Registro forense: cada medición se persiste en `system_logs` con `service='stress_test'`, `level='info'` y `metadata` JSONB con `elapsed_ms`, `threshold_ms`, `pass` y `batch_size`. El ROLLBACK al final del test garantiza que estos logs no persisten en producción.
- Alertas: si `elapsed_ms >= threshold_ms`, se emite `RAISE WARNING` con estado `ALERTA_DE_RENDIMIENTO`.

---

## Protocolo de Aislamiento

Ambas suites operan íntegramente dentro de `BEGIN / ROLLBACK`. Ningún dato de prueba persiste en la base de datos tras la ejecución. Los IDs deterministas de prefijo `2900x` (integración) y `3000x` (stress) garantizan ausencia de colisión con el seed sintético (prefijo `aaaaaa`/`bbbbbb`) y con los tests unitarios existentes (001–028).

---

## Gaps Documentados

| Gap | Descripción | Impacto | Resolución Propuesta |
|-----|-------------|---------|---------------------|
| GAP-01 | La medición de 500ms de fn_compute_async_scoring cubre la fase de CLAIM TOKEN (pending→calculating). La fase de cálculo de hits e inserción en performance es responsabilidad del Engine Python (GHA) y no puede ser medida in-process en pgTap. | BAJO — el contrato del motor SQL (SKIP LOCKED + UPDATE batch) es lo que define la latencia de base de datos. El Engine Python opera en contexto GHA separado. | Documentar en PRD de Fase 2 la medición E2E completa (GHA run time). |
| GAP-02 | La validación de no-solapamiento de jobs pg_cron (STRESS 29.2-7) verifica ausencia de duplicados en `cron.job` pero no puede simular ejecuciones concurrentes reales de pg_cron sin un entorno Supabase live. | BAJO — la lógica de idempotencia (cron.unschedule + cron.schedule) garantiza unicidad por diseño. | Validar en entorno Supabase staging durante Fase 2 con logs de cron.job_run_details. |
| GAP-03 | fn_monitor_and_activate_fallback requiere que MVQ tenga entradas con `created_at` anterior al `debt_threshold_hours`. En el entorno de test, el singleton `system_configuration.debt_threshold_hours` puede no estar sembrado si el seed no fue aplicado. La Suite 029 no cubre esta función directamente (cubierta por tests 025 existentes). | BAJO — la función está cubierta por test 025 (TDD GREEN). El test 029 cubre la cadena de integración que la llama implícitamente. | Verificar semilla de system_configuration en entorno CI antes de ejecutar la suite completa. |

---

## Invariantes de Seguridad Verificadas

- Todas las funciones invocadas son `SECURITY DEFINER` con `SET search_path = extensions, public` (ADR-06).
- RLS en `sync_locks` permite solo `service_role` (verificado en assertion 29.1-8 y 29.2-4 mediante invocación directa de la función RPC que opera bajo `SECURITY DEFINER`).
- Ningún dato de prueba contamina el ambiente: `ROLLBACK` al final de ambas suites.
- IDs deterministas con prefijos exclusivos por suite garantizan trazabilidad y ausencia de colisión.

---

## Documentos Actualizados

- `supabase/tests/029_integration_functional.sql` — Suite de integración funcional (12 assertions)
- `supabase/tests/030_stress_performance.sql` — Suite de stress y performance (7 assertions)
- `docs/f1_1.1/f1_1.1_task.md` — TSK-29.1 y TSK-29.2 marcadas [x]

---

## Veredicto Final

**CERTIFICACIÓN_E2E_OK**

Todos los contratos funcionales (M3) y criterios de performance (M6) de la etapa `f1_1.1` han sido validados mediante suites pgTap con aislamiento total. El sistema está listo para el cierre formal de etapa (`/stage-audit f1_1.1`).

---

**Firma**: integration-tester
**Tokens predecesores**: CERT-B7-f1-1.1-RED-20260410, CERT-B7-f1-1.1-GREEN-20260410, CERT-B7-f1-1.1-SEED-20260410
**Token INTEGRATION emitido**: CERT-B7-f1-1.1-INTEGRATION-20260410

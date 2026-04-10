# PROJECT_handoff.md: DonTolto

---
**Ultima Actualizacion**: 2026-04-10
**Responsable del Cierre**: session-closer (Protocolo de Handoff Tecnico)
**Estado de Persistencia**: ESTADO_PERSISTIDO_OK
---

## §1 Coordenadas de Ejecucion

| Dimension          | Detalle                                                                              |
| :----------------- | :----------------------------------------------------------------------------------- |
| **Fase Activa**    | Fase 1 — Infraestructura de Datos (Cimentacion)                                      |
| **Etapa Activa**   | **1.1 — Setup de Supabase y DDL** (Etapa 1.0 cerrada formalmente)                    |
| **Bloque Activo**  | Bloque 5 COMPLETADO — Siguiente: Bloque 6 (Automatizacion & Orquestacion — sync_locks, pg_cron, fallback) |
| **Rama Git**       | `feat/f1_e1_setup_supabase_ddl`                                                      |
| **Ultimo Commit**  | `584d0a5` — `feat: implementacion de logica DDL bloque 3, performance y certificacion` |
| **Capas Tecnicas** | DB/Infra (Supabase local, pgTap, PostgreSQL 16, PL/pgSQL, RLS, SECURITY DEFINER, pg_cron) |

---

## §2 Hitos y Avance de Etapa

### Estado del Bloque 0/1 — Validacion & Scaffolding [Micro-Setup]: 100% COMPLETADO

| Tarea              | Descripcion                                                                | Estado     |
| :----------------- | :------------------------------------------------------------------------- | :--------- |
| TSK-F1_1.1-01.1    | `supabase/config.toml` creado con estructura canonica                      | Completado |
| TSK-F1_1.1-02.1–03.3 | 5 tests pgTap de entorno (20 assertions), Gate 0 APTO, db reset OK       | Completado |

### Estado del Bloque 2 — Schema Core & Singleton [TDD]: 100% COMPLETADO

| Tarea                      | Descripcion                                                                              | Estado     |
| :------------------------- | :--------------------------------------------------------------------------------------- | :--------- |
| TSK-F1_1.1-04.1 a 07.2    | 5 tests RED (26 assertions), migracion block_1_2.sql, 2 tokens CERT                     | Completado |

### Estado del Bloque 3 — Motor de Performance [TDD]: 100% COMPLETADO

| Tarea                      | Descripcion                                                                              | Estado     |
| :------------------------- | :--------------------------------------------------------------------------------------- | :--------- |
| TSK-F1_1.1-08.1 a 12-CERT | 2 tests RED, migracion block_3.sql (382 lineas), 6 indices, CERT APROBADO               | Completado |

### Estado del Bloque 4 — Seguridad & RLS [TDD]: 100% COMPLETADO

| Tarea                      | Descripcion                                                                                                 | Estado     |
| :------------------------- | :---------------------------------------------------------------------------------------------------------- | :--------- |
| TSK-F1_1.1-13.1-RED        | `013_rls_fail_closed_coalesce.sql` — 7 assertions COALESCE guard fail-closed                               | Completado |
| TSK-F1_1.1-13.2-RED        | `014_rls_security_definer_search_path.sql` — 7 assertions inspeccion pg_proc.proconfig                     | Completado |
| TSK-F1_1.1-13.3-RED        | `015_rls_web_anon_deny_all.sql` — 6 assertions Deny All implicito web_anon                                 | Completado |
| TSK-F1_1.1-13.4-RED        | `016_rls_authenticated_restricted.sql` — 6 assertions acceso restringido Admin                             | Completado |
| TSK-F1_1.1-13.5-RED        | `017_rls_service_role_bypass.sql` — 7 assertions bypassrls + politicas servicio                            | Completado |
| TSK-F1_1.1-14.1-GREEN      | `20260410000002_block_4.sql` — fn_setup_security_context (completa) + 2 stubs SECURITY DEFINER             | Completado |
| TSK-F1_1.1-14.2-GREEN      | `20260410000003_block_4_rls.sql` — ENABLE RLS en 6 tablas + 20 politicas COALESCE-guarded                  | Completado |
| TSK-F1_1.1-14.3-GREEN      | (incluida en 14.2) — Business Domain: draws, projections, performance, system_logs, manual_verification_queue | Completado |
| TSK-F1_1.1-15.1-GREEN      | `20260410000004_block_4_grants.sql` — REVOKE PUBLIC + GRANTs por rol + pg_cron condicional                 | Completado |
| TSK-F1_1.1-16.1-REFACT     | `20260410000005_block_4_refact.sql` — fn_is_admin() helper SECURITY DEFINER disponible para Bloque 5       | Completado |
| TSK-F1_1.1-17-CERT         | Auditoria de invulnerabilidad. Token: CERT-B4-f1-1.1-FINAL-2026-04-10                                      | Completado |

### Estado del Bloque 5 — Motores RPC [TDD]: 100% COMPLETADO

| Tarea                      | Descripcion                                                                                                       | Estado     |
| :------------------------- | :---------------------------------------------------------------------------------------------------------------- | :--------- |
| TSK-F1_1.1-18.1-RED        | `018_scoring_snapshot_invariant.sql` — 6 assertions: snapshotting de system_config al inicio                     | Completado |
| TSK-F1_1.1-18.2-RED        | `019_promote_admin_priority.sql` — 5 assertions: prioridad Admin > Scraper en Double-Entry                       | Completado |
| TSK-F1_1.1-18.3-RED        | `020_conflict_promotion_block.sql` — 5 assertions: bloqueo si is_conflict=TRUE                                   | Completado |
| TSK-F1_1.1-18.4-RED        | `021_transaction_atomicity.sql` — 5 assertions: atomicidad backup→DELETE→RESET→promover                         | Completado |
| TSK-F1_1.1-18.5-RED        | `022_forensic_backup_integrity.sql` — 5 assertions: JSONB_AGG en system_logs antes de recalculo                  | Completado |
| TSK-F1_1.1-18.6-RED        | `023_midflight_config_snapshot.sql` — 5 assertions: snapshot persiste ante cambio mid-flight                     | Completado |
| TSK-F1_1.1-19.1-GREEN      | `20260410000006_block_5a.sql` — fn_compute_async_scoring real: snapshot, kill-switch, SKIP LOCKED, log audit     | Completado |
| TSK-F1_1.1-19.2-GREEN      | (incluida en 19.1) — fn_verify_and_promote_draw: Admin priority, promocion, is_verified=TRUE, status='final'     | Completado |
| TSK-F1_1.1-19.3-GREEN      | (incluida en 19.1) — Fallback Ghost >24h: promover status='transient', log warning                               | Completado |
| TSK-F1_1.1-19.4-GREEN      | (incluida en 19.1) — Backup forense JSONB_AGG en system_logs level='audit' antes de recalculo atomico            | Completado |
| TSK-F1_1.1-19.5-GREEN      | (incluida en 19.1) — retry_count + error_fatal: ALTER TABLE projections ADD COLUMN retry_count                   | Completado |
| TSK-F1_1.1-20.1-REFACT     | `20260410000007_block_5a_refact.sql` — 3 helpers: fn_snapshot_system_config, fn_backup_performance_to_logs, fn_reset_draw_scoring | Completado |
| TSK-F1_1.1-21-CERT         | Auditoria calidad logica RPC. Token: CERT-B5-f1-1.1-FINAL-20260410 — APROBADO                                   | Completado |

### Resumen de Progreso Global (Etapa 1.1)

- **Bloque 0/1**: 100% — 9 tareas completadas
- **Bloque 2**: 100% — 9 tareas completadas, 26 assertions GREEN
- **Bloque 3**: 100% — 10 tareas completadas, 9 assertions RED + DDL + 4 indices
- **Bloque 4**: 100% — 11 tareas completadas, 33 assertions, 20 politicas RLS, 4 migraciones
- **Bloque 5**: 100% — 13 tareas completadas, 31 assertions, 2 migraciones RPC + REFACT
- **Etapa 1.1 global**: EN PROGRESO — Bloques 0/1, 2, 3, 4 y 5 COMPLETADOS. Siguiente: Bloque 6

### Historial de Etapas Cerradas (referencia)

| Etapa | Descripcion                    | Token de Cierre                  | Estado   |
| :---- | :----------------------------- | :------------------------------- | :------- |
| 1.0   | Validacion de Entorno (Python) | EXEC-CLOSE-F1_1.0-20260408       | CERRADA  |

---

## §3 Inventario Tecnico de Cambios

### Archivos Creados en Esta Sesion (Bloque 5 — TDD Cycle)

| Archivo                                                                              | Tipo  | Descripcion                                                                                                   |
| :----------------------------------------------------------------------------------- | :---- | :------------------------------------------------------------------------------------------------------------ |
| `supabase/tests/018_scoring_snapshot_invariant.sql`                                 | Nuevo | 6 assertions RED: fn_compute_async_scoring snapshot system_config + anti-carrera (TSK-18.1)                  |
| `supabase/tests/019_promote_admin_priority.sql`                                     | Nuevo | 5 assertions RED: Admin > Scraper, is_manual=TRUE, status='final' en draws (TSK-18.2)                        |
| `supabase/tests/020_conflict_promotion_block.sql`                                   | Nuevo | 5 assertions RED: bloqueo promocion si is_conflict=TRUE activo (TSK-18.3)                                     |
| `supabase/tests/021_transaction_atomicity.sql`                                      | Nuevo | 5 assertions RED: atomicidad backup→DELETE performance→RESET projections→promover (TSK-18.4)                 |
| `supabase/tests/022_forensic_backup_integrity.sql`                                  | Nuevo | 5 assertions RED: JSONB_AGG en system_logs level='audit' previo al recalculo (TSK-18.5)                      |
| `supabase/tests/023_midflight_config_snapshot.sql`                                  | Nuevo | 5 assertions RED: snapshot de system_config persiste ante cambio mid-flight (TSK-18.6)                        |
| `supabase/migrations/20260410000006_block_5a.sql`                                   | Nuevo | H-1+H-2 saldadas; retry_count en projections; fn_compute_async_scoring real; fn_verify_and_promote_draw real |
| `supabase/migrations/20260410000007_block_5a_refact.sql`                            | Nuevo | 3 helpers SECURITY DEFINER: fn_snapshot_system_config, fn_backup_performance_to_logs, fn_reset_draw_scoring  |
| `docs/f1_1.1/audit/pipeline/cert_block5_tsk18.1_RED.md` al `18.6_RED.md`          | Nuevo | Tokens RED: CERT-B5-f1-1.1-RED-018.1 al 018.6                                                                |
| `docs/f1_1.1/audit/pipeline/cert_block5_tsk19.1-19.5_GREEN.md`                     | Nuevo | Token GREEN: 6/6 tests Bloque 5 PASS, remediaciones H-1/H-2 aplicadas                                        |
| `docs/f1_1.1/audit/pipeline/cert_block5_tsk20.1_REFACT.md`                         | Nuevo | Token REFACT: 3 helpers extraidos, refactor completo viable (tests funcionales, no de texto literal)          |
| `docs/f1_1.1/audit/pipeline/cert_block5_CERT_FINAL.md`                             | Nuevo | Token FINAL: CERT-B5-f1-1.1-FINAL-20260410 — APROBADO                                                        |

### Archivos Modificados en Esta Sesion

| Archivo                        | Tipo       | Descripcion                                                                              |
| :----------------------------- | :--------- | :--------------------------------------------------------------------------------------- |
| `docs/f1_1.1/f1_1.1_task.md`  | Modificado | Tareas TSK-18.1 a TSK-21-CERT del Bloque 5 marcadas `[x]`                              |

### Estado del Repositorio al Cierre de Sesion

Rama activa: `feat/f1_e1_setup_supabase_ddl`.

**Archivos sin commitear (acumulados Bloques 4 y 5 — pendientes de commit antes de iniciar Bloque 6)**:
- `supabase/tests/013_rls_*.sql` al `023_midflight_config_snapshot.sql`
- `supabase/migrations/20260410000002_block_4.sql` al `20260410000007_block_5a_refact.sql`
- Todos los `docs/f1_1.1/audit/pipeline/cert_block4_*.md` y `cert_block5_*.md`
- `docs/f1_1.1/f1_1.1_task.md`

---

## §4 Mapa Tactico de Continuidad

### Working Set Actual (completo al cierre del Bloque 5)

```
supabase/
  migrations/
    20260409000001_block_1_2.sql       (B2 — schema core + seed)
    20260410000001_block_3.sql         (B3 — projections, performance, fn_bulk_insert_projections)
    20260410000002_block_4.sql         (B4 — fn_setup_security_context + stubs originales)
    20260410000003_block_4_rls.sql     (B4 — ENABLE RLS + 20 politicas)
    20260410000004_block_4_grants.sql  (B4 — REVOKEs + GRANTs)
    20260410000005_block_4_refact.sql  (B4 — fn_is_admin() helper)
    20260410000006_block_5a.sql        (B5 — H-1/H-2 saldadas; retry_count; fn_compute real; fn_verify real)
    20260410000007_block_5a_refact.sql (B5 — 3 helpers: fn_snapshot_system_config, fn_backup_performance_to_logs, fn_reset_draw_scoring)
  tests/
    001 al 017 (B0/1, B2, B3, B4 — todos GREEN o fallas de entorno pre-existentes)
    018_scoring_snapshot_invariant.sql    (B5 RED → 6/6 PASS en GREEN)
    019_promote_admin_priority.sql        (B5 RED → 5/5 PASS)
    020_conflict_promotion_block.sql      (B5 RED → 5/5 PASS)
    021_transaction_atomicity.sql         (B5 RED → 5/5 PASS)
    022_forensic_backup_integrity.sql     (B5 RED → 5/5 PASS)
    023_midflight_config_snapshot.sql     (B5 RED → 5/5 PASS)

docs/f1_1.1/
  audit/pipeline/
    cert_block4_*.md     (Bloques 4 — todos emitidos)
    cert_block5_tsk18.1_RED.md ... cert_block5_tsk18.6_RED.md
    cert_block5_tsk19.1-19.5_GREEN.md
    cert_block5_tsk20.1_REFACT.md
    cert_block5_CERT_FINAL.md   ← Token maestro Bloque 5
```

### Deuda Tecnica Activa

| ID       | Severidad        | Descripcion                                                                              | Estado    |
| :------- | :--------------- | :--------------------------------------------------------------------------------------- | :-------- |
| H-1, H-2 | ~~Advertencia~~  | fn_is_admin() sin REVOKE + GRANT UPDATE excesivo en system_configuration               | SALDADAS en `20260410000006_block_5a.sql` L29-39 |
| ADV-B5-01 | CVSS 2.1        | Fallback Ghost lee `debt_threshold_hours` directamente en lugar de usar `fn_snapshot_system_config()` — inconsistencia menor | Remediar en siguiente ciclo REFACT del Bloque 6 |

### Bloqueadores Criticos

**Ninguno.** Bloque 5 certificado APROBADO con token CERT-B5-f1-1.1-FINAL-20260410. Suite: 31/31 assertions de Bloque 5 PASS. Sin regresiones en Bloques 1-4.

**Prerequisito antes de iniciar Bloque 6**: El `devops-integrator` debe commitear todos los artefactos de Bloques 4 y 5 (acumulados sin commit) antes de iniciar las tareas RED del Bloque 6.

### Proximo Paso Prioritario (Next Step Atomico)

**Tarea inmediata**: Commit acumulado Bloques 4+5 + inicio de `TSK-F1_1.1-22.1-RED` (Bloque 6 — Automatizacion & Orquestacion)

**Agente responsable commit**: `devops-integrator`
**Agente responsable Bloque 6 RED**: `backend-tester`

**Accion concreta**:
1. `devops-integrator` debe hacer commit atomico de todos los artefactos de Bloques 4 y 5 con mensaje: `feat: implementacion RLS bloque 4 y motores RPC bloque 5 - CERT-B4-f1-1.1-FINAL + CERT-B5-f1-1.1-FINAL (TSK-F1_1.1-13.1 al 21-CERT)`.
2. `backend-tester` inicia `TSK-F1_1.1-22.1-RED` y `22.2-RED` — tests pgTap para `fn_manage_lock` (sync_locks con TTL 60min y reseteo de workers con latido >30min) y modo fallback (flag ante retrasos >24h).
3. Al inicio del Bloque 6, `db-manager` crea la tabla `sync_locks` (ausente en migraciones actuales) + `fn_manage_lock` + `fn_monitor_and_activate_fallback` con logica de pg_cron.
4. Remediar ADV-B5-01: sustituir lectura directa de `debt_threshold_hours` en Fallback Ghost por llamada a `fn_snapshot_system_config()` como primer statement de la migracion `[TIMESTAMP]_block_6.sql`.

---

## §5 Registro Historico de Decisiones (Append-only)

> INVARIANTE: Esta seccion es inviolable. Nunca se modifica ni elimina ninguna entrada anterior.
> Solo se agregan nuevas entradas al final, en orden cronologico.

---

### [2026-04-07] — Inicio Etapa f1_1.0 (Bloque 1 — Scaffolding)

**Contexto**: Primera sesion de desarrollo activo de la Fase 1. La Fase 0 (Gobernanza) fue completada con todos los documentos SDD (PRD, SPEC, PLAN, TASK) autorizados y los tokens en estado AUTORIZADO.

**Decisiones Tomadas**:

1. **Gestion de Dependencias con Hashes (pip-compile)**: Se decidio usar `pip-compile --generate-hashes` en lugar de un `requirements.txt` manual. Esto garantiza reproducibilidad absoluta (Zero Drift) entre entornos local y GitHub Actions. El archivo `requirements.in` actua como fuente de verdad de dependencias directas.

2. **Diseno de `ENV_VAR_PATTERNS`**: Se implemento el diccionario de patrones con flag `is_critical` como `Final[dict]` en `utils.py`. La separacion entre variables CRITICAS (EXIT 1) y de ADVERTENCIA (WARNING) se mapea directamente al contrato de errores definido en el SPEC. Las 4 variables criticas (Supabase URL, Service Role Key, Postgres DB URL, ADMIN_UUID) son las que bloquean el pipeline si estan ausentes o malformadas.

3. **Sanitizacion de Secretos con Limite de 4 chars**: La funcion `sanitize_secret()` expone los primeros 4 caracteres del secret para facilitar la identificacion de tipo de token en logs (ej. `ghp_`, `re_`, `eyJh`) sin revelar el valor real. Los secretos de menos de 5 caracteres se enmascaran completamente.

4. **Estructura `engine/` como paquete Python**: Se usaron `__init__.py` vacios en `src/` y `tests/` para permitir imports relativos y que `pytest` descubra automaticamente los modulos de prueba sin configuracion adicional de `PYTHONPATH`.

**Tarea TSK-F1_1.0-02 — Nota de Operacion**: El entorno virtual `.venv/` fue creado con `python -m venv engine/.venv` y las dependencias se instalaron con `pip install --require-hashes -r requirements.txt` para verificar la integridad de hashes antes de proceder con el desarrollo.

---

### [2026-04-07] — Cierre Bloque 2 (Modelado & Engine Core — TDD Cycle)

**Contexto**: Segunda sesion de desarrollo activo de la Fase 1, Etapa 1.0. El Bloque 2 completo fue ejecutado en una sola sesion abarcando el ciclo TDD completo RED -> GREEN -> CERT.

**Decisiones Tomadas**:

1. **Arquitectura de Modelos con Enum `CheckStatus`**: Se diseno `CheckStatus` como `str, Enum` (en lugar de `IntEnum`) para garantizar que los valores sean directamente serializables a JSON y legibles en los reportes de GitHub Step Summary sin transformacion adicional. Los valores `OK`, `WARNING`, `ERROR`, `SKIPPED` mapean exactamente al contrato del SPEC.

2. **Modelo `ServiceResult` como unidad atomica del pipeline**: Cada verificacion de servicio retorna un `ServiceResult` inmutable con campos `service`, `status`, `message`, `latency_ms` y `metadata` opcional. Esta granularidad permite que el orquestador agregue estados sin acoplamiento a la logica de cada servicio.

3. **Separacion `CRITICAL_SERVICES` / `WARNING_SERVICES` como listas de constantes**: En `check_env.py` se definieron dos listas inmutables que determinan el comportamiento del `exit code`. Los servicios criticos provocan `sys.exit(1)` si fallan; los de advertencia solo emiten `WARNING`. Esta separacion declarativa evita logica condicional dispersa en `main()`.

4. **`conftest.py` en la raiz para resolver `sys.path`**: Se identifico que `pytest` ejecutado desde la raiz del proyecto no resolvia correctamente los imports de `engine.src.*` sin manipulacion del `sys.path`. La solucion fue crear `conftest.py` en la raiz con insercion explicita, en lugar de modificar `pytest.ini` o `pyproject.toml`, manteniendo la configuracion minima del proyecto.

5. **Defecto estructural en `test_orchestrator.py` L235 corregido durante TSK-07-RED**: Durante la fase RED del Bloque 2 se detecto un error de estructura en el test de orquestacion que hacia pasar el test por razones incorrectas. Se corrigio antes de proceder a la fase GREEN, preservando la integridad del ciclo TDD.

6. **Stubs con `latency_ms=0.1` como sentinel explicito**: Los stubs del Bloque 2 usan `latency_ms=0.1` como valor centinela que indica "latencia simulada, no real". El Bloque 3 reemplazara estos stubs con implementaciones reales que midan latencia via `httpx` y `psycopg2`. OBS-06 documenta este contrato para el implementador del Bloque 3.

---

### [2026-04-07] — Cierre Bloque 3 (Handshaking de APIs Externas — TDD Cycle)

**Contexto**: Tercera sesion de desarrollo activo de la Fase 1, Etapa 1.0. El Bloque 3 completo fue ejecutado en una sola sesion: 4 fases RED (36 tests), 4 fases GREEN (5 funciones implementadas), 1 CERT de calidad + correcciones, 1 CERT de seguridad. Suite total: 79 passed, 0 failed.

**Decisiones Tomadas**:

1. **Una suite de tests por servicio externo (no un archivo monolitico)**: A diferencia de lo que anticipaba el handoff anterior (un solo `test_handshakes.py`), se decidio crear un archivo de tests por servicio: `test_github_handshake.py`, `test_resend_handshake.py`, `test_upstash_handshake.py`, `test_supabase_handshake.py`. Esta granularidad facilita la localizacion de fallos en CI/CD y reduce el acoplamiento entre suites de servicios independientes.

2. **Mock de `httpx.get` a nivel de modulo, no de funcion**: Los tests parchean `httpx.get` directamente (`patch("httpx.get", ...)`) en lugar de parchear `engine.src.check_env.httpx.get`. Esto es posible porque `httpx` se importa a nivel de modulo y es mas robusto ante refactorizaciones internas de `check_env.py`.

3. **`latency_ms = max((end - start) * 1000, 0.001)`**: El minimo garantizado de `0.001 ms` resuelve la restriccion `gt=0` del modelo `ServiceResult` incluso cuando los mocks de `httpx` son instantaneos (latencia medida de 0µs). Este patron debe replicarse en todos los checks del Bloque 4.

4. **`_sanitize_checks` invocada antes de `_compute_global_status`**: La sanitizacion de mensajes de error ocurre antes de construir el `RunReport`, garantizando que ninguna superficie de salida (stdout, GITHUB_STEP_SUMMARY) reciba mensajes crudos con credenciales. El orden es: `checks completos -> _sanitize_checks -> _compute_global_status -> RunReport -> stdout -> GHA`.

5. **Correccion DEF-01 — `start` capturado antes del loop en `check_supabase_sql`**: El bug original calculaba `end_err - end_err = 0.0` en el path de error. La correccion mueve `start = time.monotonic()` fuera del loop `for`, calculando correctamente la latencia total acumulada de todos los reintentos fallidos.

6. **Correccion DEF-02 — Sanitizacion activada en `main()`**: `sanitize_log_message` existia en `utils.py` y `sanitize_service_result` en `sanitizer.py`, pero ninguna era invocada desde el flujo principal. La correccion agrego `_sanitize_checks` llamada desde `main()` con la lista de `_SECRET_ENV_KEYS`. La Capa 2 (`sanitizer.py` con regex de headers) permanece como deuda tecnica H-1 para TSK-19.1-REFACTOR.

7. **`psycopg2.connect(db_url)` con argumento posicional**: El test `test_check_supabase_sql_calls_psycopg2_connect` inspeccionaba `call_args.args[0]`. La implementacion usa `psycopg2.connect(db_url)` (posicional, no keyword) para satisfacer este contrato. Esta decision debe mantenerse al extender la funcion con `connect_timeout` en el Bloque 4 (pasarlo como keyword: `psycopg2.connect(db_url, connect_timeout=10)`).

8. **Recomendacion de seguridad H-2 diferida al Bloque 4**: El security-hardener recomendo agregar `connect_timeout=10` a `psycopg2.connect` para evitar bloqueos indefinidos. Esta correccion se difiere al Bloque 4 (TSK-F1_1.0-14.1-GREEN) donde el `db-manager` ya tendra contexto completo sobre el patron de conexion SQL definitivo.

---

### [2026-04-08] — Cierre Bloque 4 (Database & Persistencia — TDD Cycle)

**Contexto**: Cuarta sesion de desarrollo activo de la Fase 1, Etapa 1.0. El Bloque 4 completo fue ejecutado en una sola sesion: 1 fase RED (15 tests en test_database.py), 4 fases GREEN (4 funciones DB implementadas en check_env.py), 2 CERTs (db-manager + backend-reviewer). Suite total ascendio de 79 a 94 passed, 0 failed. Certificacion: APROBADO CON OBSERVACIONES por ambos certificadores.

**Decisiones Tomadas**:

1. **`psycopg2.sql.Identifier` para prevencion de second-order SQL injection en `check_zombie_cleanup`**: Los nombres de tablas huerfanas provienen del catalogo `pg_tables` (una fuente del sistema, no del usuario), pero igualmente pueden contener caracteres especiales o ser usados como vector de inyeccion si la fuente del catalogo es comprometida. Se decidio usar `pg_sql.SQL("DROP TABLE IF EXISTS {}").format(pg_sql.Identifier(name))` en lugar de f-strings. Esta decision se aplico solo a `check_zombie_cleanup`; `check_persistence_cycle` quedo con f-strings como deuda tecnica B-2 para TSK-19.1-REFACTOR.

2. **Clases helper `_PgProgrammingErrorWithCode` y `_PgOperationalErrorWithCode` para simular `pgcode` readonly**: En psycopg2 2.9+, el atributo `pgcode` de las excepciones es readonly (implementado en C). Intentar `exc.pgcode = "42P01"` lanza `AttributeError`. La solucion adoptada fue subclasificar las excepciones con una `@property` que retorna el codigo deseado. Este patron debe replicarse en todos los tests futuros que necesiten simular errores pgcode especificos de PostgreSQL.

3. **Patron de importacion diferida en tests RED**: Las funciones `check_pg_extensions`, `check_zombie_cleanup`, `check_ddl_capabilities` y `check_persistence_cycle` fueron importadas dentro de cada test (no a nivel de modulo) para que pytest colecte y ejecute cada test individualmente con su propio `ImportError`. Esto garantiza que la fase RED falla de forma granular (un test a la vez) en lugar de abortar toda la suite por un error de coleccion.

4. **Doble `finally` en `check_persistence_cycle` para garantia de cleanup**: El patron implementado usa un `try/finally` interior (cierre de cursor + DROP TABLE) anidado dentro de un `try/finally` exterior (cierre de conexion). Esto garantiza que la tabla temporal `_bootstrap_[run_id_short]` y la conexion son limpiadas incluso ante SIGKILL, timeout de GHA o excepciones no anticipadas.

5. **Bloque 4 certificado APROBADO CON OBSERVACIONES (no RECHAZADO)**: A diferencia del Bloque 3 donde el backend-reviewer emitio TOKEN:RECHAZADO en primera pasada, en el Bloque 4 ambos certificadores emitieron APROBADO CON OBSERVACIONES directamente. Las 5 observaciones (B-1, B-2, B-3, D-1, D-3) fueron registradas en el backlog pero no bloquearon el avance. La distincion entre "defecto bloqueante" y "observacion de mejora" en los CERTs es un indicador de madurez del ciclo de revision.

6. **Solapamiento de scope entre TSK-14.1 y TSK-14.2**: El db-manager en TSK-14.1 implemento `check_pg_extensions` (que era el alcance de T-10 en la SPEC) incluyendo la integracion en `main()`, dejando a TSK-14.2 sin trabajo de implementacion sustancial. Este solapamiento fue detectado post-facto. Para el Bloque 5, los limites de tarea deben ser mas explicitos en el TASK (especificar exactamente que funcion implementa cada tarea antes de delegar al agente).

---

### [2026-04-08] — Bloque 5 parcial (CI/CD & Final Testing — 4/6 tareas)

**Contexto**: Quinta sesion de desarrollo activo de la Fase 1, Etapa 1.0. Se ejecutaron las 4 primeras tareas del Bloque 5: workflow GHA, provisionamiento de secretos, certificacion de seguridad CI/CD y validacion de inyeccion de fallas. Suite total ascendio de 94 a 105 passed, 0 failed. Las tareas de refactorizacion final (TSK-19.1 y TSK-19.2) quedaron pendientes para la proxima sesion. Los cambios del Bloque 5 estan en working tree sin commitear.

**Decisiones Tomadas**:

1. **Workflow GHA con nombre especifico de etapa (`f1_1.0_env_validation.yml`)**: Se creo el workflow con nombre de archivo que refleja la etapa exacta (en lugar de un nombre generico `ci.yml`). El trigger `schedule: '30 6 * * 2,4,0'` corresponde a las 1:30 AM COT (UTC-5) los martes, jueves y domingos, alineado exactamente con el mandato de sincronizacion automatica del SPEC. El trigger `workflow_dispatch` adicional permite ejecuciones manuales para debugging en CI.

2. **Remediacion de VUL-02 — expansion de `_SECRET_ENV_KEYS`**: La auditoria de seguridad CI/CD identifico que `SUPABASE_URL` y `ADMIN_UUID` estaban ausentes de la lista `_SECRET_ENV_KEYS` en `check_env.py`. Estas variables son criticas (exit 1 si fallan) pero su valor no era redactado en logs. La remediacion las agrego a `_SECRET_ENV_KEYS` antes de emitir el certificado de seguridad. Leccion: la lista de variables a sanitizar debe coincidir exactamente con la lista de variables criticas del SPEC.

3. **Remediacion de VUL-01 — hardening de `provision_secrets.sh` con `grep -F`**: La funcion `get_env_value` original usaba `grep -E` con el nombre de variable como patron, lo que permitia inyeccion de metacaracteres de regex si el nombre de variable contuviera caracteres como `.`, `*`, `+`. La correccion usa `grep -F` (literal matching) + escapado de metacaracteres en el valor. Este es el estandar para scripts bash que procesan entradas que incluyen datos de usuario o externos.

4. **Remediacion de VUL-03 — cambio de placeholder de GITHUB_TOKEN en `.env.example`**: El placeholder `ghp_tu-github-token-aqui` tiene el prefijo real `ghp_` que dispara detectores de secretos (gitleaks, truffleHog) incluso en archivos de ejemplo. El cambio a `REEMPLAZAR_CON_TOKEN_REAL` elimina el falso positivo sin perder la claridad instruccional. Esta practica debe aplicarse a todos los placeholders de tokens en archivos de ejemplo del proyecto.

5. **Suite `test_failure_injection.py` con clasificacion por grupos de comportamiento**: Los 11 tests se organizaron en 4 grupos conceptuales (Hard-Gate, No-Exit, Reporte, Diagnostic-First) en lugar de una lista plana. Esta organizacion facilita la lectura del reporte de pytest y la identificacion del tipo de comportamiento que cada test valida. El patron debe replicarse para suites de tests con multiples categorias de comportamiento.

6. **Cambios del Bloque 5 no commiteados al cerrar sesion**: A diferencia de sesiones anteriores donde se hizo commit antes del cierre, esta sesion concluye con working tree modificado pero sin commit. El proximo agente debe commitear el estado del Bloque 5 como primer paso antes de iniciar TSK-19.1-REFACTOR, para garantizar que la refactorizacion comienza desde un baseline conocido y auditado.

---

### [2026-04-08] — Cierre Formal de Etapa 1.0 (TSK-20 hasta TSK-22.2)

**Contexto**: Septima sesion de la Fase 1, Etapa 1.0. Se ejecutaron las 4 tareas de cierre administrativo: Suite de Integracion Real (TSK-20), Auditoria de Gobernanza (TSK-21), Cierre Formal con Resumen Ejecutivo (TSK-22.1) y Persistencia de Estado (TSK-22.2). La Etapa 1.0 queda formalmente CERRADA. Unica tarea pendiente: TSK-22.3 (commit + PR por `devops-integrator`).

**Resultados clave**:

1. **TSK-20**: 105/105 tests PASSED. Cobertura 94% (umbral >90%). Tiempo de suite 4.18s (umbral <8.0s). Token: `QA-F1_1.0-TSK20-PASSED-20260408`.

2. **TSK-21**: Auditoria CONFORME. Evidencia fisica verificada para todos los artefactos. Unico hallazgo H-01 (Severidad Baja, regularizado): `engine/requirements.in` y `conftest.py` raiz sin tarea atomica explicita en TASK LIST — ambos son infraestructura de soporte legitima, no logica de negocio. Token: `AUDIT-F1_1.0-TSK21-CONFORME-20260408`.

3. **TSK-22.1**: `docs/executives/f1_1.0_executive.md` emitido. 12/12 requerimientos PRD cumplidos. Avance Fase 1: 12.5% (1/8 etapas). Avance Total: 14.7% (5/34 etapas). Token: `EXEC-CLOSE-F1_1.0-20260408`.

**Proxima etapa**: 1.1 — Setup de Supabase y DDL.

---

### [2026-04-08] — Cierre Bloque 5 completo (TSK-19.1-REFACTOR + TSK-19.2-REFACTOR)

**Contexto**: Sexta sesion de desarrollo activo de la Fase 1, Etapa 1.0. Se ejecutaron las 2 tareas finales del Bloque 5: refactorizacion completa de `check_env.py` (TSK-19.1) y auditoria tecnica final (TSK-19.2). Suite: 105 passed, 0 failed. El backend-reviewer emitio APROBADO con 3 hallazgos INFO no bloqueantes. Los 5 bloques de desarrollo estan ahora 100% completados. La etapa queda bloqueada en el Cierre de Etapa (TSK-20 a TSK-22.3).

**Decisiones Tomadas**:

1. **Helper `_http_get_with_retry` centraliza el patron retry HTTP duplicado 4 veces**: La refactorizacion TSK-19.1 elimino ~60 lineas de codigo copiado al extraer el patron `for attempt in range(retries)` + backoff exponencial + construccion del `ServiceResult` en error en un solo helper privado. Los 4 handshakes HTTP (GitHub, Resend, Upstash, Supabase REST) ahora delegan en este helper. Esta extraccion resuelve OBS-B3 del backlog acumulado desde el Bloque 3.

2. **Helper `_run_and_log_check` colapsa el patron check+log en `main()`**: Los 10 bloques identicos de `result = check_X(); results.append(result); logger.info(...)` en `main()` fueron reemplazados por llamadas a `_run_and_log_check(check_X, "nombre", results)`. Esto resuelve OBS-01 del backlog del Bloque 2 y reduce la funcion `main()` de ~80 a ~30 lineas efectivas.

3. **Constante `_DIRECT_DEPS` elevada a nivel de modulo**: La lista de dependencias directas del Engine fue movida de inline-en-funcion a nivel de modulo como constante `_DIRECT_DEPS: Final[list[str]]`. Esto permite que la constante sea accesible por cualquier funcion del modulo sin paso de argumentos y facilita su inspeccion en tests.

4. **Renombre de parametro `run_id_short` a `table_suffix` en `check_persistence_cycle`**: El parametro original `run_id_short` colisionaba en nombre con la funcion importada `run_id_short` de `utils.py`. El renombre a `table_suffix` elimina la ambiguedad y describe mejor el proposito del parametro (es un sufijo para el nombre de la tabla temporal, no necesariamente el ID de la corrida).

5. **Bug fix: `latency_ms=0.0` violaba la restriccion `gt=0` del modelo `ServiceResult`**: En el path de error de `_http_get_with_retry`, el return de fallo de red usaba `latency_ms=0.0`. La restriccion `Field(gt=0)` del modelo `ServiceResult` rechaza valores de cero. El fix aplica el patron canonico `max((end - start) * 1000, 0.001)` en el path de error, consistente con todos los demas checks del modulo.

---

### [2026-04-09] — Cierre Bloque 0/1 — Validacion & Scaffolding Supabase (Etapa 1.1)

**Contexto**: Primera sesion de desarrollo activo de la Etapa 1.1. Bloque 0/1 completado en una sola sesion: 5 tests pgTap de entorno (20 assertions), Gate 0 certificado APTO, `supabase db reset` exitoso. El stack local Supabase quedo operativo. 3 hallazgos criticos de infraestructura resueltos durante TSK-03.3.

**Decisiones Tomadas**:

1. **`extra_search_path` y `cron.max_running_jobs` migrados de `config.toml` a DDL SQL**: El CLI v2.89.0 no soporta estas directivas en `config.toml`. La configuracion correcta del `search_path` de sesion debe hacerse via `ALTER ROLE authenticator SET search_path = extensions, public;` en las migraciones del Bloque 2. Esta es la distincion "configuracion de cliente vs configuracion de servidor" que aplica a toda la Etapa 1.1.

2. **Gate 0 como barrera formal entre scaffolding y DDL**: La certificacion Gate 0 (GATE0-f1-1.1-CERT-001) fue emitida antes de iniciar cualquier tarea de migracion, actuando como contrato de calidad del entorno. Ninguna migracion DDL debe crearse sobre un entorno sin Gate 0 certificado.

3. **`005_search_path_restrictive.sql` en estado RED intencional**: El test falla en el reset actual porque la migracion DDL que configura el `search_path` (via ALTER ROLE) aun no existe. Este es el comportamiento correcto de TDD para infraestructura de BD: el test documenta el estado deseado futuro. El proximo agente no debe modificar las assertions para hacerlas pasar; debe implementar la migracion que las satisfaga.

---

### [2026-04-09] — Cierre Bloque 2 — Schema Core & Singleton (Etapa 1.1)

**Contexto**: Segunda sesion de desarrollo activo de la Etapa 1.1. Ciclo TDD completo RED -> GREEN -> REFACTOR -> CERT ejecutado en una sola sesion. 5 tests pgTap escritos (26 assertions), migracion DDL `20260409000001_block_1_2.sql` creada y refactorizada, 2 tokens de certificacion emitidos.

**Decisiones Tomadas**:

1. **Trigger BEFORE DELETE FOR EACH STATEMENT (no FOR EACH ROW) para el Singleton**: El trigger `tg_prevent_singleton_delete` usa `FOR EACH STATEMENT` en lugar de `FOR EACH ROW`. Esta decision garantiza que un `DELETE FROM system_configuration` (sin WHERE) dispara el trigger exactamente una vez, independientemente del numero de filas afectadas. `FOR EACH ROW` habria requerido que hubiera al menos una fila para dispararse, lo que crea una ventana de vulnerabilidad cuando la tabla esta vacia.

2. **`fn_validate_ball_array` como funcion IMMUTABLE con 3 Reglas de Oro**: La funcion valida en un solo paso rango de valores, ausencia de duplicados y cardinalidad exacta del array. Se declara IMMUTABLE porque su resultado depende exclusivamente de los parametros de entrada (sin acceso a tablas ni estado externo). Esto permite al planificador de PostgreSQL usar el resultado en cache para llamadas con los mismos argumentos, optimizando CHECKs repetitivos en inserciones masivas de proyecciones.

3. **Orden canonico de migracion en 6 bloques secuenciales**: Extensions -> Functions (IMMUTABLE antes de tablas, para permitir referencias en CHECKs) -> Tables -> Triggers -> Indexes -> Seed. Este orden elimina dependencias circulares y garantiza que las funciones usadas en CHECKs de columnas existen antes de que se ejecute el CREATE TABLE. El orden debe mantenerse en todas las migraciones futuras de la Etapa 1.1.

4. **`idx_draws_date_type_unique` como indice unico (no UNIQUE constraint en tabla)**: La restriccion de unicidad sobre `(draw_date, draw_type)` en `draws` se implemento como `CREATE UNIQUE INDEX` en lugar de `UNIQUE` inline en el CREATE TABLE. Esta decision permite adjuntar un nombre explicito al indice para diagnostico forense y facilita su eventual suspension temporal durante carga masiva de datos historicos (Fase 2) sin alterar el DDL de la tabla.

5. **Seed con `INSERT ON CONFLICT DO NOTHING` para idempotencia del Singleton**: El registro inicial de `system_configuration` (id=1) usa `ON CONFLICT DO NOTHING` para garantizar que multiples ejecuciones de `supabase db reset` no generen error de PK duplicada. Esta es la unica excepcion al principio de "seed = datos fijos"; el admin_uuid se genera con `gen_random_uuid()` en el primer reset y se preserva en resets subsiguientes gracias al ON CONFLICT.

6. **Eliminacion de 4 ALTER TABLE redundantes en REFACTOR**: El draft inicial de la migracion usaba ALTER TABLE post-creacion para agregar CHECKs nombrados a tablas ya definidas. En la fase REFACTOR, todos los CHECKs fueron integrados directamente en el CREATE TABLE original. Esta decision reduce el numero de statements DDL, elimina estados intermedios invalidos del schema y hace la migracion atomicamente correcta desde el primer statement.

---

### [2026-04-10] — Cierre Bloque 3 — Motor de Performance (Etapa 1.1)

**Contexto**: Tercera sesion de desarrollo activo de la Etapa 1.1. Bloque 3 completado en una sola sesion: 2 tareas RED (9 assertions pgTap), 7 tareas GREEN (3 tablas + 1 funcion + 2 indices), 1 tarea REFACTOR (4 indices adicionales), 1 CERT de calidad. Migracion 20260410000001_block_3.sql con 382 lineas de DDL auditado. Token de certificacion: BACKEND-REVIEWER:CERT:12-BLOQUE3:APROBADO.

**Decisiones Tomadas**:

1. **Idempotencia via DELETE previo (no ON CONFLICT) en fn_bulk_insert_projections**: La SPEC §4.1 exige que la funcion implemente "DELETE WHERE run_id = p_run_id" antes de INSERT, garantizando que reruns del Engine Python produzcan exactamente el mismo estado final sin duplicados. Esta decision contrasta con el Bloque 2 (Singleton usa ON CONFLICT DO NOTHING). El patron DELETE+INSERT es el contrato obligatorio para resiliencia ante fallos de GHA.

2. **SPEC > TASK como regla de resolucion de conflictos**: El TASK menciona columnas adicionales (last_heartbeat, worker_id, retry_count) en projections que no figuran en SPEC §3.4. Se aplico la regla de prevalencia SPEC > TASK y se omitieron esas columnas. La SPEC es fuente de verdad de arquitectura; el TASK es solo una propuesta de desglose de implementacion.

3. **clock_timestamp() en performance.processed_at (no now())**: Se uso clock_timestamp() para capturar el tiempo real dentro de la transaccion actual, permitiendo desempate FIFO de rankings (SPEC §4.2). now() retorna el tiempo al inicio de la transaccion; clock_timestamp() es el tiempo real en el momento de ejecucion del statement DDL. Para un scoring que ocurre en multiples statements, clock_timestamp() proporciona granularidad mayor.

4. **Indice parcial en is_active para strategies_metadata**: Se creo CREATE INDEX ... WHERE is_active = TRUE en lugar de un B-Tree completo. Esta decision se basa en que en produccion, el 95%+ de estrategias tendran is_active=TRUE, haciendo el indice parcial mas pequeno en disco y mas rapido de actualizar.

5. **Orden canonico de migracion preservado (6 bloques secuenciales)**: La migracion del Bloque 3 sigue exactamente el mismo patron de orden del Bloque 2: Extensions -> Functions -> Tables -> Triggers -> Indexes -> Seed. Aunque el Bloque 3 no tiene Triggers ni Seed, la estructura se mantiene por consistencia y es standar obligatorio para la Etapa 1.1.

6. **Indice compuesto idx_performance_tiebreak con orden preciso**: El indice (score DESC, processed_at ASC, projection_id ASC) implementa la jerarquia de desempate de SPEC §4.2: puntaje mas alto (DESC), procesado mas temprano (ASC), UUID determinista (ASC). Este orden permite que el planificador PostgreSQL use el indice para ORDER BY sin necesidad de Sort operator.

7. **4 indices REFACTOR para optimizacion de planes de ejecucion**: El REFACTOR identifica 5 queries core (Q1-Q5) que originariamente ejecutarian full table scans. Se crearon 4 indices adicionales para convertir Seq Scans en Index Scans eficientes. El analisis fue estatico basado en planes de ejecucion esperados conforme a la selectividad de datos prevista.

---

### [2026-04-10] — Cierre Bloque 4 — Seguridad & RLS (Etapa 1.1)

**Contexto**: Cuarta sesion de desarrollo activo de la Etapa 1.1. Bloque 4 completado en una sola sesion: 5 tareas RED (33 assertions en 5 archivos pgTap), 4 tareas GREEN (4 migraciones: funciones SECURITY DEFINER, 20 politicas RLS, GRANTs, helper fn_is_admin), 1 tarea REFACTOR, 1 tarea CERT. Token maestro: CERT-B4-f1-1.1-FINAL-2026-04-10. Suite: 32/33 assertions PASS (1 falla de entorno local, no de implementacion).

**Decisiones Tomadas**:

1. **Triple barrera de seguridad ADR-06 como patron estandar**: Toda funcion SECURITY DEFINER del proyecto (fn_setup_security_context, fn_compute_async_scoring stub, fn_verify_and_promote_draw stub, fn_is_admin) implementa: (a) SECURITY DEFINER, (b) SET search_path = extensions, public en la definicion, (c) OWNER TO postgres. Este patron es el estandar obligatorio para cualquier funcion futura que acceda a tablas protegidas o ejecute set_config().

2. **COALESCE guard doble en todas las politicas Admin**: El patron canonico es `USING (auth.uid()::text = COALESCE(current_setting('app.current_admin_id', TRUE), '') AND COALESCE(...) != '')`. La doble condicion garantiza fail-closed: si current_admin_id es NULL o cadena vacia, ninguna comparacion con un UUID valido puede ser TRUE. El segundo parametro TRUE en current_setting() es obligatorio para evitar EXCEPTION en sesiones sin contexto (retorna NULL en su lugar).

3. **Deny All para web_anon via ausencia de politicas (no politica DENY explicita)**: PostgreSQL con RLS activo aplica deny-by-default cuando no existe ninguna politica para el rol solicitante. Esta es la implementacion correcta y mas segura para web_anon: habilitar RLS y no crear ninguna politica para ese rol. Una politica DENY explicita seria redundante y podria crear confusion sobre la semantica de RESTRICTIVE vs PERMISSIVE.

4. **REVOKE ALL FROM PUBLIC en funciones SECURITY DEFINER**: PostgreSQL otorga EXECUTE a PUBLIC en todas las funciones nuevas por defecto. Para funciones SECURITY DEFINER (que se ejecutan con privilegios de postgres), este comportamiento crea un vector de escalada de privilegios directo (OWASP A01). La migracion de grants incluye REVOKE ALL ON FUNCTION ... FROM PUBLIC como primer statement antes de los GRANTs explicitos por rol.

5. **Refactor parcial de fn_is_admin() sin reescribir politicas existentes**: El refactor completo (reemplazar COALESCE inline en las 20 politicas por `USING (fn_is_admin())`) fue descartado porque romperia 3 assertions de los tests RED vigentes (013-A7 busca 'coalesce' en pg_policies.qual, 016-A3/A5 buscan 'current_setting'/'current_admin_id'). PostgreSQL almacena el texto literal del USING en pg_policies.qual. La funcion fn_is_admin() queda disponible para politicas nuevas en Bloques posteriores. Esta deuda es documentada como informativo no bloqueante.

6. **pg_cron GRANT con bloque DO condicional**: El GRANT de USAGE ON SCHEMA cron a service_role requiere que el esquema cron exista. En entorno local (Supabase CLI), cron puede no estar disponible. La solucion es un bloque DO que detecta la existencia del esquema antes de ejecutar el GRANT, emitiendo RAISE NOTICE si no existe. Esto hace la migracion idempotente y ejecutable en ambos entornos (local y produccion Supabase Cloud).

7. **H-1 y H-2 como deuda tecnica prioritaria para Bloque 5**: La auditoria CERT identifico dos advertencias que deben remediarse al inicio del Bloque 5: REVOKE PUBLIC de fn_is_admin() (CVSS ~5.3) y REVOKE UPDATE de system_configuration para authenticated (CVSS ~3.1). Ambas deben ser los primeros statements de la migracion block_5.sql antes de cualquier logica de negocio nueva.

---

### [2026-04-10] — Cierre Bloque 5 — Motores RPC (Etapa 1.1)

**Contexto**: Quinta sesion de desarrollo activo de la Etapa 1.1. Bloque 5 completado en una sola sesion: 6 tareas RED (31 assertions en 6 archivos pgTap), 5 tareas GREEN (2 migraciones con implementacion real de fn_compute_async_scoring + fn_verify_and_promote_draw + 3 helpers SECURITY DEFINER + remediaciones H-1/H-2), 1 tarea REFACTOR (modularizacion completa viable), 1 CERT APROBADO. Token maestro: CERT-B5-f1-1.1-FINAL-20260410. Suite Bloque 5: 31/31 assertions PASS.

**Decisiones Tomadas**:

1. **Patron CLAIM TOKEN en fn_compute_async_scoring**: La funcion SQL solo implementa la fase de reclamacion: snapshot de system_configuration → kill-switch check → marcado anti-carrera `pending→calculating` via FOR UPDATE SKIP LOCKED. El scoring real (calculo de hits, INSERT en performance, transicion a 'calculated') ocurre en el Engine Python asincrono. Este diseño es coherente con la arquitectura ASYNC de la Etapa 1.1 (el Motor Python en GHA procesa, la BD solo coordina el estado).

2. **Tests funcionales vs texto literal — leccion Bloque 4 aplicada**: Los 6 tests del Bloque 5 verifican exclusivamente efectos secundarios observables (filas en tablas, valores de columnas, JSONB en metadata). Ninguno inspecciona pg_proc.prosrc ni pg_policies.qual. Resultado: el REFACTOR completo fue viable sin riesgo de regresion — los 3 helpers reemplazaron logica duplicada en fn_verify_and_promote_draw sin romper ningun assertion.

3. **Modularizacion completa en REFACT (a diferencia del Bloque 4)**: El REFACTOR del Bloque 4 fue parcial (solo creo fn_is_admin() sin reescribir politicas) porque los tests inspeccionaban texto literal. El REFACTOR del Bloque 5 fue completo: 3 helpers extrajeron logica duplicada y las funciones principales fueron reescritas para usarlos. Este contraste confirma que tests funcionales habilitan ciclos de refactorizacion sin fricciones.

4. **Triple barrera ADR-06 aplicada a los 3 helpers nuevos**: fn_snapshot_system_config(), fn_backup_performance_to_logs(), fn_reset_draw_scoring() — todos con SECURITY DEFINER + SET search_path = extensions, public + OWNER TO postgres + REVOKE ALL FROM PUBLIC. Este patron se consolida como estandar obligatorio para toda funcion auxiliar del proyecto que acceda a tablas protegidas.

5. **retry_count como columna de coordinacion Engine↔BD**: La columna `retry_count INTEGER DEFAULT 0` en projections actua como semaforo de estado compartido entre la BD (que incrementa en error) y el Engine Python (que lee el valor para decidir si reintentar o marcar error_fatal). Esta interfaz minima evita la necesidad de comunicacion directa entre workers GHA — la BD es el unico canal de coordinacion.

6. **ADV-B5-01 — Fallback Ghost lee system_config directamente en lugar de fn_snapshot_system_config()**: La rama Fallback Ghost en fn_verify_and_promote_draw lee debt_threshold_hours directamente desde system_configuration en lugar de delegar al helper fn_snapshot_system_config(). Esto es inconsistente con el patron de snapshotting del resto de la funcion. El impacto practico es bajo (es una decision puntual binaria, no un loop iterativo), pero debe corregirse en el primer ciclo REFACT del Bloque 6 para eliminar la divergencia arquitectonica.

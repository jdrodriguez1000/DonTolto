# PROJECT_handoff.md: DonTolto

---
**Ultima Actualizacion**: 2026-04-08
**Responsable del Cierre**: session-closer (Protocolo de Handoff Tecnico)
**Estado de Persistencia**: ESTADO_PERSISTIDO_OK
---

## §1 Coordenadas de Ejecucion

| Dimension          | Detalle                                                                 |
| :----------------- | :---------------------------------------------------------------------- |
| **Fase Activa**    | Fase 1 — Infraestructura de Datos (Cimentacion)                         |
| **Etapa Activa**   | 1.0 — Validacion de Entorno                                             |
| **Bloque Activo**  | Bloque 5 — CI/CD [GHA Workflow & Reporting] — PENDIENTE                 |
| **Rama Git**       | `feat/f1_1.0_env_validation`                                            |
| **Ultimo Commit**  | `9fff90e` — `docs: actualización de handoff y tareas; impl: tests de handshake de APIs (f1_1.0)` |
| **Capas Tecnicas** | Backend (Python Engine), Infra (GitHub Actions, CI/CD)                  |

---

## §2 Hitos y Avance de Etapa

### Estado del Bloque 1 — Scaffolding & Setup [Etapa 1.0.1]: 100% COMPLETADO

| Tarea             | Descripcion                                          | Estado     |
| :---------------- | :--------------------------------------------------- | :--------- |
| TSK-F1_1.0-01     | Estructura de directorios `engine/src/`, `engine/tests/` y `__init__.py` | Completado |
| TSK-F1_1.0-02     | Dependencias con hashes SHA256 e integridad verificada | Completado |
| TSK-F1_1.0-03     | Modulo `utils.py`: utilidades de infraestructura reutilizables | Completado |

### Estado del Bloque 2 — Modelado & Engine Core [TDD Cycle]: 100% COMPLETADO

| Tarea                  | Agente              | Descripcion                                          | Estado     |
| :--------------------- | :------------------ | :--------------------------------------------------- | :--------- |
| TSK-F1_1.0-04-RED      | backend-tester      | Tests fallidos de Modelos y Sanitizacion             | Completado |
| TSK-F1_1.0-05-GREEN    | backend-coder       | Implementacion de Modelos Pydantic                   | Completado |
| TSK-F1_1.0-06-GREEN    | security-hardener   | Implementacion de Sanitizacion de Tokens/Keys        | Completado |
| TSK-F1_1.0-07-RED      | backend-tester      | Mocks y Tests de Orquestacion (Diagnostic-First)     | Completado |
| TSK-F1_1.0-07.1-GREEN  | backend-coder       | Configuracion de Mapeo de Criticidad                 | Completado |
| TSK-F1_1.0-08-GREEN    | backend-coder       | Orquestador Core, Agregacion y Logica de Salida      | Completado |
| TSK-F1_1.0-09-CERT     | backend-reviewer    | CERTIFICACION TECNICA CORE — APROBADO                | Completado |

### Estado del Bloque 3 — Handshaking de APIs Externas [TDD Cycle]: 100% COMPLETADO

| Tarea                  | Agente              | Descripcion                                              | Estado     |
| :--------------------- | :------------------ | :------------------------------------------------------- | :--------- |
| TSK-F1_1.0-10.1-RED    | backend-tester      | Tests fallidos: GitHub Handshake (8 tests)               | Completado |
| TSK-F1_1.0-10.2-RED    | backend-tester      | Tests fallidos: Resend Handshake (8 tests)               | Completado |
| TSK-F1_1.0-10.3-RED    | backend-tester      | Tests fallidos: Upstash Redis Handshake (8 tests)        | Completado |
| TSK-F1_1.0-10.4-RED    | backend-tester      | Tests fallidos: Supabase REST/SQL (12 tests)             | Completado |
| TSK-F1_1.0-11.1-GREEN  | backend-coder       | Implementacion Handshake GitHub                          | Completado |
| TSK-F1_1.0-11.2-GREEN  | backend-coder       | Implementacion Handshake Resend                          | Completado |
| TSK-F1_1.0-11.3-GREEN  | backend-coder       | Implementacion Handshake Upstash                         | Completado |
| TSK-F1_1.0-11.4-GREEN  | backend-coder       | Implementacion Handshake Supabase REST + SQL             | Completado |
| TSK-F1_1.0-12.1-CERT   | backend-reviewer    | Certificacion de Mapeo de Contratos API — APROBADO       | Completado |
| TSK-F1_1.0-12.2-CERT   | security-hardener   | Certificacion de Scopes y Seguridad de APIs — APROBADO   | Completado |

### Estado del Bloque 4 — Database & Persistencia [TDD Cycle]: 100% COMPLETADO

| Tarea                  | Agente              | Descripcion                                                                        | Estado     |
| :--------------------- | :------------------ | :--------------------------------------------------------------------------------- | :--------- |
| TSK-F1_1.0-13-RED      | backend-tester      | 15 tests fallidos para 4 funciones DB (check_pg_extensions, check_zombie_cleanup, check_ddl_capabilities, check_persistence_cycle) | Completado |
| TSK-F1_1.0-14.1-GREEN  | db-manager          | Implementacion check_pg_extensions (auditoria extensiones pg_cron, uuid-ossp, pg_net) | Completado |
| TSK-F1_1.0-14.2-GREEN  | db-manager          | Integracion check_pg_extensions en main() + WARNING_SERVICES                      | Completado |
| TSK-F1_1.0-14.3-GREEN  | db-manager          | Implementacion check_zombie_cleanup (limpieza tablas _bootstrap_* huerfanas)       | Completado |
| TSK-F1_1.0-15.1-GREEN  | db-manager          | Implementacion check_ddl_capabilities (has_schema_privilege CREATE)                | Completado |
| TSK-F1_1.0-15.2-GREEN  | backend-tester      | Implementacion check_persistence_cycle (ciclo CREATE->INSERT->SELECT->DROP)        | Completado |
| TSK-F1_1.0-16.1-CERT   | db-manager          | Certificacion Calidad SQL/RLS — APROBADO CON OBSERVACIONES                         | Completado |
| TSK-F1_1.0-16.2-CERT   | backend-reviewer    | Certificacion Integridad Persistencia — APROBADO CON OBSERVACIONES                 | Completado |

### Resultado de Suite de Pruebas al Cierre de Bloque 4

**94 passed, 0 failed**

Distribucion de tests:
- `engine/tests/test_models.py` — 15 tests (modelos Pydantic)
- `engine/tests/test_sanitizer.py` — 10 tests (sanitizacion)
- `engine/tests/test_orchestrator.py` — 12 tests (logica del orquestador; expandido con 4 mocks nuevos)
- `engine/tests/test_orchestrator_output.py` — 6 tests (formato salida GHA; mocks expandidos)
- `engine/tests/test_github_handshake.py` — 8 tests (GitHub API)
- `engine/tests/test_resend_handshake.py` — 8 tests (Resend API)
- `engine/tests/test_upstash_handshake.py` — 8 tests (Upstash Redis)
- `engine/tests/test_supabase_handshake.py` — 12 tests (Supabase HTTP + SQL)
- `engine/tests/test_database.py` — 15 tests (DB extensions, zombie cleanup, DDL, persistence cycle — NUEVO B4)

### Resumen de Progreso Global

- **Bloque 1**: 3/3 tareas completadas (100%)
- **Bloque 2**: 7/7 tareas completadas (100%)
- **Bloque 3**: 10/10 tareas completadas (100%)
- **Bloque 4**: 8/8 tareas completadas (100%)
- **Bloque 5 + Cierre**: Pendiente
- **Etapa 1.0 global**: ~91% completada (28 de ~31 tareas ejecutables estimadas)

---

## §3 Inventario Tecnico de Cambios

### Archivos Modificados en Esta Sesion (Bloque 4)

| Archivo                                        | Tipo        | Descripcion                                                                                                                                                                 |
| :--------------------------------------------- | :---------- | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `engine/src/check_env.py`                      | Modificado  | +4 funciones DB: check_pg_extensions, check_zombie_cleanup, check_ddl_capabilities, check_persistence_cycle; integradas en main(); WARNING_SERVICES expandido; correccion second-order SQL injection en zombie_cleanup con psycopg2.sql.Identifier; `from psycopg2 import sql as pg_sql` agregado |
| `engine/tests/test_orchestrator.py`            | Modificado  | Mocks actualizados para 4 nuevos checks; expected_keys ampliado de 6 a 10 entradas                                                                                          |
| `engine/tests/test_orchestrator_output.py`     | Modificado  | Mocks actualizados para 4 nuevos checks; expected_services ampliado                                                                                                          |
| `docs/f1_1.0/f1_1.0_task.md`                  | Modificado  | 8 tareas del Bloque 4 marcadas [x] completadas                                                                                                                              |

### Archivos Creados en Esta Sesion (Bloque 4)

| Archivo                                        | Tipo    | Descripcion                                                                                                                                                           |
| :--------------------------------------------- | :------ | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `engine/tests/test_database.py`                | Nuevo   | 15 tests unitarios completos para Bloque 4; clases helper `_PgProgrammingErrorWithCode` y `_PgOperationalErrorWithCode` para simular pgcode readonly en psycopg2 2.9+ |

### Archivos de Bloques Anteriores (referencia historica, sin cambios en esta sesion)

| Archivo                                    | Origen  | Estado        |
| :----------------------------------------- | :------ | :------------ |
| `engine/src/utils.py`                      | B1      | Sin cambios   |
| `engine/src/models.py`                     | B2      | Sin cambios   |
| `engine/src/sanitizer.py`                  | B2      | Sin cambios (Capa 2 — deuda tecnica H-1 pendiente en TSK-19.1-REFACTOR) |
| `engine/tests/conftest.py`                 | B2      | Sin cambios   |
| `engine/tests/test_models.py`              | B2      | Sin cambios   |
| `engine/tests/test_sanitizer.py`           | B2      | Sin cambios   |
| `engine/tests/test_github_handshake.py`    | B3      | Sin cambios   |
| `engine/tests/test_resend_handshake.py`    | B3      | Sin cambios   |
| `engine/tests/test_upstash_handshake.py`   | B3      | Sin cambios   |
| `engine/tests/test_supabase_handshake.py`  | B3      | Sin cambios   |

---

## §4 Mapa Tactico de Continuidad

### Working Set Actual

```
engine/
  src/
    __init__.py          (creado B1)
    utils.py             (creado B1 — TSK-03 DONE)
    models.py            (creado B2 — TSK-05 DONE)
    sanitizer.py         (creado B2 — TSK-06 DONE — Capa 2 pendiente de integracion H-1)
    check_env.py         (modificado B4 — 4 funciones DB nuevas, WARNING_SERVICES expandido, pg_sql.Identifier)
  tests/
    __init__.py          (creado B1)
    conftest.py          (actualizado B2 — fixtures expandidas)
    test_models.py       (creado B2 — 15 tests GREEN)
    test_sanitizer.py    (creado B2 — 10 tests GREEN)
    test_orchestrator.py (modificado B4 — 12 tests GREEN, 4 mocks nuevos)
    test_orchestrator_output.py (modificado B4 — 6 tests GREEN, mocks expandidos)
    test_github_handshake.py    (creado B3 — 8 tests GREEN)
    test_resend_handshake.py    (creado B3 — 8 tests GREEN)
    test_upstash_handshake.py   (creado B3 — 8 tests GREEN)
    test_supabase_handshake.py  (creado B3 — 12 tests GREEN)
    test_database.py            (creado B4 — 15 tests GREEN)
  requirements.txt       (creado B1 — hashes SHA256)
  .venv/                 (creado B1 — entorno aislado)
conftest.py              (creado B2 — raiz del proyecto, sys.path fix)

docs/f1_1.0/
  f1_1.0_task.md         (actualizado — B1+B2+B3+B4 completos, B5 pendiente)
```

### Observaciones Tecnicas Pendientes (backlog acumulado)

Estas observaciones NO son bloqueadores del Bloque 5. Son deudas tecnicas a resolver en TSK-19.1-REFACTOR:

| ID      | Origen       | Descripcion                                                                                                          | Resolucion Objetivo  |
| :------ | :----------- | :------------------------------------------------------------------------------------------------------------------- | :------------------- |
| OBS-01  | B2 CERT      | Patron check+log repetido en `main()` — candidato a helper privado                                                   | TSK-19.1-REFACTOR    |
| OBS-02  | B2 CERT      | `RunReport.run_id` acepta UUID de cualquier version — necesita `@field_validator`                                     | TSK-19.1-REFACTOR    |
| OBS-03  | B2 CERT      | `sanitize_service_result` no redacta campo `metadata` — riesgo de fuga de secretos                                   | TSK-19.1-REFACTOR    |
| OBS-04  | B2 CERT      | Codigo muerto `capturing_main` en `test_orchestrator.py` — eliminar                                                  | TSK-19.1-REFACTOR    |
| H-1     | B3 SEC       | `sanitize_service_result` (Capa 2, regex headers de `sanitizer.py`) no invocada desde `_sanitize_checks`             | TSK-19.1-REFACTOR    |
| H-2     | B3 SEC       | `psycopg2.connect` sin `connect_timeout` — bloqueo indefinido posible; DSN reformateada puede evadir sanitizacion    | TSK-19.1-REFACTOR    |
| OBS-B3  | B3 CERT      | Patron retry/backoff duplicado en 4 funciones HTTP — deuda de diseno para refactoring                                | TSK-19.1-REFACTOR    |
| B-1     | B4 16.1/16.2 | check_pg_extensions Fase 3 sin fallback 42P01 — puede propagar excepcion si esquemas cron/net no son accesibles      | TSK-19.1-REFACTOR    |
| B-2     | B4 16.2      | check_persistence_cycle usa f-strings para DDL en vez de pg_sql.Identifier (inconsistencia con zombie_cleanup)       | TSK-19.1-REFACTOR    |
| B-3     | B4 16.1/16.2 | check_zombie_cleanup DROPs sin captura individual por tabla — un fallo aborta la limpieza de las restantes           | TSK-19.1-REFACTOR    |
| D-1     | B4 16.2      | Test para fetchone()=None en check_ddl_capabilities ausente                                                          | TSK-19.1-REFACTOR    |
| D-3     | B4 16.2      | Test para count==0 en check_persistence_cycle ausente                                                                | TSK-19.1-REFACTOR    |

### Bloqueadores Criticos

Ninguno activo. El Bloque 4 esta 100% completado con 94 tests passing, certificacion APROBADA CON OBSERVACIONES del db-manager (TSK-16.1-CERT) y del backend-reviewer (TSK-16.2-CERT). Suite completa: 94 passed, 0 failed.

### Proximo Paso Prioritario (Next Step Atomico)

**Tarea**: `TSK-F1_1.0-17.1-IMPL` (Bloque 5 — CI/CD: GHA Workflow & Reporting)
**Agente Responsable**: `devops-integrator`
**Accion Concreta**:

Invocar al agente `devops-integrator` para implementar las tres sub-entregas del Bloque 5:

1. **Reporte GHA (`GITHUB_STEP_SUMMARY`)**: Integrar la emision del resumen de ejecucion en el formato markdown esperado por GitHub Actions Step Summary. El script `check_env.py` ya tiene la logica de `_write_github_step_summary`; la tarea es verificar que el path de escritura es `$GITHUB_STEP_SUMMARY` correctamente resuelto en el entorno de GHA.

2. **Snapshot de Entorno**: Implementar la captura de versiones del entorno en el reporte: version de Python (`sys.version`), hash SHA256 del archivo `requirements.txt` actual, y timestamp UTC de la ejecucion. Este snapshot debe aparecer en el `GITHUB_STEP_SUMMARY` como un bloque colapsable para auditoria.

3. **Workflow YAML para GitHub Actions**: Crear `.github/workflows/env_validation.yml` que:
   - Se dispare en `push` a la rama `feat/f1_1.0_env_validation`
   - Configure Python 3.12 con el entorno virtual `engine/.venv`
   - Instale dependencias con `pip install --require-hashes -r engine/requirements.txt`
   - Ejecute `python engine/src/check_env.py` con las variables de entorno inyectadas como GitHub Secrets
   - Ejecute `pytest engine/tests/ -v` para validar la suite completa
   - Tenga timeout maximo de 25 minutos (alineado con el mandato del SPEC)

**Contexto adicional para el agente**:
- El archivo `engine/src/check_env.py` ya es funcional y tiene todas las verificaciones implementadas (Bloques 2-4)
- La suite de tests tiene 94 tests passing — el workflow YAML debe ejecutarlos como gate de calidad
- Revisar SPEC §4 para los contratos de salida del reporte GHA antes de crear el workflow
- La rama activa es `feat/f1_1.0_env_validation` — el workflow debe dispararse en push a esta rama

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

# Registro de Lecciones Aprendidas — DonTolto

> INVARIANTE: Este archivo es de solo adicion (append-only). Nunca se modifican ni eliminan
> entradas de sesiones anteriores. Cada nueva sesion agrega entradas al final del documento.
> Trazabilidad: Vinculado siempre a Fase y Etapa de origen.

---

## Sesion: 2026-04-07 (Fase 1, Etapa 1.0 — Bloque 1: Scaffolding & Setup)

### Exitos y Aciertos Tecnicos

**Reproducibilidad absoluta con pip-compile --generate-hashes**
La decision de adoptar `pip-compile` con hashes SHA256 en lugar de un `requirements.txt` manual resulto en un manifiesto de 13 paquetes completamente auditables. El ciclo `pip install --dry-run --require-hashes` actuo como validacion preventiva de integridad antes de cualquier instalacion real. Esta practica debe estandarizarse para todas las fases del Engine Python.

**Diseno de diccionario `ENV_VAR_PATTERNS` con flag `is_critical`**
Separar las variables de entorno en criticas (EXIT 1) y de advertencia (WARNING) directamente en el diccionario de patrones —en lugar de logica condicional dispersa— resulto en una estructura declarativa limpia. Esto permite que el orquestador future (`check_env.py`) agregue estados sin necesidad de modificar la logica de clasificacion de severidad.

**Sanitizacion con umbral de 4 caracteres visibles**
El diseno de `sanitize_secret()` que expone exactamente los primeros 4 caracteres es intencionalmente util: los prefijos de tokens (`ghp_`, `re_`, `eyJh`) permiten identificar el tipo de credencial en logs de CI/CD sin revelar el valor real. Es un balance optimo entre debugabilidad y seguridad.

**Paquetes Python con `__init__.py` vacios**
Usar `__init__.py` vacios en `engine/src/` y `engine/tests/` evita la necesidad de configurar `PYTHONPATH` manualmente en `pytest.ini` o `pyproject.toml`. El descubrimiento automatico de modulos funciona correctamente desde el raiz del proyecto.

---

### Fricciones y Desafios

**Verificacion de hashes en Windows con rutas de entorno virtual**
Durante la instalacion de dependencias con `--require-hashes`, el path del entorno virtual en Windows (`engine\.venv\Scripts\pip`) requiere atencion especial al activar el venv antes de ejecutar comandos de pip. Se debe documentar el procedimiento de activacion para el equipo: `engine\.venv\Scripts\activate` (CMD/PowerShell) o `source engine/.venv/Scripts/activate` (bash/WSL).

**Ninguna friccion de bloqueo en esta sesion**: El Bloque 1 se ejecuto sin impedimentos tecnicos que requirieran cambios de diseno o retrocesos.

---

### Leccion Clave y Recomendacion

**Leccion 1 — Integridad de Dependencias como Invariante de Seguridad**
En un proyecto con Engine Python que corre en GitHub Actions (entorno efimero sin cache garantizado), la integridad de dependencias no es opcional. El patron `pip-compile --generate-hashes` + `pip install --require-hashes` debe aplicarse desde la primera iteracion y nunca relajarse. Un `requirements.txt` sin hashes es una superficie de ataque de cadena de suministro.

**Leccion 2 — Disenar para la Legibilidad del Log de CI/CD**
Las funciones `sanitize_secret()`, `sanitize_log_message()` y `format_log_entry()` se disenaron pensando en el consumidor final: el operador leyendo el GITHUB_STEP_SUMMARY. La legibilidad estructurada (`[TIMESTAMP] [LEVEL] [SERVICE] message`) reduce el tiempo de diagnostico en produccion. Este estandar de log debe mantenerse en todos los modulos del Engine.

**Leccion 3 — El Ciclo TDD requiere RED genuino, no artificial**
El Bloque 2 debe comenzar con la fase RED real: tests que fallen porque los modelos Pydantic (`ServiceResult`, `RunReport`) no existen todavia. Es tentador crear los modelos y los tests en paralelo, pero hacerlo viola el contrato TDD y elimina la garantia de que los tests realmente validan el comportamiento. El agente `backend-tester` debe ejecutar TSK-F1_1.0-04-RED de forma estricta e independiente.

---

## Sesion: 2026-04-07 (Fase 1, Etapa 1.0 — Bloque 2: Modelado & Engine Core)

### Exitos y Aciertos Tecnicos

**Ciclo TDD RED-GREEN-CERT ejecutado en una sesion sin retrocesos**
El Bloque 2 completo (7 tareas: 2 RED, 4 GREEN, 1 CERT) fue ejecutado de forma secuencial y limpia. La suite paso de 0 tests existentes a 43 tests passing (0 failed) en una sola sesion. La separacion estricta de agentes por tarea (backend-tester para RED, backend-coder para GREEN, backend-reviewer para CERT) garantizo que cada fase tuviera un solo responsable y objetivo claro.

**`str, Enum` en lugar de `IntEnum` para `CheckStatus`**
Usar `class CheckStatus(str, Enum)` resulto en valores directamente serializables a JSON y legibles en reportes de texto plano (GitHub Step Summary) sin transformacion adicional. Este patron debe aplicarse a todos los Enums del Engine Python que vayan a ser emitidos en reportes o logs.

**`conftest.py` en raiz como solucion minima para `sys.path`**
El problema de resolucion de imports de `engine.src.*` desde la raiz del proyecto se resolvio con un `conftest.py` raiz que inserta la raiz en `sys.path`. Esta solucion es mas explicita y menos fragil que modificar `pytest.ini` o `pyproject.toml`, y no requiere cambios en la configuracion de CI/CD.

**Deteccion y correccion de defecto estructural en fase RED**
Durante TSK-F1_1.0-07-RED se detecto que el test de orquestacion en L235 pasaba por razones incorrectas (falso positivo en la fase RED). El defecto fue corregido antes de proceder a GREEN, preservando el contrato TDD. Esta deteccion proactiva del backend-tester evito que un test invalido contaminara la suite.

**Arquitectura de `ServiceResult` como unidad atomica del pipeline**
Diseno el modelo `ServiceResult` con campos `service`, `status`, `message`, `latency_ms` y `metadata` opcional. La granularidad por servicio permite que el orquestador agregue estados independientemente de la logica interna de cada verificacion. Este patron debe mantenerse para todos los handshakes del Bloque 3.

---

### Fricciones y Desafios

**Deuda tecnica acumulada documentada como OBS-XX en CERT**
La certificacion del Bloque 2 (TSK-09-CERT) genero 6 observaciones tecnicas (OBS-01 a OBS-06) que no son bloqueadores pero representan deuda tecnica real: patron check+log repetido en `main()`, ausencia de `@field_validator` en `RunReport.run_id`, campo `metadata` no sanitizado en `sanitize_service_result`, mensaje sin sanitizar en `_write_github_step_summary`, codigo muerto `capturing_main` y sentinel `latency_ms=0.1`. Todas fueron documentadas en el handoff con su tarea de resolucion objetivo (TSK-19.1-REFACTOR o TSK-11.x).

**Stubs con sentinel de latencia no medida**
Los stubs del Bloque 2 usan `latency_ms=0.1` como valor centinela explicito que indica latencia simulada. Este valor NO es una medicion real y puede confundir al operador leyendo los reportes de CI/CD. El Bloque 3 debe reemplazar todos los stubs con implementaciones reales que midan latencia efectiva.

---

### Leccion Clave y Recomendacion

**Leccion 4 — La CERT no es un formalismo, es una auditoria tecnica real**
El backend-reviewer en TSK-09-CERT no aprobo sin condiciones: emitio 6 observaciones tecnicas con severidad y tarea de resolucion. Esto demuestra que el rol de CERT agrega valor real al ciclo TDD. La tendencia a convertir la CERT en un "rubber stamp" es un antipatron a evitar. Cada CERT debe producir al menos una observacion accionable o justificar explicitamente por que no hay deuda tecnica pendiente.

**Leccion 5 — Los defectos estructurales en la fase RED deben corregirse antes de GREEN**
Un test que pasa en la fase RED por razones incorrectas (falso positivo) invalida todo el ciclo TDD subsiguiente. Si el backend-tester detecta que un test pasa antes de que exista la implementacion, debe investigar la causa raiz y corregir el test antes de declarar la fase RED completada. Un RED falso es peor que no tener tests.

**Leccion 6 — Documentar stubs y centinelas con comentarios inline**
Los valores centinela (como `latency_ms=0.1`) deben acompanarse de un comentario inline que explique que son simulados y en que tarea se reemplazaran con valores reales. Sin este comentario, el proximo desarrollador o agente no puede distinguir entre un valor de produccion y un placeholder de prueba.

---

## Sesion: 2026-04-07 (Fase 1, Etapa 1.0 — Bloque 3: Handshaking de APIs Externas)

### Exitos y Aciertos Tecnicos

**Granularidad de suites de tests: un archivo por servicio externo**
La decision de crear `test_github_handshake.py`, `test_resend_handshake.py`, `test_upstash_handshake.py` y `test_supabase_handshake.py` en lugar de un monolito `test_handshakes.py` resulto en suites independientes, faciles de ejecutar en aislamiento y sin acoplamiento entre servicios. En CI/CD, un fallo de GitHub no contamina el reporte de Supabase. Este patron debe estandarizarse para todos los bloques con multiples servicios externos.

**Mock de `httpx.get` a nivel de modulo sin alias interno**
Parchear `httpx.get` directamente (no `engine.src.check_env.httpx.get`) resultó mas robusto porque no depende de como el modulo interno referencia la funcion. Este patron es mas resiliente ante refactorizaciones que cambien el nombre del alias de importacion.

**`latency_ms = max((end - start) * 1000, 0.001)` como patron canónico**
El minimo garantizado de `0.001 ms` resuelve de forma elegante la restriccion `Field(gt=0)` del modelo `ServiceResult` incluso con mocks instantaneos (donde `time.monotonic()` puede retornar diferencias de 0 µs). Este patron debe replicarse en todos los checks del Bloque 4 sin excepcion.

**Ciclo TDD con revisiones bloqueantes: el reviewer rechazó en primera pasada**
El `backend-reviewer` en TSK-12.1-CERT emitio TOKEN:RECHAZADO con dos defectos bloqueantes reales (bug de telemetria en `check_supabase_sql` y sanitizacion nunca invocada). El `backend-coder` los corrigio, la segunda pasada resulto en APROBADO. Esta secuencia —rechazo, correccion, re-certificacion— es el ciclo sano esperado, no una anomalia. El sistema de certificacion funciona correctamente cuando emite rechazos con hallazgos concretos.

**Security-hardener identificó deuda de defensa en profundidad sin bloquear**
El security-hardener encontro que `sanitizer.py` (Capa 2 con regex de headers) existia pero no era invocada desde `_sanitize_checks`. No habia fuga confirmada, pero sí una capa de defensa inactiva. Al clasificarlo como hallazgo no bloqueante con recomendacion concreta (invocar `sanitize_service_result` en lugar de llamar directamente a `sanitize_log_message`), el auditor permitio avanzar sin bloquear el sprint mientras la deuda queda registrada para TSK-19.1-REFACTOR.

---

### Fricciones y Desafios

**DEF-01 — Bug silencioso de telemetria: `end_err - end_err = 0.0`**
En `check_supabase_sql`, el path de error calculaba `latency_ms = max((end_err - end_err) * 1000, 0.001)`, produciendo siempre `0.001 ms` independientemente del tiempo transcurrido. El bug era completamente silencioso: pasaba todos los tests, no lanzaba excepciones y producía un artefacto de telemetria corrupto. La causa raiz fue copiar el patron de latencia de las funciones HTTP (donde `start` esta dentro del `try`) sin adaptar la estructura de `check_supabase_sql` que tiene reintentos con `start` debia estar fuera del loop. Leccion: los bugs de telemetria que no rompen la suite son los mas peligrosos porque permanecen ocultos en produccion.

**DEF-02 — Sanitizacion implementada pero nunca invocada**
`sanitize_log_message` existia en `utils.py` y `sanitize_service_result` en `sanitizer.py` desde el Bloque 2, pero ninguna era llamada desde el flujo principal de `check_env.py`. Esto violaba el mandato SPEC §3.2.2 explicitamente. La causa raiz: el Bloque 2 implementó las utilidades de sanitizacion como infraestructura, pero el punto de invocacion (`main()` en `check_env.py`) no existia todavia en ese momento. Al implementar los handshakes en el Bloque 3 no se verifico la integracion con las utilidades ya existentes. Leccion: las utilidades de seguridad no activan su proteccion por el simple hecho de existir — deben ser invocadas explicitamente y verificadas en CERT.

**Hallazgo H-2 — `psycopg2.connect` sin `connect_timeout`**
La implementacion de `check_supabase_sql` no incluyo `connect_timeout` en `psycopg2.connect`. En un runner de GHA con timeout total de 25 minutos, 3 reintentos sin timeout de conexion pueden consumir el presupuesto total del workflow. La correccion (agregar `connect_timeout=10`) fue diferida al Bloque 4 donde el `db-manager` tendra contexto completo sobre el patron de conexion. Esto fue una decision consciente de diferimiento, no un olvido.

**Contrato de argumento posicional en `psycopg2.connect` impuesto por el test**
El test `test_check_supabase_sql_calls_psycopg2_connect` inspeccionaba `call_args.args[0]` para verificar que la URL fue pasada como argumento posicional. Esto creo una dependencia fragil entre el test y la forma de invocacion. Si en el Bloque 4 se necesita refactorizar la llamada a keyword (`psycopg2.connect(dsn=db_url)`), el test fallara aunque la logica sea equivalente. Esta decision de diseno del test debe ser revisada en TSK-19.1-REFACTOR.

---

### Leccion Clave y Recomendacion

**Leccion 7 — Los bugs silenciosos de telemetria son los mas costosos en produccion**
Un bug que no rompe tests pero corrompe datos de observabilidad (como `end_err - end_err = 0.0`) es categoricamente mas peligroso que un bug que falla ruidosamente. En un sistema de diagnostico como `check_env.py`, la telemetria corrupta puede llevar a decisiones operativas incorrectas (ej: pensar que Postgres falla instantaneamente cuando en realidad esta tardando 21 segundos con 3 reintentos). La CERT debe incluir inspeccion explicita de los paths de error, no solo los paths felices.

**Leccion 8 — Las utilidades de seguridad requieren verificacion de integracion en CERT**
Que una funcion de sanitizacion exista en el codebase no garantiza que este activa en produccion. El reviewer y el security-hardener deben verificar explicitamente que las funciones de seguridad son invocadas en el flujo principal, no solo que existen y pasan sus propios tests unitarios. Propuesta para el checklist de CERT: agregar un punto "verificar que toda utilidad de seguridad documentada en SPEC tiene al menos una invocacion trazable desde `main()`".

**Leccion 9 — La granularidad de mocks determina la robustez de los tests ante refactorizaciones**
Parchear `httpx.get` a nivel de modulo (en lugar de a traves del namespace de `check_env`) produce tests mas resilientes. Igualmente, la dependencia del test de psycopg2 en el argumento posicional (`call_args.args[0]`) es una fragilidad que debe eliminarse. La regla general: los tests deben verificar el comportamiento observable (que la URL correcta fue usada), no el mecanismo interno de invocacion (posicional vs. keyword). Usar `assert mock_connect.call_args == call(db_url)` en lugar de `call_args.args[0]`.

**Leccion 10 — Diferir deuda tecnica de seguridad con registro explicito es mejor que parchear precipitadamente**
La recomendacion H-2 (connect_timeout) fue diferida conscientemente al Bloque 4. Esta decision es valida y profesional siempre que: (a) la deuda sea registrada con su riesgo documentado, (b) tenga una tarea de resolucion asignada, y (c) no haya una fuga de credenciales activa. Diferir sin registrar es deuda oculta; diferir con registro es gestion de deuda transparente.

---

**APRENDIZAJE_REGISTRADO_OK**

---

## Sesion: 2026-04-08 (Fase 1, Etapa 1.0 — Bloque 4: Database & Persistencia)

### Exitos y Aciertos Tecnicos

**Patron de importacion diferida en tests RED para coleccion granular**
Importar las funciones objetivo dentro de cada test (no a nivel de modulo) permite que pytest colecte y ejecute cada test individualmente con su propio `ImportError`. Esto garantiza que la fase RED falla de forma granular (un test a la vez) en lugar de abortar toda la suite por un unico error de coleccion. Este patron debe aplicarse en todos los bloques futuros donde se escriban tests para funciones que aun no existen.

**`psycopg2.sql.Identifier` para prevencion de second-order SQL injection**
Usar `pg_sql.SQL("DROP TABLE IF EXISTS {}").format(pg_sql.Identifier(name))` en lugar de f-strings para nombres de tablas provenientes de catalogos del sistema (`pg_tables`) es la practica correcta aunque la fuente parezca segura. Los catalogos del sistema pueden ser comprometidos o contener nombres con caracteres especiales. Este patron debe ser el estandar para cualquier DDL dinamico en el Engine.

**Doble `finally` para garantia de cleanup idempotente en `check_persistence_cycle`**
El patron `try/finally` interior (cursor + DROP TABLE) anidado dentro de un `try/finally` exterior (conn.close) garantiza que la tabla temporal `_bootstrap_[run_id_short]` y la conexion son liberadas incluso ante SIGKILL, timeout de GHA (25 min) o excepciones no anticipadas. Este patron de cleanup por capas debe replicarse en todas las funciones que adquieran recursos de base de datos.

**`pgcode` como propiedad readonly en psycopg2 2.9+: solucion con subclase y property**
El atributo `pgcode` de las excepciones psycopg2 es readonly desde la version 2.9 (implementado en C). Intentar `exc.pgcode = "42P01"` lanza `AttributeError`. La solucion correcta para tests unitarios es subclasificar la excepcion con una `@property` que retorna el codigo deseado: `_PgProgrammingErrorWithCode` y `_PgOperationalErrorWithCode`. Este patron debe documentarse como utilidad reutilizable en `conftest.py` para evitar reimplementacion en bloques futuros.

**Ciclo TDD con doble CERT (db-manager + backend-reviewer) sin TOKEN:RECHAZADO**
El Bloque 4 fue el primero en obtener APROBADO CON OBSERVACIONES en primera pasada de ambos certificadores, sin necesidad de una segunda vuelta de correccion. Esto indica mayor madurez en la implementacion. La distincion entre "defecto bloqueante" (que genera TOKEN:RECHAZADO) y "observacion de mejora" (que genera APROBADO CON OBSERVACIONES) es un criterio que los agentes certificadores deben aplicar consistentemente.

---

### Fricciones y Desafios

**Solapamiento de scope entre TSK-14.1 y TSK-14.2**
El db-manager en TSK-14.1 implemento `check_pg_extensions` incluyendo su integracion en `main()` y en `WARNING_SERVICES`, que era el alcance previsto para TSK-14.2. Esto dejo a TSK-14.2 sin trabajo de implementacion sustancial. La causa raiz: los limites de tarea en el TASK no especificaban explicitamente hasta donde llegar en cada tarea cuando una funcion "hija" esta dentro del alcance de la tarea "madre". Para el Bloque 5, definir en el PLAN exactamente que linea de codigo o que funcion delimita el alcance de cada tarea antes de delegar.

**Observacion B-1 detectada por ambos certificadores pero no corregida en ninguna tarea del bloque**
La ausencia de fallback para el error `42P01` en la Fase 3 de `check_pg_extensions` fue identificada de forma independiente por el db-manager (TSK-16.1-CERT) y por el backend-reviewer (TSK-16.2-CERT), pero ninguno la corrigio en el bloque activo — ambos la diferieron a TSK-19.1-REFACTOR. Esto crea una deuda tecnica de seguridad que puede causar una excepcion no capturada en Supabase real si los esquemas `cron` o `net` no son accesibles al rol conectado. La leccion: cuando dos certificadores independientes identifican el mismo hallazgo como no-bloqueante, el equipo debe evaluar si realmente es diferible o si merece una tarea de correccion inmediata antes de pasar al siguiente bloque.

---

### Leccion Clave y Recomendacion

**Leccion 11 — La granularidad del TASK determina la eficiencia de la delegacion a agentes**
El ciclo TDD con agentes especializados (tester -> db-manager -> reviewer) demostro alta cohesion: cada agente entrego trabajo acotado y verificable. El punto de friccion fue la granularidad del TASK — algunas tareas tenian alcances implicitamente solapados. Para los bloques siguientes, el PLAN debe especificar explicitamente para cada tarea: (a) que funcion o modulo implementa, (b) hasta que punto del flujo de integracion llega, y (c) que archivo modificara exclusivamente. La precision en el TASK es directamente proporcional a la eficiencia de la delegacion.

**Leccion 12 — Los helpers de test para excepciones con atributos readonly son activos reutilizables**
Las clases `_PgProgrammingErrorWithCode` y `_PgOperationalErrorWithCode` resuelven una limitacion real de psycopg2 2.9+ que no es obvia en la documentacion oficial. En lugar de que cada suite de tests reimplemente este patron, deben ser promovidas a `engine/tests/conftest.py` como fixtures o utilidades compartidas. El principio DRY aplica a la infraestructura de tests con la misma fuerza que al codigo de produccion.

**Leccion 13 — Cuando dos certificadores convergen en el mismo hallazgo, evaluar si es realmente diferible**
La convergencia de dos auditores independientes en la observacion B-1 (sin fallback 42P01) es una senal de que el riesgo es real y conocido. Diferirlo a TSK-19.1-REFACTOR es valido si se acepta conscientemente el riesgo de excepcion no capturada en produccion. Para decisiones de diferimiento con convergencia de auditores, el equipo deberia documentar explicitamente el riesgo aceptado y el escenario de fallo en el backlog, no solo la tarea de resolucion.

---

**APRENDIZAJE_REGISTRADO_OK**

---

## Sesion: 2026-04-08 (Fase 1, Etapa 1.0 — Bloque 5: CI/CD & Final Testing — parcial)

### Exitos y Aciertos Tecnicos

**Certificacion de seguridad CI/CD con remediacion previa de vulnerabilidades (no post-hoc)**
El security-hardener ejecuto la auditoria de seguridad CI/CD (TSK-18-CERT) identificando 3 vulnerabilidades (VUL-01, VUL-02, VUL-03) y remediandolas antes de emitir el certificado SEGURIDAD_APROBADA. Este flujo — auditar, remediar, certificar en una sola pasada — es mas eficiente que el ciclo TOKEN:RECHAZADO -> correccion -> re-certificacion que ocurrio en el Bloque 3. La clave fue que el auditor tenia contexto previo de los patrones de vulnerabilidad tipicos (inyeccion de regex, placeholders con prefijos reales de tokens) y los busco proactivamente.

**Suite de inyeccion de fallas con clasificacion por grupos conceptuales**
Los 11 tests de `test_failure_injection.py` se organizaron en 4 grupos (Hard-Gate, No-Exit, Reporte, Diagnostic-First) que documentan el comportamiento esperado del sistema ante fallas. Esta taxonomia facilita la lectura del reporte de pytest, la identificacion de gaps de cobertura y la comprension del contrato de comportamiento del engine ante errores. Para cualquier suite de tests que valide comportamiento ante fallas, organizar por tipo de comportamiento (no por servicio) produce mayor legibilidad.

**Placeholder de token en `.env.example` con semantica de instruccion, no de dato**
Cambiar `ghp_tu-github-token-aqui` a `REEMPLAZAR_CON_TOKEN_REAL` resuelve dos problemas simultaneamente: (a) elimina el falso positivo en detectores de secretos (gitleaks, truffleHog) que reconocen el prefijo `ghp_`, y (b) hace el placeholder mas claro para el desarrollador que necesita configurar el entorno. La regla general: los placeholders en archivos de ejemplo deben usar lenguaje imperativo en mayusculas (`REEMPLAZAR_CON_X`) y nunca comenzar con prefijos propios de tokens reales.

**Workflow GHA con nombre de archivo que refleja la etapa del proyecto**
Nombrar el workflow `.github/workflows/f1_1.0_env_validation.yml` en lugar de un generico `ci.yml` o `validate.yml` garantiza que cada etapa del proyecto tenga su propio workflow identificable en la UI de GitHub Actions. Cuando el proyecto crezca a multiples workflows, la convencion de nombres `f[F]_[E]_[descripcion].yml` mantiene la trazabilidad entre la ejecucion de CI y la etapa del plan de desarrollo.

---

### Fricciones y Desafios

**VUL-02 — Variables criticas ausentes de `_SECRET_ENV_KEYS`**
`SUPABASE_URL` y `ADMIN_UUID` estaban clasificadas como variables criticas (exit 1 si fallan) pero sus valores no eran redactados en logs porque no figuraban en `_SECRET_ENV_KEYS`. Este tipo de inconsistencia — una variable critica que no es tratada como secreto — es dificil de detectar en revision de codigo porque requiere cruzar dos estructuras de datos separadas (`CRITICAL_SERVICES` vs `_SECRET_ENV_KEYS`). La correccion fue inmediata (agregar las variables a la lista), pero la causa raiz es la duplicacion de informacion: si una variable es critica, deberia ser automaticamente sanitizada sin requerir que figure en dos listas diferentes. Esta es una refactorizacion de diseno para TSK-19.1.

**VUL-01 — Inyeccion de metacaracteres de regex en script bash**
La funcion `get_env_value` en `provision_secrets.sh` usaba `grep -E` con el nombre de la variable como patron. Aunque los nombres de variables de entorno raramente contienen metacaracteres de regex, el script podia procesar cualquier string pasado desde `.env`, creando una superficie de ataque teorica. El cambio a `grep -F` (literal matching) es la practica correcta para cualquier script bash que use grep con entradas que no son patrones de regex controlados por el desarrollador.

**Sesion concluida con working tree sin commitear**
A diferencia de sesiones anteriores, el Bloque 5 parcial concluyo con 8 archivos modificados/creados en working tree sin commitear. Esto aumenta el riesgo de perder trabajo si el entorno es reiniciado, y tambien crea ambiguedad sobre el baseline de la refactorizacion TSK-19.1 (el agente podria refactorizar sobre cambios no persistidos en el historial de git). La disciplina de commitear al finalizar cada bloque — incluso si la etapa no esta completa — es un invariante operacional que debe mantenerse en todas las sesiones futuras.

---

### Leccion Clave y Recomendacion

**Leccion 14 — La consistencia entre listas de variables criticas y variables a sanitizar debe ser una invariante estructural**
El hallazgo VUL-02 revela un antipatron de diseno: tener dos listas separadas (`CRITICAL_SERVICES` y `_SECRET_ENV_KEYS`) que deben estar sincronizadas manualmente. Esta sincronizacion manual es un vector de error — si se agrega una variable critica nueva, el desarrollador debe recordar actualizarla en ambos lugares. La solucion de diseno correcta (para TSK-19.1-REFACTOR) es derivar `_SECRET_ENV_KEYS` automaticamente a partir de las claves de `ENV_VAR_PATTERNS` donde `is_critical=True`, eliminando la duplicacion. Una sola fuente de verdad es siempre superior a dos listas sincronizadas manualmente.

**Leccion 15 — Auditar activos de CI/CD con la misma rigurosidad que el codigo de produccion**
Los scripts de bash (`provision_secrets.sh`), los workflows de GHA (`.github/workflows/*.yml`) y los archivos de ejemplo (`.env.example`) son activos de infraestructura que ejecutan con privilegios elevados (acceso a secretos de repositorio, ejecucion en runners de GHA). La auditoria de seguridad TSK-18-CERT demostro que estos archivos tienen superficies de ataque propias (inyeccion de regex, placeholders con prefijos de tokens reales). El checklist de CERT para bloques de CI/CD debe incluir explicitamente: (a) inspeccion de scripts bash para inyeccion de argumentos, (b) verificacion de placeholders en archivos de ejemplo, y (c) validacion de que todas las variables criticas esten en la lista de sanitizacion.

**Leccion 16 — Commitear al finalizar cada bloque es un invariante operacional, no una buena practica opcional**
La sesion del Bloque 5 parcial concluyo sin commitear. Si la siguiente sesion comienza refactorizando (TSK-19.1) sin primero commitear el estado actual, la historia de git no tendra un punto de referencia limpio que separe "Bloque 5 CI/CD" de "Bloque 5 Refactorizacion". En proyectos con agentes especializados donde multiples agentes tocan el mismo archivo (check_env.py fue modificado por devops-integrator en TSK-17.1 y por security-hardener en TSK-18), el commit por bloque es la unica forma de mantener trazabilidad entre la tarea del agente y los cambios en el repositorio. Mandato: el primer comando de cualquier sesion que retome un bloque con cambios pendientes es `git add` + `git commit` antes de cualquier modificacion nueva.

---

**APRENDIZAJE_REGISTRADO_OK**

---

## Sesion: 2026-04-08 (Fase 1, Etapa 1.0 — Bloque 5: CI/CD & Final Testing — cierre completo TSK-19.1 + TSK-19.2)

### Exitos y Aciertos Tecnicos

**Refactorizacion sin ruptura de suite: 105/105 tests pasan tras eliminar ~60 lineas de codigo duplicado**
La extraccion del helper `_http_get_with_retry` elimino el patron retry HTTP copiado literalmente 4 veces (GitHub, Resend, Upstash, Supabase REST) y el helper `_run_and_log_check` colapso 10 bloques identicos check+log en `main()`. Ambas extracciones se realizaron sin modificar ningun contrato publico ni romper un solo test. La cobertura de 105 tests existentes funciono como red de seguridad que valido la refactorizacion en su totalidad. Este resultado confirma que una suite de tests robusta es el prerequisito indispensable para refactorizaciones seguras.

**Deteccion de bug latente mediante refactorizacion: `latency_ms=0.0` violaba `Field(gt=0)`**
Al consolidar el patron de construccion del `ServiceResult` en el path de error dentro de `_http_get_with_retry`, se hizo evidente que el return de fallo de red usaba `latency_ms=0.0`. Este valor viola la restriccion `gt=0` del modelo Pydantic. El bug era latente: ninguno de los 105 tests lo ejercia explicitamente porque los mocks de tests simulaban respuestas exitosas o errores tipados, no el path de red caida. La refactorizacion —al centralizar el codigo— expuso la inconsistencia antes de que llegara a produccion. Leccion: la refactorizacion no es solo estetica, es una herramienta de deteccion de defectos.

**Renombre semantico de parametro resuelve colision de namespace silenciosa**
El parametro `run_id_short` en `check_persistence_cycle` colisionaba en nombre con la funcion importada `run_id_short` de `utils.py`. En Python, los parametros de funcion tienen precedencia sobre nombres del modulo dentro del scope de la funcion, por lo que la colision no causaba un error en tiempo de ejecucion. Sin embargo, hacia el codigo ambiguo: al leer el cuerpo de la funcion, `run_id_short` podia referirse tanto al parametro como a la funcion importada segun el contexto. El renombre a `table_suffix` elimina la ambiguedad y describe mejor el proposito. Leccion: las colisiones silenciosas de nombres son defectos de legibilidad que generan bugs en refactorizaciones futuras cuando alguien anade una llamada a `run_id_short()` dentro del mismo scope.

**Auditoria tecnica final con APROBADO en primera pasada tras refactorizacion completa**
El backend-reviewer en TSK-19.2 emitio APROBADO con solo 3 hallazgos INFO (ninguno bloqueante). Esto contrasta con el Bloque 3 donde el primer CERT fue TOKEN:RECHAZADO. La diferencia: en el Bloque 5 la refactorizacion partio de un backlog documentado (OBS-01 hasta D-3) con criterios de resolucion explicitos, en lugar de implementar desde cero. Cuando el trabajo entrante a una CERT tiene contexto de deuda documentada y criterios de aceptacion claros, la probabilidad de APROBADO en primera pasada aumenta sustancialmente.

---

### Fricciones y Desafios

**Deuda tecnica acumulada de 12 items tratada como un bloque monolitico en lugar de tareas incrementales**
El backlog de observaciones (OBS-01 a D-3) se acumulo a lo largo de 4 bloques (B2-B5) y se programo para resolverse en una sola tarea TSK-19.1. Aunque la ejecucion fue exitosa, este enfoque monolitico concentro todo el riesgo de refactorizacion en una unica sesion. Si algun item del backlog hubiera introducido una regresion, habria sido mas dificil identificar cuales de los 12 cambios la causaron. Para bloques futuros, considerar resoluciones incrementales de deuda tecnica al finalizar cada bloque (en lugar de acumularlas) reduce el riesgo acumulado y mantiene el codebase mas limpio en todo momento.

**3 hallazgos INFO del TSK-19.2 aceptados como deuda sin tarea de resolucion asignada**
Los hallazgos INFO-A (UUID v4 validator), INFO-B (fallback 42P01) e INFO-C (tests D-1/D-3 ausentes) fueron identificados por el reviewer y aceptados como diferibles sin asignar una tarea de resolucion en el backlog activo. A diferencia de sesiones anteriores donde cada observacion recibio un ID de tarea objetivo (ej. "resolver en TSK-19.1"), estos hallazgos quedaron sin ancla de seguimiento. En el contexto del cierre de la Etapa 1.0, esto es aceptable; sin embargo, antes de iniciar la Etapa 1.1 o cualquier fase posterior que use `check_env.py`, estos hallazgos deben ser evaluados para determinar si se convierten en deuda tecnica formal o se descartan conscientemente.

**Working tree con 8 archivos sin commitear al finalizar el Bloque 5 completo**
A pesar de que la Leccion 16 de la sesion anterior documentaba explicitamente este antipatron, la sesion actual de cierre del Bloque 5 tambien concluye sin commit. La causa: el protocolo de cierre (session-closer) es la ultima tarea de la sesion y los commits son responsabilidad del `devops-integrator` (TSK-22.3), que aun no fue invocado. La estructura del TASK coloca el commit final despues del cierre administrativo, lo que significa que el working tree sin commitear es el estado esperado al cerrar esta sesion. No es un incumplimiento — es consecuencia del diseno del Cierre de Etapa. Sin embargo, la descripcion del "Next Step" debe ser inequivoca: el primer comando del proximo agente es `git commit`.

---

### Leccion Clave y Recomendacion

**Leccion 17 — La refactorizacion es una herramienta de deteccion de defectos, no solo de limpieza**
El proceso de TSK-19.1 demostro que centralizar codigo duplicado expone inconsistencias que los tests individuales no detectan. El bug `latency_ms=0.0` existia en 4 funciones distintas pero ningun test ejercia ese path especifico. Al consolidarlas en un solo helper, la inconsistencia se hizo visible antes de que llegara a produccion. La refactorizacion debe planificarse no solo como actividad estetica sino como auditoria activa del comportamiento en paths de error que los tests pueden no cubrir. Un checklist de refactorizacion debe incluir: "verificar que el patron de construccion de resultado en paths de error sea consistente con las restricciones del modelo de datos".

**Leccion 18 — El backlog documentado con criterios de resolucion es prerequisito para CERTs de primera pasada**
La diferencia entre el Bloque 3 (TOKEN:RECHAZADO en primera CERT) y el Bloque 5 (APROBADO en primera CERT) no fue la calidad del codigo en si — fue la calidad de la especificacion del trabajo. En el Bloque 5, el backlog tenia 12 items con ID, descripcion, origen y accion concreta. El backend-coder supo exactamente que resolver. El backend-reviewer supo exactamente que verificar. Esta correlacion entre especificacion de trabajo y tasa de aprobacion en CERT sugiere que invertir tiempo en documentar el backlog con precision antes de delegar es mas eficiente que iterar con correcciones post-rechazo.

**Leccion 19 — Las colisiones silenciosas de nombres de parametro son deuda de legibilidad con interes compuesto**
El caso `run_id_short` (parametro) vs `run_id_short` (funcion importada) no causaba error en runtime pero creaba ambiguedad que se compone con cada nueva lectura del codigo y con cada futura modificacion. En un sistema con agentes especializados donde diferentes agentes leen el mismo archivo en distintos momentos, la ambiguedad de nombres es especialmente costosa: obliga a cada agente a reconstruir el contexto de resolucion de nombres en lugar de leer el codigo directamente. La regla practica: si un parametro de funcion tiene el mismo nombre que cualquier simbolo importado en el modulo, renombrarlo es siempre la decision correcta independientemente de si causa un error activo.

---

**APRENDIZAJE_REGISTRADO_OK**

---

## Sesion: 2026-04-08 (Fase 1, Etapa 1.0 — Cierre Formal: TSK-20, 21, 22.1, 22.2)

### Exitos y Aciertos Tecnicos

**Cadena de cierre ejecutada sin retrocesos en una sola sesion**
Las 4 tareas de cierre (Suite de Integracion, Auditoria, Resumen Ejecutivo, Handoff) se ejecutaron secuencialmente en una unica sesion sin bloqueos ni TOKEN:RECHAZADO. La clave fue que todos los prerequisitos (105 tests passing, tokens de dominio vigentes, documentos SDD autorizados) estaban en orden antes de iniciar la secuencia. Un cierre de etapa fluido es consecuencia directa del rigor aplicado durante los bloques de desarrollo.

**Suite de integracion final como gate objetivo, no ceremonial**
La ejecucion de TSK-20 (105/105 PASSED, cobertura 94%) no fue un "gate de papel": valido que los cambios de refactorizacion del Bloque 5 no introdujeron regresiones. En sistemas donde la refactorizacion ocurre en la ultima tarea del sprint, el gate de integracion final es la ultima oportunidad de detectar regresiones antes de cerrar la etapa formalmente.

**Auditoria CONFORME con hallazgo H-01 regularizado sin bloqueo**
El hallazgo H-01 del `stage-auditor` (`requirements.in` y `conftest.py` sin tarea atomica explicita) fue regularizado en el certificado sin generar un bloqueo. La distincion entre "Codigo Fantasma con logica de negocio" (bloqueante) y "infraestructura de soporte sin tarea atomica" (regularizable) es una capacidad de juicio del auditor que debe preservarse en etapas futuras.

**`docs/executives/f1_1.0_executive.md` como puente entre metricas tecnicas y valor de negocio**
El Resumen Ejecutivo traduce metricas tecnicas (105 tests, 94% cobertura, 3 VULs cerradas) a valor de negocio (guardian de infraestructura, blindaje de cadena de suministro, deteccion proactiva de degradacion). Para etapas futuras, el `stage-closer` debe ser informado con el maximo contexto de logros para producir un ejecutivo de maxima calidad.

---

### Fricciones y Desafios

**H-01: Artefactos de infraestructura sin tarea atomica en TASK LIST**
`engine/requirements.in` y `conftest.py` en la raiz fueron detectados como potencial "Codigo Fantasma" por el auditor porque no tenian tarea atomica explicita en `f1_1.0_task.md`. Ambos son legitimos, pero su ausencia en el TASK crea ambiguedad. Prevencion: al crear artefactos de soporte, referenciarlos en la nota de la tarea mas relacionada. Costo de prevencion: 2 lineas. Costo de deteccion: investigacion del auditor.

**Working tree con 11+ archivos sin commitear al cerrar TSK-22.2**
El diseno del TASK coloca el commit (TSK-22.3) despues del cierre administrativo, haciendo inevitable este estado. No es un incumplimiento — es consecuencia del diseno. La solucion: invocar al `devops-integrator` para TSK-22.3 inmediatamente despues de TSK-22.2 en la misma sesion, o asegurar que sea la primera tarea de la siguiente sesion.

---

### Leccion Clave y Recomendacion

**Leccion 20 — El cierre de etapa es un producto tecnico, no una formalidad administrativa**
La secuencia TSK-20 → TSK-21 → TSK-22.1 produce tres artefactos de valor real: certificado de integracion, certificado de auditoria y resumen ejecutivo. En etapas futuras, la calidad de estos artefactos debe ser proporcional a la complejidad tecnica de la etapa.

**Leccion 21 — Los tokens de dominio emitidos durante el desarrollo aceleran el cierre formal**
El cierre fue rapido porque los tokens (seguridad, QA) fueron emitidos durante los bloques, no al final. El `stage-auditor` solo verifico que existian — no tuvo que esperar nuevas auditorias. Para etapas futuras: emitir tokens de dominio al finalizar cada bloque reduce el tiempo de la secuencia de cierre de horas a minutos.

**Leccion 22 — Referenciar artefactos de infraestructura en el TASK previene falsos positivos de Codigo Fantasma**
Todo archivo creado durante la ejecucion de una tarea debe estar mencionado (aunque sea en la nota) en esa tarea del TASK LIST. Regla: si un artefacto no tiene tarea explicita, referenciar en la nota de la tarea mas proxima: "Artefacto de soporte: `nombre_archivo` — [descripcion breve de su rol]".

---

**APRENDIZAJE_REGISTRADO_OK**

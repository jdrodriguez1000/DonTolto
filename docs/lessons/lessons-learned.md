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

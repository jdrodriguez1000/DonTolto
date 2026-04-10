# Registro de Lecciones Aprendidas — DonTolto

> INVARIANTE: Este archivo es de solo adicion (append-only). Nunca se modifican ni eliminan
> entradas de sesiones anteriores. Cada nueva sesion agrega entradas al final del documento.
> Trazabilidad: Vinculado siempre a Fase y Etapa de origen.

> NOTA DE CONTINUIDAD: Las lecciones aprendidas de la Etapa 1.0 (Fase 1) han sido archivadas en
> `docs/lessons/history/lessons_learned_F1_1.0.md`. Este archivo recoge las lecciones de la
> Etapa 1.1 en adelante.

---

## Sesion: 2026-04-09 (Fase 1, Etapa 1.1 — Bloque 0/1: Validacion & Scaffolding Supabase)

### Exitos y Aciertos Tecnicos

**Cadena SDD completa y operativa como acelerador de ejecucion**
Los 4 documentos SDD de la Etapa 1.1 (PRD, SPEC, PLAN, TASK) estaban en estado AUTORIZADO al inicio de la sesion. Esto permitio ejecutar las 9 tareas del Bloque 0/1 sin ambiguedades de requerimiento ni pausas de diseno. La inversion en gobernanza previa se traduce directamente en velocidad de ejecucion en el Bloque 0/1.

**Suite de tests pgTap como contrato de regresion de entorno**
Los 5 archivos de tests creados (001_environment_extensions.sql a 005_search_path_restrictive.sql) cumplen un doble rol: validacion inicial del entorno Y suite de regresion permanente. Si alguna actualizacion futura del CLI o del servidor local degrada extensiones, version o search_path, los tests fallaran en el siguiente `supabase db reset`, generando alerta temprana sin instrumentacion adicional.

**Gate 0 como hito de control de calidad entre scaffolding y DDL**
La certificacion formal Gate 0 (token GATE0-f1-1.1-CERT-001) actua como barrera de calidad entre el scaffolding de entorno (Bloque 0/1) y el desarrollo real de migraciones DDL (Bloque 2). Esta separacion explicita evita que el Bloque 2 inicie sobre un entorno no certificado, reduciendo el riesgo de fallos de infraestructura que contaminen el ciclo TDD de migraciones.

**`supabase db reset` como validacion final del scaffolding**
Ejecutar `supabase db reset` como ultima tarea del Bloque 0/1 (TSK-03.3) fue una decision correcta: funciona como prueba de integracion del scaffolding completo antes de iniciar el DDL. Un reset exitoso prueba que el `config.toml`, las extensiones del servidor local y la estructura de directorios son coherentes.

---

### Fricciones y Desafios

**`SUPABASE_PROJECT-ID` con guion invalido en `.env` bloqueo el stack local**
La variable de entorno usaba guion (`-`) en el nombre, lo cual es invalido en bash (los nombres de variables no pueden contener guiones) y en la mayoria de parsers dotenv. El error paso desapercibido durante la configuracion inicial porque bash no emite error al asignar la variable en formato KEY=VALUE, pero falla silenciosamente al intentar expandirla o exportarla. Leccion: todos los nombres de variables en `.env` deben usar exclusivamente `[A-Z][A-Z0-9_]*` (mayusculas, digitos y guion bajo).

**`supabase/config.toml` incompatible con CLI v2.89.0 en 3 puntos**
El TASK original especificaba configuraciones que resultaron invalidas para la version actual del CLI:
1. `[db].extra_search_path` — la seccion `[db]` no acepta esta clave en v2.89.0.
2. `[db.settings].cron.max_running_jobs` como dotted key — TOML lo interpreta como clave literal `cron.max_running_jobs` (con punto), no como tabla anidada.
3. `[project].project_id` — la clave `project_id` debe estar al nivel raiz del TOML, no bajo una seccion `[project]`.
Estos errores generaron fallos de parse al ejecutar `supabase db reset` que requirieron diagnostico iterativo.

**`extra_search_path` no persistible via `config.toml` — migracion a DDL obligatoria**
El objetivo de restringir el `search_path` de sesion (excluir esquemas internos de Supabase) no puede lograrse via `config.toml` en CLI v2.89.0. La alternativa correcta es usar `ALTER ROLE authenticator SET search_path = extensions, public;` y equivalentes en las migraciones SQL del Bloque 2. Esta limitacion del CLI implica que el test RED `005_search_path_restrictive.sql` fallara en el reset actual (estado esperado) y pasara solo despues de aplicar la migracion correspondiente en el Bloque 2.

---

### Lecciones Clave y Recomendaciones

**Leccion 1 — Verificar compatibilidad del CLI antes de redactar el TASK**
Los documentos TASK de etapas de infraestructura deben especificar la version del CLI/herramienta objetivo y verificar la compatibilidad de cada directiva de configuracion antes de redactar las tareas de implementacion. En este caso, el TASK fue escrito asumiendo una version de CLI que no era la instalada localmente (v2.89.0). La brecha entre la especificacion y la realidad del CLI genero 3 correcciones de infraestructura no planificadas en TSK-03.3.

**Leccion 2 — Las configuraciones de servidor de BD no pertenecen a archivos de cliente**
`extra_search_path` y `cron.max_running_jobs` son parametros del servidor PostgreSQL, no del cliente CLI de Supabase. El lugar correcto para configurarlos es en las migraciones SQL mediante `ALTER ROLE` y `ALTER SYSTEM` (o verificacion via `pg_settings`), no en `config.toml`. Esta distincion entre "configuracion de cliente" y "configuracion de servidor" debe aplicarse sistematicamente en el diseno de tareas de infraestructura de Supabase.

**Leccion 3 — Los nombres de variables de entorno solo deben contener `[A-Z0-9_]`**
Cualquier caracter fuera de este conjunto (guion, punto, espacio) en el nombre de una variable de entorno genera comportamiento indefinido en bash, dotenv y en la mayoria de sistemas de inyeccion de secretos (GitHub Actions Secrets, Vault). Este invariante debe verificarse mediante linting automatico del archivo `.env.example` como parte del pipeline CI/CD de la Etapa 1.2 o superior.

**Leccion 4 — El test RED de search_path es un recordatorio de deuda DDL, no un error**
El archivo `005_search_path_restrictive.sql` falla intencionalmente en el estado actual del repositorio (antes de la migracion DDL del Bloque 2). Este es el comportamiento correcto de la fase RED en TDD para infraestructura de base de datos: el test documenta el estado deseado futuro, no el estado actual. El proximo agente no debe intentar "arreglar" este test modificando las assertions — debe implementar la migracion DDL que haga pasar el test.

---

## Sesion: 2026-04-09 (Fase 1, Etapa 1.1 — Bloque 2: Schema Core & Singleton)

### Exitos y Aciertos Tecnicos

**Ciclo TDD RED -> GREEN -> REFACTOR -> CERT completado en una sola sesion con 26 assertions en VERDE**
El Bloque 2 ejecuto el ciclo TDD completo para el schema core de Supabase sin interrupciones ni regresiones. Los 5 archivos de tests pgTap (006 a 010) cubren 4 dominios criticos: invariante Singleton, bloqueo de DELETE via trigger, constantes de seed, constraints de arrays en draws, y las 3 Reglas de Oro de fn_validate_ball_array. La densidad de 26 assertions en 5 archivos (promedio 5.2 por archivo) refleja una granularidad adecuada para tests de esquema de base de datos.

**Orden canonico de migracion como patron de prevencion de dependencias circulares**
La estructura en 6 bloques secuenciales (Extensions -> Functions -> Tables -> Triggers -> Indexes -> Seed) resolvio el problema de dependencias entre funciones IMMUTABLE usadas en CHECKs de columnas. Definir las funciones antes de las tablas que las referencian en CHECKs es un invariante que debe aplicarse a todas las migraciones futuras de la Etapa 1.1, especialmente cuando el Bloque 3 introduzca funciones de validacion para proyecciones y performance.

**REFACTOR como etapa formal del ciclo TDD en DDL (no solo en codigo de aplicacion)**
La fase REFACTOR del Bloque 2 elimino 4 ALTER TABLE redundantes, consolido COMMENTs duplicados y nombro el CHECK Singleton (`chk_singleton_id`). Este nivel de limpieza en DDL — analogo al REFACTOR de codigo de aplicacion — previene la acumulacion de deuda tecnica en el schema y facilita las auditorias forenses. La fase REFACTOR en DDL debe ser un paso obligatorio del ciclo TDD de migraciones, no una actividad opcional.

**`FOR EACH STATEMENT` en trigger Singleton resuelve la vulnerabilidad de tabla vacia**
El trigger `tg_prevent_singleton_delete` usa `FOR EACH STATEMENT` en lugar de `FOR EACH ROW`. Si se hubiera usado `FOR EACH ROW`, un DELETE sobre una tabla vacia no habria disparado el trigger, creando una ventana donde el Singleton podria ser vaciado y luego re-insertado con un id diferente a 1, violando la invariante. `FOR EACH STATEMENT` dispara siempre, incluso con cero filas afectadas.

---

### Fricciones y Desafios

**Draft inicial de migracion con ALTER TABLE post-creacion generaba estados intermedios invalidos**
El primer borrador de `20260409000001_block_1_2.sql` usaba ALTER TABLE para agregar CHECKs nombrados despues de crear las tablas. Esto genera un estado intermedio donde la tabla existe sin sus constraints, lo que es peligroso en entornos con transacciones concurrentes o si la migracion falla a mitad. La solucion correcta (integrar todos los CHECKs en el CREATE TABLE original) fue aplicada en la fase REFACTOR, pero idealmente debe ser el diseno desde el draft inicial.

**`INSERT ON CONFLICT DO NOTHING` requiere claridad sobre que columna genera el conflicto**
La clausula ON CONFLICT del seed inicial de `system_configuration` asume conflicto en la PK (id=1). Si en el futuro se agrega una columna UNIQUE adicional, el ON CONFLICT DO NOTHING silenciara tambien conflictos en esa columna sin generar error, lo que puede ocultar inserciones duplicadas con datos diferentes. Para seeds futuros con multiples columnas UNIQUE, es preferible usar `ON CONFLICT (columna_especifica) DO NOTHING` en lugar de la forma generica.

---

### Lecciones Clave y Recomendaciones

**Leccion 5 — Las funciones IMMUTABLE usadas en CHECKs deben preceder a sus tablas en la migracion**
En PostgreSQL, un CHECK que referencia una funcion requiere que esa funcion exista en el momento de ejecutar el CREATE TABLE. Si la funcion y la tabla estan en la misma migracion, la funcion debe declararse primero. El orden canonico de 6 bloques (Extensions -> Functions -> Tables -> Triggers -> Indexes -> Seed) debe adoptarse como estandar obligatorio para todas las migraciones de la Etapa 1.1 y documentarse en la SPEC de etapas posteriores.

**Leccion 6 — `FOR EACH STATEMENT` vs `FOR EACH ROW` en triggers de proteccion de invariantes**
Para triggers cuya semantica es "prohibir esta operacion sobre la tabla" (en lugar de "procesar cada fila afectada"), usar `FOR EACH STATEMENT` es la eleccion correcta. `FOR EACH ROW` en triggers de proteccion crea una falsa sensacion de seguridad cuando la tabla esta vacia. Esta distincion debe verificarse en el diseno de cualquier trigger de tipo "guardia" en etapas futuras (ej. triggers de proteccion sobre `sync_locks` o `strategies_metadata`).

**Leccion 7 — Los CHECKs nombrados en DDL son instrumentos de auditoria forense, no solo de validacion**
Nombrar explicitamente cada CHECK (ej. `chk_singleton_id`, `chk_draws_ball_range`) permite identificar la constraint violada por nombre en los mensajes de error de PostgreSQL, sin necesidad de inspeccionar el schema. En entornos con triggers, RLS y migraciones concurrentes, esta trazabilidad es critica para diagnostico rapido. Todos los CHECKs de la Etapa 1.1 deben tener nombre explicito; los CHECKs anonimos deben considerarse deuda tecnica.

**Leccion 8 — El indice unico como alternativa a UNIQUE inline permite suspension temporal en cargas masivas**
Implementar unicidad como `CREATE UNIQUE INDEX` en lugar de `UNIQUE` en el CREATE TABLE ofrece flexibilidad operacional: el indice puede deshabilitarse temporalmente (o crearse como `INVALID`) durante cargas masivas de datos historicos (Fase 2) sin alterar el DDL de la tabla. Esta estrategia debe considerarse para todas las restricciones de unicidad sobre tablas de alto volumen de insercion en el proyecto (draws, projections).

---

## Sesion: 2026-04-10 (Fase 1, Etapa 1.1 — Bloque 3: Motor de Performance)

### Exitos y Aciertos Tecnicos

**Ciclo TDD RED -> GREEN -> REFACTOR -> CERT completado en una sola sesion con 9 assertions en RED + 7 tareas GREEN + REFACTOR + CERT**
El Bloque 3 ejecuto el ciclo TDD completo para el motor de performance (scoring y ranking de proyecciones) sin interrupciones ni regresiones. Los 2 archivos de tests pgTap (011_projections_idempotency.sql, 012_bulk_insert_chunking.sql) cubren 2 dominios criticos: idempotencia de insercion masiva (DELETE+INSERT por run_id) y chunking de 1000 registros (REQ-11). La migracion 20260410000001_block_3.sql contiene 382 lineas de DDL con 3 tablas + 1 funcion + 6 indices, todos auditados y certificados.

**Patrón DELETE+INSERT como contrato obligatorio de idempotencia en Engine Python**
La SPEC §4.1 exige que fn_bulk_insert_projections implemente DELETE WHERE run_id previo al INSERT, garantizando que reruns del Engine (en caso de fallo de GHA) produzcan exactamente el mismo estado final sin duplicados. Esta decision es distinta de la idempotencia del Bloque 2 (Singleton usa ON CONFLICT DO NOTHING). El patrón DELETE+INSERT es mas explosivo pero mas seguro para datos de alto volumen: 1,802 proyecciones por run_id pueden acumularse si ON CONFLICT solo ignora PK duplicadas pero no elimina registros previos del mismo run_id.

**clock_timestamp() como patron para desempate FIFO en rankings de performance**
La columna performance.processed_at usa clock_timestamp() en lugar de now(). Esto es critico porque now() retorna el mismo valor para todos los statements de una transaccion (inicio de transaccion), mientras que clock_timestamp() captura el tiempo real en el momento exacto de ejecucion del DDL. Para un scoring que ocurre sobre multiples filas (1,802 proyecciones) en statements secuenciales, clock_timestamp() proporciona granularidad temporal suficiente para desempate FIFO. La SPEC §4.2 requiere este desempate para garantizar rankings deterministas.

**Indices parciales como optimizacion operacional para columnas de baja cardinalidad**
Se creo idx_strategies_metadata_is_active como indice parcial (WHERE is_active = TRUE) en lugar de B-Tree completo sobre is_active. La heuristica de 95%+ de estrategias activas en produccion justifica que el indice indexe solo el subconjunto activo. El indice parcial es mas pequeno en disco (menos bloques para leer), mas rapido de mantener en inserciones (menos updateos) y cubre la query mas comun (JOIN con estrategias activas). Este patron debe replicarse para cualquier columna de baja cardinalidad con clara distribucion desigual de valores (ej. is_archived, is_suspended).

**REFACTOR en DDL como fase obligatoria para optimizacion de planes de ejecucion**
La fase REFACTOR del Bloque 3 no fue solo limpieza de codigo sino analisis proactivo de 5 queries core (Q1-Q5) identificadas en el SPEC §4.1 y §4.2. Cada query fue analizada estaticamente para determinar que tipo de scan ejecutaria PostgreSQL sin indice, y se crearon 4 indices adicionales (idx_projections_run_id, idx_projections_status, idx_projections_date_status, idx_strategies_metadata_is_active) para convertir Seq Scans ineficientes en Index Scans. Este analisis proactivo evita regresiones de rendimiento en Fase 2 (carga de datos historicos) cuando el volumen de filas haria visible la degradacion.

---

### Fricciones y Desafios

**SPEC §3.4 vs TASK menciona columnas que no existen en SPEC: decision correcta de aplicar SPEC > TASK pero requiere verificacion en PRD**
El TASK mencionaba last_heartbeat, worker_id, retry_count en projections; estas columnas no figuran en SPEC §3.4. Se aplico correctamente la regla de prevalencia SPEC > TASK y se omitieron. Sin embargo, esto revela que el TASK no fue revisado con cuidado contra la SPEC antes de ser autorizado. Para etapas futuras, el proceso de autorizacion del TASK debe incluir una verificacion explicita de que no haya menciones de campos, funciones o constraints no documentados en la SPEC.

**Tests RED (011, 012) no pueden ser ejecutados contra Supabase real sin la migracion: dependencia circular de validacion**
Los tests pgTap del Bloque 3 se escribieron correctamente en RED y estan diseñados para fallar (las tablas no existen). Cuando la migracion 20260410000001_block_3.sql sea aplicada, los tests pasaran GREEN. Sin embargo, hasta que la migracion sea aplicada, no es posible ejecutar estos tests contra una instancia de Supabase real para verificar que el DDL es sintacticamente valido y ejecutable. La dependencia es: migracion → tests pasan. Esta es la naturaleza de TDD para infraestructura de BD, pero requiere que el proximo agente (db-manager) aplique la migracion como primer paso del Bloque 3-GREEN.

---

### Lecciones Clave y Recomendaciones

**Leccion 9 — DELETE+INSERT es el contrato obligatorio para idempotencia en pipelines de alto volumen con reintentos**
El patrón ON CONFLICT es util para evitar duplicados en operaciones de insercion unica (ej. admin_uuid en Singleton). Pero para operaciones masivas con reintentos de pipeline (ej. Engine Python generando 1,802 proyecciones por run), DELETE+INSERT es el patron correcto. Razón: ON CONFLICT solo previene violaciones de constraint (PK, UNIQUE); no elimina registros previos del mismo batch identificador (run_id). Si el Engine falla despues de insertar 900 proyecciones y reinicia, ON CONFLICT ignorara el error de PK pero dejara las 900 filas previas en la tabla, resultando en duplicados. DELETE WHERE run_id = p_run_id antes del INSERT garantiza un estado final limpio. Esta distincion debe documentarse en la SPEC de cualquier tabla que sea destino de reintentos masivos.

**Leccion 10 — clock_timestamp() no es opcional en columnas de desempate temporal en rankings**
La columna processed_at usa clock_timestamp() para capturar tiempo real intra-transaccion. Si se hubiera usado now() (que retorna el tiempo al inicio de la transaccion), todas las 1,802 filas de proyecciones insertadas en una sola transaccion tendrian el mismo processed_at, haciendo imposible el desempate FIFO. El SPEC §4.2 exige desempate FIFO; esto obliga a clock_timestamp(). Esta leccion debe replicarse: cualquier columna de timestamp que sea parte de un ORDER BY para ranking o desempate debe usar clock_timestamp(), no now().

**Leccion 11 — Indices parciales (WHERE clause) para columnas de baja cardinalidad con distribucion desigual**
El indice idx_strategies_metadata_is_active indexa solo is_active=TRUE. Esta decision es correcta cuando se espera que >90% de filas cumplan la condicion del WHERE. El indice parcial es mas eficiente que un B-Tree completo porque: (a) ocupa menos espacio en disco, (b) requiere menos mantenimiento en inserciones/updates, (c) es mas rapido para scans porque evita bloques de indice innecesarios. Esta tecnica debe aplicarse sistematicamente en la Etapa 1.1 para cualquier columna booleana o enum de baja cardinalidad con distribucion conocida desigual (ej. is_archived, is_active, status='pending').

**Leccion 12 — REFACTOR en DDL no es limpieza opcional: es analisis proactivo de planes de ejecucion**
La fase REFACTOR del Bloque 3 no se limito a renombrar o comentar. Identifico 5 queries core que ejecutarian full table scans sin indices y creo 4 indices para optimizarlas. Este analisis proactivo debe ser estandar en cualquier migracion DDL compleja (>10 tablas, >20 indices). La herramienta es EXPLAIN ANALYZE (o analisis estatico basado en cardinalidad esperada) para cada query identificada en la SPEC. Sin esta fase, se asume que el planificador PostgreSQL optimizara dinamicamente, lo cual es falso para queries que no han sido indexadas explicitamente.

**Leccion 13 — La validacion de SPEC vs TASK debe ser parte del proceso de autorizacion del TASK**
El TASK menciono columnas inexistentes en SPEC; esto paso desapercibido hasta el Bloque 3. Para futuras etapas, el auditor de TASK debe verificar explicitamente: (1) cada tabla mencionada en TASK existe en SPEC §3.x, (2) cada columna mencionada en TASK existe en la definicion SPEC, (3) cada funcion mencionada en TASK existe en SPEC §4.x. Esta verificacion debe ocurrir ANTES de emitir el token de autorizacion del TASK, no durante la ejecucion.

**Leccion 14 — Los tests RED de infraestructura DDL no son ejecutables contra BD real hasta que la migracion sea aplicada**
Esto es una observacion de arquitectura, no un error. Los tests pgTap se escriben RED (fallan porque las tablas no existen) y pasan GREEN solo despues de que la migracion sea aplicada. Esto es correcto para TDD en infraestructura. El proximo agente (db-manager) debe ser consciente de esta dependencia y aplicar la migracion como primer paso antes de ejecutar los tests contra BD real.

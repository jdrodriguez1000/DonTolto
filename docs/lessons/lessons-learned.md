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

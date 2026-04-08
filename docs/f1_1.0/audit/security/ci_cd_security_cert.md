# Certificacion de Seguridad CI/CD — f1_1.0

**Trazabilidad**: TSK-F1_1.0-18-CERT  
**Auditor**: security-hardener  
**Fecha**: 2026-04-08  
**Protocolo**: Zero-Trust / OWASP Top 10 / Principio de Minimo Privilegio

---

## Veredicto: SEGURIDAD_APROBADA

Tres hallazgos de severidad media-baja fueron identificados y remediados en esta sesion. Ninguno constituia una vulnerabilidad critica (exposicion de credencial real, bypass de autenticacion o inyeccion explotable). El sistema pasa la certificacion tras las remediaciones aplicadas.

---

## Hallazgos por componente

### A. Workflow YAML — `.github/workflows/f1_1.0_env_validation.yml`

| # | Control | Estado | Observacion |
|---|---|---|---|
| 1 | Sin secretos hardcodeados | APROBADO | Ninguna credencial literal en el YAML. Solo referencias `${{ secrets.X }}`. |
| 2 | Inyeccion correcta de secretos | APROBADO | Todos los secretos inyectados exclusivamente via bloque `env:` del step. Ningun `${{ secrets.X }}` aparece dentro de comandos `run:`. |
| 3 | Permisos minimos | APROBADO | `permissions: contents: read` declarado explicitamente en el job. |
| 4 | No echo de secretos | APROBADO | Ningun step ejecuta `echo $SECRET` ni expone valores en comandos de shell. |
| 5 | Versiones pinadas de actions | INFORMATIVO | `actions/checkout@v4` y `actions/setup-python@v5` usan tag de version mayor sin SHA de commit. Aceptable segun politica del proyecto. Riesgo teorico de supply-chain attack si las actions upstream son comprometidas. |
| 6 | GITHUB_TOKEN scope | APROBADO | `secrets.GITHUB_TOKEN` inyectado via `env:` al scope del step. El job declara `permissions: contents: read`, limitando el alcance del token automatico de GHA. |
| 7 | No desactivacion de trace sospechosa | APROBADO | No existe `set +x` ni ninguna directiva que enmascare la traza de ejecucion de shell. |
| 8 | Dependencias con hashes | APROBADO | `pip install --require-hashes -r engine/requirements.txt` garantiza reproducibilidad y proteccion contra tampering de paquetes PyPI. |

**Resultado del componente**: APROBADO (1 hallazgo informativo sin severidad critica)

---

### B. Script de Provisionamiento — `engine/scripts/provision_secrets.sh`

| # | Control | Estado | Observacion |
|---|---|---|---|
| 1 | Sin valores hardcodeados | APROBADO | El script no contiene credenciales. Solo contiene el nombre del repositorio y la lista de claves a cargar. |
| 2 | Parseo seguro del .env | APROBADO | La carga se realiza via `echo "${secret_value}" | gh secret set "${secret_name}"`. El valor nunca se pasa como argumento de linea de comandos, previniendo exposicion en `ps aux`. |
| 3 | No expansion de variables en logs | APROBADO | Los logs imprimen solo el nombre (`${secret_name}`) y el estado (OK/FALLO). Ningun valor de secreto se imprime a stdout o stderr. |
| 4 | Proteccion contra path traversal | APROBADO PARCIAL | La ruta al `.env` se construye canonicamente via `cd && pwd` desde el `SCRIPT_DIR` del propio script. Sin embargo, se identifico que la funcion `get_env_value` usaba interpolacion directa de `${key}` como patron de regex en `grep -E`, exponiendo un vector de inyeccion de regex si el nombre de la clave contuviera metacaracteres (ej. `KEY.NAME`). **REMEDIADO.** |

**Hallazgo B.4 — Inyeccion de Regex en `get_env_value` (Severidad: Media-Baja)**

- **Descripcion**: La funcion `get_env_value` construia el patron grep como `"^${key}="` sin escapar el nombre de la clave. Si `key` contuviera `.`, `*`, `+` u otros metacaracteres de regex, el patron produciria coincidencias erroneas o comportamiento inesperado.
- **Explotabilidad**: Baja. Las claves estan hardcodeadas en `SECRETS_TO_PROVISION` y no provienen de entrada de usuario. Sin embargo, el principio de defensa en profundidad exige la correccion.
- **Remediacion aplicada**: Se modifico `get_env_value` para (1) usar `grep -F` como primera pasada de filtrado literal y (2) construir el patron de la segunda pasada `grep -E` escapando los metacaracteres del nombre de clave con `sed`.

**Resultado del componente**: APROBADO (1 hallazgo remediado)

---

### C. Engine Python — `engine/src/check_env.py`

| # | Control | Estado | Observacion |
|---|---|---|---|
| 1 | Sanitizacion de logs | APROBADO | `_sanitize_checks` invoca `sanitize_log_message` sobre cada `ServiceResult.message` antes de construir el `RunReport`. La sanitizacion ocurre antes de cualquier emision a stdout o GITHUB_STEP_SUMMARY. |
| 2 | No fuga en GITHUB_STEP_SUMMARY | APROBADO | `_write_github_step_summary` recibe el `RunReport` ya sanitizado. Los mensajes de detalle en la tabla markdown provienen de `result.message` post-sanitizacion. Ningun valor de secreto puede escapar a este canal. |
| 3 | Secretos en memoria | APROBADO PARCIAL | Los secretos se extraen del entorno una sola vez en `_SECRET_ENV_KEYS`. Sin embargo, se identifico que `SUPABASE_URL` y `ADMIN_UUID` estaban ausentes de la lista de claves a sanitizar. Mensajes de error de psycopg2/httpx pueden contener la URL de conexion o el UUID del admin. **REMEDIADO.** |

**Hallazgo C.3 — Variables sensibles ausentes de `_SECRET_ENV_KEYS` (Severidad: Media)**

- **Descripcion**: La tupla `_SECRET_ENV_KEYS` (linea 1093) omitia `SUPABASE_URL` y `ADMIN_UUID`. Mensajes de error de psycopg2 en `check_supabase_sql`, `check_pg_extensions` o `check_persistence_cycle` pueden incluir la URL completa de conexion (que contiene credenciales en el formato `postgresql://usuario:password@host/db`). Igualmente, el UUID del admin podria aparecer en mensajes de error de validacion.
- **Impacto**: La URL de PostgreSQL (`POSTGRES_DB_URL`) ya estaba incluida y sanitizaria la mayor parte del riesgo. `SUPABASE_URL` no contiene credenciales intrinsecas, pero es un identificador de infraestructura que conviene sanitizar. `ADMIN_UUID` es un identificador de privilegio elevado.
- **Remediacion aplicada**: Se agregaron `SUPABASE_URL` y `ADMIN_UUID` a `_SECRET_ENV_KEYS`. Ahora la lista cubre el conjunto completo de variables de entorno sensibles del sistema.

**Resultado del componente**: APROBADO (1 hallazgo remediado)

---

### D. Blueprint de Variables — `.env.example`

| # | Control | Estado | Observacion |
|---|---|---|---|
| 1 | Sin valores reales | APROBADO | Todos los valores son placeholders descriptivos. Ningun token real esta presente. |
| 2 | Ausencia de secretos reales | APROBADO PARCIAL | Se identifico que el placeholder `GITHUB_TOKEN=ghp_tu-github-token-aqui` usaba el prefijo `ghp_`, que es el prefijo exacto de tokens reales de GitHub. Herramientas de escaneo de secretos como `trufflehog`, `gitleaks` o `detect-secrets` podrian generar falsos positivos sobre este archivo. **REMEDIADO.** |

**Hallazgo D.2 — Placeholder de GITHUB_TOKEN con prefijo real (Severidad: Baja)**

- **Descripcion**: El valor `ghp_tu-github-token-aqui` comienza con `ghp_`, patrón que coincide con las reglas de deteccion de secretos de GitHub y herramientas de SAST. Aunque no es un token real, genera ruido en los escaneos automatizados y puede causar bloqueos en pipelines de seguridad que usen `gitleaks` o `git-secrets`.
- **Remediacion aplicada**: El placeholder fue cambiado a `REEMPLAZAR_CON_TOKEN_REAL`, eliminando el prefijo que disparaba la deteccion. El comentario explica que el token real debe comenzar con `ghp_` o `github_pat_`.

**Resultado del componente**: APROBADO (1 hallazgo remediado)

---

## Resumen de Vulnerabilidades Detectadas

| ID | Componente | Severidad | Estado |
|---|---|---|---|
| VUL-01 | `provision_secrets.sh` — inyeccion regex en `get_env_value` | Media-Baja | REMEDIADO |
| VUL-02 | `check_env.py` — `SUPABASE_URL` y `ADMIN_UUID` ausentes de sanitizacion | Media | REMEDIADO |
| VUL-03 | `.env.example` — placeholder `GITHUB_TOKEN` con prefijo `ghp_` | Baja | REMEDIADO |
| INFO-01 | Workflow YAML — actions sin SHA de commit pinado | Informativo | ACEPTADO (politica del proyecto) |

---

## Remediaciones Aplicadas

### VUL-01: `engine/scripts/provision_secrets.sh`

Funcion `get_env_value` modificada para usar `grep -F` como filtrado literal previo y escapar metacaracteres del nombre de clave antes de la pasada `grep -E`. Previene inyeccion de regex ante nombres de clave con caracteres especiales.

### VUL-02: `engine/src/check_env.py`

Tupla `_SECRET_ENV_KEYS` ampliada para incluir `SUPABASE_URL` y `ADMIN_UUID`. El conjunto de variables sanitizadas ahora cubre la totalidad de identificadores sensibles del sistema.

### VUL-03: `.env.example`

Placeholder de `GITHUB_TOKEN` modificado de `ghp_tu-github-token-aqui` a `REEMPLAZAR_CON_TOKEN_REAL`. Elimina falsos positivos en herramientas de deteccion de secretos.

---

## Firma de Certificacion

```
ESTADO:     SEGURIDAD_APROBADA
AUDITOR:    security-hardener
PROTOCOLO:  Zero-Trust / OWASP Top 10
TAREA:      TSK-F1_1.0-18-CERT
FECHA:      2026-04-08
ARCHIVOS:   .github/workflows/f1_1.0_env_validation.yml
            engine/scripts/provision_secrets.sh
            engine/src/check_env.py
            .env.example
```

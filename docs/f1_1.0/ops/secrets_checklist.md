# Checklist de Provisionamiento de Secretos — GHA (`f1_1.0`)

> **Trazabilidad**: TSK-F1_1.0-17.2-OPS | `docs/f1_1.0/f1_1.0_spec.md` [Sec 4]
> **Repo**: `jdrodriguez1000/DonTolto`
> **Workflow**: `.github/workflows/f1_1.0_env_validation.yml`

---

## 1. Tabla de Secretos a Provisionar

| Nombre | Regex de Validacion | Descripcion | Critico |
|---|---|---|---|
| `SUPABASE_URL` | `^https://[a-z0-9]+\.supabase\.co$` | URL base del proyecto Supabase. Requerida para handshake REST y SQL. | SI |
| `SUPABASE_SERVICE_ROLE_KEY` | `^eyJh.*$` (min 120 chars) | Service Role Key de Supabase. Bypass de RLS. Nunca exponer en frontend. | SI |
| `POSTGRES_DB_URL` | `^postgresql://.*:.*@.*:[0-9]{4,5}/postgres$` | Cadena de conexion directa a PostgreSQL. Soporta puerto 5432 (direct) o 6543 (pooler). | SI |
| `UPSTASH_REDIS_REST_URL` | `^https://.*\.upstash\.io$` | URL REST de la instancia Redis en Upstash. | WARNING |
| `UPSTASH_REDIS_REST_TOKEN` | `^.*$` (min 20 chars) | Token de autorizacion para la REST API de Upstash Redis. | WARNING |
| `RESEND_API_KEY` | `^re_.*$` | API Key del servicio Resend para envio de emails transaccionales. | WARNING |
| `ADMIN_UUID` | UUID v4: `^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$` | UUID del administrador principal. Debe existir en `auth.users` de Supabase. | WARNING |

> **Secreto excluido**: `GITHUB_TOKEN` es generado y gestionado automaticamente por GitHub Actions en cada ejecucion del workflow. No requiere carga manual y no puede sobrescribirse como secreto de repositorio de forma util.

---

## 2. Instrucciones de Carga

### Opcion A — Script automatizado (recomendado)

Prerequisitos:
- `gh` CLI instalado: https://cli.github.com/
- Autenticacion activa: `gh auth login`
- Archivo `.env` real en la raiz del repo (basado en `.env.example`)

```bash
# Desde la raiz del repositorio
bash engine/scripts/provision_secrets.sh

# O especificando ruta alternativa al .env
bash engine/scripts/provision_secrets.sh --env-file /ruta/a/.env
```

El script:
1. Verifica que `gh` CLI esta instalado y autenticado.
2. Verifica que el archivo `.env` existe.
3. Lee cada secreto del `.env` ignorando comentarios y lineas en blanco.
4. Carga cada secreto con `gh secret set --repo jdrodriguez1000/DonTolto`.
5. Muestra un resumen de carga y ejecuta la verificacion automatica.

---

### Opcion B — Carga manual via gh CLI

Ejecutar individualmente para cada secreto:

```bash
# Ejemplo: cargar SUPABASE_URL
gh secret set SUPABASE_URL --repo jdrodriguez1000/DonTolto

# El CLI solicitara el valor de forma interactiva (sin exponer en terminal)
# O bien, piping desde variable de entorno local:
echo "$SUPABASE_URL" | gh secret set SUPABASE_URL --repo jdrodriguez1000/DonTolto
```

Repetir para cada secreto de la tabla anterior.

---

### Opcion C — Carga manual via GitHub Settings UI

1. Navegar a: `https://github.com/jdrodriguez1000/DonTolto/settings/secrets/actions`
2. Hacer clic en **"New repository secret"**.
3. Ingresar el **Name** (exactamente como aparece en la tabla).
4. Ingresar el **Secret** (valor real).
5. Hacer clic en **"Add secret"**.
6. Repetir para cada secreto de la tabla.

---

## 3. Comando de Verificacion Post-Carga

```bash
# Listar todos los secretos registrados en el repositorio (solo nombres)
gh secret list --repo jdrodriguez1000/DonTolto
```

Salida esperada (los 7 secretos deben aparecer):

```
ADMIN_UUID                  Updated YYYY-MM-DD
POSTGRES_DB_URL             Updated YYYY-MM-DD
RESEND_API_KEY              Updated YYYY-MM-DD
SUPABASE_SERVICE_ROLE_KEY   Updated YYYY-MM-DD
SUPABASE_URL                Updated YYYY-MM-DD
UPSTASH_REDIS_REST_TOKEN    Updated YYYY-MM-DD
UPSTASH_REDIS_REST_URL      Updated YYYY-MM-DD
```

> Los valores nunca se exponen; solo los nombres y fechas de actualizacion son visibles.

---

## 4. Nota sobre GITHUB_TOKEN

`GITHUB_TOKEN` es un token especial gestionado por la propia plataforma GitHub Actions:

- Se genera automaticamente al inicio de cada ejecucion del workflow.
- Sus permisos se configuran en el campo `permissions` del archivo YAML del workflow.
- No debe cargarse como secreto de repositorio.
- El script `provision_secrets.sh` lo excluye explicitamente de la carga.

Referencia: https://docs.github.com/en/actions/security-guides/automatic-token-authentication

---

## 5. Seguridad

- Nunca incluir valores reales de secretos en el repositorio (`.gitignore` cubre `.env`).
- El archivo `.env.example` solo contiene placeholders y regex de validacion.
- Los secretos de nivel `CRITICO` (`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `POSTGRES_DB_URL`) deben rotarse ante cualquier sospecha de compromiso.
- Revisar accesos en `Settings > Secrets and variables > Actions` periodicamente.

#!/usr/bin/env bash
# =============================================================================
# provision_secrets.sh — Provisionamiento de Secretos en GitHub Actions
# =============================================================================
# Proyecto   : DonTolto
# Repo remoto: jdrodriguez1000/DonTolto
# Trazabilidad: docs/f1_1.0/ops/secrets_checklist.md
#               TSK-F1_1.0-17.2-OPS
#
# Uso:
#   1. Asegúrese de tener `gh` CLI instalado y autenticado:
#      gh auth login
#   2. Asegúrese de tener el archivo `.env` real en la raíz del proyecto.
#   3. Ejecute desde la raíz del repo:
#      bash engine/scripts/provision_secrets.sh
#      ó
#      bash engine/scripts/provision_secrets.sh --env-file /ruta/a/.env
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuración
# ---------------------------------------------------------------------------

REPO="jdrodriguez1000/DonTolto"

# Secretos que se deben cargar en GHA.
# NOTA: GITHUB_TOKEN es automático en GHA; no se carga manualmente.
SECRETS_TO_PROVISION=(
    "SUPABASE_URL"
    "SUPABASE_SERVICE_ROLE_KEY"
    "POSTGRES_DB_URL"
    "UPSTASH_REDIS_REST_URL"
    "UPSTASH_REDIS_REST_TOKEN"
    "RESEND_API_KEY"
    "ADMIN_UUID"
)

# Ruta por defecto al archivo .env (raíz del repo, nivel superior al script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ENV_FILE="$(cd "${SCRIPT_DIR}/../.." && pwd)/.env"
ENV_FILE="${DEFAULT_ENV_FILE}"

# ---------------------------------------------------------------------------
# Parseo de argumentos
# ---------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        --env-file)
            ENV_FILE="$2"
            shift 2
            ;;
        --help|-h)
            echo "Uso: $0 [--env-file <ruta_al_.env>]"
            echo ""
            echo "Opciones:"
            echo "  --env-file   Ruta al archivo .env con los valores reales."
            echo "               Por defecto: <raiz_del_repo>/.env"
            exit 0
            ;;
        *)
            echo "[ERROR] Argumento desconocido: $1" >&2
            echo "Use --help para ver las opciones disponibles." >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Validaciones previas
# ---------------------------------------------------------------------------

echo "============================================================"
echo " DonTolto — Provisionamiento de Secretos en GitHub Actions"
echo " Repo: ${REPO}"
echo "============================================================"
echo ""

# 1. Verificar que gh CLI está instalado
if ! command -v gh &>/dev/null; then
    echo "[ERROR] 'gh' CLI no está instalado o no está en el PATH." >&2
    echo "        Instálelo desde: https://cli.github.com/" >&2
    exit 1
fi

echo "[OK] gh CLI detectado: $(gh --version | head -n1)"

# 2. Verificar que el usuario está autenticado en gh
if ! gh auth status &>/dev/null; then
    echo "[ERROR] No está autenticado en gh CLI." >&2
    echo "        Ejecute: gh auth login" >&2
    exit 1
fi

echo "[OK] Autenticación gh CLI verificada."

# 3. Verificar que el archivo .env existe
if [[ ! -f "${ENV_FILE}" ]]; then
    echo "[ERROR] Archivo .env no encontrado en: ${ENV_FILE}" >&2
    echo "        Cree el archivo .env basándose en .env.example" >&2
    echo "        y complete los valores reales antes de ejecutar este script." >&2
    exit 1
fi

echo "[OK] Archivo .env encontrado: ${ENV_FILE}"
echo ""

# ---------------------------------------------------------------------------
# Función: extraer valor de una variable desde el .env
# Ignora líneas en blanco y comentarios (#).
# Soporta: KEY=VALUE, KEY="VALUE", KEY='VALUE'
# ---------------------------------------------------------------------------

get_env_value() {
    local key="$1"
    local value

    # Buscar la clave ignorando comentarios y líneas en blanco.
    # Se usa grep -F (cadena literal) para evitar inyección de regex si el nombre
    # de la clave contuviera caracteres especiales. El sed posterior usa la clave
    # escapada para el reemplazo del prefijo.
    local escaped_key
    escaped_key=$(printf '%s\n' "${key}" | sed 's/[[\.*^$()+?{|]/\\&/g')
    value=$(grep -F "${key}=" "${ENV_FILE}" | grep -E "^${escaped_key}=" | head -n1 | sed "s/^${escaped_key}=//" | sed "s/^['\"]//;s/['\"]$//") || true

    echo "${value}"
}

# ---------------------------------------------------------------------------
# Carga de secretos
# ---------------------------------------------------------------------------

echo "------------------------------------------------------------"
echo " Cargando secretos en GitHub Actions..."
echo "------------------------------------------------------------"

LOADED_COUNT=0
SKIPPED_COUNT=0
FAILED_COUNT=0

for secret_name in "${SECRETS_TO_PROVISION[@]}"; do
    secret_value=$(get_env_value "${secret_name}")

    if [[ -z "${secret_value}" ]]; then
        echo "[OMITIDO] ${secret_name}: valor vacío o no encontrado en .env — saltando."
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    fi

    echo -n "[CARGANDO] ${secret_name}... "

    if echo "${secret_value}" | gh secret set "${secret_name}" --repo "${REPO}" 2>/dev/null; then
        echo "OK"
        LOADED_COUNT=$((LOADED_COUNT + 1))
    else
        echo "FALLO"
        echo "[ERROR] No se pudo cargar el secreto: ${secret_name}" >&2
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
done

echo ""
echo "------------------------------------------------------------"
echo " Resumen de carga"
echo "------------------------------------------------------------"
echo "  Cargados exitosamente : ${LOADED_COUNT}"
echo "  Omitidos (sin valor)  : ${SKIPPED_COUNT}"
echo "  Fallidos              : ${FAILED_COUNT}"
echo ""

# ---------------------------------------------------------------------------
# Verificación post-carga
# ---------------------------------------------------------------------------

echo "------------------------------------------------------------"
echo " Verificación: Secretos registrados en el repositorio"
echo " (Solo nombres — los valores nunca se exponen)"
echo "------------------------------------------------------------"

gh secret list --repo "${REPO}"

echo ""

# ---------------------------------------------------------------------------
# Resultado final
# ---------------------------------------------------------------------------

if [[ "${FAILED_COUNT}" -gt 0 ]]; then
    echo "[ADVERTENCIA] ${FAILED_COUNT} secreto(s) no pudieron cargarse." >&2
    echo "              Revise los errores anteriores y vuelva a ejecutar." >&2
    exit 1
fi

if [[ "${SKIPPED_COUNT}" -gt 0 ]]; then
    echo "[ADVERTENCIA] ${SKIPPED_COUNT} secreto(s) estaban vacíos en .env y fueron omitidos."
    echo "              Complete el .env con los valores reales y vuelva a ejecutar."
fi

echo "[COMPLETADO] Provisionamiento de secretos finalizado correctamente."
echo ""
echo "NOTA: GITHUB_TOKEN es gestionado automáticamente por GitHub Actions"
echo "      y NO requiere carga manual en Settings."

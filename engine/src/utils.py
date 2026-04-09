"""
Utilidades de infraestructura reutilizables para el motor DonTolto.

Módulo de helpers de bajo nivel: generación de identificadores, formateo
de logs estructurados y sanitización de secretos para salida segura.
No contiene lógica de negocio ni handshakes con servicios externos.

Trazabilidad: TSK-F1_1.0-03 / docs/f1_1.0/f1_1.0_spec.md [Sec 4]
"""

import re
import uuid
from datetime import datetime, timezone
from typing import Final

# ---------------------------------------------------------------------------
# Constantes de nivel de log aceptados
# ---------------------------------------------------------------------------

VALID_LOG_LEVELS: Final[tuple[str, ...]] = ("INFO", "WARNING", "ERROR", "CRITICAL")

# ---------------------------------------------------------------------------
# Patrones de validación de variables de entorno
# Estructura: { NOMBRE: (regex, es_critica) }
# es_critica=True  → fallo provoca EXIT 1 (ERROR)
# es_critica=False → fallo produce WARNING, no rompe el pipeline
# Trazabilidad: docs/f1_1.0/f1_1.0_spec.md [Sec 4]
# ---------------------------------------------------------------------------

ENV_VAR_PATTERNS: Final[dict[str, tuple[str, bool]]] = {
    "SUPABASE_URL": (
        r"^https://[a-z0-9]+\.supabase\.co$",
        True,
    ),
    "SUPABASE_SERVICE_ROLE_KEY": (
        r"^eyJh.{116,}$",
        True,
    ),
    "POSTGRES_DB_URL": (
        r"^postgresql://.*:.*@.*:[0-9]{4,5}/postgres$",
        True,
    ),
    "UPSTASH_REDIS_REST_URL": (
        r"^https://.*\.upstash\.io$",
        False,
    ),
    "UPSTASH_REDIS_REST_TOKEN": (
        r"^.{20,}$",
        False,
    ),
    "RESEND_API_KEY": (
        r"^re_.*$",
        False,
    ),
    "GITHUB_TOKEN": (
        r"^(ghp_|github_pat_).*$",
        False,
    ),
    "ADMIN_UUID": (
        r"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
        True,
    ),
}


# ---------------------------------------------------------------------------
# Funciones de identificación
# ---------------------------------------------------------------------------


def generate_run_id() -> str:
    """Genera un identificador único de corrida como UUID v4.

    Returns:
        str: UUID v4 en formato canónico con guiones
             (ej: "550e8400-e29b-41d4-a716-446655440000").
    """
    return str(uuid.uuid4())


def run_id_short(run_id: str) -> str:
    """Retorna los primeros 8 caracteres del run_id, excluyendo guiones.

    Usado como sufijo de nombre de tabla efímera en Supabase:
    ``public._bootstrap_[run_id_short]``.

    Args:
        run_id: UUID v4 como string, con o sin guiones.

    Returns:
        str: Primeros 8 caracteres del UUID sin guiones
             (ej: "550e8400").

    Example:
        >>> run_id_short("550e8400-e29b-41d4-a716-446655440000")
        '550e8400'
    """
    return run_id.replace("-", "")[:8]


# ---------------------------------------------------------------------------
# Funciones de tiempo
# ---------------------------------------------------------------------------


def get_timestamp() -> str:
    """Retorna el timestamp actual en formato ISO 8601 UTC.

    Returns:
        str: Timestamp en formato ``YYYY-MM-DDTHH:MM:SS.ffffff+00:00``
             (ej: "2026-04-07T14:30:00.000000+00:00").
    """
    return datetime.now(tz=timezone.utc).isoformat()


# ---------------------------------------------------------------------------
# Funciones de formateo de logs
# ---------------------------------------------------------------------------


def format_log_entry(level: str, service: str, message: str) -> str:
    """Formatea una entrada de log estructurada para salida a consola o CI.

    Produce una línea con el formato:
    ``[{timestamp}] [{level}] [{service}] {message}``

    Args:
        level: Nivel de severidad. Debe ser uno de: INFO, WARNING, ERROR,
               CRITICAL. Se normaliza a mayúsculas antes de validar.
        service: Nombre del servicio o módulo que origina el log
                 (ej: "env_validator", "pg_check").
        message: Cuerpo del mensaje. Debe estar previamente sanitizado si
                 contiene secretos.

    Returns:
        str: Línea de log formateada con timestamp UTC en el momento de la
             llamada.

    Raises:
        ValueError: Si ``level`` no pertenece a ``VALID_LOG_LEVELS``.

    Example:
        >>> format_log_entry("INFO", "env_validator", "Validacion completada")
        '[2026-04-07T14:30:00.000000+00:00] [INFO] [env_validator] Validacion completada'
    """
    normalized_level = level.upper()
    if normalized_level not in VALID_LOG_LEVELS:
        raise ValueError(
            f"Nivel de log invalido: '{level}'. "
            f"Valores aceptados: {', '.join(VALID_LOG_LEVELS)}"
        )
    timestamp = get_timestamp()
    return f"[{timestamp}] [{normalized_level}] [{service}] {message}"


# ---------------------------------------------------------------------------
# Funciones de sanitización de secretos
# ---------------------------------------------------------------------------


def sanitize_secret(value: str) -> str:
    """Enmascara un secreto para emisión segura en logs.

    Conserva los primeros 4 caracteres visibles y reemplaza el resto con
    ``****``. Si el string tiene menos de 5 caracteres, retorna ``"****"``
    completo para evitar revelar el secreto por longitud.

    Args:
        value: String que contiene un secreto (token, clave API, etc.).

    Returns:
        str: Versión enmascarada del secreto
             (ej: "ghp_AbCdEf123456" → "ghp_****").

    Example:
        >>> sanitize_secret("ghp_AbCdEf123456")
        'ghp_****'
        >>> sanitize_secret("abc")
        '****'
    """
    if len(value) < 5:
        return "****"
    return value[:4] + "****"


def sanitize_log_message(message: str, secrets: list[str]) -> str:
    """Reemplaza ocurrencias de secretos en un mensaje de log por ``[REDACTED]``.

    Protege contra fugas accidentales de credenciales en el ``RunReport``
    y en el ``GITHUB_STEP_SUMMARY``. El reemplazo es case-sensitive y
    procesa la lista de secretos en el orden recibido.

    Los secretos vacíos o de un solo carácter se omiten para evitar
    sustituciones masivas indeseadas.

    Args:
        message: Texto del mensaje que puede contener secretos.
        secrets: Lista de strings sensibles a redactar. Las entradas vacías
                 o de longitud menor a 2 son ignoradas silenciosamente.

    Returns:
        str: Mensaje con cada secreto sustituido por ``[REDACTED]``.

    Example:
        >>> sanitize_log_message("token=ghp_abc123", ["ghp_abc123"])
        'token=[REDACTED]'
        >>> sanitize_log_message("sin secretos", [])
        'sin secretos'
    """
    sanitized = message
    for secret in secrets:
        if len(secret) < 2:
            continue
        sanitized = sanitized.replace(secret, "[REDACTED]")
    return sanitized

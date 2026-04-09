"""
Modulo de sanitizacion de secretos para ServiceResult del motor DonTolto.

Provee la funcion `sanitize_service_result` que retorna una copia inmutable
del ServiceResult con el campo `message` redactado de cualquier secreto
explicito o patron de header HTTP de autorizacion.

No contiene logica de negocio ni llamadas a servicios externos.
Implementacion determinista: mismo input produce siempre el mismo output.

Trazabilidad: TSK-F1_1.0-06-GREEN / docs/f1_1.0/f1_1.0_spec.md §3.2.2
"""

import re

from engine.src.models import ServiceResult
from engine.src.utils import sanitize_log_message

# ---------------------------------------------------------------------------
# Patron regex para headers HTTP de autorizacion
# Cubre:
#   Authorization: Bearer <cualquier_cosa>
#   Authorization: token <cualquier_cosa>
# ---------------------------------------------------------------------------

_AUTH_HEADER_PATTERN: re.Pattern[str] = re.compile(
    r"Authorization:\s*(Bearer|token)\s+\S+",
    re.IGNORECASE,
)

_AUTH_HEADER_REPLACEMENT: str = "Authorization: [REDACTED]"


def sanitize_service_result(
    result: ServiceResult,
    secrets: list[str],
) -> ServiceResult:
    """Retorna una copia del ServiceResult con el campo `message` sanitizado.

    Aplica dos capas de redaccion sobre el mensaje:
    1. Sustituye cualquier valor presente en ``secrets`` por ``[REDACTED]``
       usando `sanitize_log_message` de utils.py (secretos con menos de 2
       caracteres se ignoran silenciosamente).
    2. Detecta y redacta patrones de headers HTTP de autorizacion:
       ``Authorization: Bearer <valor>`` y ``Authorization: token <valor>``.

    No altera los campos ``status``, ``latency_ms`` ni ``metadata``.
    El ``ServiceResult`` original nunca es mutado; se retorna una copia nueva.
    Si ``result.message`` es ``None``, el resultado se retorna sin cambios.

    Args:
        result: ServiceResult cuyo campo message puede contener secretos.
        secrets: Lista de strings sensibles a redactar. Las entradas con
                 longitud menor a 2 son ignoradas silenciosamente.

    Returns:
        ServiceResult: Copia del original con `message` sanitizado, o el
        mismo objeto si `message` era None.

    Example:
        >>> r = ServiceResult(status="OK", latency_ms=1.0,
        ...                   message="token=ghp_fake_token_abc")
        >>> sanitize_service_result(r, ["ghp_fake_token_abc"]).message
        'token=[REDACTED]'
    """
    if result.message is None:
        return result

    # Capa 1: redactar secretos explicitos
    sanitized_message: str = sanitize_log_message(result.message, secrets)

    # Capa 2: redactar headers HTTP de autorizacion
    sanitized_message = _AUTH_HEADER_PATTERN.sub(
        _AUTH_HEADER_REPLACEMENT, sanitized_message
    )

    return result.model_copy(update={"message": sanitized_message})

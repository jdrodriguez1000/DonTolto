"""
Modelos de datos y funciones de validacion del motor DonTolto.

Define los contratos de datos estructurados usados a lo largo del pipeline
de validacion de entorno: CheckStatus (Enum), ServiceResult y RunReport
(BaseModel Pydantic v2), y la funcion validate_env_vars.

No contiene logica de negocio ni llamadas a servicios externos.

Trazabilidad: TSK-F1_1.0-05-GREEN / docs/f1_1.0/f1_1.0_spec.md §2.1
"""

import re
from enum import Enum
from typing import Annotated
from uuid import UUID

from pydantic import BaseModel, Field

from engine.src.utils import ENV_VAR_PATTERNS


# ---------------------------------------------------------------------------
# Enum de estados de verificacion
# ---------------------------------------------------------------------------


class CheckStatus(str, Enum):
    """Estados posibles para el resultado de un check de servicio.

    Hereda de str para que Pydantic acepte strings literales en la
    construccion de modelos (ej: status="OK").
    """

    OK = "OK"
    WARNING = "WARNING"
    ERROR = "ERROR"


# ---------------------------------------------------------------------------
# Modelo: ServiceResult
# ---------------------------------------------------------------------------


class ServiceResult(BaseModel):
    """Resultado de la verificacion de un servicio o variable de entorno.

    Attributes:
        status: Estado resultante del check (OK, WARNING o ERROR).
        latency_ms: Latencia observada en milisegundos. Debe ser estrictamente
                    mayor que cero (constraint gt=0).
        message: Descripcion opcional del resultado o causa del fallo.
        metadata: Diccionario opcional con datos adicionales del check.
    """

    status: CheckStatus
    latency_ms: Annotated[float, Field(gt=0)]
    message: str | None = None
    metadata: dict | None = None


# ---------------------------------------------------------------------------
# Modelo: RunReport
# ---------------------------------------------------------------------------


class RunReport(BaseModel):
    """Reporte consolidado de una corrida de validacion del motor.

    Attributes:
        run_id: Identificador unico de corrida en formato UUID v4.
        timestamp: Momento de ejecucion en formato ISO 8601 UTC.
        status: Estado global de la corrida, determinado por el peor
                resultado entre los checks individuales.
        checks: Mapa de nombre de servicio a su ServiceResult correspondiente.
    """

    run_id: UUID
    timestamp: str
    status: CheckStatus
    checks: dict[str, ServiceResult]


# ---------------------------------------------------------------------------
# Funcion: validate_env_vars
# ---------------------------------------------------------------------------


def validate_env_vars(env: dict) -> dict[str, ServiceResult]:
    """Valida cada variable de entorno contra su patron regex esperado.

    Itera sobre todas las claves definidas en ENV_VAR_PATTERNS y evalua
    si el valor presente en ``env`` existe y satisface el patron asociado.
    El resultado de cada variable se clasifica como OK, ERROR o WARNING
    segun si la variable es critica o no.

    Args:
        env: Diccionario que representa las variables de entorno a validar.
             Puede estar vacio; en ese caso todas las claves produciran
             un resultado de fallo (ERROR o WARNING segun criticidad).

    Returns:
        dict[str, ServiceResult]: Un ServiceResult por cada clave de
        ENV_VAR_PATTERNS, independientemente de si estaba en ``env``.

        - status OK      → valor presente y pasa el regex.
        - status ERROR   → ausente o falla regex, y la variable es critica.
        - status WARNING → ausente o falla regex, y la variable no es critica.
    """
    results: dict[str, ServiceResult] = {}

    for var_name, (pattern, is_critical) in ENV_VAR_PATTERNS.items():
        value: str | None = env.get(var_name)

        if value is not None and re.match(pattern, value):
            results[var_name] = ServiceResult(
                status=CheckStatus.OK,
                latency_ms=0.1,
                message=None,
            )
        else:
            failure_status = CheckStatus.ERROR if is_critical else CheckStatus.WARNING
            reason = "ausente" if value is None else "formato invalido"
            results[var_name] = ServiceResult(
                status=failure_status,
                latency_ms=0.1,
                message=f"{var_name} {reason}",
            )

    return results

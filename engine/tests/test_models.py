"""
Suite de pruebas RED para engine.src.models.

Valida los contratos de ServiceResult, RunReport y validate_env_vars
segun la SPEC §2.1. Todos los tests deben FALLAR en la fase RED porque
engine/src/models.py no existe aun.

Fase TDD: RED
Trazabilidad: TSK-F1_1.0-04-RED / docs/f1_1.0/f1_1.0_spec.md §2.1
"""

import pytest
from pydantic import ValidationError

# Importacion deliberada de modulo que NO EXISTE.
# Todos los tests fallaran con ImportError/ModuleNotFoundError en fase RED.
from engine.src.models import (  # noqa: E402
    RunReport,
    ServiceResult,
    validate_env_vars,
)


# ===========================================================================
# Grupo 1: ServiceResult
# ===========================================================================


def test_service_result_valid_ok_status():
    """Debe ser posible instanciar ServiceResult con status OK y latency > 0."""
    # Arrange
    status = "OK"
    latency_ms = 42.5

    # Act
    result = ServiceResult(status=status, latency_ms=latency_ms)

    # Assert
    assert result.status.value == "OK"
    assert result.latency_ms == 42.5


def test_service_result_invalid_status_raises():
    """Un status desconocido debe provocar ValidationError de Pydantic."""
    # Arrange
    bad_status = "UNKNOWN"

    # Act / Assert
    with pytest.raises(ValidationError):
        ServiceResult(status=bad_status, latency_ms=10.0)


def test_service_result_negative_latency_raises():
    """Una latencia negativa debe provocar ValidationError (constraint > 0)."""
    # Arrange / Act / Assert
    with pytest.raises(ValidationError):
        ServiceResult(status="OK", latency_ms=-1.0)


def test_service_result_zero_latency_raises():
    """Una latencia de 0.0 debe provocar ValidationError (constraint estricto > 0)."""
    # Arrange / Act / Assert
    with pytest.raises(ValidationError):
        ServiceResult(status="OK", latency_ms=0.0)


def test_service_result_nullable_fields():
    """Los campos message y metadata son opcionales (nullable)."""
    # Arrange
    status = "WARNING"
    latency_ms = 5.0

    # Act
    result = ServiceResult(status=status, latency_ms=latency_ms, message=None, metadata=None)

    # Assert
    assert result.message is None
    assert result.metadata is None


# ===========================================================================
# Grupo 2: RunReport
# ===========================================================================


def test_run_report_valid_construction(valid_run_id, valid_timestamp):
    """RunReport con campos validos y checks vacio debe instanciarse sin errores."""
    # Arrange / Act
    report = RunReport(
        run_id=valid_run_id,
        timestamp=valid_timestamp,
        status="OK",
        checks={},
    )

    # Assert
    assert str(report.run_id) == valid_run_id
    assert report.status.value == "OK"
    assert report.checks == {}


def test_run_report_invalid_run_id_raises(invalid_run_id, valid_timestamp):
    """Un run_id que no es UUID v4 debe provocar ValidationError."""
    # Arrange / Act / Assert
    with pytest.raises(ValidationError):
        RunReport(
            run_id=invalid_run_id,
            timestamp=valid_timestamp,
            status="OK",
            checks={},
        )


def test_run_report_status_derives_from_checks(valid_run_id, valid_timestamp):
    """El status global debe reflejar el peor estado de los checks individuales.

    - Todos OK  → status global OK.
    - Alguno ERROR → status global ERROR.
    """
    # Arrange: todos OK
    ok_check = ServiceResult(status="OK", latency_ms=10.0)
    report_all_ok = RunReport(
        run_id=valid_run_id,
        timestamp=valid_timestamp,
        status="OK",
        checks={"supabase": ok_check},
    )

    # Assert: status global OK cuando todos los checks son OK
    assert report_all_ok.status.value == "OK"

    # Arrange: un check con ERROR
    error_check = ServiceResult(
        status="ERROR",
        latency_ms=1.0,
        message="fallo de conexion",
    )
    report_with_error = RunReport(
        run_id=valid_run_id,
        timestamp=valid_timestamp,
        status="ERROR",
        checks={"supabase": ok_check, "postgres": error_check},
    )

    # Assert: status global ERROR cuando algun check falla
    assert report_with_error.status.value == "ERROR"


def test_run_report_checks_is_dict_of_service_results(valid_run_id, valid_timestamp):
    """El campo checks debe ser dict[str, ServiceResult]."""
    # Arrange
    check_a = ServiceResult(status="OK", latency_ms=20.0)
    check_b = ServiceResult(status="WARNING", latency_ms=150.0, message="lento")

    # Act
    report = RunReport(
        run_id=valid_run_id,
        timestamp=valid_timestamp,
        status="WARNING",
        checks={"supabase": check_a, "redis": check_b},
    )

    # Assert
    assert isinstance(report.checks, dict)
    assert len(report.checks) == 2
    assert isinstance(report.checks["supabase"], ServiceResult)
    assert isinstance(report.checks["redis"], ServiceResult)


# ===========================================================================
# Grupo 3: validate_env_vars
# ===========================================================================


def test_validate_env_vars_all_valid(valid_env_vars):
    """Con todas las variables presentes y correctas, todos los resultados son OK."""
    # Act
    results = validate_env_vars(valid_env_vars)

    # Assert
    for var_name, service_result in results.items():
        assert service_result.status.value == "OK", (
            f"Se esperaba OK para '{var_name}' pero se obtuvo "
            f"{service_result.status.value}: {service_result.message}"
        )


def test_validate_env_vars_missing_critical_var(valid_env_vars):
    """Omitir una variable critica (SUPABASE_URL) debe producir status ERROR."""
    # Arrange
    env = dict(valid_env_vars)
    env.pop("SUPABASE_URL")

    # Act
    results = validate_env_vars(env)

    # Assert
    assert results["SUPABASE_URL"].status.value == "ERROR"


def test_validate_env_vars_missing_warning_var(valid_env_vars):
    """Omitir una variable no critica (RESEND_API_KEY) debe producir status WARNING."""
    # Arrange
    env = dict(valid_env_vars)
    env.pop("RESEND_API_KEY")

    # Act
    results = validate_env_vars(env)

    # Assert
    assert results["RESEND_API_KEY"].status.value == "WARNING"


def test_validate_env_vars_invalid_regex_critical(valid_env_vars):
    """SUPABASE_URL con formato incorrecto debe producir status ERROR."""
    # Arrange
    env = dict(valid_env_vars)
    env["SUPABASE_URL"] = "http://wrong-format.example.com"

    # Act
    results = validate_env_vars(env)

    # Assert
    assert results["SUPABASE_URL"].status.value == "ERROR"


def test_validate_env_vars_invalid_regex_warning(valid_env_vars):
    """GITHUB_TOKEN con formato incorrecto debe producir status WARNING."""
    # Arrange
    env = dict(valid_env_vars)
    env["GITHUB_TOKEN"] = "invalid_token_sin_prefijo"

    # Act
    results = validate_env_vars(env)

    # Assert
    assert results["GITHUB_TOKEN"].status.value == "WARNING"


def test_validate_env_vars_returns_all_keys(valid_env_vars):
    """validate_env_vars debe retornar un ServiceResult por cada clave de
    ENV_VAR_PATTERNS, incluso si la variable no esta en el input."""
    # Arrange: dict completamente vacio
    env_vacio = {}

    # Act
    results = validate_env_vars(env_vacio)

    # Assert: importar el patron para conocer las claves esperadas
    from engine.src.utils import ENV_VAR_PATTERNS

    assert set(results.keys()) == set(ENV_VAR_PATTERNS.keys())
    for var_name, service_result in results.items():
        assert isinstance(service_result, ServiceResult), (
            f"Se esperaba ServiceResult para '{var_name}'"
        )

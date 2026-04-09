"""
Suite de pruebas GREEN para engine.src.sanitizer.

Valida que la sanitizacion de ServiceResult es correcta, determinista
y no filtra secretos en ningun escenario cubierto por la SPEC §3.2.2.
Todos los tests deben PASAR en la fase GREEN.

Los valores de tokens usados en estos tests son ficticios y no corresponden
a credenciales reales de ninguna plataforma o servicio.

Fase TDD: GREEN
Trazabilidad: TSK-F1_1.0-06-GREEN / docs/f1_1.0/f1_1.0_spec.md §3.2.2
"""

import pytest

from engine.src.models import CheckStatus, ServiceResult
from engine.src.sanitizer import sanitize_service_result
from engine.src.utils import sanitize_log_message, sanitize_secret


# ===========================================================================
# Grupo 1: sanitize_service_result — redaccion de secretos explícitos
# ===========================================================================


def test_sanitize_service_result_redacts_secret_in_message():
    """Un secreto presente en message debe quedar sustituido por [REDACTED]."""
    # Arrange
    fake_token = "ghp_fake_token_for_testing"
    result = ServiceResult(
        status=CheckStatus.OK,
        latency_ms=1.0,
        message=f"Conexion fallida con token={fake_token}",
    )

    # Act
    sanitized = sanitize_service_result(result, [fake_token])

    # Assert
    assert fake_token not in sanitized.message
    assert "[REDACTED]" in sanitized.message


def test_sanitize_service_result_redacts_bearer_token_header():
    """Authorization: Bearer <token> en message debe quedar redactado."""
    # Arrange
    result = ServiceResult(
        status=CheckStatus.ERROR,
        latency_ms=5.0,
        message="HTTP 401 - Authorization: Bearer ghp_fake_bearer_token_abc123",
    )

    # Act
    sanitized = sanitize_service_result(result, [])

    # Assert
    assert "ghp_fake_bearer_token_abc123" not in sanitized.message
    assert "Bearer ghp_fake_bearer_token_abc123" not in sanitized.message
    assert "[REDACTED]" in sanitized.message


def test_sanitize_service_result_redacts_token_header():
    """Authorization: token <valor> en message debe quedar redactado."""
    # Arrange
    result = ServiceResult(
        status=CheckStatus.ERROR,
        latency_ms=5.0,
        message="HTTP 403 - Authorization: token ghp_fake_token_abc123",
    )

    # Act
    sanitized = sanitize_service_result(result, [])

    # Assert
    assert "ghp_fake_token_abc123" not in sanitized.message
    assert "token ghp_fake_token_abc123" not in sanitized.message
    assert "[REDACTED]" in sanitized.message


# ===========================================================================
# Grupo 2: sanitize_service_result — invariantes de inmutabilidad
# ===========================================================================


def test_sanitize_service_result_preserves_status_and_latency():
    """La sanitizacion NO debe alterar status ni latency_ms del ServiceResult."""
    # Arrange
    fake_key = "re_fake_resend_api_key_for_test"
    result = ServiceResult(
        status=CheckStatus.WARNING,
        latency_ms=123.456,
        message=f"Advertencia: clave={fake_key}",
    )

    # Act
    sanitized = sanitize_service_result(result, [fake_key])

    # Assert
    assert sanitized.status == CheckStatus.WARNING
    assert sanitized.latency_ms == 123.456


def test_sanitize_service_result_none_message_unchanged():
    """Si message es None, el ServiceResult debe retornarse sin cambios."""
    # Arrange
    result = ServiceResult(
        status=CheckStatus.OK,
        latency_ms=10.0,
        message=None,
    )

    # Act
    sanitized = sanitize_service_result(result, ["algún_secreto_cualquiera"])

    # Assert
    assert sanitized.message is None
    assert sanitized is result  # mismo objeto, no copia


def test_sanitize_service_result_no_leak_of_short_secret():
    """Secreto de longitud < 2 no debe causar redaccion (comportamiento de
    sanitize_log_message: secretos cortos se ignoran silenciosamente)."""
    # Arrange
    short_secret = "x"  # longitud 1, debe ser ignorado
    result = ServiceResult(
        status=CheckStatus.OK,
        latency_ms=1.0,
        message="mensaje con x en el texto",
    )

    # Act
    sanitized = sanitize_service_result(result, [short_secret])

    # Assert: la 'x' NO debe ser redactada porque el secreto es demasiado corto
    assert "[REDACTED]" not in sanitized.message
    assert "x" in sanitized.message


def test_sanitize_service_result_does_not_mutate_original():
    """El ServiceResult original no debe ser modificado; se retorna una copia."""
    # Arrange
    fake_token = "eyJh_fake_jwt_token_for_mutation_test"
    original_message = f"Error con clave={fake_token}"
    result = ServiceResult(
        status=CheckStatus.ERROR,
        latency_ms=2.0,
        message=original_message,
    )

    # Act
    sanitized = sanitize_service_result(result, [fake_token])

    # Assert: el original no fue mutado
    assert result.message == original_message
    assert fake_token in result.message
    # Assert: la copia tiene el mensaje redactado
    assert fake_token not in sanitized.message
    assert sanitized is not result


# ===========================================================================
# Grupo 3: sanitize_log_message — multiples secretos
# ===========================================================================


def test_sanitize_log_message_multiple_secrets():
    """Un mensaje con multiples secretos distintos debe quedar completamente
    redactado sin dejar ninguna credencial en texto plano."""
    # Arrange
    secret_a = "re_fake_resend_key_12345"
    secret_b = "ghp_fake_github_token_67890"
    secret_c = "eyJh_fake_supabase_service_key"
    message = (
        f"Fallo al conectar: resend={secret_a}, "
        f"github={secret_b}, supabase={secret_c}"
    )

    # Act
    sanitized = sanitize_log_message(message, [secret_a, secret_b, secret_c])

    # Assert
    assert secret_a not in sanitized
    assert secret_b not in sanitized
    assert secret_c not in sanitized
    assert sanitized.count("[REDACTED]") == 3


# ===========================================================================
# Grupo 4: sanitize_secret — enmascaramiento de valor individual
# ===========================================================================


def test_sanitize_secret_short_value():
    """Un valor con menos de 5 caracteres debe retornar '****' completo."""
    # Arrange
    short_values = ["", "a", "ab", "abc", "abcd"]

    # Act / Assert
    for val in short_values:
        result = sanitize_secret(val)
        assert result == "****", (
            f"sanitize_secret('{val}') debio retornar '****' pero retorno '{result}'"
        )


def test_sanitize_secret_long_value():
    """Un valor de 5 o mas caracteres debe retornar los primeros 4 chars + '****'."""
    # Arrange
    test_cases = [
        ("ghp_AbCdEf123456", "ghp_****"),
        ("re_fake_api_key_for_tests", "re_f****"),
        ("eyJhbGciOiJIUzI1NiJ9", "eyJh****"),
        ("12345", "1234****"),
    ]

    # Act / Assert
    for value, expected in test_cases:
        result = sanitize_secret(value)
        assert result == expected, (
            f"sanitize_secret('{value}') debio retornar '{expected}' "
            f"pero retorno '{result}'"
        )

"""
Fixtures compartidas para la suite de pruebas del motor DonTolto.

Centraliza datos de prueba reutilizables y estados complejos siguiendo
el protocolo de aislamiento: sin llamadas reales a APIs ni red externa.

Trazabilidad: TSK-F1_1.0-04-RED / docs/f1_1.0/f1_1.0_spec.md
"""

import pytest


# ---------------------------------------------------------------------------
# Fixtures de identificadores
# ---------------------------------------------------------------------------


@pytest.fixture
def valid_run_id() -> str:
    """UUID v4 canónico para pruebas de RunReport."""
    return "550e8400-e29b-41d4-a716-446655440000"


@pytest.fixture
def invalid_run_id() -> str:
    """String que no es un UUID v4 valido."""
    return "not-a-uuid"


# ---------------------------------------------------------------------------
# Fixtures de variables de entorno validas
# ---------------------------------------------------------------------------


@pytest.fixture
def valid_env_vars() -> dict:
    """Conjunto completo de variables de entorno con valores que pasan todos
    los patrones de validacion definidos en ENV_VAR_PATTERNS (utils.py).

    Ninguno de estos valores corresponde a credenciales reales de produccion.
    """
    return {
        "SUPABASE_URL": "https://abcdef123456.supabase.co",
        "SUPABASE_SERVICE_ROLE_KEY": (
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
            "eyJyb2xlIjoic2VydmljZV9yb2xlIiwiaWF0IjoxNjAwMDAwMDAwfQ."
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        ),
        "POSTGRES_DB_URL": "postgresql://user:password@localhost:5432/postgres",
        "UPSTASH_REDIS_REST_URL": "https://my-redis.upstash.io",
        "UPSTASH_REDIS_REST_TOKEN": "a" * 25,
        "RESEND_API_KEY": "re_test_api_key_for_unit_tests",
        "GITHUB_TOKEN": "ghp_test_token_for_unit_tests_abc123",
        "ADMIN_UUID": "550e8400-e29b-41d4-a716-446655440000",
    }


@pytest.fixture
def valid_timestamp() -> str:
    """Timestamp ISO 8601 UTC valido para pruebas."""
    return "2026-04-07T00:00:00.000000+00:00"


# ---------------------------------------------------------------------------
# Fixtures de ServiceResult para pruebas de orquestacion
# ---------------------------------------------------------------------------


@pytest.fixture
def ok_result():
    """ServiceResult en estado OK con latencia minima.

    Usado para mockear checks exitosos en los tests del orquestador.
    Trazabilidad: TSK-F1_1.0-07-RED / docs/f1_1.0/f1_1.0_spec.md §1
    """
    from engine.src.models import ServiceResult

    return ServiceResult(status="OK", latency_ms=10.0)


@pytest.fixture
def error_result():
    """ServiceResult en estado ERROR con mensaje de fallo simulado.

    Usado para mockear checks criticos fallidos en los tests del orquestador.
    Trazabilidad: TSK-F1_1.0-07-RED / docs/f1_1.0/f1_1.0_spec.md §1
    """
    from engine.src.models import ServiceResult

    return ServiceResult(status="ERROR", latency_ms=1.0, message="fallo simulado")


@pytest.fixture
def warning_result():
    """ServiceResult en estado WARNING con mensaje de advertencia simulada.

    Usado para mockear checks no criticos con fallo leve en los tests del orquestador.
    Trazabilidad: TSK-F1_1.0-07-RED / docs/f1_1.0/f1_1.0_spec.md §1
    """
    from engine.src.models import ServiceResult

    return ServiceResult(status="WARNING", latency_ms=1.0, message="advertencia simulada")

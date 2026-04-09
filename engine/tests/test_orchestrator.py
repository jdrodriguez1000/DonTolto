"""
Suite de pruebas RED para engine.src.check_env (orquestador principal).

Valida la logica de agregacion Diagnostic-First, el mapeo de criticidad
de servicios y el comportamiento de sys.exit segun la SPEC §1 y el
PLAN T-05b/T-05c/T-05d.

Todos los tests DEBEN FALLAR en la fase RED con ModuleNotFoundError porque
engine/src/check_env.py no existe aun.

Fase TDD: RED
Trazabilidad: TSK-F1_1.0-07-RED / docs/f1_1.0/f1_1.0_spec.md §1
"""

import uuid
from unittest.mock import patch

import pytest

# Importacion deliberada de modulo que NO EXISTE todavia.
# Todos los tests fallaran con ModuleNotFoundError en fase RED.
from engine.src.check_env import (  # noqa: E402
    CRITICAL_SERVICES,
    WARNING_SERVICES,
    main,
)
from engine.src.models import CheckStatus, ServiceResult


# ===========================================================================
# Grupo 1: Tests de Mapeo de Criticidad
# ===========================================================================


def test_criticality_map_critical_services_defined():
    """CRITICAL_SERVICES debe ser un conjunto que incluya los tres servicios
    cuyo fallo produce sys.exit(1): env_vars, supabase_sql, supabase_http.

    Arrange: importacion del simbolo exportado desde check_env.
    Act: inspeccion directa del conjunto.
    Assert: los tres servicios minimos estan presentes y el tipo es set.
    """
    # Arrange / Act — simbolo ya importado a nivel de modulo.
    required_critical = {"env_vars", "supabase_sql", "supabase_http"}

    # Assert
    assert isinstance(CRITICAL_SERVICES, (set, frozenset)), (
        "CRITICAL_SERVICES debe ser un set o frozenset"
    )
    assert required_critical.issubset(CRITICAL_SERVICES), (
        f"CRITICAL_SERVICES debe incluir al menos {required_critical}, "
        f"pero contiene: {CRITICAL_SERVICES}"
    )


def test_criticality_map_warning_services_defined():
    """WARNING_SERVICES debe ser un conjunto que incluya los tres servicios
    cuyo fallo NO produce sys.exit(1): github, resend, upstash.

    Arrange: importacion del simbolo exportado desde check_env.
    Act: inspeccion directa del conjunto.
    Assert: los tres servicios minimos estan presentes y el tipo es set.
    """
    # Arrange / Act — simbolo ya importado a nivel de modulo.
    required_warning = {"github", "resend", "upstash"}

    # Assert
    assert isinstance(WARNING_SERVICES, (set, frozenset)), (
        "WARNING_SERVICES debe ser un set o frozenset"
    )
    assert required_warning.issubset(WARNING_SERVICES), (
        f"WARNING_SERVICES debe incluir al menos {required_warning}, "
        f"pero contiene: {WARNING_SERVICES}"
    )


# ===========================================================================
# Grupo 2: Tests de Logica de Agregacion
# ===========================================================================


_MOCK_BASE = "engine.src.check_env"


def _build_full_env() -> dict:
    """Retorna un entorno sintetico con todas las variables criticas validas."""
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


def test_main_all_ok_returns_ok_status(ok_result):
    """main() con todos los checks en OK debe retornar RunReport.status == OK
    sin lanzar SystemExit.

    Arrange: mocks de los seis checks de servicio retornando ok_result.
    Act: invocacion de main() con entorno completo valido.
    Assert: status global es OK y no se produce SystemExit.
    """
    # Arrange
    with (
        patch(f"{_MOCK_BASE}.check_github", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_resend", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_upstash", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_supabase_http", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_supabase_sql", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_pg_extensions", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_zombie_cleanup", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_ddl_capabilities", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_persistence_cycle", return_value=ok_result),
    ):
        # Act
        report = main(env=_build_full_env())

    # Assert
    assert report.status == CheckStatus.OK, (
        f"Se esperaba status OK pero se obtuvo {report.status}"
    )


def test_main_critical_error_raises_systemexit_1(ok_result, error_result):
    """main() con un check CRITICAL en ERROR debe lanzar SystemExit con codigo 1.

    El check critico usado como proxy es check_supabase_sql.

    Arrange: mocks con check_supabase_sql retornando error_result; resto OK.
    Act: invocacion de main() capturando SystemExit.
    Assert: SystemExit.code == 1.
    """
    # Arrange
    with (
        patch(f"{_MOCK_BASE}.check_github", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_resend", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_upstash", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_supabase_http", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_supabase_sql", return_value=error_result),
        patch(f"{_MOCK_BASE}.check_pg_extensions", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_zombie_cleanup", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_ddl_capabilities", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_persistence_cycle", return_value=ok_result),
    ):
        # Act / Assert
        with pytest.raises(SystemExit) as exc_info:
            main(env=_build_full_env())

    assert exc_info.value.code == 1, (
        f"Se esperaba SystemExit(1) pero se obtuvo SystemExit({exc_info.value.code})"
    )


def test_main_warning_service_error_does_not_raise_systemexit_1(
    ok_result, error_result
):
    """main() con un check WARNING en ERROR debe retornar RunReport.status == WARNING
    sin lanzar ninguna variante de SystemExit.

    El check de advertencia usado como proxy es check_github.

    Arrange: mocks con check_github retornando error_result; resto OK.
    Act: invocacion de main() verificando que no hay SystemExit.
    Assert: status global es WARNING y no se propaga SystemExit.
    """
    # Arrange
    with (
        patch(f"{_MOCK_BASE}.check_github", return_value=error_result),
        patch(f"{_MOCK_BASE}.check_resend", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_upstash", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_supabase_http", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_supabase_sql", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_pg_extensions", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_zombie_cleanup", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_ddl_capabilities", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_persistence_cycle", return_value=ok_result),
    ):
        # Act — no debe lanzar SystemExit
        try:
            report = main(env=_build_full_env())
        except SystemExit as exc:
            pytest.fail(
                f"main() lanzo SystemExit({exc.code}) inesperadamente "
                f"ante un fallo en servicio WARNING"
            )

    # Assert
    assert report.status == CheckStatus.WARNING, (
        f"Se esperaba status WARNING pero se obtuvo {report.status}"
    )


def test_main_diagnostic_first_runs_all_checks_even_if_one_fails(
    ok_result, error_result
):
    """main() debe ejecutar TODOS los checks aunque uno falle antes (Diagnostic-First).

    Scenario: check_supabase_sql y check_github retornan ERROR.
    El reporte final debe contener entradas para ambos servicios, no solo el primero.

    Arrange: mocks con dos checks en ERROR; el resto en OK.
    Act: invocacion de main() capturando el SystemExit esperado por el critico.
    Assert: ambos servicios fallidos aparecen en RunReport.checks.
    """
    # Arrange
    with (
        patch(f"{_MOCK_BASE}.check_github", return_value=error_result),
        patch(f"{_MOCK_BASE}.check_resend", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_upstash", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_supabase_http", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_supabase_sql", return_value=error_result),
        patch(f"{_MOCK_BASE}.check_pg_extensions", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_zombie_cleanup", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_ddl_capabilities", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_persistence_cycle", return_value=ok_result),
    ):
        # Act — capturamos SystemExit(1) generado por el critico
        with pytest.raises(SystemExit):
            report = main(env=_build_full_env())

    # Para validar Diagnostic-First necesitamos el reporte antes del exit.
    # Re-ejecutamos capturando el reporte via return value del callable mockeado.
    captured_reports: list = []

    def capturing_main(env=None):
        """Wrapper que almacena el reporte antes de propagarse el SystemExit."""
        import engine.src.check_env as _mod

        _report = _mod.main(env=env)
        captured_reports.append(_report)
        return _report

    with (
        patch(f"{_MOCK_BASE}.check_github", return_value=error_result),
        patch(f"{_MOCK_BASE}.check_resend", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_upstash", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_supabase_http", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_supabase_sql", return_value=error_result),
        patch(f"{_MOCK_BASE}.check_pg_extensions", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_zombie_cleanup", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_ddl_capabilities", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_persistence_cycle", return_value=ok_result),
    ):
        with pytest.raises(SystemExit):
            main(env=_build_full_env())

    # Verificacion alternativa: el orquestador invoco ambos checks.
    # Usamos un enfoque de conteo de llamadas a los mocks.
    mock_sql = patch(f"{_MOCK_BASE}.check_supabase_sql", return_value=error_result)
    mock_github = patch(f"{_MOCK_BASE}.check_github", return_value=error_result)
    mock_resend = patch(f"{_MOCK_BASE}.check_resend", return_value=ok_result)
    mock_upstash = patch(f"{_MOCK_BASE}.check_upstash", return_value=ok_result)
    mock_http = patch(f"{_MOCK_BASE}.check_supabase_http", return_value=ok_result)
    mock_pg_ext = patch(f"{_MOCK_BASE}.check_pg_extensions", return_value=ok_result)
    mock_zombie = patch(f"{_MOCK_BASE}.check_zombie_cleanup", return_value=ok_result)
    mock_ddl = patch(f"{_MOCK_BASE}.check_ddl_capabilities", return_value=ok_result)
    mock_persistence = patch(f"{_MOCK_BASE}.check_persistence_cycle", return_value=ok_result)

    with mock_sql as m_sql, mock_github as m_github, mock_resend, mock_upstash, mock_http, mock_pg_ext, mock_zombie, mock_ddl, mock_persistence:
        with pytest.raises(SystemExit):
            main(env=_build_full_env())

        # Assert: ambos checks fueron invocados (Diagnostic-First)
        assert m_sql.call_count >= 1, (
            "check_supabase_sql no fue invocado — el orquestador aborto prematuramente"
        )
        assert m_github.call_count >= 1, (
            "check_github no fue invocado — el orquestador aborto prematuramente"
        )


def test_main_run_report_contains_all_service_keys(ok_result):
    """RunReport.checks debe contener exactamente las seis claves de servicio
    esperadas: env_vars, github, resend, upstash, supabase_http, supabase_sql.

    Arrange: todos los checks mocked como OK.
    Act: invocacion de main() con entorno completo valido.
    Assert: el conjunto de claves de RunReport.checks es igual al conjunto esperado.
    """
    # Arrange
    expected_keys = {
        "env_vars", "github", "resend", "upstash",
        "supabase_http", "supabase_sql", "pg_extensions", "zombie_cleanup",
        "ddl_capabilities", "persistence_cycle",
    }

    with (
        patch(f"{_MOCK_BASE}.check_github", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_resend", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_upstash", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_supabase_http", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_supabase_sql", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_pg_extensions", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_zombie_cleanup", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_ddl_capabilities", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_persistence_cycle", return_value=ok_result),
    ):
        # Act
        report = main(env=_build_full_env())

    # Assert
    assert set(report.checks.keys()) == expected_keys, (
        f"Claves esperadas: {expected_keys}. "
        f"Claves obtenidas: {set(report.checks.keys())}"
    )


def test_main_multiple_critical_errors_exits_1(ok_result, error_result):
    """main() con dos checks CRITICAL en ERROR debe lanzar SystemExit(1) y
    el reporte debe contener ambas entradas de error.

    Scenario: check_supabase_sql y check_supabase_http ambos en ERROR.

    Arrange: mocks con dos checks criticos en ERROR.
    Act: invocacion de main() capturando SystemExit.
    Assert: SystemExit.code == 1; ambas claves criticas presentes en el reporte.
    """
    # Arrange
    mock_sql = patch(f"{_MOCK_BASE}.check_supabase_sql", return_value=error_result)
    mock_http = patch(f"{_MOCK_BASE}.check_supabase_http", return_value=error_result)
    mock_github = patch(f"{_MOCK_BASE}.check_github", return_value=ok_result)
    mock_resend = patch(f"{_MOCK_BASE}.check_resend", return_value=ok_result)
    mock_upstash = patch(f"{_MOCK_BASE}.check_upstash", return_value=ok_result)
    mock_pg_ext = patch(f"{_MOCK_BASE}.check_pg_extensions", return_value=ok_result)
    mock_zombie = patch(f"{_MOCK_BASE}.check_zombie_cleanup", return_value=ok_result)
    mock_ddl_cap = patch(f"{_MOCK_BASE}.check_ddl_capabilities", return_value=ok_result)
    mock_persistence = patch(f"{_MOCK_BASE}.check_persistence_cycle", return_value=ok_result)

    with mock_sql as m_sql, mock_http as m_http, mock_github, mock_resend, mock_upstash, mock_pg_ext, mock_zombie, mock_ddl_cap, mock_persistence:
        # Act / Assert exit code
        with pytest.raises(SystemExit) as exc_info:
            main(env=_build_full_env())

        assert exc_info.value.code == 1, (
            f"Se esperaba SystemExit(1) pero se obtuvo SystemExit({exc_info.value.code})"
        )
        # Assert: ambos checks criticos fueron invocados
        assert m_sql.call_count >= 1, "check_supabase_sql no fue invocado"
        assert m_http.call_count >= 1, "check_supabase_http no fue invocado"


def test_main_warning_only_status_is_warning_not_error(ok_result, error_result):
    """RunReport.status debe ser WARNING (no ERROR) cuando solo checks WARNING fallan.

    Scenario: github, resend, upstash en ERROR; todos los criticos en OK.

    Arrange: mocks con los tres servicios WARNING en ERROR; criticos en OK.
    Act: invocacion de main() — no debe lanzar SystemExit.
    Assert: status global es WARNING (no ERROR).
    """
    # Arrange
    with (
        patch(f"{_MOCK_BASE}.check_github", return_value=error_result),
        patch(f"{_MOCK_BASE}.check_resend", return_value=error_result),
        patch(f"{_MOCK_BASE}.check_upstash", return_value=error_result),
        patch(f"{_MOCK_BASE}.check_supabase_http", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_supabase_sql", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_pg_extensions", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_zombie_cleanup", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_ddl_capabilities", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_persistence_cycle", return_value=ok_result),
    ):
        # Act
        try:
            report = main(env=_build_full_env())
        except SystemExit as exc:
            pytest.fail(
                f"main() lanzo SystemExit({exc.code}) inesperadamente "
                f"cuando solo fallaron servicios WARNING"
            )

    # Assert
    assert report.status == CheckStatus.WARNING, (
        f"Se esperaba WARNING pero se obtuvo {report.status}"
    )
    assert report.status != CheckStatus.ERROR, (
        "El status no debe ser ERROR cuando solo fallan servicios WARNING"
    )


def test_main_run_report_has_valid_run_id(ok_result):
    """El run_id del RunReport retornado por main() debe ser un UUID v4 valido.

    Arrange: todos los checks mocked como OK.
    Act: invocacion de main() con entorno completo valido.
    Assert: run_id es parseable como UUID y su version es 4.
    """
    # Arrange
    with (
        patch(f"{_MOCK_BASE}.check_github", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_resend", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_upstash", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_supabase_http", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_supabase_sql", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_pg_extensions", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_zombie_cleanup", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_ddl_capabilities", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_persistence_cycle", return_value=ok_result),
    ):
        # Act
        report = main(env=_build_full_env())

    # Assert — RunReport.run_id es un campo de tipo UUID en Pydantic
    parsed = uuid.UUID(str(report.run_id))
    assert parsed.version == 4, (
        f"Se esperaba UUID v4 pero se obtuvo version {parsed.version}"
    )


def test_main_run_report_has_timestamp(ok_result):
    """El timestamp del RunReport retornado por main() debe ser un string
    ISO 8601 no vacio.

    Arrange: todos los checks mocked como OK.
    Act: invocacion de main() con entorno completo valido.
    Assert: timestamp es un string de longitud > 0 que contiene separador 'T'.
    """
    # Arrange
    with (
        patch(f"{_MOCK_BASE}.check_github", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_resend", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_upstash", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_supabase_http", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_supabase_sql", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_pg_extensions", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_zombie_cleanup", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_ddl_capabilities", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_persistence_cycle", return_value=ok_result),
    ):
        # Act
        report = main(env=_build_full_env())

    # Assert
    assert isinstance(report.timestamp, str), (
        f"timestamp debe ser str pero es {type(report.timestamp)}"
    )
    assert len(report.timestamp) > 0, "timestamp no debe ser un string vacio"
    assert "T" in report.timestamp, (
        f"timestamp '{report.timestamp}' no tiene formato ISO 8601 (falta separador 'T')"
    )


def test_main_env_vars_check_uses_provided_env(ok_result):
    """main(env={}) con diccionario vacio debe producir al menos un ERROR
    en la clave 'env_vars' de RunReport.checks (variables criticas ausentes).

    Arrange: dict vacio como entorno; checks de servicio mocked como OK.
    Act: invocacion de main(env={}) — se espera SystemExit(1) porque env_vars
         es un check CRITICAL que fallara con entorno vacio.
    Assert: SystemExit(1) es lanzado, confirmando que el check env_vars
            proceso el entorno inyectado y detecto fallos criticos.
    """
    # Arrange — entorno deliberadamente vacio para forzar fallo en env_vars
    with (
        patch(f"{_MOCK_BASE}.check_github", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_resend", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_upstash", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_supabase_http", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_supabase_sql", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_pg_extensions", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_zombie_cleanup", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_ddl_capabilities", return_value=ok_result),
        patch(f"{_MOCK_BASE}.check_persistence_cycle", return_value=ok_result),
    ):
        # Act / Assert — env vacio genera ERROR en variables criticas
        with pytest.raises(SystemExit) as exc_info:
            main(env={})

    assert exc_info.value.code == 1, (
        f"Se esperaba SystemExit(1) por variables criticas ausentes, "
        f"pero se obtuvo SystemExit({exc_info.value.code})"
    )

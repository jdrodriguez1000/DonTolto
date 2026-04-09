"""
Suite de pruebas VERIF para inyeccion de fallas y comportamiento Hard-Gate.

Valida que el orquestador main() respeta el contrato de exit code 1 ante
secretos invalidos o fallos en servicios CRITICOS, que los servicios WARNING
no provoquen SystemExit, y que el RunReport emitido antes del exit contenga
informacion diagnostica suficiente para auditar el fallo.

Arquitectura de aislamiento: todos los checks de red son mocked para
garantizar que ninguna llamada real llega a servicios externos.

Fase TDD: VERIF
Trazabilidad: TSK-F1_1.0-18.2-VERIF / docs/f1_1.0/f1_1.0_spec.md §6 / PLAN T-13
"""

import json
from unittest.mock import patch

import pytest

from engine.src.check_env import main
from engine.src.models import CheckStatus, ServiceResult

# ---------------------------------------------------------------------------
# Constante de aislamiento de rutas de mock
# ---------------------------------------------------------------------------

_MOCK_BASE = "engine.src.check_env"


# ---------------------------------------------------------------------------
# Helpers internos
# ---------------------------------------------------------------------------


def _ok() -> ServiceResult:
    """ServiceResult canonico de estado OK para mocks de servicios de red."""
    return ServiceResult(status="OK", latency_ms=5.0)


def _error(message: str = "fallo inyectado") -> ServiceResult:
    """ServiceResult canonico de estado ERROR para mocks de inyeccion de fallo."""
    return ServiceResult(status="ERROR", latency_ms=1.0, message=message)


def _all_network_ok_patches():
    """Contexto que mockea todos los checks de red externos retornando OK.

    Cubre la totalidad de los servicios externos para aislar el comportamiento
    bajo prueba (env vars inválidas) sin generar llamadas reales.
    """
    return (
        patch(f"{_MOCK_BASE}.check_github", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_resend", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_upstash", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_supabase_http", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_supabase_sql", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_pg_extensions", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_zombie_cleanup", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_ddl_capabilities", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_persistence_cycle", return_value=_ok()),
    )


# ===========================================================================
# Grupo 1 — Exit code ante secretos invalidos (Hard-Gate)
# ===========================================================================


def test_main_exits_1_when_supabase_url_invalid(valid_env_vars):
    """main() debe lanzar SystemExit(1) cuando SUPABASE_URL esta vacio.

    SUPABASE_URL es una variable CRITICA (is_critical=True en ENV_VAR_PATTERNS).
    Un valor vacio no satisface el patron regex esperado, lo que genera
    un ServiceResult ERROR en env_vars y obliga al exit code 1.

    Arrange: entorno valido con SUPABASE_URL sobreescrita a "".
    Act: llamar main() mocked de todos los checks de red.
    Assert: SystemExit con codigo 1.

    Trazabilidad: TSK-F1_1.0-18.2-VERIF / SPEC §6
    """
    # Arrange
    env = dict(valid_env_vars)
    env["SUPABASE_URL"] = ""

    # Act / Assert
    with (
        patch(f"{_MOCK_BASE}.check_github", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_resend", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_upstash", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_supabase_http", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_supabase_sql", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_pg_extensions", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_zombie_cleanup", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_ddl_capabilities", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_persistence_cycle", return_value=_ok()),
    ):
        with pytest.raises(SystemExit) as exc_info:
            main(env=env)

    assert exc_info.value.code == 1, (
        f"Se esperaba SystemExit(1) por SUPABASE_URL vacia, "
        f"pero se obtuvo SystemExit({exc_info.value.code})"
    )


def test_main_exits_1_when_supabase_service_role_key_missing(valid_env_vars):
    """main() debe lanzar SystemExit(1) cuando SUPABASE_SERVICE_ROLE_KEY esta vacio.

    SUPABASE_SERVICE_ROLE_KEY es una variable CRITICA. Un valor vacio no
    satisface el patron JWT (^eyJh.{116,}$), produciendo ERROR en env_vars.

    Arrange: entorno valido con SUPABASE_SERVICE_ROLE_KEY sobreescrita a "".
    Act: llamar main() con todos los checks de red mocked como OK.
    Assert: SystemExit con codigo 1.

    Trazabilidad: TSK-F1_1.0-18.2-VERIF / SPEC §6
    """
    # Arrange
    env = dict(valid_env_vars)
    env["SUPABASE_SERVICE_ROLE_KEY"] = ""

    # Act / Assert
    with (
        patch(f"{_MOCK_BASE}.check_github", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_resend", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_upstash", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_supabase_http", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_supabase_sql", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_pg_extensions", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_zombie_cleanup", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_ddl_capabilities", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_persistence_cycle", return_value=_ok()),
    ):
        with pytest.raises(SystemExit) as exc_info:
            main(env=env)

    assert exc_info.value.code == 1, (
        f"Se esperaba SystemExit(1) por SUPABASE_SERVICE_ROLE_KEY vacia, "
        f"pero se obtuvo SystemExit({exc_info.value.code})"
    )


def test_main_exits_1_when_postgres_db_url_malformed(valid_env_vars):
    """main() debe lanzar SystemExit(1) cuando POSTGRES_DB_URL no cumple el patron esperado.

    POSTGRES_DB_URL es una variable CRITICA. El valor 'not-a-valid-url' no
    satisface el patron postgresql://.*:.*@.*:[0-9]{4,5}/postgres, generando
    ERROR en env_vars y forzando el exit code 1.

    Arrange: entorno valido con POSTGRES_DB_URL sobreescrita a valor malformado.
    Act: llamar main() con todos los checks de red mocked como OK.
    Assert: SystemExit con codigo 1.

    Trazabilidad: TSK-F1_1.0-18.2-VERIF / SPEC §6
    """
    # Arrange
    env = dict(valid_env_vars)
    env["POSTGRES_DB_URL"] = "not-a-valid-url"

    # Act / Assert
    with (
        patch(f"{_MOCK_BASE}.check_github", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_resend", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_upstash", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_supabase_http", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_supabase_sql", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_pg_extensions", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_zombie_cleanup", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_ddl_capabilities", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_persistence_cycle", return_value=_ok()),
    ):
        with pytest.raises(SystemExit) as exc_info:
            main(env=env)

    assert exc_info.value.code == 1, (
        f"Se esperaba SystemExit(1) por POSTGRES_DB_URL malformada, "
        f"pero se obtuvo SystemExit({exc_info.value.code})"
    )


def test_main_exits_1_when_critical_service_check_fails(valid_env_vars):
    """main() debe llamar sys.exit(1) cuando un servicio CRITICO retorna ERROR.

    check_supabase_sql es un servicio CRITICO. Su fallo con ServiceResult ERROR
    debe activar el Hard-Gate y terminar el proceso con codigo 1, independientemente
    del estado del resto de los servicios.

    Arrange: env valido; check_supabase_sql mockeado con ERROR.
    Act: llamar main(env=valid_env_vars).
    Assert: SystemExit con codigo 1.

    Trazabilidad: TSK-F1_1.0-18.2-VERIF / SPEC §6
    """
    error_result = ServiceResult(status="ERROR", latency_ms=1.0, message="connection refused")

    with (
        patch(f"{_MOCK_BASE}.check_supabase_sql", return_value=error_result),
        patch(f"{_MOCK_BASE}.check_supabase_http", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_github", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_resend", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_upstash", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_pg_extensions", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_zombie_cleanup", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_ddl_capabilities", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_persistence_cycle", return_value=_ok()),
    ):
        with pytest.raises(SystemExit) as exc_info:
            main(env=valid_env_vars)

    assert exc_info.value.code == 1, (
        f"Se esperaba SystemExit(1) por check_supabase_sql ERROR, "
        f"pero se obtuvo SystemExit({exc_info.value.code})"
    )


def test_main_exits_1_when_supabase_http_check_fails(valid_env_vars):
    """main() debe llamar sys.exit(1) cuando check_supabase_http retorna ERROR.

    check_supabase_http es un servicio CRITICO. Su fallo debe activar el
    Hard-Gate de la misma forma que check_supabase_sql.

    Arrange: env valido; check_supabase_http mockeado con ERROR.
    Act: llamar main(env=valid_env_vars).
    Assert: SystemExit con codigo 1.

    Trazabilidad: TSK-F1_1.0-18.2-VERIF / SPEC §6
    """
    error_result = ServiceResult(status="ERROR", latency_ms=1.0, message="HTTP 401 Unauthorized")

    with (
        patch(f"{_MOCK_BASE}.check_supabase_http", return_value=error_result),
        patch(f"{_MOCK_BASE}.check_supabase_sql", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_github", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_resend", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_upstash", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_pg_extensions", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_zombie_cleanup", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_ddl_capabilities", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_persistence_cycle", return_value=_ok()),
    ):
        with pytest.raises(SystemExit) as exc_info:
            main(env=valid_env_vars)

    assert exc_info.value.code == 1, (
        f"Se esperaba SystemExit(1) por check_supabase_http ERROR, "
        f"pero se obtuvo SystemExit({exc_info.value.code})"
    )


# ===========================================================================
# Grupo 2 — NO exit ante fallos no criticos
# ===========================================================================


def test_main_does_not_exit_when_only_github_fails(valid_env_vars):
    """main() NO debe lanzar SystemExit cuando solo check_github retorna ERROR.

    github es un servicio WARNING. Su fallo eleva el status global a WARNING
    pero no activa el Hard-Gate. El RunReport debe tener status WARNING.

    Arrange: env valido; check_github mockeado con ERROR; todos los criticos OK.
    Act: llamar main(env=valid_env_vars).
    Assert: no se lanza SystemExit; report.status == WARNING.

    Trazabilidad: TSK-F1_1.0-18.2-VERIF / SPEC §6
    """
    error_github = ServiceResult(status="ERROR", latency_ms=1.0, message="401 Unauthorized")

    with (
        patch(f"{_MOCK_BASE}.check_github", return_value=error_github),
        patch(f"{_MOCK_BASE}.check_resend", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_upstash", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_supabase_http", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_supabase_sql", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_pg_extensions", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_zombie_cleanup", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_ddl_capabilities", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_persistence_cycle", return_value=_ok()),
    ):
        try:
            report = main(env=valid_env_vars)
        except SystemExit as exc:
            pytest.fail(
                f"main() lanzo SystemExit({exc.code}) inesperadamente "
                f"cuando solo fallo el servicio WARNING 'github'"
            )

    assert report.status == CheckStatus.WARNING, (
        f"Se esperaba status WARNING pero se obtuvo {report.status}"
    )


def test_main_does_not_exit_when_only_resend_fails(valid_env_vars):
    """main() NO debe lanzar SystemExit cuando solo check_resend retorna ERROR.

    resend es un servicio WARNING. Su fallo eleva el status a WARNING pero
    no activa el Hard-Gate.

    Arrange: env valido; check_resend mockeado con ERROR; todos los criticos OK.
    Act: llamar main(env=valid_env_vars).
    Assert: no se lanza SystemExit; report.status == WARNING.

    Trazabilidad: TSK-F1_1.0-18.2-VERIF / SPEC §6
    """
    error_resend = ServiceResult(status="ERROR", latency_ms=1.0, message="API key invalida")

    with (
        patch(f"{_MOCK_BASE}.check_github", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_resend", return_value=error_resend),
        patch(f"{_MOCK_BASE}.check_upstash", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_supabase_http", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_supabase_sql", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_pg_extensions", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_zombie_cleanup", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_ddl_capabilities", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_persistence_cycle", return_value=_ok()),
    ):
        try:
            report = main(env=valid_env_vars)
        except SystemExit as exc:
            pytest.fail(
                f"main() lanzo SystemExit({exc.code}) inesperadamente "
                f"cuando solo fallo el servicio WARNING 'resend'"
            )

    assert report.status == CheckStatus.WARNING, (
        f"Se esperaba status WARNING pero se obtuvo {report.status}"
    )


def test_main_does_not_exit_when_only_upstash_fails(valid_env_vars):
    """main() NO debe lanzar SystemExit cuando solo check_upstash retorna ERROR.

    upstash es un servicio WARNING. Su fallo eleva el status a WARNING pero
    no activa el Hard-Gate.

    Arrange: env valido; check_upstash mockeado con ERROR; todos los criticos OK.
    Act: llamar main(env=valid_env_vars).
    Assert: no se lanza SystemExit; report.status == WARNING.

    Trazabilidad: TSK-F1_1.0-18.2-VERIF / SPEC §6
    """
    error_upstash = ServiceResult(status="ERROR", latency_ms=1.0, message="timeout de conexion")

    with (
        patch(f"{_MOCK_BASE}.check_github", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_resend", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_upstash", return_value=error_upstash),
        patch(f"{_MOCK_BASE}.check_supabase_http", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_supabase_sql", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_pg_extensions", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_zombie_cleanup", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_ddl_capabilities", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_persistence_cycle", return_value=_ok()),
    ):
        try:
            report = main(env=valid_env_vars)
        except SystemExit as exc:
            pytest.fail(
                f"main() lanzo SystemExit({exc.code}) inesperadamente "
                f"cuando solo fallo el servicio WARNING 'upstash'"
            )

    assert report.status == CheckStatus.WARNING, (
        f"Se esperaba status WARNING pero se obtuvo {report.status}"
    )


# ===========================================================================
# Grupo 3 — Claridad del reporte ante fallo
# ===========================================================================


def test_main_report_contains_error_detail_on_critical_failure(valid_env_vars, capsys):
    """El JSON impreso a stdout debe contener status ERROR y el servicio critico fallido.

    Cuando check_supabase_sql devuelve ERROR, el RunReport emitido antes del
    sys.exit(1) debe contener 'status': 'ERROR' en el nivel global y el
    servicio 'supabase_sql' debe estar presente en 'checks' con status ERROR.

    Arrange: env valido; check_supabase_sql mockeado con ERROR y mensaje especifico.
    Act: capturar SystemExit; leer stdout capturado con capsys.
    Assert: JSON tiene status "ERROR" y checks.supabase_sql.status es "ERROR".

    Trazabilidad: TSK-F1_1.0-18.2-VERIF / SPEC §6
    """
    error_result = ServiceResult(
        status="ERROR", latency_ms=1.0, message="connection refused"
    )

    with (
        patch(f"{_MOCK_BASE}.check_supabase_sql", return_value=error_result),
        patch(f"{_MOCK_BASE}.check_supabase_http", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_github", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_resend", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_upstash", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_pg_extensions", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_zombie_cleanup", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_ddl_capabilities", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_persistence_cycle", return_value=_ok()),
    ):
        with pytest.raises(SystemExit):
            main(env=valid_env_vars)

    captured = capsys.readouterr()
    stdout_text = captured.out.strip()

    assert stdout_text, "stdout no debe estar vacio — se esperaba JSON del RunReport"

    parsed = json.loads(stdout_text)

    assert parsed.get("status") == "ERROR", (
        f"El JSON debe tener 'status': 'ERROR' pero tiene 'status': '{parsed.get('status')}'"
    )
    assert "checks" in parsed, "El JSON debe contener la clave 'checks'"
    assert "supabase_sql" in parsed["checks"], (
        f"El JSON debe contener la entrada 'supabase_sql' en 'checks'. "
        f"Claves actuales: {list(parsed['checks'].keys())}"
    )
    assert parsed["checks"]["supabase_sql"]["status"] == "ERROR", (
        f"checks.supabase_sql.status debe ser 'ERROR' pero es "
        f"'{parsed['checks']['supabase_sql']['status']}'"
    )


def test_main_report_global_status_is_warning_when_non_critical_fails(valid_env_vars):
    """El RunReport retornado debe tener status WARNING cuando solo fallan servicios WARNING.

    Cuando check_github falla con ERROR y todos los criticos son OK, el
    status global computado debe ser WARNING (no ERROR), reflejando que el
    entorno es operativo con degradacion parcial no critica.

    Arrange: env valido; check_github mockeado con ERROR; criticos OK.
    Act: llamar main(env=valid_env_vars) — no debe lanzar SystemExit.
    Assert: report.status == CheckStatus.WARNING.

    Trazabilidad: TSK-F1_1.0-18.2-VERIF / SPEC §6
    """
    error_github = ServiceResult(status="ERROR", latency_ms=1.0, message="403 Forbidden")

    with (
        patch(f"{_MOCK_BASE}.check_github", return_value=error_github),
        patch(f"{_MOCK_BASE}.check_resend", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_upstash", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_supabase_http", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_supabase_sql", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_pg_extensions", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_zombie_cleanup", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_ddl_capabilities", return_value=_ok()),
        patch(f"{_MOCK_BASE}.check_persistence_cycle", return_value=_ok()),
    ):
        report = main(env=valid_env_vars)

    assert report.status == CheckStatus.WARNING, (
        f"Se esperaba CheckStatus.WARNING pero se obtuvo {report.status}"
    )
    assert report.status != CheckStatus.ERROR, (
        "El status global no debe ser ERROR cuando solo fallan servicios WARNING"
    )


# ===========================================================================
# Grupo 4 — Diagnostico completo (Diagnostic-First)
# ===========================================================================


def test_main_runs_all_checks_even_when_critical_fails(valid_env_vars, capsys):
    """main() debe ejecutar y reportar TODOS los checks aunque uno CRITICO falle.

    El modelo Diagnostic-First garantiza que el orquestador no aborta ante el
    primer fallo. Ambos servicios fallidos (supabase_sql y github) deben
    aparecer en el RunReport emitido antes del sys.exit(1).

    Arrange: env valido; check_supabase_sql con ERROR; check_github con ERROR;
             resto mockeado como OK.
    Act: capturar SystemExit; inspeccionar stdout JSON.
    Assert: ambos servicios aparecen en 'checks' con sus respectivos estados ERROR;
            supabase_sql como CRITICO y github como WARNING.

    Trazabilidad: TSK-F1_1.0-18.2-VERIF / SPEC §6
    """
    error_sql = ServiceResult(
        status="ERROR", latency_ms=1.0, message="connection refused"
    )
    error_github = ServiceResult(
        status="ERROR", latency_ms=1.0, message="401 Unauthorized"
    )

    mock_sql = patch(f"{_MOCK_BASE}.check_supabase_sql", return_value=error_sql)
    mock_github = patch(f"{_MOCK_BASE}.check_github", return_value=error_github)
    mock_resend = patch(f"{_MOCK_BASE}.check_resend", return_value=_ok())
    mock_upstash = patch(f"{_MOCK_BASE}.check_upstash", return_value=_ok())
    mock_http = patch(f"{_MOCK_BASE}.check_supabase_http", return_value=_ok())
    mock_pg_ext = patch(f"{_MOCK_BASE}.check_pg_extensions", return_value=_ok())
    mock_zombie = patch(f"{_MOCK_BASE}.check_zombie_cleanup", return_value=_ok())
    mock_ddl = patch(f"{_MOCK_BASE}.check_ddl_capabilities", return_value=_ok())
    mock_persistence = patch(f"{_MOCK_BASE}.check_persistence_cycle", return_value=_ok())

    with (
        mock_sql as m_sql,
        mock_github as m_github,
        mock_resend,
        mock_upstash,
        mock_http,
        mock_pg_ext,
        mock_zombie,
        mock_ddl,
        mock_persistence,
    ):
        with pytest.raises(SystemExit):
            main(env=valid_env_vars)

        # Verificar que ambos checks fueron invocados (Diagnostic-First)
        assert m_sql.call_count >= 1, (
            "check_supabase_sql no fue invocado — el orquestador aborto prematuramente"
        )
        assert m_github.call_count >= 1, (
            "check_github no fue invocado — el orquestador aborto prematuramente"
        )

    # Verificar que el JSON emitido a stdout contiene ambos servicios fallidos
    captured = capsys.readouterr()
    stdout_text = captured.out.strip()

    assert stdout_text, "stdout no debe estar vacio — se esperaba JSON del RunReport"

    parsed = json.loads(stdout_text)
    checks = parsed.get("checks", {})

    assert "supabase_sql" in checks, (
        f"El reporte JSON debe contener 'supabase_sql' en 'checks'. "
        f"Claves actuales: {list(checks.keys())}"
    )
    assert "github" in checks, (
        f"El reporte JSON debe contener 'github' en 'checks'. "
        f"Claves actuales: {list(checks.keys())}"
    )
    assert checks["supabase_sql"]["status"] == "ERROR", (
        f"checks.supabase_sql.status debe ser 'ERROR' pero es "
        f"'{checks['supabase_sql']['status']}'"
    )
    assert checks["github"]["status"] == "ERROR", (
        f"checks.github.status debe ser 'ERROR' pero es "
        f"'{checks['github']['status']}'"
    )

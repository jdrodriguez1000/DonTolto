"""
Suite de pruebas GREEN para el output del orquestador (TSK-F1_1.0-08-GREEN).

Valida la salida JSON a stdout, el logging estructurado a stderr y la
escritura del reporte markdown en GITHUB_STEP_SUMMARY, segun la SPEC
§2.1, §3.2.2 y §6.

Aislamiento garantizado: sin llamadas reales a servicios externos.
Todos los checks de servicio son mocked via conftest.py (ok_result / error_result).

Fase TDD: GREEN
Trazabilidad: TSK-F1_1.0-08-GREEN / docs/f1_1.0/f1_1.0_spec.md §2.1, §3.2.2, §6
"""

import json
from pathlib import Path
from unittest.mock import patch

import pytest

from engine.src.check_env import main

# ---------------------------------------------------------------------------
# Constantes de aislamiento
# ---------------------------------------------------------------------------

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


# ===========================================================================
# Test 1: Salida JSON a stdout
# ===========================================================================


def test_main_prints_json_to_stdout(ok_result, capsys, monkeypatch):
    """main() debe imprimir el RunReport como JSON valido a stdout.

    El JSON debe contener las claves: run_id, status, checks.
    Los logs deben ir a stderr, no a stdout, para no contaminar el JSON.

    Arrange: todos los checks mocked como OK; GITHUB_STEP_SUMMARY ausente.
    Act: invocacion de main() con entorno valido; captura de stdout con capsys.
    Assert: stdout es JSON parseable con run_id, status y checks presentes.
    """
    # Arrange — asegurar que GITHUB_STEP_SUMMARY no esta definida
    monkeypatch.delenv("GITHUB_STEP_SUMMARY", raising=False)

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
        main(env=_build_full_env())

    # Assert
    captured = capsys.readouterr()
    stdout_text = captured.out.strip()

    assert stdout_text, "stdout no debe estar vacio — se esperaba JSON del RunReport"

    parsed = json.loads(stdout_text)

    assert "run_id" in parsed, f"El JSON no contiene 'run_id'. Keys: {list(parsed.keys())}"
    assert "status" in parsed, f"El JSON no contiene 'status'. Keys: {list(parsed.keys())}"
    assert "checks" in parsed, f"El JSON no contiene 'checks'. Keys: {list(parsed.keys())}"


# ===========================================================================
# Test 2: Logging estructurado a stderr
# ===========================================================================


def test_main_logs_to_stderr(ok_result, capsys, monkeypatch):
    """main() debe emitir logging estructurado a stderr durante su ejecucion.

    El stderr debe contener al menos una entrada con el patron '[INFO]'
    para garantizar que el canal de logging esta separado del canal de datos
    (stdout = JSON).

    Arrange: todos los checks mocked como OK; GITHUB_STEP_SUMMARY ausente.
    Act: invocacion de main() con entorno valido; captura de stderr con capsys.
    Assert: stderr contiene al menos una linea con '[INFO]'.
    """
    # Arrange
    monkeypatch.delenv("GITHUB_STEP_SUMMARY", raising=False)

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
        main(env=_build_full_env())

    # Assert
    captured = capsys.readouterr()
    stderr_text = captured.err

    assert "[INFO]" in stderr_text, (
        f"stderr debe contener al menos un '[INFO]'. stderr recibido:\n{stderr_text}"
    )


# ===========================================================================
# Test 3: Escritura de GITHUB_STEP_SUMMARY cuando la variable esta definida
# ===========================================================================


def test_main_writes_github_step_summary_when_env_set(ok_result, tmp_path, monkeypatch):
    """main() debe escribir la tabla markdown en el archivo apuntado por
    GITHUB_STEP_SUMMARY cuando la variable esta definida en os.environ.

    El archivo resultante debe contener una fila por cada uno de los seis
    servicios validados por el orquestador.

    Arrange: GITHUB_STEP_SUMMARY apunta a un archivo temporal; todos los
             checks mocked como OK.
    Act: invocacion de main() con entorno valido.
    Assert: el archivo existe y contiene las 6 filas de servicios esperadas.
    """
    # Arrange
    summary_file: Path = tmp_path / "summary.md"
    monkeypatch.setenv("GITHUB_STEP_SUMMARY", str(summary_file))

    expected_services = [
        "env_vars", "github", "resend", "upstash",
        "supabase_http", "supabase_sql", "pg_extensions", "zombie_cleanup",
        "ddl_capabilities", "persistence_cycle",
    ]

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
        main(env=_build_full_env())

    # Assert
    assert summary_file.exists(), (
        f"El archivo GITHUB_STEP_SUMMARY no fue creado en: {summary_file}"
    )

    content = summary_file.read_text(encoding="utf-8")

    for service in expected_services:
        assert service in content, (
            f"El summary no contiene la fila del servicio '{service}'.\n"
            f"Contenido del archivo:\n{content}"
        )


# ===========================================================================
# Test 4: No falla cuando GITHUB_STEP_SUMMARY no esta definida
# ===========================================================================


def test_main_skips_github_step_summary_when_env_not_set(ok_result, monkeypatch):
    """main() no debe lanzar excepcion ni crear archivos inesperados cuando
    GITHUB_STEP_SUMMARY no esta definida en os.environ.

    Arrange: GITHUB_STEP_SUMMARY eliminada de os.environ; todos los checks OK.
    Act: invocacion de main() con entorno valido.
    Assert: no se propaga ninguna excepcion.
    """
    # Arrange — garantizar ausencia de la variable
    monkeypatch.delenv("GITHUB_STEP_SUMMARY", raising=False)

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
        # Act / Assert — no debe propagar ninguna excepcion
        try:
            main(env=_build_full_env())
        except Exception as exc:
            pytest.fail(
                f"main() lanzo una excepcion inesperada cuando GITHUB_STEP_SUMMARY "
                f"no estaba definida: {type(exc).__name__}: {exc}"
            )


# ===========================================================================
# Test 5: El summary contiene emoji OK cuando todos los checks son OK
# ===========================================================================


def test_main_github_step_summary_contains_emoji_ok(ok_result, tmp_path, monkeypatch):
    """El archivo GITHUB_STEP_SUMMARY debe contener '✅ OK' cuando todos los
    checks retornan status OK.

    Arrange: GITHUB_STEP_SUMMARY apunta a un archivo temporal; todos los
             checks mocked como OK.
    Act: invocacion de main() con entorno valido.
    Assert: el contenido del archivo contiene '✅ OK'.
    """
    # Arrange
    summary_file: Path = tmp_path / "summary.md"
    monkeypatch.setenv("GITHUB_STEP_SUMMARY", str(summary_file))

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
        main(env=_build_full_env())

    # Assert
    content = summary_file.read_text(encoding="utf-8")
    assert "✅ OK" in content, (
        f"El summary debe contener '✅ OK' cuando todos los checks son OK.\n"
        f"Contenido del archivo:\n{content}"
    )


# ===========================================================================
# Test 6: El summary contiene emoji ERROR cuando un check critico falla
# ===========================================================================


def test_main_github_step_summary_contains_emoji_error(
    ok_result, error_result, tmp_path, monkeypatch
):
    """El archivo GITHUB_STEP_SUMMARY debe contener '❌ ERROR' cuando un check
    critico retorna ERROR, incluso antes de que main() llame a sys.exit(1).

    El summary debe ser escrito ANTES del sys.exit para garantizar trazabilidad
    completa en el pipeline de CI/CD.

    Arrange: GITHUB_STEP_SUMMARY apunta a un archivo temporal; check_supabase_sql
             mocked como ERROR (servicio critico); resto mocked como OK.
    Act: invocacion de main() capturando el SystemExit(1) esperado.
    Assert: el archivo existe y contiene '❌ ERROR'.
    """
    # Arrange
    summary_file: Path = tmp_path / "summary_error.md"
    monkeypatch.setenv("GITHUB_STEP_SUMMARY", str(summary_file))

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
        # Act — capturar SystemExit(1) esperado por el check critico fallido
        with pytest.raises(SystemExit) as exc_info:
            main(env=_build_full_env())

    # Assert exit code correcto
    assert exc_info.value.code == 1, (
        f"Se esperaba SystemExit(1) pero se obtuvo SystemExit({exc_info.value.code})"
    )

    # Assert summary escrito antes del exit
    assert summary_file.exists(), (
        f"El archivo GITHUB_STEP_SUMMARY no fue creado antes del sys.exit(1): {summary_file}"
    )

    content = summary_file.read_text(encoding="utf-8")
    assert "❌ ERROR" in content, (
        f"El summary debe contener '❌ ERROR' cuando un check critico falla.\n"
        f"Contenido del archivo:\n{content}"
    )

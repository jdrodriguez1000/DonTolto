"""
Suite de pruebas RED para las funciones check_supabase_http y check_supabase_sql
en engine.src.check_env.

Valida el contrato tecnico definido en la SPEC §2.2 y §3.3 para los dos
handshakes con Supabase: verificacion HTTP via PostgREST y conectividad directa
a PostgreSQL via psycopg2. Se valida el manejo de errores HTTP, errores de
conexion SQL, medicion de latencia, contrato de cabeceras y ausencia del
mensaje stub "not implemented".

Todos los tests DEBEN FALLAR en la fase RED porque las implementaciones actuales
son stubs que retornan WARNING con mensaje "not implemented" sin realizar ninguna
llamada HTTP real ni conexion a base de datos.

Fase TDD: RED
Trazabilidad: TSK-F1_1.0-10.4-RED / docs/f1_1.0/f1_1.0_spec.md §2.2, §3.3
"""

from unittest.mock import MagicMock, patch

import psycopg2
import pytest

from engine.src.check_env import check_supabase_http, check_supabase_sql
from engine.src.models import CheckStatus, ServiceResult


# ===========================================================================
# Helpers de construccion de mocks
# ===========================================================================


def _make_httpx_response(status_code: int) -> MagicMock:
    """Construye un mock de httpx.Response con el status code indicado.

    Args:
        status_code: Codigo HTTP de la respuesta simulada.

    Returns:
        MagicMock configurado para simular una respuesta httpx.
    """
    mock_response = MagicMock()
    mock_response.status_code = status_code
    return mock_response


def _make_psycopg2_mock() -> MagicMock:
    """Mock de psycopg2.connect con cursor que ejecuta SELECT 1 sin error.

    Configura un mock_conn que soporta tanto el uso como context manager
    (with psycopg2.connect(...) as conn) como el uso directo (conn.cursor()).

    Returns:
        MagicMock configurado para simular una conexion psycopg2 exitosa.
    """
    mock_conn = MagicMock()
    mock_cursor = MagicMock()
    mock_conn.cursor.return_value.__enter__ = MagicMock(return_value=mock_cursor)
    mock_conn.cursor.return_value.__exit__ = MagicMock(return_value=False)
    mock_conn.__enter__ = MagicMock(return_value=mock_conn)
    mock_conn.__exit__ = MagicMock(return_value=False)
    return mock_conn


# ===========================================================================
# Grupo 1: check_supabase_http — flujos exitosos y manejo de errores HTTP
# ===========================================================================


def test_check_supabase_http_returns_ok_on_200():
    """check_supabase_http debe retornar OK cuando PostgREST responde HTTP 200.

    Arrange: mock de httpx.get que retorna status 200.
    Act: invocar check_supabase_http con url y key ficticios.
    Assert: el status del ServiceResult es OK.

    Trazabilidad: SPEC §2.2 punto 2
    """
    # Arrange
    mock_response = _make_httpx_response(status_code=200)

    with patch("httpx.get", return_value=mock_response):
        # Act
        result: ServiceResult = check_supabase_http(
            url="https://abcdef123456.supabase.co",
            key="fake_service_role_key_for_test",
        )

    # Assert
    assert result.status == CheckStatus.OK, (
        f"Se esperaba OK ante HTTP 200, se obtuvo: {result.status}"
    )


def test_check_supabase_http_returns_error_on_401():
    """check_supabase_http debe retornar ERROR cuando PostgREST responde HTTP 401.

    Arrange: mock de httpx.get que retorna status 401.
    Act: invocar check_supabase_http con url y key ficticios.
    Assert: el status del ServiceResult es ERROR.

    Trazabilidad: SPEC §2.2 punto 3
    """
    # Arrange
    mock_response = _make_httpx_response(status_code=401)

    with patch("httpx.get", return_value=mock_response):
        # Act
        result: ServiceResult = check_supabase_http(
            url="https://abcdef123456.supabase.co",
            key="fake_service_role_key_for_test",
        )

    # Assert
    assert result.status == CheckStatus.ERROR, (
        f"Se esperaba ERROR ante HTTP 401, se obtuvo: {result.status}"
    )


def test_check_supabase_http_returns_error_on_403():
    """check_supabase_http debe retornar ERROR cuando PostgREST responde HTTP 403.

    Arrange: mock de httpx.get que retorna status 403.
    Act: invocar check_supabase_http con url y key ficticios.
    Assert: el status del ServiceResult es ERROR.

    Trazabilidad: SPEC §2.2 punto 3
    """
    # Arrange
    mock_response = _make_httpx_response(status_code=403)

    with patch("httpx.get", return_value=mock_response):
        # Act
        result: ServiceResult = check_supabase_http(
            url="https://abcdef123456.supabase.co",
            key="fake_service_role_key_for_test",
        )

    # Assert
    assert result.status == CheckStatus.ERROR, (
        f"Se esperaba ERROR ante HTTP 403, se obtuvo: {result.status}"
    )


# ===========================================================================
# Grupo 2: check_supabase_http — medicion de latencia e invocacion HTTP
# ===========================================================================


def test_check_supabase_http_measures_latency():
    """check_supabase_http debe registrar latencia mayor que cero e invocar httpx.get.

    El stub retorna latency_ms=0.1 hardcodeado sin instrumentar el tiempo real
    de la solicitud HTTP. La implementacion real debe medir la duracion efectiva
    de la llamada al endpoint /rest/v1/ e invocar httpx.get al menos una vez.

    Arrange: mock de httpx.get que retorna 200.
    Act: invocar check_supabase_http con url y key ficticios.
    Assert: latency_ms > 0 Y httpx.get fue invocado al menos una vez.

    Trazabilidad: SPEC §2.2
    """
    # Arrange
    mock_response = _make_httpx_response(status_code=200)

    with patch("httpx.get", return_value=mock_response) as mock_get:
        # Act
        result: ServiceResult = check_supabase_http(
            url="https://abcdef123456.supabase.co",
            key="fake_service_role_key_for_test",
        )

    # Assert
    assert result.latency_ms > 0, (
        f"latency_ms debe ser mayor que cero, se obtuvo: {result.latency_ms}"
    )
    mock_get.assert_called()


# ===========================================================================
# Grupo 3: check_supabase_http — contrato de mensaje
# ===========================================================================


def test_check_supabase_http_does_not_return_not_implemented_message():
    """check_supabase_http NO debe retornar el mensaje 'not implemented' del stub.

    El stub actual siempre devuelve message='not implemented'. La implementacion
    real debe retornar None o un mensaje semantico segun el resultado del check.
    Este test falla en RED porque el stub viola esta condicion.

    Arrange: mock de httpx.get que retorna 200.
    Act: invocar check_supabase_http con url y key ficticios.
    Assert: message != 'not implemented'.

    Trazabilidad: SPEC §2.2 (contrato de mensajes del servicio)
    """
    # Arrange
    mock_response = _make_httpx_response(status_code=200)

    with patch("httpx.get", return_value=mock_response):
        # Act
        result: ServiceResult = check_supabase_http(
            url="https://abcdef123456.supabase.co",
            key="fake_service_role_key_for_test",
        )

    # Assert
    assert result.message != "not implemented", (
        "El mensaje 'not implemented' es propio del stub y no debe aparecer "
        "en la implementacion real"
    )


# ===========================================================================
# Grupo 4: check_supabase_http — contrato de llamada HTTP (endpoint y cabeceras)
# ===========================================================================


def test_check_supabase_http_calls_rest_v1_endpoint():
    """check_supabase_http debe realizar GET a {url}/rest/v1/ segun SPEC §2.2 punto 1.

    La SPEC §2.2 define que la verificacion HTTP se realiza via GET al endpoint
    /rest/v1/ del proyecto Supabase. Cualquier otra ruta viola el contrato.

    Arrange: mock de httpx.get que retorna 200; url base ficticia.
    Act: invocar check_supabase_http con la url base.
    Assert: httpx.get fue llamado con una URL que termina en '/rest/v1/'.

    Trazabilidad: SPEC §2.2 punto 1
    """
    # Arrange
    base_url = "https://abcdef123456.supabase.co"
    mock_response = _make_httpx_response(status_code=200)

    with patch("httpx.get", return_value=mock_response) as mock_get:
        # Act
        check_supabase_http(url=base_url, key="fake_service_role_key_for_test")

    # Assert
    assert mock_get.called, "httpx.get debe haber sido invocado"
    call_args = mock_get.call_args
    called_url: str = (
        call_args.args[0] if call_args.args else call_args.kwargs.get("url", "")
    )
    assert called_url.endswith("/rest/v1/"), (
        f"Se esperaba una URL que termine en '/rest/v1/', se obtuvo: '{called_url}'"
    )


def test_check_supabase_http_sends_apikey_header():
    """check_supabase_http debe incluir el header 'apikey: <key>' en la solicitud.

    La SPEC §2.2 punto 1 especifica que la autenticacion incluye el header
    'apikey' con el Service Role Key. La ausencia de este header viola el contrato.

    Arrange: mock de httpx.get que retorna 200; key de prueba ficticia.
    Act: invocar check_supabase_http con la key de prueba.
    Assert: httpx.get fue llamado con un kwarg 'headers' que contiene la clave 'apikey'.

    Trazabilidad: SPEC §2.2 punto 1
    """
    # Arrange
    test_key = "fake_service_role_key_abc123"
    mock_response = _make_httpx_response(status_code=200)

    with patch("httpx.get", return_value=mock_response) as mock_get:
        # Act
        check_supabase_http(
            url="https://abcdef123456.supabase.co",
            key=test_key,
        )

    # Assert
    assert mock_get.called, "httpx.get debe haber sido invocado"
    call_kwargs = mock_get.call_args.kwargs
    headers_sent: dict = call_kwargs.get("headers", {})
    assert "apikey" in headers_sent, (
        "El header 'apikey' debe estar presente en la llamada a httpx.get"
    )


# ===========================================================================
# Grupo 5: check_supabase_sql — flujos exitosos y manejo de errores SQL
# ===========================================================================


def test_check_supabase_sql_returns_ok_on_successful_connection():
    """check_supabase_sql debe retornar OK cuando la conexion PostgreSQL es exitosa.

    Arrange: mock de psycopg2.connect que retorna un mock de conexion con cursor
             que ejecuta SELECT 1 sin error.
    Act: invocar check_supabase_sql con un db_url ficticio.
    Assert: el status del ServiceResult es OK.

    Trazabilidad: SPEC §3.3 punto 2
    """
    # Arrange
    mock_conn = _make_psycopg2_mock()

    with patch("psycopg2.connect", return_value=mock_conn):
        # Act
        result: ServiceResult = check_supabase_sql(
            db_url="postgresql://user:password@localhost:5432/postgres"
        )

    # Assert
    assert result.status == CheckStatus.OK, (
        f"Se esperaba OK ante conexion PostgreSQL exitosa, se obtuvo: {result.status}"
    )


def test_check_supabase_sql_returns_error_on_operational_error():
    """check_supabase_sql debe retornar ERROR cuando psycopg2 lanza OperationalError.

    Un OperationalError indica que la conexion fue rechazada o agoto el tiempo
    de espera (SQLState 08001 o 08006). La implementacion real debe capturarlo
    y retornar ERROR con un mensaje descriptivo.

    Arrange: mock de psycopg2.connect que lanza OperationalError("connection refused").
    Act: invocar check_supabase_sql con un db_url ficticio.
    Assert: el status del ServiceResult es ERROR.

    Trazabilidad: SPEC §3.3 punto 3
    """
    # Arrange
    with patch(
        "psycopg2.connect",
        side_effect=psycopg2.OperationalError("connection refused"),
    ):
        # Act
        result: ServiceResult = check_supabase_sql(
            db_url="postgresql://user:password@localhost:5432/postgres"
        )

    # Assert
    assert result.status == CheckStatus.ERROR, (
        f"Se esperaba ERROR ante OperationalError de psycopg2, se obtuvo: {result.status}"
    )


# ===========================================================================
# Grupo 6: check_supabase_sql — medicion de latencia e invocacion de psycopg2
# ===========================================================================


def test_check_supabase_sql_measures_latency():
    """check_supabase_sql debe registrar latencia mayor que cero e invocar psycopg2.connect.

    El stub retorna latency_ms=0.1 hardcodeado sin instrumentar el tiempo real
    de la conexion. La implementacion real debe medir la duracion efectiva de la
    conexion y consulta SELECT 1, e invocar psycopg2.connect al menos una vez.

    Arrange: mock de psycopg2.connect exitoso.
    Act: invocar check_supabase_sql con un db_url ficticio.
    Assert: latency_ms > 0 Y psycopg2.connect fue invocado al menos una vez.

    Trazabilidad: SPEC §3.3
    """
    # Arrange
    mock_conn = _make_psycopg2_mock()

    with patch("psycopg2.connect", return_value=mock_conn) as mock_connect:
        # Act
        result: ServiceResult = check_supabase_sql(
            db_url="postgresql://user:password@localhost:5432/postgres"
        )

    # Assert
    assert result.latency_ms > 0, (
        f"latency_ms debe ser mayor que cero, se obtuvo: {result.latency_ms}"
    )
    mock_connect.assert_called()


# ===========================================================================
# Grupo 7: check_supabase_sql — contrato de mensaje
# ===========================================================================


def test_check_supabase_sql_does_not_return_not_implemented_message():
    """check_supabase_sql NO debe retornar el mensaje 'not implemented' del stub.

    El stub actual siempre devuelve message='not implemented'. La implementacion
    real debe retornar None o un mensaje semantico segun el resultado del check.
    Este test falla en RED porque el stub viola esta condicion.

    Arrange: mock de psycopg2.connect exitoso.
    Act: invocar check_supabase_sql con un db_url ficticio.
    Assert: message != 'not implemented'.

    Trazabilidad: SPEC §3.3 (contrato de mensajes del servicio)
    """
    # Arrange
    mock_conn = _make_psycopg2_mock()

    with patch("psycopg2.connect", return_value=mock_conn):
        # Act
        result: ServiceResult = check_supabase_sql(
            db_url="postgresql://user:password@localhost:5432/postgres"
        )

    # Assert
    assert result.message != "not implemented", (
        "El mensaje 'not implemented' es propio del stub y no debe aparecer "
        "en la implementacion real"
    )


# ===========================================================================
# Grupo 8: check_supabase_sql — contrato de llamada (db_url correcto)
# ===========================================================================


def test_check_supabase_sql_calls_psycopg2_connect():
    """check_supabase_sql debe llamar a psycopg2.connect con el db_url proporcionado.

    La SPEC §3.3 punto 1 define que la conexion se realiza via psycopg2.connect
    pasando la URL completa de conexion PostgreSQL. Cualquier otra forma de
    conectar viola el contrato.

    Arrange: mock de psycopg2.connect exitoso; db_url de prueba especifica.
    Act: invocar check_supabase_sql con el db_url de prueba.
    Assert: psycopg2.connect fue llamado con el db_url exacto proporcionado.

    Trazabilidad: SPEC §3.3 punto 1
    """
    # Arrange
    test_db_url = "postgresql://user:password@db.supabase.co:5432/postgres"
    mock_conn = _make_psycopg2_mock()

    with patch("psycopg2.connect", return_value=mock_conn) as mock_connect:
        # Act
        check_supabase_sql(db_url=test_db_url)

    # Assert
    mock_connect.assert_called()
    called_args = mock_connect.call_args
    # El db_url puede pasarse como posicional o como keyword 'dsn'/'database'
    called_url: str = (
        called_args.args[0] if called_args.args else called_args.kwargs.get("dsn", "")
    )
    assert called_url == test_db_url, (
        f"psycopg2.connect debe haber sido llamado con '{test_db_url}', "
        f"se obtuvo: '{called_url}'"
    )

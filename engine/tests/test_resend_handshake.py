"""
Suite de pruebas RED para la funcion check_resend en engine.src.check_env.

Valida el contrato tecnico definido en la SPEC §2.2 para el handshake con
la API de Resend: autenticacion via Bearer token, manejo de errores HTTP
(401, 403, 5xx), medicion de latencia y verificacion del endpoint correcto.

Todos los tests DEBEN FALLAR en la fase RED porque la implementacion actual
es un stub que retorna WARNING con mensaje "not implemented" sin ejecutar
ninguna llamada HTTP real.

Fase TDD: RED
Trazabilidad: TSK-F1_1.0-10.2-RED / docs/f1_1.0/f1_1.0_spec.md §2.2
"""

from unittest.mock import MagicMock, patch

import pytest

from engine.src.check_env import check_resend
from engine.src.models import CheckStatus, ServiceResult


# ===========================================================================
# Helpers de construccion de mocks HTTP
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


# ===========================================================================
# Grupo 1: Flujo exitoso (HTTP 200)
# ===========================================================================


def test_check_resend_returns_ok_on_200():
    """check_resend debe retornar OK cuando la API responde 200.

    Arrange: mock de httpx.get que retorna status 200.
    Act: invocar check_resend con una api_key ficticia.
    Assert: el status del ServiceResult es OK.

    Trazabilidad: SPEC §2.2 punto 2
    """
    # Arrange
    mock_response = _make_httpx_response(status_code=200)

    with patch("httpx.get", return_value=mock_response):
        # Act
        result: ServiceResult = check_resend("re_fake_api_key_for_test")

    # Assert
    assert result.status == CheckStatus.OK, (
        f"Se esperaba OK ante HTTP 200, se obtuvo: {result.status}"
    )


# ===========================================================================
# Grupo 2: Manejo de errores HTTP (401 / 403 / 5xx)
# ===========================================================================


def test_check_resend_returns_error_on_401():
    """check_resend debe retornar ERROR cuando la API responde 401 Unauthorized.

    Arrange: mock de httpx.get que retorna status 401.
    Act: invocar check_resend con una api_key ficticia.
    Assert: el status del ServiceResult es ERROR.

    Trazabilidad: SPEC §2.2 punto 3
    """
    # Arrange
    mock_response = _make_httpx_response(status_code=401)

    with patch("httpx.get", return_value=mock_response):
        # Act
        result: ServiceResult = check_resend("re_fake_api_key_for_test")

    # Assert
    assert result.status == CheckStatus.ERROR, (
        f"Se esperaba ERROR ante HTTP 401, se obtuvo: {result.status}"
    )


def test_check_resend_returns_error_on_403():
    """check_resend debe retornar ERROR cuando la API responde 403 Forbidden.

    Arrange: mock de httpx.get que retorna status 403.
    Act: invocar check_resend con una api_key ficticia.
    Assert: el status del ServiceResult es ERROR.

    Trazabilidad: SPEC §2.2 punto 4
    """
    # Arrange
    mock_response = _make_httpx_response(status_code=403)

    with patch("httpx.get", return_value=mock_response):
        # Act
        result: ServiceResult = check_resend("re_fake_api_key_for_test")

    # Assert
    assert result.status == CheckStatus.ERROR, (
        f"Se esperaba ERROR ante HTTP 403, se obtuvo: {result.status}"
    )


def test_check_resend_returns_error_on_5xx():
    """check_resend debe retornar ERROR cuando la API responde 500 Internal Server Error.

    Arrange: mock de httpx.get que retorna status 500.
    Act: invocar check_resend con una api_key ficticia.
    Assert: el status del ServiceResult es ERROR.

    Trazabilidad: SPEC §2.2 punto 5
    """
    # Arrange
    mock_response = _make_httpx_response(status_code=500)

    with patch("httpx.get", return_value=mock_response):
        # Act
        result: ServiceResult = check_resend("re_fake_api_key_for_test")

    # Assert
    assert result.status == CheckStatus.ERROR, (
        f"Se esperaba ERROR ante HTTP 500, se obtuvo: {result.status}"
    )


# ===========================================================================
# Grupo 3: Medicion de latencia
# ===========================================================================


def test_check_resend_measures_latency():
    """check_resend debe registrar una latencia mayor que cero en respuestas exitosas
    y ejecutar la llamada HTTP real (no retornar valores hardcodeados del stub).

    El stub retorna latency_ms=0.1 hardcodeado sin instrumentar el tiempo real
    de la solicitud HTTP. La implementacion real debe medir la duracion efectiva
    de la llamada a la API y ademas invocar httpx.get efectivamente.

    Arrange: mock de httpx.get que retorna 200.
    Act: invocar check_resend con una api_key ficticia.
    Assert: latency_ms > 0 Y httpx.get fue invocado exactamente una vez.

    Trazabilidad: SPEC §2.2 punto 7
    """
    # Arrange
    mock_response = _make_httpx_response(status_code=200)

    with patch("httpx.get", return_value=mock_response) as mock_get:
        # Act
        result: ServiceResult = check_resend("re_fake_api_key_for_test")

    # Assert — la latencia debe ser positiva y la llamada HTTP debe haberse ejecutado
    assert result.latency_ms > 0, (
        f"latency_ms debe ser mayor que cero, se obtuvo: {result.latency_ms}"
    )
    # Verificacion adicional: httpx.get fue efectivamente invocado
    mock_get.assert_called_once()


# ===========================================================================
# Grupo 4: Coherencia del mensaje retornado
# ===========================================================================


def test_check_resend_does_not_return_not_implemented_message():
    """check_resend NO debe retornar el mensaje 'not implemented' del stub.

    El stub actual siempre devuelve message='not implemented'. La implementacion
    real debe retornar None o un mensaje semantico segun el resultado del check.
    Este test falla en RED porque el stub viola esta condicion.

    Arrange: mock de httpx.get que retorna 200.
    Act: invocar check_resend con una api_key ficticia.
    Assert: message != 'not implemented'.

    Trazabilidad: SPEC §2.2 (contrato de mensajes del servicio)
    """
    # Arrange
    mock_response = _make_httpx_response(status_code=200)

    with patch("httpx.get", return_value=mock_response):
        # Act
        result: ServiceResult = check_resend("re_fake_api_key_for_test")

    # Assert
    assert result.message != "not implemented", (
        "El mensaje 'not implemented' es propio del stub y no debe aparecer "
        "en la implementacion real"
    )


# ===========================================================================
# Grupo 5: Contrato de llamada HTTP (endpoint y cabeceras)
# ===========================================================================


def test_check_resend_calls_correct_endpoint():
    """check_resend debe realizar la solicitud GET a https://api.resend.com/api-keys.

    La SPEC §2.2 punto 1 define el endpoint exacto de verificacion de identidad
    de Resend. Cualquier otra URL constituye una violacion del contrato.

    Arrange: mock de httpx.get que retorna 200.
    Act: invocar check_resend con una api_key ficticia.
    Assert: httpx.get fue llamado con la URL 'https://api.resend.com/api-keys'
            como primer argumento posicional o como argumento 'url'.

    Trazabilidad: SPEC §2.2 punto 1
    """
    # Arrange
    mock_response = _make_httpx_response(status_code=200)

    with patch("httpx.get", return_value=mock_response) as mock_get:
        # Act
        check_resend("re_fake_api_key_for_test")

    # Assert — verificar que el primer argumento posicional es el endpoint correcto
    assert mock_get.called, "httpx.get debe haber sido invocado"
    call_args = mock_get.call_args
    # El endpoint puede pasarse como posicional o como keyword 'url'
    called_url = call_args.args[0] if call_args.args else call_args.kwargs.get("url")
    assert called_url == "https://api.resend.com/api-keys", (
        f"Se esperaba llamada a 'https://api.resend.com/api-keys', "
        f"se obtuvo: '{called_url}'"
    )


def test_check_resend_sends_bearer_auth_header():
    """check_resend debe incluir el header 'Authorization: Bearer <api_key>' en la solicitud.

    La SPEC §2.2 punto 1 especifica que la autenticacion se realiza mediante
    el esquema Bearer en el header Authorization. Pasar la clave por cualquier
    otro mecanismo viola el contrato.

    Arrange: mock de httpx.get que retorna 200; api_key de prueba con formato re_*.
    Act: invocar check_resend con la api_key de prueba.
    Assert: httpx.get fue llamado con un kwarg 'headers' que contiene
            la clave 'Authorization' con valor 'Bearer re_test_key_abc123'.

    Trazabilidad: SPEC §2.2 punto 1
    """
    # Arrange
    test_api_key = "re_test_key_abc123"
    mock_response = _make_httpx_response(status_code=200)

    with patch("httpx.get", return_value=mock_response) as mock_get:
        # Act
        check_resend(test_api_key)

    # Assert — los headers deben incluir Authorization: Bearer <api_key>
    assert mock_get.called, "httpx.get debe haber sido invocado"
    call_kwargs = mock_get.call_args.kwargs
    headers_sent: dict = call_kwargs.get("headers", {})
    assert "Authorization" in headers_sent, (
        "El header 'Authorization' debe estar presente en la llamada a httpx.get"
    )
    expected_auth = f"Bearer {test_api_key}"
    assert headers_sent["Authorization"] == expected_auth, (
        f"Se esperaba 'Bearer {test_api_key}', se obtuvo: '{headers_sent.get('Authorization')}'"
    )

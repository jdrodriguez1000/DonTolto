"""
Suite de pruebas RED para la funcion check_upstash en engine.src.check_env.

Valida el contrato tecnico definido en la SPEC §2.2 para el handshake con
el cluster Redis en Upstash: autenticacion via Bearer token, verificacion
de respuesta PONG, manejo de errores HTTP (401, 403, body inesperado),
medicion de latencia y verificacion del endpoint /ping correcto.

Todos los tests DEBEN FALLAR en la fase RED porque la implementacion actual
es un stub que retorna WARNING con mensaje "not implemented" sin ejecutar
ninguna llamada HTTP real.

Fase TDD: RED
Trazabilidad: TSK-F1_1.0-10.3-RED / docs/f1_1.0/f1_1.0_spec.md §2.2
"""

from unittest.mock import MagicMock, patch

from engine.src.check_env import check_upstash
from engine.src.models import CheckStatus, ServiceResult


# ===========================================================================
# Helpers de construccion de mocks HTTP
# ===========================================================================


def _make_httpx_response(
    status_code: int, json_body: dict | None = None
) -> MagicMock:
    """Construye un mock de httpx.Response con el status code y body JSON indicados.

    Args:
        status_code: Codigo HTTP de la respuesta simulada.
        json_body: Diccionario que simula el cuerpo JSON de la respuesta.
                   None produce un objeto vacio por defecto.

    Returns:
        MagicMock configurado para simular una respuesta httpx.
    """
    mock_response = MagicMock()
    mock_response.status_code = status_code
    mock_response.json.return_value = json_body if json_body is not None else {}
    return mock_response


# ===========================================================================
# Grupo 1: Flujo exitoso (HTTP 200 + body PONG)
# ===========================================================================


def test_check_upstash_returns_ok_on_pong_response():
    """check_upstash debe retornar OK cuando el cluster responde 200 con {"result": "PONG"}.

    Arrange: mock de httpx.get que retorna status 200 y body {"result": "PONG"}.
    Act: invocar check_upstash con url y token ficticios.
    Assert: el status del ServiceResult es OK.

    Trazabilidad: SPEC §2.2 punto 2
    """
    # Arrange
    mock_response = _make_httpx_response(
        status_code=200,
        json_body={"result": "PONG"},
    )

    with patch("httpx.get", return_value=mock_response):
        # Act
        result: ServiceResult = check_upstash(
            url="https://my-redis.upstash.io",
            token="fake_upstash_token_for_test",
        )

    # Assert
    assert result.status == CheckStatus.OK, (
        f"Se esperaba OK ante respuesta PONG valida, se obtuvo: {result.status}"
    )


# ===========================================================================
# Grupo 2: Manejo de errores HTTP (401 / 403)
# ===========================================================================


def test_check_upstash_returns_error_on_401():
    """check_upstash debe retornar ERROR cuando el cluster responde 401 Unauthorized.

    Arrange: mock de httpx.get que retorna status 401.
    Act: invocar check_upstash con url y token ficticios.
    Assert: el status del ServiceResult es ERROR.

    Trazabilidad: SPEC §2.2 punto 3
    """
    # Arrange
    mock_response = _make_httpx_response(status_code=401)

    with patch("httpx.get", return_value=mock_response):
        # Act
        result: ServiceResult = check_upstash(
            url="https://my-redis.upstash.io",
            token="fake_upstash_token_for_test",
        )

    # Assert
    assert result.status == CheckStatus.ERROR, (
        f"Se esperaba ERROR ante HTTP 401, se obtuvo: {result.status}"
    )


def test_check_upstash_returns_error_on_403():
    """check_upstash debe retornar ERROR cuando el cluster responde 403 Forbidden.

    Arrange: mock de httpx.get que retorna status 403.
    Act: invocar check_upstash con url y token ficticios.
    Assert: el status del ServiceResult es ERROR.

    Trazabilidad: SPEC §2.2 punto 4
    """
    # Arrange
    mock_response = _make_httpx_response(status_code=403)

    with patch("httpx.get", return_value=mock_response):
        # Act
        result: ServiceResult = check_upstash(
            url="https://my-redis.upstash.io",
            token="fake_upstash_token_for_test",
        )

    # Assert
    assert result.status == CheckStatus.ERROR, (
        f"Se esperaba ERROR ante HTTP 403, se obtuvo: {result.status}"
    )


# ===========================================================================
# Grupo 3: Validacion del body de respuesta
# ===========================================================================


def test_check_upstash_returns_error_on_unexpected_body():
    """check_upstash debe retornar ERROR cuando el body de la respuesta 200 no es PONG.

    Si el cluster responde 200 pero el campo "result" no es "PONG", la respuesta
    es inesperada y debe clasificarse como ERROR segun SPEC §2.2 punto 5.

    Arrange: mock de httpx.get que retorna status 200 con body {"result": "NOT_PONG"}.
    Act: invocar check_upstash con url y token ficticios.
    Assert: el status del ServiceResult es ERROR.

    Trazabilidad: SPEC §2.2 punto 5
    """
    # Arrange
    mock_response = _make_httpx_response(
        status_code=200,
        json_body={"result": "NOT_PONG"},
    )

    with patch("httpx.get", return_value=mock_response):
        # Act
        result: ServiceResult = check_upstash(
            url="https://my-redis.upstash.io",
            token="fake_upstash_token_for_test",
        )

    # Assert
    assert result.status == CheckStatus.ERROR, (
        f"Se esperaba ERROR ante body inesperado (NOT_PONG), se obtuvo: {result.status}"
    )


# ===========================================================================
# Grupo 4: Medicion de latencia
# ===========================================================================


def test_check_upstash_measures_latency():
    """check_upstash debe registrar una latencia mayor que cero e invocar httpx.get.

    El stub retorna latency_ms=0.1 hardcodeado sin instrumentar el tiempo real
    de la solicitud HTTP. La implementacion real debe medir la duracion efectiva
    de la llamada al endpoint /ping y ademas invocar httpx.get efectivamente.

    Arrange: mock de httpx.get que retorna 200 con body PONG valido.
    Act: invocar check_upstash con url y token ficticios.
    Assert: latency_ms > 0 Y httpx.get fue invocado exactamente una vez.

    Trazabilidad: SPEC §2.2 punto 7
    """
    # Arrange
    mock_response = _make_httpx_response(
        status_code=200,
        json_body={"result": "PONG"},
    )

    with patch("httpx.get", return_value=mock_response) as mock_get:
        # Act
        result: ServiceResult = check_upstash(
            url="https://my-redis.upstash.io",
            token="fake_upstash_token_for_test",
        )

    # Assert — la latencia debe ser positiva y la llamada HTTP debe haberse ejecutado
    assert result.latency_ms > 0, (
        f"latency_ms debe ser mayor que cero, se obtuvo: {result.latency_ms}"
    )
    mock_get.assert_called_once()


# ===========================================================================
# Grupo 5: Coherencia del mensaje retornado
# ===========================================================================


def test_check_upstash_does_not_return_not_implemented_message():
    """check_upstash NO debe retornar el mensaje 'not implemented' del stub.

    El stub actual siempre devuelve message='not implemented'. La implementacion
    real debe retornar None o un mensaje semantico segun el resultado del check.
    Este test falla en RED porque el stub viola esta condicion.

    Arrange: mock de httpx.get que retorna 200 con body PONG valido.
    Act: invocar check_upstash con url y token ficticios.
    Assert: message != 'not implemented'.

    Trazabilidad: SPEC §2.2 (contrato de mensajes del servicio)
    """
    # Arrange
    mock_response = _make_httpx_response(
        status_code=200,
        json_body={"result": "PONG"},
    )

    with patch("httpx.get", return_value=mock_response):
        # Act
        result: ServiceResult = check_upstash(
            url="https://my-redis.upstash.io",
            token="fake_upstash_token_for_test",
        )

    # Assert
    assert result.message != "not implemented", (
        "El mensaje 'not implemented' es propio del stub y no debe aparecer "
        "en la implementacion real"
    )


# ===========================================================================
# Grupo 6: Contrato de llamada HTTP (endpoint y cabeceras)
# ===========================================================================


def test_check_upstash_calls_ping_endpoint():
    """check_upstash debe realizar la solicitud GET al endpoint /ping del cluster.

    La SPEC §2.2 punto 1 define que la verificacion se realiza via GET a
    {url}/ping. Cualquier otra ruta constituye una violacion del contrato.

    Arrange: mock de httpx.get que retorna 200 con body PONG valido.
    Act: invocar check_upstash con url base ficticia.
    Assert: httpx.get fue llamado con una URL que termina en '/ping'.

    Trazabilidad: SPEC §2.2 punto 1
    """
    # Arrange
    base_url = "https://my-redis.upstash.io"
    mock_response = _make_httpx_response(
        status_code=200,
        json_body={"result": "PONG"},
    )

    with patch("httpx.get", return_value=mock_response) as mock_get:
        # Act
        check_upstash(url=base_url, token="fake_upstash_token_for_test")

    # Assert — verificar que la URL llamada incluye el path /ping
    assert mock_get.called, "httpx.get debe haber sido invocado"
    call_args = mock_get.call_args
    called_url: str = (
        call_args.args[0] if call_args.args else call_args.kwargs.get("url", "")
    )
    assert called_url.endswith("/ping"), (
        f"Se esperaba una URL que termine en '/ping', se obtuvo: '{called_url}'"
    )


def test_check_upstash_sends_bearer_auth_header():
    """check_upstash debe incluir el header 'Authorization: Bearer <token>' en la solicitud.

    La SPEC §2.2 punto 1 especifica que la autenticacion se realiza mediante
    el esquema Bearer en el header Authorization. Pasar el token por cualquier
    otro mecanismo viola el contrato.

    Arrange: mock de httpx.get que retorna 200 con body PONG; token de prueba.
    Act: invocar check_upstash con la url y el token de prueba.
    Assert: httpx.get fue llamado con un kwarg 'headers' que contiene
            la clave 'Authorization' con valor 'Bearer <token>'.

    Trazabilidad: SPEC §2.2 punto 1
    """
    # Arrange
    test_token = "upstash_test_token_abc123"
    mock_response = _make_httpx_response(
        status_code=200,
        json_body={"result": "PONG"},
    )

    with patch("httpx.get", return_value=mock_response) as mock_get:
        # Act
        check_upstash(url="https://my-redis.upstash.io", token=test_token)

    # Assert — los headers deben incluir Authorization: Bearer <token>
    assert mock_get.called, "httpx.get debe haber sido invocado"
    call_kwargs = mock_get.call_args.kwargs
    headers_sent: dict = call_kwargs.get("headers", {})
    assert "Authorization" in headers_sent, (
        "El header 'Authorization' debe estar presente en la llamada a httpx.get"
    )
    expected_auth = f"Bearer {test_token}"
    assert headers_sent["Authorization"] == expected_auth, (
        f"Se esperaba 'Bearer {test_token}', "
        f"se obtuvo: '{headers_sent.get('Authorization')}'"
    )

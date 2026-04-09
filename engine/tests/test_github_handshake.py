"""
Suite de pruebas RED para la funcion check_github en engine.src.check_env.

Valida el contrato tecnico definido en la SPEC §2.2 para el handshake con
la API de GitHub: autenticacion via Bearer token, verificacion de scopes
OAuth, manejo de errores HTTP y medicion de latencia.

Todos los tests DEBEN FALLAR en la fase RED porque la implementacion actual
es un stub que retorna WARNING con mensaje "not implemented" sin ejecutar
ninguna llamada HTTP real.

Fase TDD: RED
Trazabilidad: TSK-F1_1.0-10.1-RED / docs/f1_1.0/f1_1.0_spec.md §2.2
"""

from unittest.mock import MagicMock, patch

import pytest

from engine.src.check_env import check_github
from engine.src.models import CheckStatus, ServiceResult


# ===========================================================================
# Helpers de construccion de mocks HTTP
# ===========================================================================


def _make_httpx_response(status_code: int, scopes: str | None = None) -> MagicMock:
    """Construye un mock de httpx.Response con el status code y headers indicados.

    Args:
        status_code: Codigo HTTP de la respuesta simulada.
        scopes: Valor del header X-OAuth-Scopes. None omite el header.

    Returns:
        MagicMock configurado para simular una respuesta httpx.
    """
    mock_response = MagicMock()
    mock_response.status_code = status_code

    headers: dict[str, str] = {}
    if scopes is not None:
        headers["X-OAuth-Scopes"] = scopes
    mock_response.headers = headers

    return mock_response


# ===========================================================================
# Grupo 1: Manejo de errores HTTP (401 / 403)
# ===========================================================================


def test_check_github_returns_error_on_401():
    """check_github debe retornar ERROR cuando la API responde 401 Unauthorized.

    Arrange: mock de httpx.get que retorna status 401.
    Act: invocar check_github con un token ficticio.
    Assert: el status del ServiceResult es ERROR.

    Trazabilidad: SPEC §2.2 punto 3
    """
    # Arrange
    mock_response = _make_httpx_response(status_code=401)

    with patch("httpx.get", return_value=mock_response):
        # Act
        result: ServiceResult = check_github("ghp_fake_token_for_test")

    # Assert
    assert result.status == CheckStatus.ERROR, (
        f"Se esperaba ERROR ante HTTP 401, se obtuvo: {result.status}"
    )


def test_check_github_returns_error_on_403():
    """check_github debe retornar ERROR cuando la API responde 403 Forbidden.

    Arrange: mock de httpx.get que retorna status 403.
    Act: invocar check_github con un token ficticio.
    Assert: el status del ServiceResult es ERROR.

    Trazabilidad: SPEC §2.2 punto 4
    """
    # Arrange
    mock_response = _make_httpx_response(status_code=403)

    with patch("httpx.get", return_value=mock_response):
        # Act
        result: ServiceResult = check_github("ghp_fake_token_for_test")

    # Assert
    assert result.status == CheckStatus.ERROR, (
        f"Se esperaba ERROR ante HTTP 403, se obtuvo: {result.status}"
    )


# ===========================================================================
# Grupo 2: Flujos exitosos con scopes OAuth
# ===========================================================================


def test_check_github_returns_ok_with_required_scopes():
    """check_github debe retornar OK cuando la respuesta 200 incluye los scopes requeridos.

    Los scopes 'repo' y 'workflow' son obligatorios segun la SPEC §2.2 punto 5.

    Arrange: mock de httpx.get que retorna 200 con X-OAuth-Scopes conteniendo
             'repo', 'workflow' y 'read:user'.
    Act: invocar check_github con un token ficticio.
    Assert: el status del ServiceResult es OK.

    Trazabilidad: SPEC §2.2 punto 5
    """
    # Arrange
    mock_response = _make_httpx_response(
        status_code=200,
        scopes="repo, workflow, read:user",
    )

    with patch("httpx.get", return_value=mock_response):
        # Act
        result: ServiceResult = check_github("ghp_fake_token_for_test")

    # Assert
    assert result.status == CheckStatus.OK, (
        f"Se esperaba OK con scopes completos, se obtuvo: {result.status}"
    )


def test_check_github_returns_warning_on_missing_scopes():
    """check_github debe retornar WARNING con mensaje de scopes faltantes.

    Si la respuesta es 200 pero X-OAuth-Scopes no contiene 'repo' ni 'workflow',
    el resultado debe degradarse a WARNING con un mensaje que mencione los scopes
    ausentes (ej: 'missing scopes: repo, workflow'), segun SPEC §2.2 punto 6.

    El stub actual retorna WARNING con message='not implemented', lo que coincide
    en status pero NO en el contenido semantico del mensaje. Este test falla en
    fase RED porque el mensaje del stub no menciona los scopes faltantes.

    Arrange: mock de httpx.get que retorna 200 con X-OAuth-Scopes = 'read:user'
             (ausencia de 'repo' y 'workflow').
    Act: invocar check_github con un token ficticio.
    Assert: el status es WARNING Y el mensaje contiene 'missing scopes'.

    Trazabilidad: SPEC §2.2 punto 6
    """
    # Arrange
    mock_response = _make_httpx_response(
        status_code=200,
        scopes="read:user",
    )

    with patch("httpx.get", return_value=mock_response):
        # Act
        result: ServiceResult = check_github("ghp_fake_token_for_test")

    # Assert — status correcto Y mensaje semantico con los scopes ausentes
    assert result.status == CheckStatus.WARNING, (
        f"Se esperaba WARNING con scopes incompletos, se obtuvo: {result.status}"
    )
    assert result.message is not None and "missing scopes" in result.message, (
        f"El mensaje debe indicar los scopes faltantes con 'missing scopes: ...', "
        f"se obtuvo: '{result.message}'"
    )


# ===========================================================================
# Grupo 3: Medicion de latencia
# ===========================================================================


def test_check_github_measures_latency():
    """check_github debe registrar una latencia mayor que cero en respuestas exitosas.

    El stub retorna latency_ms=0.1 hardcodeado en lugar de medir el tiempo
    real de la solicitud HTTP. La implementacion real debe medir la duracion
    efectiva de la llamada a la API, lo que siempre producira latency_ms > 0
    de forma reproducible incluso con mocks (la medicion debe ocurrir aunque
    el mock sea instantaneo).

    Arrange: mock de httpx.get que retorna 200 con scopes correctos.
    Act: invocar check_github con un token ficticio.
    Assert: latency_ms > 0 (debe ser un valor medido, no hardcodeado en 0.1
            de forma no instrumentada).

    Nota: este test en fase RED verifica que la latencia sea dinamicamente
    medida. El stub retorna 0.1 fijo, lo que tecnicamente es > 0, por lo que
    necesitamos verificar que la implementacion real instrumenta el tiempo.
    Este test complementa test_check_github_does_not_return_not_implemented_message
    para asegurar que la funcion ejecuta el camino de codigo real.

    Trazabilidad: SPEC §2.2 punto 8
    """
    # Arrange
    mock_response = _make_httpx_response(
        status_code=200,
        scopes="repo, workflow, read:user",
    )

    with patch("httpx.get", return_value=mock_response) as mock_get:
        # Act
        result: ServiceResult = check_github("ghp_fake_token_for_test")

    # Assert — la latencia debe ser positiva y la llamada HTTP debe haberse ejecutado
    assert result.latency_ms > 0, (
        f"latency_ms debe ser mayor que cero, se obtuvo: {result.latency_ms}"
    )
    # Verificacion adicional: httpx.get fue efectivamente invocado
    mock_get.assert_called_once()


# ===========================================================================
# Grupo 4: Coherencia del mensaje retornado
# ===========================================================================


def test_check_github_does_not_return_not_implemented_message():
    """check_github NO debe retornar el mensaje 'not implemented' del stub.

    El stub actual siempre devuelve message='not implemented'. La implementacion
    real debe retornar None o un mensaje semantico segun el resultado del check.
    Este test falla en RED porque el stub viola esta condicion.

    Arrange: mock de httpx.get que retorna 200 con scopes correctos.
    Act: invocar check_github con un token ficticio.
    Assert: message != 'not implemented'.

    Trazabilidad: SPEC §2.2 (contrato de mensajes del servicio)
    """
    # Arrange
    mock_response = _make_httpx_response(
        status_code=200,
        scopes="repo, workflow, read:user",
    )

    with patch("httpx.get", return_value=mock_response):
        # Act
        result: ServiceResult = check_github("ghp_fake_token_for_test")

    # Assert
    assert result.message != "not implemented", (
        "El mensaje 'not implemented' es propio del stub y no debe aparecer "
        "en la implementacion real"
    )


# ===========================================================================
# Grupo 5: Contrato de llamada HTTP (endpoint y cabeceras)
# ===========================================================================


def test_check_github_calls_correct_endpoint():
    """check_github debe realizar la solicitud GET a https://api.github.com/user.

    La SPEC §2.2 punto 1 define el endpoint exacto de verificacion de identidad
    de GitHub. Cualquier otra URL constituye una violacion del contrato.

    Arrange: mock de httpx.get que retorna 200 con scopes correctos.
    Act: invocar check_github con un token ficticio.
    Assert: httpx.get fue llamado con la URL 'https://api.github.com/user'
            como primer argumento posicional o como argumento 'url'.

    Trazabilidad: SPEC §2.2 punto 1
    """
    # Arrange
    mock_response = _make_httpx_response(
        status_code=200,
        scopes="repo, workflow, read:user",
    )

    with patch("httpx.get", return_value=mock_response) as mock_get:
        # Act
        check_github("ghp_fake_token_for_test")

    # Assert — verificar que el primer argumento posicional es el endpoint correcto
    assert mock_get.called, "httpx.get debe haber sido invocado"
    call_args = mock_get.call_args
    # El endpoint puede pasarse como posicional o como keyword 'url'
    called_url = call_args.args[0] if call_args.args else call_args.kwargs.get("url")
    assert called_url == "https://api.github.com/user", (
        f"Se esperaba llamada a 'https://api.github.com/user', "
        f"se obtuvo: '{called_url}'"
    )


def test_check_github_sends_bearer_auth_header():
    """check_github debe incluir el header 'Authorization: Bearer <token>' en la solicitud.

    La SPEC §2.2 punto 1 especifica que la autenticacion se realiza mediante
    el esquema Bearer en el header Authorization. Pasar el token por cualquier
    otro mecanismo viola el contrato.

    Arrange: mock de httpx.get que retorna 200 con scopes correctos; token
             de prueba con formato valido ghp_*.
    Act: invocar check_github con el token de prueba.
    Assert: httpx.get fue llamado con un kwarg 'headers' que contiene
            la clave 'Authorization' con valor 'Bearer ghp_test_token_abc123'.

    Trazabilidad: SPEC §2.2 punto 1
    """
    # Arrange
    test_token = "ghp_test_token_abc123"
    mock_response = _make_httpx_response(
        status_code=200,
        scopes="repo, workflow, read:user",
    )

    with patch("httpx.get", return_value=mock_response) as mock_get:
        # Act
        check_github(test_token)

    # Assert — los headers deben incluir Authorization: Bearer <token>
    assert mock_get.called, "httpx.get debe haber sido invocado"
    call_kwargs = mock_get.call_args.kwargs
    headers_sent: dict = call_kwargs.get("headers", {})
    assert "Authorization" in headers_sent, (
        "El header 'Authorization' debe estar presente en la llamada a httpx.get"
    )
    expected_auth = f"Bearer {test_token}"
    assert headers_sent["Authorization"] == expected_auth, (
        f"Se esperaba 'Bearer {test_token}', se obtuvo: '{headers_sent.get('Authorization')}'"
    )

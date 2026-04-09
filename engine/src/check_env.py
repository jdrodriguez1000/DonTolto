"""
Orquestador principal de validacion de entorno para el motor DonTolto.

Implementa la logica Diagnostic-First: ejecuta todos los checks de servicio
antes de evaluar el status global, garantizando trazabilidad completa incluso
ante fallos multiples. El resultado se estructura en un RunReport canonico.

Stubs de funciones de servicio: la implementacion real de cada check externo
se incorporara en fases posteriores (TSK-F1_1.0-11.1-GREEN en adelante).
Los stubs retornan WARNING para no romper la suite cuando no son mocked.

Trazabilidad: TSK-F1_1.0-07.1-GREEN / TSK-F1_1.0-08-GREEN
docs/f1_1.0/f1_1.0_spec.md §1, §2.1, §3.2.2, §6 / T-05b, T-05c
"""

import os
import re
import sys
import time
from pathlib import Path
from typing import Final

import httpx
import psycopg2
from psycopg2 import sql as pg_sql

from engine.src.models import CheckStatus, RunReport, ServiceResult, validate_env_vars
from engine.src.utils import format_log_entry, generate_run_id, get_timestamp, run_id_short, sanitize_log_message

# ---------------------------------------------------------------------------
# Constantes HTTP compartidas por todos los checks de servicio externo
# ---------------------------------------------------------------------------

_HTTP_MAX_RETRIES: Final[int] = 3
_HTTP_TIMEOUT_SECONDS: Final[float] = 10.0

# ---------------------------------------------------------------------------
# Dependencias directas del proyecto para el Environment Snapshot (T-12b)
# Definida a nivel de modulo para reutilizacion y evitar redeclaracion local.
# ---------------------------------------------------------------------------

_DIRECT_DEPS: Final[list[str]] = [
    "httpx",
    "psycopg2-binary",
    "python-dotenv",
    "pydantic",
]

# ---------------------------------------------------------------------------
# Mapeo de criticidad de servicios
# CRITICAL_SERVICES: fallo provoca sys.exit(1)
# WARNING_SERVICES:  fallo eleva el status global a WARNING, sin exit
# ---------------------------------------------------------------------------

CRITICAL_SERVICES: Final[frozenset[str]] = frozenset(
    {"env_vars", "supabase_sql", "supabase_http"}
)

WARNING_SERVICES: Final[frozenset[str]] = frozenset(
    {"github", "resend", "upstash", "pg_extensions", "zombie_cleanup", "ddl_capabilities", "persistence_cycle"}
)


# ---------------------------------------------------------------------------
# Helper HTTP privado — implementa retry con backoff exponencial
# ---------------------------------------------------------------------------


def _http_get_with_retry(
    url: str,
    headers: dict[str, str],
    timeout: float = _HTTP_TIMEOUT_SECONDS,
    max_retries: int = _HTTP_MAX_RETRIES,
) -> tuple[httpx.Response | None, float, Exception | None]:
    """Ejecuta un GET HTTP con reintentos y backoff exponencial.

    Args:
        url: URL del endpoint a consultar.
        headers: Cabeceras HTTP a incluir en la peticion.
        timeout: Tiempo maximo de espera por intento en segundos.
        max_retries: Numero maximo de intentos ante errores de red/timeout.

    Returns:
        Tupla (response, latency_ms, last_exc):
        - response: objeto httpx.Response si la peticion fue exitosa, None si todos
          los intentos fallaron por timeout o error de red.
        - latency_ms: latencia medida en el ultimo intento exitoso, o 0.0 si fallo.
        - last_exc: ultima excepcion capturada, o None si hubo respuesta exitosa.
    """
    last_exc: Exception | None = None

    for attempt in range(max_retries):
        try:
            start: float = time.monotonic()
            response = httpx.get(url, headers=headers, timeout=timeout)
            end: float = time.monotonic()
            # Garantizar minimo de 0.001 ms para satisfacer la restriccion
            # gt=0 del modelo ServiceResult incluso con mocks instantaneos.
            latency_ms: float = max((end - start) * 1000, 0.001)
            return response, latency_ms, None
        except (httpx.TimeoutException, httpx.NetworkError) as exc:
            last_exc = exc
            if attempt < max_retries - 1:
                time.sleep(2**attempt)

    return None, 0.0, last_exc


# ---------------------------------------------------------------------------
# Stubs de checks de servicio externo
# Implementacion real: TSK-F1_1.0-11.1-GREEN y siguientes
# ---------------------------------------------------------------------------


def check_github(token: str) -> ServiceResult:
    """Verifica la disponibilidad y autenticacion del token de GitHub.

    Realiza un GET a https://api.github.com/user con autenticacion Bearer
    y verifica que los scopes 'repo' y 'workflow' esten presentes en el
    header X-OAuth-Scopes de la respuesta. Implementa reintentos con
    backoff exponencial ante errores de red o timeout.

    Args:
        token: Personal Access Token de GitHub (ghp_* o github_pat_*).

    Returns:
        ServiceResult con el estado del servicio y latencia medida:
        - OK si HTTP 200 y scopes requeridos presentes.
        - WARNING si HTTP 200 pero faltan scopes requeridos.
        - ERROR si HTTP 401, 403 o excepcion de red/timeout.

    Trazabilidad: TSK-F1_1.0-11.1-GREEN / SPEC §2.2
    """
    _ENDPOINT: str = "https://api.github.com/user"
    _REQUIRED_SCOPES: frozenset[str] = frozenset({"repo", "workflow"})

    headers: dict[str, str] = {"Authorization": f"Bearer {token}"}
    response, latency_ms, last_exc = _http_get_with_retry(_ENDPOINT, headers)

    if response is None:
        return ServiceResult(
            status=CheckStatus.ERROR,
            latency_ms=0.001,
            message=str(last_exc),
        )

    if response.status_code == 401:
        return ServiceResult(
            status=CheckStatus.ERROR,
            latency_ms=latency_ms,
            message="401 Unauthorized",
        )

    if response.status_code == 403:
        return ServiceResult(
            status=CheckStatus.ERROR,
            latency_ms=latency_ms,
            message="403 Forbidden",
        )

    if response.status_code == 200:
        raw_scopes: str = response.headers.get("X-OAuth-Scopes", "")
        present_scopes: set[str] = {s.strip() for s in raw_scopes.split(",") if s.strip()}
        missing: list[str] = sorted(_REQUIRED_SCOPES - present_scopes)

        if missing:
            return ServiceResult(
                status=CheckStatus.WARNING,
                latency_ms=latency_ms,
                message=f"missing scopes: {', '.join(missing)}",
            )

        return ServiceResult(
            status=CheckStatus.OK,
            latency_ms=latency_ms,
            message=None,
        )

    # Guardia: cualquier otro codigo HTTP no mapeado (ej: 5xx)
    return ServiceResult(
        status=CheckStatus.ERROR,
        latency_ms=latency_ms,
        message=f"HTTP {response.status_code}",
    )


def check_resend(api_key: str) -> ServiceResult:
    """Verifica la disponibilidad y autenticacion de la API de Resend.

    Realiza un GET a https://api.resend.com/api-keys con autenticacion Bearer
    e interpreta el codigo HTTP de respuesta para determinar el estado del
    servicio. Implementa reintentos con backoff exponencial ante errores de
    red o timeout.

    Args:
        api_key: Clave de API de Resend (prefijo re_*).

    Returns:
        ServiceResult con el estado del servicio y latencia medida:
        - OK si HTTP 200.
        - ERROR si HTTP 401, 403, cualquier otro codigo de error, o excepcion
          de red/timeout.

    Trazabilidad: TSK-F1_1.0-11.2-GREEN / SPEC §2.2
    """
    _ENDPOINT: str = "https://api.resend.com/api-keys"

    headers: dict[str, str] = {"Authorization": f"Bearer {api_key}"}
    response, latency_ms, last_exc = _http_get_with_retry(_ENDPOINT, headers)

    if response is None:
        return ServiceResult(
            status=CheckStatus.ERROR,
            latency_ms=0.001,
            message=str(last_exc),
        )

    if response.status_code == 401:
        return ServiceResult(
            status=CheckStatus.ERROR,
            latency_ms=latency_ms,
            message="401 Unauthorized",
        )

    if response.status_code == 403:
        return ServiceResult(
            status=CheckStatus.ERROR,
            latency_ms=latency_ms,
            message="403 Forbidden",
        )

    if response.status_code == 200:
        return ServiceResult(
            status=CheckStatus.OK,
            latency_ms=latency_ms,
            message=None,
        )

    # Cualquier otro codigo HTTP de error (4xx/5xx distinto a los anteriores)
    return ServiceResult(
        status=CheckStatus.ERROR,
        latency_ms=latency_ms,
        message=f"HTTP {response.status_code}",
    )


def check_upstash(url: str, token: str) -> ServiceResult:
    """Verifica la disponibilidad del cluster Redis en Upstash via endpoint /ping.

    Realiza un GET a {url}/ping con autenticacion Bearer y verifica que el
    cuerpo de la respuesta sea {"result": "PONG"}. Implementa reintentos con
    backoff exponencial ante errores de red o timeout.

    Args:
        url: URL REST del cluster Upstash (https://*.upstash.io).
        token: Token de autenticacion REST de Upstash.

    Returns:
        ServiceResult con el estado del servicio y latencia medida:
        - OK si HTTP 200 y body == {"result": "PONG"}.
        - ERROR si HTTP 401, 403, body inesperado o excepcion de red/timeout.

    Trazabilidad: TSK-F1_1.0-11.3-GREEN / SPEC §2.2
    """
    _ENDPOINT: str = f"{url}/ping"

    headers: dict[str, str] = {"Authorization": f"Bearer {token}"}
    response, latency_ms, last_exc = _http_get_with_retry(_ENDPOINT, headers)

    if response is None:
        return ServiceResult(
            status=CheckStatus.ERROR,
            latency_ms=0.001,
            message=str(last_exc),
        )

    if response.status_code == 401:
        return ServiceResult(
            status=CheckStatus.ERROR,
            latency_ms=latency_ms,
            message="401 Unauthorized",
        )

    if response.status_code == 403:
        return ServiceResult(
            status=CheckStatus.ERROR,
            latency_ms=latency_ms,
            message="403 Forbidden",
        )

    if response.status_code == 200:
        body: dict = response.json()
        if body == {"result": "PONG"}:
            return ServiceResult(
                status=CheckStatus.OK,
                latency_ms=latency_ms,
                message=None,
            )
        return ServiceResult(
            status=CheckStatus.ERROR,
            latency_ms=latency_ms,
            message=f"unexpected response: {body}",
        )

    return ServiceResult(
        status=CheckStatus.ERROR,
        latency_ms=latency_ms,
        message=f"HTTP {response.status_code}",
    )


def check_supabase_http(url: str, key: str) -> ServiceResult:
    """Verifica la disponibilidad de Supabase via HTTP (PostgREST).

    Realiza un GET a {url}/rest/v1/ con los headers de autenticacion de
    Supabase (apikey y Authorization Bearer). Implementa reintentos con
    backoff exponencial ante errores de red o timeout.

    Args:
        url: URL publica del proyecto Supabase.
        key: Service Role Key del proyecto Supabase.

    Returns:
        ServiceResult con el estado del servicio y latencia medida:
        - OK si HTTP 200.
        - ERROR si HTTP 401, 403, cualquier otro codigo de error o
          excepcion de red/timeout.

    Trazabilidad: TSK-F1_1.0-11.4-GREEN / SPEC §2.2
    """
    _ENDPOINT: str = f"{url}/rest/v1/"

    headers: dict[str, str] = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
    }
    response, latency_ms, last_exc = _http_get_with_retry(_ENDPOINT, headers)

    if response is None:
        return ServiceResult(
            status=CheckStatus.ERROR,
            latency_ms=0.001,
            message=str(last_exc),
        )

    if response.status_code == 401:
        return ServiceResult(
            status=CheckStatus.ERROR,
            latency_ms=latency_ms,
            message="401 Unauthorized",
        )

    if response.status_code == 403:
        return ServiceResult(
            status=CheckStatus.ERROR,
            latency_ms=latency_ms,
            message="403 Forbidden",
        )

    if response.status_code == 200:
        return ServiceResult(
            status=CheckStatus.OK,
            latency_ms=latency_ms,
            message=None,
        )

    return ServiceResult(
        status=CheckStatus.ERROR,
        latency_ms=latency_ms,
        message=f"HTTP {response.status_code}",
    )


def check_supabase_sql(db_url: str) -> ServiceResult:
    """Verifica la conectividad directa a PostgreSQL via psycopg2.

    Establece conexion con psycopg2.connect(db_url) y ejecuta SELECT 1
    para confirmar que la base de datos responde. Implementa reintentos
    con backoff exponencial ante OperationalError. La conexion se cierra
    siempre en el bloque finally para evitar fugas de recursos.

    Args:
        db_url: URL de conexion PostgreSQL completa (postgresql://...).

    Returns:
        ServiceResult con el estado del servicio y latencia medida:
        - OK si la conexion y la consulta son exitosas.
        - ERROR si psycopg2.OperationalError o cualquier otra excepcion.

    Trazabilidad: TSK-F1_1.0-11.4-GREEN / SPEC §3.3
    """
    _MAX_RETRIES: int = 3
    last_exc: Exception | None = None
    start: float = time.monotonic()

    for attempt in range(_MAX_RETRIES):
        conn = None
        try:
            conn = psycopg2.connect(db_url)
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
            end: float = time.monotonic()
            latency_ms: float = max((end - start) * 1000, 0.001)
            return ServiceResult(
                status=CheckStatus.OK,
                latency_ms=latency_ms,
                message=None,
            )
        except psycopg2.OperationalError as exc:
            last_exc = exc
            if attempt < _MAX_RETRIES - 1:
                time.sleep(2**attempt)
        except Exception as exc:  # noqa: BLE001
            last_exc = exc
            break
        finally:
            if conn is not None:
                conn.close()

    end_err: float = time.monotonic()
    latency_ms_err: float = max((end_err - start) * 1000, 0.001)
    return ServiceResult(
        status=CheckStatus.ERROR,
        latency_ms=latency_ms_err,
        message=str(last_exc),
    )


def check_pg_extensions(db_url: str) -> ServiceResult:
    """Audita la disponibilidad de las extensiones PostgreSQL requeridas por el sistema.

    Intenta crear las extensiones uuid-ossp, pg_cron y pg_net con
    CREATE EXTENSION IF NOT EXISTS. Si el rol de conexion no tiene privilegios
    de superusuario (pgcode=42501), verifica su existencia en el catalogo
    pg_extension. Si las extensiones estan presentes retorna WARNING indicando
    degradacion de privilegios. Si alguna extension no existe retorna ERROR.

    En caso de exito en la creacion, verifica la visibilidad de las tablas
    cron.job y net.http_request_queue como comprobacion adicional de integracion.

    La conexion se cierra siempre en el bloque finally para evitar fugas
    de recursos.

    Args:
        db_url: URL de conexion PostgreSQL completa (postgresql://...).

    Returns:
        ServiceResult con el estado del servicio y latencia medida:
        - OK si CREATE exitoso y consultas de visibilidad responden.
        - WARNING si CREATE falla por permisos (42501) pero todas las extensiones
          existen en pg_extension.
        - ERROR si CREATE falla por permisos y alguna extension no existe, o si
          psycopg2.OperationalError impide la conexion.

    Trazabilidad: TSK-F1_1.0-14.1-GREEN / docs/f1_1.0/f1_1.0_spec.md §3.3-A
    """
    _EXTENSIONS: list[str] = ["uuid-ossp", "pg_cron", "pg_net"]
    _VISIBILITY_QUERIES: list[str] = [
        "SELECT count(*) FROM cron.job",
        "SELECT count(*) FROM net.http_request_queue",
    ]

    conn = None
    start: float = time.monotonic()

    try:
        conn = psycopg2.connect(db_url)

        # Fase 1: intentar CREATE EXTENSION IF NOT EXISTS para cada extension
        permission_denied: bool = False
        for ext in _EXTENSIONS:
            with conn.cursor() as cur:
                try:
                    cur.execute(f'CREATE EXTENSION IF NOT EXISTS "{ext}"')
                except psycopg2.ProgrammingError as pg_err:
                    if getattr(pg_err, "pgcode", None) == "42501":
                        permission_denied = True
                        # Salir del loop — se verificara pg_extension para todas
                        break
                    raise

        if permission_denied:
            # Fase 2: fallback — verificar existencia en pg_extension para cada ext
            for ext in _EXTENSIONS:
                with conn.cursor() as cur:
                    cur.execute(
                        "SELECT count(*) FROM pg_extension WHERE extname = %s",
                        (ext,),
                    )
                    row = cur.fetchone()
                    count: int = row[0] if row else 0
                    if count == 0:
                        end_err: float = time.monotonic()
                        latency_ms_err: float = max((end_err - start) * 1000, 0.001)
                        return ServiceResult(
                            status=CheckStatus.ERROR,
                            latency_ms=latency_ms_err,
                            message=f"extension '{ext}' no encontrada en pg_extension (sin permisos CREATE)",
                        )

            # Todas las extensiones existen pero sin privilegio de creacion
            end_warn: float = time.monotonic()
            latency_ms_warn: float = max((end_warn - start) * 1000, 0.001)
            return ServiceResult(
                status=CheckStatus.WARNING,
                latency_ms=latency_ms_warn,
                message="extensiones presentes pero sin privilegio CREATE EXTENSION (42501)",
            )

        # Fase 3: verificar visibilidad de tablas de integracion
        for visibility_query in _VISIBILITY_QUERIES:
            with conn.cursor() as cur:
                cur.execute(visibility_query)
                cur.fetchone()

        end: float = time.monotonic()
        latency_ms: float = max((end - start) * 1000, 0.001)
        return ServiceResult(
            status=CheckStatus.OK,
            latency_ms=latency_ms,
            message=None,
        )

    except psycopg2.OperationalError as exc:
        end_exc: float = time.monotonic()
        latency_ms_exc: float = max((end_exc - start) * 1000, 0.001)
        return ServiceResult(
            status=CheckStatus.ERROR,
            latency_ms=latency_ms_exc,
            message=str(exc),
        )
    finally:
        if conn is not None:
            conn.close()


def check_zombie_cleanup(db_url: str) -> ServiceResult:
    """Busca y elimina tablas huerfanas public._bootstrap_* de corridas interrumpidas.

    Conecta via psycopg2, consulta pg_tables buscando tablas con el prefijo
    _bootstrap_ en el schema public (restos de ciclos de persistencia abortados)
    y ejecuta DROP TABLE IF EXISTS por cada una encontrada. La conexion se
    cierra siempre en el bloque finally para evitar fugas de recursos.

    Args:
        db_url: URL de conexion PostgreSQL completa (postgresql://...).

    Returns:
        ServiceResult con el estado de la limpieza y latencia medida:
        - OK si la busqueda se ejecuta sin error (con o sin zombies encontrados).
        - ERROR si psycopg2.OperationalError impide la conexion.

    Trazabilidad: TSK-F1_1.0-14.3-GREEN / docs/f1_1.0/f1_1.0_spec.md §3.3 T-10b
    """
    _SEARCH_QUERY: str = (
        "SELECT tablename FROM pg_tables "
        "WHERE schemaname = 'public' AND tablename LIKE '_bootstrap_%'"
    )

    conn = None
    start: float = time.monotonic()

    try:
        conn = psycopg2.connect(db_url)

        # Fase 1: buscar tablas zombie del prefijo _bootstrap_
        with conn.cursor() as cur:
            cur.execute(_SEARCH_QUERY)
            zombie_rows: list = cur.fetchall()

        if not zombie_rows:
            end: float = time.monotonic()
            latency_ms: float = max((end - start) * 1000, 0.001)
            return ServiceResult(
                status=CheckStatus.OK,
                latency_ms=latency_ms,
                message="0 tablas zombie encontradas — sin limpieza necesaria",
            )

        # Fase 2: eliminar cada tabla zombie encontrada
        # Se usa psycopg2.sql.Identifier para componer el identificador de tabla de
        # forma segura, previniendo second-order SQL injection ante nombres de tabla
        # maliciosos. Fuente: pg_tables (catalogo del sistema), pero la defensa es
        # obligatoria por estandar de seguridad (db-management skill §Seguridad SQL).
        with conn.cursor() as cur:
            for row in zombie_rows:
                tablename: str = row[0]
                cur.execute(
                    pg_sql.SQL("DROP TABLE IF EXISTS public.{}").format(
                        pg_sql.Identifier(tablename)
                    )
                )

        count: int = len(zombie_rows)
        end_clean: float = time.monotonic()
        latency_ms_clean: float = max((end_clean - start) * 1000, 0.001)
        return ServiceResult(
            status=CheckStatus.OK,
            latency_ms=latency_ms_clean,
            message=f"{count} tablas zombie eliminadas: {[r[0] for r in zombie_rows]}",
        )

    except psycopg2.OperationalError as exc:
        end_exc: float = time.monotonic()
        latency_ms_exc: float = max((end_exc - start) * 1000, 0.001)
        return ServiceResult(
            status=CheckStatus.ERROR,
            latency_ms=latency_ms_exc,
            message=str(exc),
        )
    finally:
        if conn is not None:
            conn.close()


def check_ddl_capabilities(db_url: str) -> ServiceResult:
    """Verifica que el usuario de BD tiene privilegio CREATE en el esquema public.

    Conecta via psycopg2.connect(db_url) y ejecuta la funcion del sistema
    has_schema_privilege para determinar si el rol actual puede crear objetos
    en el esquema public. La conexion se cierra siempre en el bloque finally
    para evitar fugas de recursos.

    Args:
        db_url: URL de conexion PostgreSQL completa (postgresql://...).

    Returns:
        ServiceResult con el estado del privilegio DDL y latencia medida:
        - OK si fetchone() retorna (True,) — el usuario tiene privilegio CREATE.
        - WARNING si fetchone() retorna (False,) o resultado no booleano —
          el usuario no tiene privilegio CREATE (no critico pero advierte
          que los checks DDL posteriores podran fallar).
        - ERROR si psycopg2.OperationalError impide la conexion.

    Trazabilidad: TSK-F1_1.0-15.1-GREEN / docs/f1_1.0/f1_1.0_spec.md §3.3 T-10c
    """
    _PRIVILEGE_QUERY: str = (
        "SELECT has_schema_privilege(current_user, 'public', 'CREATE')"
    )

    conn = None
    start: float = time.monotonic()

    try:
        conn = psycopg2.connect(db_url)

        with conn.cursor() as cur:
            cur.execute(_PRIVILEGE_QUERY)
            row = cur.fetchone()

        end: float = time.monotonic()
        latency_ms: float = max((end - start) * 1000, 0.001)

        # Comportamiento defensivo: si el resultado es None o no es booleano → WARNING
        if row is None or not isinstance(row[0], bool):
            return ServiceResult(
                status=CheckStatus.WARNING,
                latency_ms=latency_ms,
                message="resultado inesperado de has_schema_privilege — sin privilegio confirmado",
            )

        if row[0] is True:
            return ServiceResult(
                status=CheckStatus.OK,
                latency_ms=latency_ms,
                message=None,
            )

        # row[0] es False — usuario sin privilegio CREATE
        return ServiceResult(
            status=CheckStatus.WARNING,
            latency_ms=latency_ms,
            message="usuario sin privilegio CREATE en esquema public",
        )

    except psycopg2.OperationalError as exc:
        end_exc: float = time.monotonic()
        latency_ms_exc: float = max((end_exc - start) * 1000, 0.001)
        return ServiceResult(
            status=CheckStatus.ERROR,
            latency_ms=latency_ms_exc,
            message=str(exc),
        )
    finally:
        if conn is not None:
            conn.close()


def check_persistence_cycle(db_url: str, table_suffix: str) -> ServiceResult:
    """Ejecuta un ciclo forense idempotente CREATE→INSERT→SELECT→DROP para validar
    los privilegios de persistencia completos del usuario de base de datos.

    Crea una tabla temporal public._bootstrap_[table_suffix], inserta un registro,
    verifica que el conteo sea >= 1 y elimina la tabla en el bloque finally para
    garantizar limpieza incluso ante fallos intermedios (invariante de idempotencia).

    Args:
        db_url: URL de conexion PostgreSQL completa (postgresql://...).
        table_suffix: Sufijo corto del run_id activo (8 caracteres hex). Forma el
                      nombre unico de la tabla temporal del ciclo.

    Returns:
        ServiceResult con el estado del ciclo y latencia medida:
        - OK si todos los pasos (CREATE, INSERT, SELECT, DROP) se ejecutan sin error.
        - WARNING si CREATE lanza ProgrammingError con pgcode=42501 (sin privilegios DDL).
        - ERROR si psycopg2.OperationalError impide la conexion (pgcodes 08001/08006)
          o cualquier otra excepcion no controlada interrumpe el ciclo.

    Trazabilidad: TSK-F1_1.0-15.2-GREEN / docs/f1_1.0/f1_1.0_spec.md §3.3-B
    """
    table_name: str = f"public._bootstrap_{table_suffix}"
    conn = None
    start: float = time.monotonic()

    try:
        conn = psycopg2.connect(db_url)
        cur = conn.cursor()
        try:
            # Paso 1: CREATE — tabla temporal con uuid y timestamp por defecto
            cur.execute(
                f"CREATE TABLE IF NOT EXISTS {table_name} "
                f"(id uuid DEFAULT gen_random_uuid(), ts timestamp DEFAULT now())"
            )
            # Paso 2: INSERT — registro sin valores explicitos (usa defaults)
            cur.execute(f"INSERT INTO {table_name} DEFAULT VALUES")
            # Paso 3: SELECT — verificar que al menos un registro existe
            cur.execute(f"SELECT count(*) FROM {table_name}")
            row = cur.fetchone()
            count: int = row[0] if row else 0

            end: float = time.monotonic()
            latency_ms: float = max((end - start) * 1000, 0.001)

            if count >= 1:
                return ServiceResult(
                    status=CheckStatus.OK,
                    latency_ms=latency_ms,
                    message=None,
                )

            return ServiceResult(
                status=CheckStatus.ERROR,
                latency_ms=latency_ms,
                message=f"ciclo de persistencia completado pero count={count} (esperado >= 1)",
            )

        except psycopg2.ProgrammingError as exc:
            # pgcode=42501: sin privilegios DDL para CREATE — degradacion no critica
            if getattr(exc, "pgcode", None) == "42501":
                end_warn: float = time.monotonic()
                latency_ms_warn: float = max((end_warn - start) * 1000, 0.001)
                return ServiceResult(
                    status=CheckStatus.WARNING,
                    latency_ms=latency_ms_warn,
                    message="sin privilegios DDL para CREATE en esquema public (42501)",
                )
            raise

        finally:
            # Invariante: DROP siempre ejecutado para garantizar idempotencia del ciclo.
            # La excepcion se suprime deliberadamente para no enmascarar el error original
            # del ciclo (ej: INSERT fallido) con un fallo secundario del DROP.
            try:
                cur.execute(f"DROP TABLE IF EXISTS {table_name}")
            except Exception:  # noqa: BLE001
                pass
            cur.close()

    except psycopg2.OperationalError as exc:
        end_exc: float = time.monotonic()
        latency_ms_exc: float = max((end_exc - start) * 1000, 0.001)
        return ServiceResult(
            status=CheckStatus.ERROR,
            latency_ms=latency_ms_exc,
            message=str(exc),
        )
    except Exception as exc:  # noqa: BLE001
        end_exc2: float = time.monotonic()
        latency_ms_exc2: float = max((end_exc2 - start) * 1000, 0.001)
        return ServiceResult(
            status=CheckStatus.ERROR,
            latency_ms=latency_ms_exc2,
            message=str(exc),
        )
    finally:
        if conn is not None:
            conn.close()


# ---------------------------------------------------------------------------
# Orquestador principal
# ---------------------------------------------------------------------------


def _run_and_log_check(
    name: str,
    fn: object,
    *args: object,
) -> ServiceResult:
    """Ejecuta un check de servicio y emite su resultado a stderr en formato estructurado.

    Args:
        name: Clave del check (ej: 'github', 'supabase_sql').
        fn: Callable que implementa el check y retorna un ServiceResult.
        *args: Argumentos posicionales a pasar al callable.

    Returns:
        ServiceResult retornado por el callable.
    """
    result: ServiceResult = fn(*args)  # type: ignore[operator]
    print(
        format_log_entry("INFO", "orchestrator", f"Check '{name}': {result.status.value}"),
        file=sys.stderr,
    )
    return result


def _sanitize_checks(
    checks: dict[str, ServiceResult], secrets: list[str]
) -> dict[str, ServiceResult]:
    """Sanitiza los mensajes de todos los ServiceResult para evitar fugas de credenciales.

    Reemplaza cualquier ocurrencia de los secretos conocidos en los campos
    message de cada ServiceResult por [REDACTED], siguiendo SPEC §3.2.2.

    Args:
        checks: Mapa de nombre de servicio a ServiceResult con mensajes crudos.
        secrets: Lista de valores sensibles a redactar (tokens, keys, passwords).

    Returns:
        Nuevo dict con ServiceResult cuyos mensajes han sido sanitizados.
    """
    sanitized: dict[str, ServiceResult] = {}
    for key, result in checks.items():
        if result.message is not None:
            clean_msg = sanitize_log_message(result.message, secrets)
            sanitized[key] = result.model_copy(update={"message": clean_msg})
        else:
            sanitized[key] = result
    return sanitized


def _aggregate_env_vars_result(env: dict) -> ServiceResult:
    """Calcula el peor status de todos los ServiceResult de validate_env_vars.

    Args:
        env: Diccionario de variables de entorno a validar.

    Returns:
        ServiceResult unico que representa el estado global de env_vars.
    """
    env_results: dict[str, ServiceResult] = validate_env_vars(env)
    statuses = [r.status for r in env_results.values()]

    if CheckStatus.ERROR in statuses:
        env_global_status = CheckStatus.ERROR
    elif CheckStatus.WARNING in statuses:
        env_global_status = CheckStatus.WARNING
    else:
        env_global_status = CheckStatus.OK

    return ServiceResult(
        status=env_global_status,
        latency_ms=0.1,
        message=(
            None
            if env_global_status == CheckStatus.OK
            else "variables de entorno con errores"
        ),
    )


def _compute_global_status(checks: dict[str, ServiceResult]) -> CheckStatus:
    """Determina el status global segun la criticidad de los fallos.

    Regla de precedencia:
    - Si cualquier check CRITICO tiene ERROR  → ERROR
    - Si ningun critico tiene ERROR pero algun check tiene ERROR o WARNING → WARNING
    - Si todos son OK → OK

    Args:
        checks: Mapa de nombre de servicio a su ServiceResult.

    Returns:
        CheckStatus global que representa el peor estado ponderado por criticidad.
    """
    for service_key, result in checks.items():
        if service_key in CRITICAL_SERVICES and result.status == CheckStatus.ERROR:
            return CheckStatus.ERROR

    for result in checks.values():
        if result.status in (CheckStatus.ERROR, CheckStatus.WARNING):
            return CheckStatus.WARNING

    return CheckStatus.OK


def _write_github_step_summary(report: RunReport) -> None:
    """Escribe un reporte markdown en la ruta apuntada por GITHUB_STEP_SUMMARY.

    Solo se ejecuta cuando la variable de entorno GITHUB_STEP_SUMMARY esta
    presente en el entorno real del proceso (os.environ), no en el env
    inyectado por tests. Si la variable no existe, la funcion retorna
    silenciosamente sin efecto secundario alguno.

    El archivo es abierto en modo 'a' (append) siguiendo la convencion de
    GitHub Actions, que acumula secciones markdown en el mismo archivo
    durante la ejecucion del workflow.

    Args:
        report: RunReport con el resultado consolidado de todos los checks.
    """
    summary_path: str | None = os.environ.get("GITHUB_STEP_SUMMARY")
    if not summary_path:
        return

    emoji_map: dict[CheckStatus, str] = {
        CheckStatus.OK: "OK",
        CheckStatus.WARNING: "WARNING",
        CheckStatus.ERROR: "ERROR",
    }

    emoji_prefix: dict[CheckStatus, str] = {
        CheckStatus.OK: "✅",
        CheckStatus.WARNING: "⚠️",
        CheckStatus.ERROR: "❌",
    }

    def _format_status(status: CheckStatus) -> str:
        return f"{emoji_prefix[status]} {emoji_map[status]}"

    lines: list[str] = [
        "## Reporte de Validacion de Entorno\n",
        f"**Run ID**: `{report.run_id}`  ",
        f"**Timestamp**: `{report.timestamp}`  ",
        f"**Status Global**: {_format_status(report.status)}\n",
        "| Servicio | Estado | Detalle |",
        "|---|---|---|",
    ]

    for service, result in report.checks.items():
        detail: str = result.message or "-"
        lines.append(f"| {service} | {_format_status(result.status)} | {detail} |")

    # ------------------------------------------------------------------
    # T-12b: Environment Snapshot — version Python y hashes de deps directas
    # Resolucion de ruta relativa al archivo para compatibilidad local/GHA.
    # ------------------------------------------------------------------
    dep_hashes: dict[str, str] = {dep: "N/A" for dep in _DIRECT_DEPS}
    try:
        req_path: Path = Path(__file__).parent.parent / "requirements.txt"
        req_text: str = req_path.read_text(encoding="utf-8")
        # Parsear bloque de cada dependencia directa: busca "nombre==" y extrae
        # el primer hash sha256 del bloque de entrada.
        for dep in _DIRECT_DEPS:
            # Patron: linea que comienza con el nombre del paquete seguido de ==
            pkg_pattern = re.compile(
                rf"^{re.escape(dep)}==.*?(?=\n\S|\Z)",
                re.MULTILINE | re.DOTALL,
            )
            pkg_match = pkg_pattern.search(req_text)
            if pkg_match:
                hash_match = re.search(r"--hash=sha256:([a-f0-9]+)", pkg_match.group(0))
                if hash_match:
                    full_hash: str = hash_match.group(1)
                    dep_hashes[dep] = f"sha256:{full_hash[:16]}..."
    except Exception:
        # Fallback silencioso: los valores ya son "N/A"
        pass

    python_version: str = sys.version.replace("\n", " ")
    lines.append("\n## Environment Snapshot\n")
    lines.append("| Componente | Version / Hash |")
    lines.append("|---|---|")
    lines.append(f"| Python | {python_version} |")
    for dep in _DIRECT_DEPS:
        lines.append(f"| {dep} | {dep_hashes[dep]} |")

    with open(summary_path, "a", encoding="utf-8") as summary_file:
        summary_file.write("\n".join(lines) + "\n")


def main(env: dict | None = None) -> RunReport:
    """Orquesta la validacion completa del entorno de ejecucion.

    Ejecuta todos los checks en modo Diagnostic-First: todos los servicios
    son evaluados antes de calcular el status global, garantizando
    trazabilidad total aunque multiples checks fallen simultaneamente.

    Emite logging estructurado a stderr durante la ejecucion para no
    contaminar el JSON de stdout. Al finalizar, imprime el RunReport
    serializado como JSON a stdout y escribe el reporte markdown en
    GITHUB_STEP_SUMMARY si la variable de entorno esta definida.

    Args:
        env: Diccionario de variables de entorno a usar. Si es None se usa
             os.environ. Permite inyeccion de entornos sinteticos en tests.

    Returns:
        RunReport con el resultado consolidado de todos los checks.

    Raises:
        SystemExit: Con codigo 1 si el status global es ERROR (algun servicio
                    critico fallo). El reporte es construido y emitido antes
                    de hacer exit para garantizar trazabilidad completa.
    """
    resolved_env: dict = env if env is not None else dict(os.environ)

    # Generar run_id anticipado para usarlo en los logs de inicio
    run_id: str = generate_run_id()
    short_id: str = run_id_short(run_id)

    # Log de inicio
    print(
        format_log_entry("INFO", "orchestrator", f"Iniciando validacion de entorno — run_id: {short_id}"),
        file=sys.stderr,
    )

    # Fase 1: ejecutar TODOS los checks (Diagnostic-First)
    # _run_and_log_check ejecuta el callable y emite el log de resultado a stderr.
    checks: dict[str, ServiceResult] = {}

    checks["env_vars"] = _run_and_log_check("env_vars", _aggregate_env_vars_result, resolved_env)
    checks["github"] = _run_and_log_check("github", check_github, resolved_env.get("GITHUB_TOKEN", ""))
    checks["resend"] = _run_and_log_check("resend", check_resend, resolved_env.get("RESEND_API_KEY", ""))
    checks["upstash"] = _run_and_log_check(
        "upstash",
        check_upstash,
        resolved_env.get("UPSTASH_REDIS_REST_URL", ""),
        resolved_env.get("UPSTASH_REDIS_REST_TOKEN", ""),
    )
    checks["supabase_http"] = _run_and_log_check(
        "supabase_http",
        check_supabase_http,
        resolved_env.get("SUPABASE_URL", ""),
        resolved_env.get("SUPABASE_SERVICE_ROLE_KEY", ""),
    )
    checks["supabase_sql"] = _run_and_log_check(
        "supabase_sql", check_supabase_sql, resolved_env.get("POSTGRES_DB_URL", "")
    )

    # Limpieza de tablas zombie _bootstrap_* antes de cualquier auditoria de esquema.
    # Se ejecuta en el arranque para garantizar un estado limpio antes de los checks DDL.
    # Criticidad WARNING: la presencia de zombies no bloquea el entorno pero debe advertirse.
    # Trazabilidad: TSK-F1_1.0-14.3-GREEN / docs/f1_1.0/f1_1.0_spec.md §3.3 T-10b
    checks["zombie_cleanup"] = _run_and_log_check(
        "zombie_cleanup", check_zombie_cleanup, resolved_env.get("POSTGRES_DB_URL", "")
    )

    # Sonda de capacidades DDL: verifica que el usuario de BD tiene privilegio
    # CREATE en el esquema public antes de auditar extensiones y ciclos de persistencia.
    # Criticidad WARNING: sin privilegio CREATE el entorno puede arrancar pero los
    # checks DDL posteriores advertiran o fallaran segun sus propias reglas.
    # Trazabilidad: TSK-F1_1.0-15.1-GREEN / docs/f1_1.0/f1_1.0_spec.md §3.3 T-10c
    checks["ddl_capabilities"] = _run_and_log_check(
        "ddl_capabilities", check_ddl_capabilities, resolved_env.get("POSTGRES_DB_URL", "")
    )

    # Auditoria de extensiones PostgreSQL requeridas (pg_cron, uuid-ossp, pg_net).
    # Se ejecuta despues de supabase_sql ya que depende de que la conexion SQL sea posible.
    # Criticidad WARNING: el entorno puede operar sin estas extensiones inicialmente,
    # pero se debe advertir para garantizar la funcionalidad completa del sistema.
    # Trazabilidad: TSK-F1_1.0-14.2-GREEN / docs/f1_1.0/f1_1.0_spec.md §3.3-A
    checks["pg_extensions"] = _run_and_log_check(
        "pg_extensions", check_pg_extensions, resolved_env.get("POSTGRES_DB_URL", "")
    )

    # Ciclo forense de persistencia: valida que el usuario puede CREATE, INSERT, SELECT y DROP
    # en el esquema public. Usa la tabla temporal _bootstrap_[short_id] que se elimina en finally.
    # Se ejecuta despues de ddl_capabilities para ejercer los privilegios ya sondeados.
    # Criticidad WARNING: un fallo indica restriccion de permisos DDL, no bloquea el arranque.
    # Trazabilidad: TSK-F1_1.0-15.2-GREEN / docs/f1_1.0/f1_1.0_spec.md §3.3-B
    checks["persistence_cycle"] = _run_and_log_check(
        "persistence_cycle",
        check_persistence_cycle,
        resolved_env.get("POSTGRES_DB_URL", ""),
        short_id,
    )

    # Extraer secretos del entorno para sanitizar mensajes de error antes de emitir
    # cualquier reporte, previniendo fugas de credenciales en stdout y en GHA.
    # Trazabilidad: SPEC §3.2.2
    _SECRET_ENV_KEYS = (
        "SUPABASE_URL",
        "SUPABASE_SERVICE_ROLE_KEY",
        "POSTGRES_DB_URL",
        "UPSTASH_REDIS_REST_TOKEN",
        "RESEND_API_KEY",
        "GITHUB_TOKEN",
        "ADMIN_UUID",
    )
    secrets: list[str] = [
        resolved_env[k] for k in _SECRET_ENV_KEYS if resolved_env.get(k)
    ]
    checks = _sanitize_checks(checks, secrets)

    # Fase 2: agregar status global ponderado por criticidad
    global_status: CheckStatus = _compute_global_status(checks)

    # Fase 3: construir el reporte canonico con el run_id pre-generado
    report = RunReport(
        run_id=run_id,
        timestamp=get_timestamp(),
        status=global_status,
        checks=checks,
    )

    # Log de finalizacion con nivel acorde al status global
    completion_level: str = (
        "ERROR" if global_status == CheckStatus.ERROR
        else "WARNING" if global_status == CheckStatus.WARNING
        else "INFO"
    )
    print(
        format_log_entry(
            completion_level,
            "orchestrator",
            f"Validacion completada — status: {global_status.value}",
        ),
        file=sys.stderr,
    )

    # Fase 4: emitir JSON a stdout (canal de datos, separado del logging)
    print(report.model_dump_json(indent=2))

    # Fase 5: escribir GITHUB_STEP_SUMMARY si la variable esta definida
    _write_github_step_summary(report)

    # Fase 6: exit code — solo despues de emitir el reporte completo
    if global_status == CheckStatus.ERROR:
        sys.exit(1)

    return report

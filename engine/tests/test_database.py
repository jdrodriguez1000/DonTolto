"""
Suite de pruebas RED (TDD) para las funciones de auditoría de base de datos.

Cubre los cuatro checks de infraestructura PostgreSQL del Bloque 4:
  - check_pg_extensions   : auditoría de extensiones pg_cron, uuid-ossp, pg_net
  - check_zombie_cleanup  : limpieza de tablas _bootstrap_* huérfanas
  - check_ddl_capabilities: sonda de privilegios DDL (has_schema_privilege)
  - check_persistence_cycle: ciclo CREATE→INSERT→SELECT→DROP con tabla temporal

Todos los tests usan unittest.mock para aislar psycopg2.connect.
No se realizan llamadas reales a la base de datos en ningún escenario.

Trazabilidad: TSK-F1_1.0-13-RED / docs/f1_1.0/f1_1.0_spec.md §3.3
"""

from unittest.mock import MagicMock, call, patch

import psycopg2
import pytest

from engine.src.models import CheckStatus, ServiceResult


# ---------------------------------------------------------------------------
# Importación diferida de funciones bajo prueba.
# Las cuatro funciones aún no existen en check_env.py. Se importan dentro de
# cada test para que pytest pueda recolectar y ejecutar todos los casos
# individualmente, obteniendo un fallo semántico (ImportError / AttributeError)
# por test en lugar de un único error de colección.
# ---------------------------------------------------------------------------


def _import_check_pg_extensions():
    """Importa check_pg_extensions; falla con ImportError en fase RED."""
    from engine.src.check_env import check_pg_extensions  # noqa: PLC0415
    return check_pg_extensions


def _import_check_zombie_cleanup():
    """Importa check_zombie_cleanup; falla con ImportError en fase RED."""
    from engine.src.check_env import check_zombie_cleanup  # noqa: PLC0415
    return check_zombie_cleanup


def _import_check_ddl_capabilities():
    """Importa check_ddl_capabilities; falla con ImportError en fase RED."""
    from engine.src.check_env import check_ddl_capabilities  # noqa: PLC0415
    return check_ddl_capabilities


def _import_check_persistence_cycle():
    """Importa check_persistence_cycle; falla con ImportError en fase RED."""
    from engine.src.check_env import check_persistence_cycle  # noqa: PLC0415
    return check_persistence_cycle

# ---------------------------------------------------------------------------
# Helpers de prueba
# ---------------------------------------------------------------------------


class _PgProgrammingErrorWithCode(psycopg2.ProgrammingError):
    """Subclase de ProgrammingError que permite asignar pgcode como atributo Python.

    En psycopg2 >= 2.9 el atributo pgcode es readonly a nivel C y no puede
    asignarse directamente sobre instancias de ProgrammingError. Esta subclase
    sobrescribe el atributo via property para que los tests puedan controlar
    el codigo de error sin depender de un cursor real ni de un servidor Postgres.
    """

    def __init__(self, msg: str, code: str) -> None:
        super().__init__(msg)
        self._pgcode: str = code

    @property  # type: ignore[override]
    def pgcode(self) -> str:  # type: ignore[override]
        return self._pgcode


class _PgOperationalErrorWithCode(psycopg2.OperationalError):
    """Subclase de OperationalError que permite asignar pgcode como atributo Python.

    En psycopg2 >= 2.9 el atributo pgcode es readonly a nivel C y no puede
    asignarse directamente sobre instancias de OperationalError. Esta subclase
    sobrescribe el atributo via property para que los tests puedan controlar
    el codigo de error sin depender de un cursor real ni de un servidor Postgres.
    """

    def __init__(self, msg: str, code: str) -> None:
        super().__init__(msg)
        self._pgcode: str = code

    @property  # type: ignore[override]
    def pgcode(self) -> str:  # type: ignore[override]
        return self._pgcode


# ---------------------------------------------------------------------------
# Constantes de prueba
# ---------------------------------------------------------------------------

_FAKE_DB_URL: str = "postgresql://user:pass@localhost:5432/testdb"
_FAKE_RUN_ID_SHORT: str = "abc12345"


# ===========================================================================
# Grupo 1: check_pg_extensions
# ===========================================================================


class TestCheckPgExtensions:
    """Pruebas unitarias para check_pg_extensions.

    Verifica el comportamiento ante extensiones presentes, ausentes,
    sin permisos de creación y errores de conexión.
    """

    def test_check_pg_extensions_all_present_returns_ok(self):
        """Caso feliz: CREATE de extensiones y conteo de cron.job/http_request_queue
        se ejecutan sin error; debe retornar OK.

        Arrange: cursor mock ejecuta todos los comandos sin excepción;
                 fetchone() devuelve (1,) para los count queries de visibilidad.
        Act: llamar check_pg_extensions(db_url).
        Assert: ServiceResult.status == OK.
        """
        check_pg_extensions = _import_check_pg_extensions()

        mock_cursor = MagicMock()
        mock_cursor.__enter__ = lambda s: s
        mock_cursor.__exit__ = MagicMock(return_value=False)
        mock_cursor.fetchone.return_value = (1,)

        mock_conn = MagicMock()
        mock_conn.__enter__ = lambda s: s
        mock_conn.__exit__ = MagicMock(return_value=False)
        mock_conn.cursor.return_value = mock_cursor

        with patch("psycopg2.connect", return_value=mock_conn):
            result = check_pg_extensions(_FAKE_DB_URL)

        assert isinstance(result, ServiceResult)
        assert result.status == CheckStatus.OK

    def test_check_pg_extensions_permission_denied_but_exists_returns_warning(self):
        """Degradación parcial: CREATE falla por 42501 pero la extensión existe
        en pg_extension → debe retornar WARNING (funcional pero sin privilegio CREATE).

        Arrange: primera llamada a cursor.execute lanza ProgrammingError con pgcode=42501;
                 consulta a pg_extension devuelve (1,) confirmando existencia.
        Act: llamar check_pg_extensions(db_url).
        Assert: ServiceResult.status == WARNING.
        """
        check_pg_extensions = _import_check_pg_extensions()

        # psycopg2.ProgrammingError.pgcode es readonly en la capa C (psycopg2 2.9+).
        # Se usa _PgProgrammingErrorWithCode (subclase con property) para poder
        # asignar el codigo de error y que sea capturable por except ProgrammingError.
        permission_error = _PgProgrammingErrorWithCode("permission denied", "42501")

        mock_cursor = MagicMock()
        mock_cursor.__enter__ = lambda s: s
        mock_cursor.__exit__ = MagicMock(return_value=False)
        # Primera ejecución (CREATE) lanza error de permisos; las siguientes (SELECT) van bien
        mock_cursor.execute.side_effect = [permission_error, None, None, None, None, None]
        mock_cursor.fetchone.return_value = (1,)

        mock_conn = MagicMock()
        mock_conn.__enter__ = lambda s: s
        mock_conn.__exit__ = MagicMock(return_value=False)
        mock_conn.cursor.return_value = mock_cursor

        with patch("psycopg2.connect", return_value=mock_conn):
            result = check_pg_extensions(_FAKE_DB_URL)

        assert isinstance(result, ServiceResult)
        assert result.status == CheckStatus.WARNING

    def test_check_pg_extensions_connection_error_returns_error(self):
        """Fallo de conectividad: psycopg2.connect lanza OperationalError
        → debe retornar ERROR.

        Arrange: psycopg2.connect lanza OperationalError directamente.
        Act: llamar check_pg_extensions(db_url).
        Assert: ServiceResult.status == ERROR.
        """
        check_pg_extensions = _import_check_pg_extensions()

        with patch("psycopg2.connect", side_effect=psycopg2.OperationalError("connection refused")):
            result = check_pg_extensions(_FAKE_DB_URL)

        assert isinstance(result, ServiceResult)
        assert result.status == CheckStatus.ERROR

    def test_check_pg_extensions_missing_extension_returns_error(self):
        """Extensión ausente: CREATE falla por 42501 y pg_extension devuelve (0,)
        → la extensión no existe ni con permisos ni sin ellos → debe retornar ERROR.

        Arrange: cursor.execute lanza ProgrammingError con pgcode=42501;
                 fetchone() devuelve (0,) indicando ausencia total.
        Act: llamar check_pg_extensions(db_url).
        Assert: ServiceResult.status == ERROR.
        """
        check_pg_extensions = _import_check_pg_extensions()

        # psycopg2.ProgrammingError.pgcode es readonly en la capa C (psycopg2 2.9+).
        # Se usa _PgProgrammingErrorWithCode (subclase con property) para poder
        # asignar el codigo de error y que sea capturable por except ProgrammingError.
        permission_error = _PgProgrammingErrorWithCode("permission denied", "42501")

        mock_cursor = MagicMock()
        mock_cursor.__enter__ = lambda s: s
        mock_cursor.__exit__ = MagicMock(return_value=False)
        mock_cursor.execute.side_effect = [permission_error, None, None, None, None, None]
        mock_cursor.fetchone.return_value = (0,)

        mock_conn = MagicMock()
        mock_conn.__enter__ = lambda s: s
        mock_conn.__exit__ = MagicMock(return_value=False)
        mock_conn.cursor.return_value = mock_cursor

        with patch("psycopg2.connect", return_value=mock_conn):
            result = check_pg_extensions(_FAKE_DB_URL)

        assert isinstance(result, ServiceResult)
        assert result.status == CheckStatus.ERROR


# ===========================================================================
# Grupo 2: check_zombie_cleanup
# ===========================================================================


class TestCheckZombieCleanup:
    """Pruebas unitarias para check_zombie_cleanup.

    Verifica la detección y eliminación de tablas _bootstrap_* huérfanas.
    """

    def test_check_zombie_cleanup_no_zombies_returns_ok(self):
        """Sin zombies: la query de búsqueda retorna 0 filas → OK con mensaje
        indicando que no había tablas huérfanas.

        Arrange: cursor.fetchall() devuelve lista vacía.
        Act: llamar check_zombie_cleanup(db_url).
        Assert: ServiceResult.status == OK.
        """
        check_zombie_cleanup = _import_check_zombie_cleanup()

        mock_cursor = MagicMock()
        mock_cursor.__enter__ = lambda s: s
        mock_cursor.__exit__ = MagicMock(return_value=False)
        mock_cursor.fetchall.return_value = []

        mock_conn = MagicMock()
        mock_conn.__enter__ = lambda s: s
        mock_conn.__exit__ = MagicMock(return_value=False)
        mock_conn.cursor.return_value = mock_cursor

        with patch("psycopg2.connect", return_value=mock_conn):
            result = check_zombie_cleanup(_FAKE_DB_URL)

        assert isinstance(result, ServiceResult)
        assert result.status == CheckStatus.OK
        # El mensaje debe indicar que no se encontraron tablas huérfanas
        assert result.message is not None
        assert "0" in result.message or "no" in result.message.lower() or "sin" in result.message.lower()

    def test_check_zombie_cleanup_drops_zombie_tables_returns_ok(self):
        """Con zombies: la query retorna 2 tablas huérfanas; mock verifica que
        DROP fue llamado; resultado debe ser OK con mención de tablas eliminadas.

        Arrange: cursor.fetchall() devuelve 2 nombres de tabla zombie;
                 cursor.execute está disponible para los DROP.
        Act: llamar check_zombie_cleanup(db_url).
        Assert: ServiceResult.status == OK y el mensaje indica tablas eliminadas.
        """
        check_zombie_cleanup = _import_check_zombie_cleanup()

        zombie_tables = [("_bootstrap_aaa11111",), ("_bootstrap_bbb22222",)]

        mock_cursor = MagicMock()
        mock_cursor.__enter__ = lambda s: s
        mock_cursor.__exit__ = MagicMock(return_value=False)
        mock_cursor.fetchall.return_value = zombie_tables

        mock_conn = MagicMock()
        mock_conn.__enter__ = lambda s: s
        mock_conn.__exit__ = MagicMock(return_value=False)
        mock_conn.cursor.return_value = mock_cursor

        with patch("psycopg2.connect", return_value=mock_conn):
            result = check_zombie_cleanup(_FAKE_DB_URL)

        assert isinstance(result, ServiceResult)
        assert result.status == CheckStatus.OK
        # Verificar que se ejecutaron comandos DROP (al menos 2 llamadas a execute)
        assert mock_cursor.execute.call_count >= 2
        # El mensaje debe indicar que se limpiaron tablas
        assert result.message is not None
        assert any(kw in result.message.lower() for kw in ["eliminad", "dropp", "limpi", "2"])

    def test_check_zombie_cleanup_connection_error_returns_error(self):
        """Fallo de conectividad: psycopg2.connect lanza OperationalError → ERROR.

        Arrange: psycopg2.connect lanza OperationalError.
        Act: llamar check_zombie_cleanup(db_url).
        Assert: ServiceResult.status == ERROR.
        """
        check_zombie_cleanup = _import_check_zombie_cleanup()

        with patch("psycopg2.connect", side_effect=psycopg2.OperationalError("host unreachable")):
            result = check_zombie_cleanup(_FAKE_DB_URL)

        assert isinstance(result, ServiceResult)
        assert result.status == CheckStatus.ERROR


# ===========================================================================
# Grupo 3: check_ddl_capabilities
# ===========================================================================


class TestCheckDdlCapabilities:
    """Pruebas unitarias para check_ddl_capabilities.

    Valida la sonda de privilegios DDL via has_schema_privilege.
    """

    def test_check_ddl_capabilities_has_create_privilege_returns_ok(self):
        """Privilegio presente: fetchone() devuelve (True,) → OK.

        Arrange: cursor.fetchone() retorna (True,).
        Act: llamar check_ddl_capabilities(db_url).
        Assert: ServiceResult.status == OK.
        """
        check_ddl_capabilities = _import_check_ddl_capabilities()

        mock_cursor = MagicMock()
        mock_cursor.__enter__ = lambda s: s
        mock_cursor.__exit__ = MagicMock(return_value=False)
        mock_cursor.fetchone.return_value = (True,)

        mock_conn = MagicMock()
        mock_conn.__enter__ = lambda s: s
        mock_conn.__exit__ = MagicMock(return_value=False)
        mock_conn.cursor.return_value = mock_cursor

        with patch("psycopg2.connect", return_value=mock_conn):
            result = check_ddl_capabilities(_FAKE_DB_URL)

        assert isinstance(result, ServiceResult)
        assert result.status == CheckStatus.OK

    def test_check_ddl_capabilities_no_create_privilege_returns_warning(self):
        """Sin privilegio: fetchone() devuelve (False,) → WARNING (no crítico pero
        los checks DDL posteriores fallarán).

        Arrange: cursor.fetchone() retorna (False,).
        Act: llamar check_ddl_capabilities(db_url).
        Assert: ServiceResult.status == WARNING.
        """
        check_ddl_capabilities = _import_check_ddl_capabilities()

        mock_cursor = MagicMock()
        mock_cursor.__enter__ = lambda s: s
        mock_cursor.__exit__ = MagicMock(return_value=False)
        mock_cursor.fetchone.return_value = (False,)

        mock_conn = MagicMock()
        mock_conn.__enter__ = lambda s: s
        mock_conn.__exit__ = MagicMock(return_value=False)
        mock_conn.cursor.return_value = mock_cursor

        with patch("psycopg2.connect", return_value=mock_conn):
            result = check_ddl_capabilities(_FAKE_DB_URL)

        assert isinstance(result, ServiceResult)
        assert result.status == CheckStatus.WARNING

    def test_check_ddl_capabilities_connection_error_returns_error(self):
        """Fallo de conectividad: psycopg2.connect lanza OperationalError → ERROR.

        Arrange: psycopg2.connect lanza OperationalError.
        Act: llamar check_ddl_capabilities(db_url).
        Assert: ServiceResult.status == ERROR.
        """
        check_ddl_capabilities = _import_check_ddl_capabilities()

        with patch("psycopg2.connect", side_effect=psycopg2.OperationalError("timeout")):
            result = check_ddl_capabilities(_FAKE_DB_URL)

        assert isinstance(result, ServiceResult)
        assert result.status == CheckStatus.ERROR


# ===========================================================================
# Grupo 4: check_persistence_cycle
# ===========================================================================


class TestCheckPersistenceCycle:
    """Pruebas unitarias para check_persistence_cycle.

    Valida el ciclo CREATE→INSERT→SELECT→DROP con tabla temporal
    _bootstrap_[run_id_short] y las garantías del bloque finally.
    """

    def test_check_persistence_cycle_success_returns_ok(self):
        """Ciclo completo exitoso: todos los pasos se ejecutan sin error;
        SELECT count retorna 1 → OK.

        Arrange: cursor mock ejecuta CREATE, INSERT, SELECT (fetchone → (1,)) y DROP
                 sin lanzar excepción.
        Act: llamar check_persistence_cycle(db_url, run_id_short).
        Assert: ServiceResult.status == OK.
        """
        check_persistence_cycle = _import_check_persistence_cycle()

        mock_cursor = MagicMock()
        mock_cursor.__enter__ = lambda s: s
        mock_cursor.__exit__ = MagicMock(return_value=False)
        mock_cursor.fetchone.return_value = (1,)

        mock_conn = MagicMock()
        mock_conn.__enter__ = lambda s: s
        mock_conn.__exit__ = MagicMock(return_value=False)
        mock_conn.cursor.return_value = mock_cursor

        with patch("psycopg2.connect", return_value=mock_conn):
            result = check_persistence_cycle(_FAKE_DB_URL, _FAKE_RUN_ID_SHORT)

        assert isinstance(result, ServiceResult)
        assert result.status == CheckStatus.OK

    def test_check_persistence_cycle_cleanup_runs_on_failure(self):
        """Garantía de limpieza: si INSERT lanza excepción, el bloque finally
        debe ejecutar DROP de todas formas.

        Arrange: cursor.execute lanza excepción en la segunda llamada (INSERT);
                 se verifica que execute fue llamado con DROP al final.
        Act: llamar check_persistence_cycle(db_url, run_id_short).
        Assert: cursor.execute fue invocado con un comando DROP al finalizar.
        """
        check_persistence_cycle = _import_check_persistence_cycle()

        mock_cursor = MagicMock()
        mock_cursor.__enter__ = lambda s: s
        mock_cursor.__exit__ = MagicMock(return_value=False)

        # CREATE pasa, INSERT falla
        mock_cursor.execute.side_effect = [
            None,                               # CREATE TABLE
            Exception("insert failed"),         # INSERT → falla
        ]

        mock_conn = MagicMock()
        mock_conn.__enter__ = lambda s: s
        mock_conn.__exit__ = MagicMock(return_value=False)
        mock_conn.cursor.return_value = mock_cursor

        with patch("psycopg2.connect", return_value=mock_conn):
            result = check_persistence_cycle(_FAKE_DB_URL, _FAKE_RUN_ID_SHORT)

        # Verificar que se intentó un DROP (cleanup en finally)
        drop_calls = [
            str(c) for c in mock_cursor.execute.call_args_list
            if "DROP" in str(c).upper()
        ]
        assert len(drop_calls) >= 1, "El bloque finally debe ejecutar DROP TABLE"
        # El resultado debe ser ERROR o WARNING (no OK) dado el fallo
        assert result.status in (CheckStatus.ERROR, CheckStatus.WARNING)

    def test_check_persistence_cycle_connection_refused_returns_error(self):
        """Error de conectividad 08001: OperationalError con pgcode 08001
        → ERROR con mención de problema de conectividad.

        Arrange: psycopg2.connect lanza OperationalError con pgcode 08001.
        Act: llamar check_persistence_cycle(db_url, run_id_short).
        Assert: ServiceResult.status == ERROR.
        """
        check_persistence_cycle = _import_check_persistence_cycle()

        # psycopg2.OperationalError.pgcode es readonly en la capa C (psycopg2 2.9+).
        # Se usa _PgOperationalErrorWithCode (subclase con property) para controlar
        # el pgcode sin depender de un servidor real.
        conn_error = _PgOperationalErrorWithCode("connection refused", "08001")

        with patch("psycopg2.connect", side_effect=conn_error):
            result = check_persistence_cycle(_FAKE_DB_URL, _FAKE_RUN_ID_SHORT)

        assert isinstance(result, ServiceResult)
        assert result.status == CheckStatus.ERROR

    def test_check_persistence_cycle_insufficient_privilege_returns_warning(self):
        """Sin privilegios DDL: CREATE lanza ProgrammingError con pgcode 42501
        → WARNING (el usuario no tiene permisos de CREATE pero la DB es accesible).

        Arrange: cursor.execute lanza ProgrammingError con pgcode=42501 en CREATE.
        Act: llamar check_persistence_cycle(db_url, run_id_short).
        Assert: ServiceResult.status == WARNING.
        """
        check_persistence_cycle = _import_check_persistence_cycle()

        # psycopg2.ProgrammingError.pgcode es readonly en la capa C (psycopg2 2.9+).
        # Se usa _PgProgrammingErrorWithCode (subclase con property) para controlar
        # el pgcode sin depender de un servidor real.
        priv_error = _PgProgrammingErrorWithCode("permission denied for schema public", "42501")

        mock_cursor = MagicMock()
        mock_cursor.__enter__ = lambda s: s
        mock_cursor.__exit__ = MagicMock(return_value=False)
        mock_cursor.execute.side_effect = [priv_error]

        mock_conn = MagicMock()
        mock_conn.__enter__ = lambda s: s
        mock_conn.__exit__ = MagicMock(return_value=False)
        mock_conn.cursor.return_value = mock_cursor

        with patch("psycopg2.connect", return_value=mock_conn):
            result = check_persistence_cycle(_FAKE_DB_URL, _FAKE_RUN_ID_SHORT)

        assert isinstance(result, ServiceResult)
        assert result.status == CheckStatus.WARNING

    def test_check_persistence_cycle_uses_run_id_short_in_table_name(self):
        """Contrato de nombrado: el nombre de tabla generado internamente debe
        contener el run_id_short provisto como parámetro.

        Arrange: cursor mock exitoso; se capturan las llamadas a execute.
        Act: llamar check_persistence_cycle(db_url, run_id_short="test9999").
        Assert: alguna llamada a execute contiene "test9999" en su argumento SQL.
        """
        check_persistence_cycle = _import_check_persistence_cycle()

        custom_run_id = "test9999"

        mock_cursor = MagicMock()
        mock_cursor.__enter__ = lambda s: s
        mock_cursor.__exit__ = MagicMock(return_value=False)
        mock_cursor.fetchone.return_value = (1,)

        mock_conn = MagicMock()
        mock_conn.__enter__ = lambda s: s
        mock_conn.__exit__ = MagicMock(return_value=False)
        mock_conn.cursor.return_value = mock_cursor

        with patch("psycopg2.connect", return_value=mock_conn):
            check_persistence_cycle(_FAKE_DB_URL, custom_run_id)

        # Todos los SQL emitidos como string
        all_sql_calls = " ".join(str(c) for c in mock_cursor.execute.call_args_list)
        assert custom_run_id in all_sql_calls, (
            f"El run_id_short '{custom_run_id}' debe aparecer en el nombre de tabla "
            f"usado en los comandos SQL. Llamadas registradas: {all_sql_calls}"
        )

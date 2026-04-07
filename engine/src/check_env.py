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
import sys
from typing import Final

from engine.src.models import CheckStatus, RunReport, ServiceResult, validate_env_vars
from engine.src.utils import format_log_entry, generate_run_id, get_timestamp, run_id_short

# ---------------------------------------------------------------------------
# Mapeo de criticidad de servicios
# CRITICAL_SERVICES: fallo provoca sys.exit(1)
# WARNING_SERVICES:  fallo eleva el status global a WARNING, sin exit
# ---------------------------------------------------------------------------

CRITICAL_SERVICES: Final[frozenset[str]] = frozenset(
    {"env_vars", "supabase_sql", "supabase_http"}
)

WARNING_SERVICES: Final[frozenset[str]] = frozenset(
    {"github", "resend", "upstash"}
)


# ---------------------------------------------------------------------------
# Stubs de checks de servicio externo
# Implementacion real: TSK-F1_1.0-11.1-GREEN y siguientes
# ---------------------------------------------------------------------------


def check_github(token: str) -> ServiceResult:
    """Verifica la disponibilidad y autenticacion del token de GitHub.

    Args:
        token: Personal Access Token de GitHub (ghp_* o github_pat_*).

    Returns:
        ServiceResult con el estado del servicio y latencia medida.
    """
    # Stub: implementacion real en TSK-F1_1.0-11.1-GREEN
    return ServiceResult(
        status=CheckStatus.WARNING,
        latency_ms=0.1,
        message="not implemented",
    )


def check_resend(api_key: str) -> ServiceResult:
    """Verifica la disponibilidad y autenticacion de la API de Resend.

    Args:
        api_key: Clave de API de Resend (prefijo re_*).

    Returns:
        ServiceResult con el estado del servicio y latencia medida.
    """
    # Stub: implementacion real en TSK-F1_1.0-11.1-GREEN
    return ServiceResult(
        status=CheckStatus.WARNING,
        latency_ms=0.1,
        message="not implemented",
    )


def check_upstash(url: str, token: str) -> ServiceResult:
    """Verifica la disponibilidad del cluster Redis en Upstash.

    Args:
        url: URL REST del cluster Upstash (https://*.upstash.io).
        token: Token de autenticacion REST de Upstash.

    Returns:
        ServiceResult con el estado del servicio y latencia medida.
    """
    # Stub: implementacion real en TSK-F1_1.0-11.1-GREEN
    return ServiceResult(
        status=CheckStatus.WARNING,
        latency_ms=0.1,
        message="not implemented",
    )


def check_supabase_http(url: str, key: str) -> ServiceResult:
    """Verifica la disponibilidad de Supabase via HTTP (PostgREST/healthcheck).

    Args:
        url: URL publica del proyecto Supabase.
        key: Service Role Key del proyecto Supabase.

    Returns:
        ServiceResult con el estado del servicio y latencia medida.
    """
    # Stub: implementacion real en TSK-F1_1.0-11.1-GREEN
    return ServiceResult(
        status=CheckStatus.WARNING,
        latency_ms=0.1,
        message="not implemented",
    )


def check_supabase_sql(db_url: str) -> ServiceResult:
    """Verifica la conectividad directa a PostgreSQL via psycopg2.

    Args:
        db_url: URL de conexion PostgreSQL completa (postgresql://...).

    Returns:
        ServiceResult con el estado del servicio y latencia medida.
    """
    # Stub: implementacion real en TSK-F1_1.0-11.1-GREEN
    return ServiceResult(
        status=CheckStatus.WARNING,
        latency_ms=0.1,
        message="not implemented",
    )


# ---------------------------------------------------------------------------
# Orquestador principal
# ---------------------------------------------------------------------------


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
    checks: dict[str, ServiceResult] = {}

    checks["env_vars"] = _aggregate_env_vars_result(resolved_env)
    print(
        format_log_entry("INFO", "orchestrator", f"Check 'env_vars': {checks['env_vars'].status.value}"),
        file=sys.stderr,
    )

    checks["github"] = check_github(resolved_env.get("GITHUB_TOKEN", ""))
    print(
        format_log_entry("INFO", "orchestrator", f"Check 'github': {checks['github'].status.value}"),
        file=sys.stderr,
    )

    checks["resend"] = check_resend(resolved_env.get("RESEND_API_KEY", ""))
    print(
        format_log_entry("INFO", "orchestrator", f"Check 'resend': {checks['resend'].status.value}"),
        file=sys.stderr,
    )

    checks["upstash"] = check_upstash(
        resolved_env.get("UPSTASH_REDIS_REST_URL", ""),
        resolved_env.get("UPSTASH_REDIS_REST_TOKEN", ""),
    )
    print(
        format_log_entry("INFO", "orchestrator", f"Check 'upstash': {checks['upstash'].status.value}"),
        file=sys.stderr,
    )

    checks["supabase_http"] = check_supabase_http(
        resolved_env.get("SUPABASE_URL", ""),
        resolved_env.get("SUPABASE_SERVICE_ROLE_KEY", ""),
    )
    print(
        format_log_entry("INFO", "orchestrator", f"Check 'supabase_http': {checks['supabase_http'].status.value}"),
        file=sys.stderr,
    )

    checks["supabase_sql"] = check_supabase_sql(
        resolved_env.get("POSTGRES_DB_URL", "")
    )
    print(
        format_log_entry("INFO", "orchestrator", f"Check 'supabase_sql': {checks['supabase_sql'].status.value}"),
        file=sys.stderr,
    )

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

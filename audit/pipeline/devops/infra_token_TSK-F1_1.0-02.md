# Token de Infraestructura — TSK-F1_1.0-02

| Campo             | Valor                                      |
|-------------------|--------------------------------------------|
| Tarea             | TSK-F1_1.0-02                              |
| Etapa             | f1_1.0 — Validacion de Entorno             |
| Agente            | devops-integrator                          |
| Fecha             | 2026-04-07                                 |
| Estado            | AUTORIZADO                                 |

## Artefactos Generados

| Artefacto                    | Descripcion                                                        |
|------------------------------|--------------------------------------------------------------------|
| `engine/requirements.txt`    | Manifiesto con hashes SHA256 (pip-compile --generate-hashes)      |
| `engine/requirements.in`     | Archivo fuente con 4 dependencias directas                        |
| `engine/.venv/`              | Entorno virtual Python 3.12 aislado (no incluido en repo)         |

## Dependencias Directas Bloqueadas

| Paquete            | Version  | Proposito                        |
|--------------------|----------|----------------------------------|
| httpx              | 0.27.0   | Cliente HTTP asincrono           |
| psycopg2-binary    | 2.9.9    | Driver Postgres                  |
| python-dotenv      | 1.0.1    | Gestion de variables de entorno  |
| pydantic           | 2.6.4    | Validacion de esquemas de datos  |

## Dependencias Transitivas Resueltas

annotated-types==0.7.0, anyio==4.13.0, certifi==2026.2.25, h11==0.16.0,
httpcore==1.0.9, idna==3.11, pydantic-core==2.16.3, sniffio==1.3.1,
typing-extensions==4.15.0

**Total paquetes con hashes**: 13 (4 directos + 9 transitivos)

## Validacion de Integridad

- Comando de validacion ejecutado: `pip install --dry-run --require-hashes -r engine/requirements.txt`
- Resultado: EXITOSO — Todos los hashes verificados sin errores.
- Reproducibilidad: El archivo puede usarse en entorno limpio con un solo comando.

## Criterios de DoD — Cumplimiento

- [x] requirements.txt generado con hashes SHA256 reales desde PyPI
- [x] Todas las dependencias directas y transitivas incluidas
- [x] Cabecera en espanol con fecha y herramienta de generacion
- [x] Validacion --dry-run --require-hashes exitosa
- [x] No se instalaron paquetes en el Python global del sistema
- [x] Ambiente virtual creado en `engine/.venv` exclusivamente
- [x] Archivo fuente `requirements.in` documentado

## Estado Final

**DoD CUMPLIDO**: requirements.txt con hashes verificados en engine/requirements.txt

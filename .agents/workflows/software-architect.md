---
description: Flujo estructurado para el diseño técnico y validación de arquitectura por un Senior Software Architect. (Fase 0 a 5).
---

# Workflow: Diseño de Arquitectura Estructurada

Sigue este flujo secuencial estricto para establecer la arquitectura técnica del proyecto.

## Fase 0 — Verificación de Gobernanza y Alcance
1. **Leer `scope_token.md`**: Validar que el estatus sea `AUTORIZADO` en `.audit/governance/`. Si no, detener el proceso.
2. **Analizar `PROJECT_scope.md`**: Extraer objetivos, historias de usuario (US), restricciones y KPIs.
3. **Identificar Hallazgos**: Detectar vacíos o ambigüedades técnicas en los requerimientos del scope.

## Fase 1 — Diseño de Capas (Visión 3 Capas)
1. **Definir Responsabilidades**: Separar lógica de Scraping (Motor Python) de la persistencia y la visualización.
2. **Diseñar Diagrama Mermaid**: Visualizar el flujo de datos desde el sitio web origen hasta el navegador del usuario final.
3. **Definir Orquestación**: Configurar los disparadores de GitHub Actions (Cron) alineados con los días de sorteo.

## Fase 2 — Especificación de Datos y Filtros (DDL)
1. **Esquema de Base de Datos**: Diseñar tablas, índices (GIN para arrays) y tipos de Postgres que optimicen la búsqueda de "hits".
2. **Contratos de Interfaz**: Definir la estructura exacta de JSON/objetos que el Scraper enviará a Supabase.
3. **Mecánica de Backtesting**: Detalla cómo la base de datos comparará juegos proyectados vs reales mediante funciones SQL.

## Fase 3 — Stack Tecnológico y Seguridad
1. **Validar Stack**: Confirmar versiones y herramientas (Python 3.12, Pandera, Upstash Redis, Lucide React).
2. **Estrategia de Seguridad**: Definir el Rate Limiting (Protección de cuota de Supabase) y políticas de RLS.

## Fase 4 — Emisión de Tokens y Documento Maestro
1. **Generar `PROJECT_architecture.md`**: Crear el documento draft en `docs/governance/`.
2. **Crear `architecture_token.md`**: Definir el estatus (`AUTORIZADO` o `BLOQUEADO`) y listar hallazgos técnicos específicos en `.audit/governance/architecture_token.md`.

## Fase 5 — Auditoría y Aprobación Técnica
1. **Presentar Hallazgos**: Reportar al usuario cualquier vacío crítico o riesgo de costo.
2. **Solicitar Cierre**: Pedir explícitamente:
   - ✅ "Apruebo la arquitectura"
   - ✏️ "Hay cambios técnicos"
3. **Cierre de Ciclo**: Tras aprobación, marcar el estado como `Approved` en el documento y en el token.

---
description: Flujo de trabajo para la planificación estratégica y auditoría de etapas por el Senior Project Manager.
---

# Workflow: Planificación Maestra y Auditoría PMP (Project Plan)

Sigue este flujo secuencial para establecer el mapa de ruta macro del proyecto AnyLott.

## Fase 0 — Auditoría de Gobernanza e Insumos
1. **Verificar Architecture Token**: Leer `.audit/governance/architecture_token.md`. Si es `BLOQUEADO`, detener el flujo.
2. **Analizar Alcance y Arquitectura**: Extraer US (Scope) y Componentes (Arquitectura) para asegurar viabilidad.

## Fase 1 — Diseño de Fases y Ruta Crítica (Devil's Advocate)
1. **Definir Fases**: Agrupar hitos en 3 a 4 fases de valor (ej. Fase 1: Datos y Cimentación).
2. **Identificar Bloqueos**: Determinar la secuencia lógica (ej. Supabase -> GHA -> Dashboard).

## Fase 2 — Desglose de Etapas y Agentes
1. **Dividir en Etapas**: Definir bloques de trabajo de 1-2 semanas.
2. **Asignar Roles**: Sugerir tipos de agente (Coder para implementación, Tester para validación, Auditor para cierre de etapa).

## Fase 3 — Mapeo Detallado de Entregables
1. **Main Deliverable**: Núcleo funcional (Ej. "Esquema DDL con RLS aprobado").
2. **Auxiliary Deliverables**: Logs, variables de entorno, scripts de prueba o documentación técnica.

## Fase 4 — Construcción y Emisión de Gobernanza
1. **Generar `PROJECT_plan.md`**: Escribir el plan maestro en `docs/governance/`.
2. **Emitir `plan_token.md`**: En `.audit/governance/`, realizar el análisis de "huecos".
   - **Estatus: AUTORIZADO**: Plan sólido.
   - **Estatus: BLOQUEADO**: Existencia de vacíos o riesgos detectados (detallar motivos).

## Fase 5 — Aprobación Final
1. **Feedback del Usuario**: Presentar resumen y token para visto bueno:
   - ✅ "Plan Aprobado"
   - ✏️ "Ajustar prioridad/etapas"
2. **Cierre**: Una vez autorizado, marcar el plan como `Approved`.

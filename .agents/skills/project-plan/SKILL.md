---
name: project-plan-sdd
description: Crea o actualiza el Plan Maestro del Proyecto (PROJECT_plan.md) definiendo Fases, Etapas, Entregables y Responsabilidades.
---

# Skill: Planificación Proyectiva Integral (PROJECT-PLAN)

Esta habilidad permite al agente actuar como un PM Senior/Auditor para estructurar la hoja de ruta del proyecto bajo una mirada crítica y técnica.

## 📜 Capacidades
- **Blueprint de Ejecución**: Descompone el alcance en Fases (hitos) y Etapas (sprints 1-2 semanas).
- **Mapeo de Entregables (Main/Aux)**: Define exactamente qué se recibe al final de cada etapa, incluyendo soporte técnico.
- **Asignación de Agentes**: Identifica el perfil de agente (Core, Auditor, Tester) necesario para cada etapa.
- **Auditoría de "Gaps"**: Capacidad para encontrar fallas negativas o dependencias no resueltas en el diseño.

## 🛠️ Herramientas y Recursos
- **Insumos**: `PROJECT_scope.md` y `PROJECT_architecture.md`.
- **Insumo Crítico**: `.audit/governance/architecture_token.md` (Estado: `AUTORIZADO`).
- **Salida**: `docs/governance/PROJECT_plan.md` y `.audit/governance/plan_token.md`.

## 📝 Reglas de Ejecución Mundiales
1. **Validación de Token**: No iniciar si la arquitectura no está autorizada.
2. **Definición de DoD**: Cada plan debe finalizar con una sección clara de "Definition of Done".
3. **Roles Sugeridos**: Cada etapa debe especificar qué tipo de agente intervendrá.
4. **Gobernanza de Tokens**: Emitir el `.audit/governance/plan_token.md` detallando cualquier motivo de bloqueo.

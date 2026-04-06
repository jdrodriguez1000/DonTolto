---
description: Flujo de trabajo para realizar auditorías SDD por etapa y emisión del token de validación final (sdd_token.md).
---

# Workflow: Auditoría de Alineación SDD

## Paso 0 — Higiene de Git (Protección de Ramas) 🛡️
1. **Verificar Rama**: Si estás en `main` o `dev`, informa al equipo y detente. Toda auditoría final de una etapa debe realizarse en la rama `feat/f[F]_[E]...`.

## Paso 0.5 — Identificar Contexto y Prerrequisitos (Hard Gate) 🚩
1. **Validación de Entradas (Docs)**: Confirma la existencia de `PRD`, `SPEC`, `PLAN` y `TASK` en `docs/f[F]_[E]/`.
2. **Validación de Entradas (Tokens)**: Confirma que `docs/f[F]_[E]/audit/sdd/prd_token.md`, `spec_token.md`, `plan_i_token.md` y `task_token.md` estén en estado **`Autorizado`**.
   - **Si falta un token o el estado es Bloqueado**: El Auditor DEBE informar la falla de la cadena y detenerse.

## Paso 2 — Análisis de Alineación (Abogado del Diablo) 🔍
1. **Auditoría Transversal**: Lee los 4 documentos simultáneamente buscando:
   - **Contradicciones**: El PRD pide A, la SPEC diseña B.
   - **Redundancias**: Esfuerzos duplicados entre tareas.
   - **Faltas Negativas (Gaps)**: El PLAN asume un componente que no existe en la SPEC.
   - **Vaguedad**: DoD (Definition of Done) en las tareas que son ambiguos.

## Paso 3 — Emisión de Token Maestro (sdd_token.md) 📜
1. **Generar Token**: Crea o actualiza `docs/f[F]_[E]/audit/sdd/sdd_token.md`.
   - **Estado `Autorizado`**: Si el diseño es perfecto y coherente.
   - **Estado `Bloqueado`**: Si se detectan riesgos técnicos. El auditor debe listar los motivos exactos del bloqueo para que sean corregidos.

## Paso 4 — Reporte de Cierre y Próximos Pasos 🚀
Muestra el estado final con los sellos correspondientes:
- `🟢 SDD VALIDADO`: La etapa f[F]_[E] entra en modo implementación.
- `🔴 SDD BLOQUEADO`: Se requiere corrección de alineación.

Siguiente paso (si es validado): Iniciar el primer bloque de la Task List.

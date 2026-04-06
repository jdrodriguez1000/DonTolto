---
description: Flujo para la creación estructurada de la Task List (Lista de Tareas) ejecutable de una etapa.
---

# Workflow: Creación de TASK LIST Estructurada

## Paso 0 — Higiene de Git (Protección de Ramas) 🛡️
1.  **Verificar Rama**: Si estás en `main` o `dev`, informa al usuario y procede a crear/saltar a la rama de funcionalidad `feat/f[F]_[E]_[nombre]`. Prohibido desglosar tareas en ramas protegidas.

## Paso 0.5 — Identificar Contexto y Prerrequisitos
1. **Inferir Etapa**: Identifica la fase/etapa (ej. f1_1.1) a desglosar.
2. **Validación de PLAN (Hard Gate)**: Verifica `docs/f[F]_[E]/audit/sdd/plan_i_token.md`.
   - **Si el estado NO es `Autorizado`**: Detente. No se pueden generar tareas si el plan de ejecución no ha sido validado.
3. **Guardias Maestras**: Verifica visado de gobernanza y documentos de la etapa.

## Paso 2 — Análisis de Implementación (Abogado del Diablo)
1. **Auditoría de Checklist**: Analiza el PLAN buscando pasos técnicos omitidos (migraciones, setup de entorno, tests unitarios).
2. **Preservación**: Si `docs/f[F]_[E]/f[F]_[E]_task.md` existe, léelo. **Prohibido borrar tareas `[x]`**.

## Paso 3 — Recopilación de Detalles Granulares
Si hay dudas sobre la asignación de agentes responsables (Coder/Tester) o el DoD de alguna tarea, pregunta al usuario.

## Paso 4 — Generación de TASK LIST y Token
1. **Generar TASK LIST**: Escribe en `docs/f[F]_[E]/f[F]_[E]_task.md` usando el skill `sdd-task`.
2. **Generar Token de Validación**: Crea `docs/f[F]_[E]/audit/sdd/task_token.md`.
   - **Estado `Autorizado`**: Si el checklist es granular, atómico y cubre el 100% del PLAN.
   - **Estado `Bloqueado`**: Si se detectan tareas vagas o falta de asignación clara.

## Paso 5 — Reporte de Cierre
```
✅ TASK LIST Procesada: docs/f[F]_[E]/f[F]_[E]_task.md
📄 Token de Validación: docs/f[F]_[E]/audit/sdd/task_token.md (Estado: [Autorizado/Bloqueado])
Siguiente paso: /governance-auditor (auditoría final de etapa)
```


---
name: sdd-task
description: "Crea o actualiza la Lista de Tareas (Task List) que desglosa el Plan en checklist ejecutable y granular."
---

# Skill: sdd-task (Task List — Devil's Advocate)

Eres un Desarrollador Senior con mentalidad de **Abogado del Diablo**. Tu responsabilidad es desglosar el PLAN en una Lista de Tareas (TASK LIST) atómica y ejecutable, asegurando que no falte ningún paso técnico, que las dependencias sean reales y que los criterios de aceptación (DoD) sean verificables sin ambigüedad.

## 🛡️ Mentalidad de Abogado del Diablo
1. **Cero Placeholders**: Prohibido "Tarea general", "Codificar lógica" o descripciones vagas. Cada tarea debe tener un verbo de acción, un objeto y un archivo destino.
2. **Atomicidad Extrema**: Si una tarea dura más de 2 días, divídela. Si no se puede dividir, justifica el riesgo.
3. **Validación de PLAN**: Antes de iniciar, verifica que `docs/f[F]_[E]/audit/sdd/plan_i_token.md` esté en estado **`Autorizado`**.
4. **Emisión de Token**: Al finalizar, genera/actualiza el archivo `docs/f[F]_[E]/audit/sdd/task_token.md`.

## 📜 Estructura del Token (`task_token.md`)
- **Estado**: `Autorizado` (Checklist completo y atómico) o `Bloqueado` (Motivo de granularidad o lógica documentado).
- **Etapa**: `f[F]_[E]`.
- **Hallazgos**: Lista de tareas omitidas (ej. tests, migraciones), dependencias imposibles o DoD vagos.
- **Veredicto**: Justificación del estado desde la perspectiva de implementación.

## 🚀 Atomicidad y Ejecución
Tu objetivo es que el Coder no tenga que pensar "qué sigue", sino simplemente marcar `[x]` en una secuencia perfecta.

## Convenciones de Anotación (Vital)
- **`(independiente)`** — Sin dependencias, puede iniciar de inmediato.
- **`(depends_on: TSK-F-XX)`** — Espera a que `TSK-F-XX` esté completa.
- **`(parallel_with: TSK-F-XX)`** — Puede ejecutarse simultáneamente con `TSK-F-XX`.

## Estructura de Documento (TASK LIST)

```markdown
# Lista de Tareas — [Nombre de la Etapa] (`f[F]_[E]`)

> Trazabilidad: Estas tareas implementan `docs/f[F]_[E]/f[F]_[E]_plan.md`.
> Actualiza marcando `[x]` al completar. **NUNCA borres tareas completadas.**

## Mapa de Dependencias
[Diagrama ASCII o de texto agrupando tareas por grupos paralelos o dependientes en el tiempo]

## Bloque 1 — [Nombre del Bloque (B1 del Plan)]
- [ ] `[TSK-F-01]` [Acción técnica concreta: verbo + qué + dónde] _(independiente)_
  - **Agente responsable**: [nombre del agente]
  - **REQ que implementa**: [REQ-XX]
  - **Archivos**: `[ruta/archivo]`
  - **DoD**: [Criterio verificable de completitud]

- [ ] `[TSK-F-02]` [Acción técnica concreta] _(parallel_with: TSK-F-01)_
  - **Agente responsable**: [nombre del agente]
  - **REQ que implementa**: [REQ-XX]
  - **Archivos**: `[ruta/archivo]`
  - **DoD**: [Criterio verificable]

## Cierre de Etapa
> **Responsabilidades de cierre:**
> - `PROJECT_handoff.md` → lo actualiza `session-closer` al **cerrar la sesión**, no al cerrar la etapa.
> - El cierre de etapa tiene dos pasos: (1) auditoría con `/stage-audit` y (2) ejecutivo con `/close-stage`.

- [ ] `[TSK-F-XX]` Ejecutar suite de pruebas unitarias y de integración _(depends_on: tareas de codificación)_
  - **Agente responsable**: `general-purpose`
- [ ] `[TSK-F-XX]` Verificar persistencia triple...
- [ ] `[TSK-F-XX]` Ejecutar auditoría de etapa `/stage-audit f[F]_[E]` _(depends_on: todas las tareas anteriores)_
  - **Agente responsable**: `stage-auditor`
- [ ] `[TSK-F-XX]` Ejecutar cierre formal `/close-stage f[F]_[E]` — genera documento ejecutivo _(depends_on: auditoría aprobada)_
  - **Agente responsable**: `stage-closer`
- [ ] `[TSK-F-XX]` Crear commit atómico en `feat/etapa-[F]-[E]` _(depends_on: ejecutivo generado)_
  - **Agente responsable**: `git-pusher`
```

## Tabla de Agentes Disponibles
- `feature-coder`: Construcción de lógica y componentes funcionales.
- `quality-tester`: Creación y ejecución de validaciones y tests.
- `architecture-reviewer`: Revisión de código y alineación técnica.
- `stage-auditor` y `stage-closer` para cierres organizacionales.
- Si ninguno encaja: `general-purpose`.

## Reglas de Calidad Irrenunciables
1. **Granularidad**: 1-3 días de esfuerzo.
2. **Anotación dependencias**: Toda tarea DEBE tener su estado de paralelo/dependencia.
3. **Agente responsable**: Toda tarea DEBE indicar un Agente responsable exacto.
4. **Trazabilidad**: Toda tarea con tag único y mapeo a REQ.
5. **NUNCA borrar completadas**: `[x]` es historia escrita.

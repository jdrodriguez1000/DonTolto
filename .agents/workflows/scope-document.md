---
description: Flujo de proceso estructurado para definir, refinar y cerrar el alcance de un proyecto. (Analista de Negocios Senior)
---

# Workflow: Scope Document (Senior Business Analyst)

Este workflow guía al analista de negocios en la definición técnica y formal del alcance de un proyecto de software, asegurando la calidad y la aprobación del usuario en cada paso.

## Fases y Pasos

1. **Fase 1: Preparación y Contextualización**:
   - Analizar los inputs iniciales (ej: `BluePrint - Alto nivel.txt`).
   - Generar un borrador de alcance y presentarlo al usuario como punto de partida.

2. **Fase 2: Levantamiento y Cuestionamiento (Abogado del Diablo)**:
   - **Identificación de Gaps**: Detectar vacíos de información o contradicciones.
   - **Historias de Usuario**: Traducir ideas en historias ("Como... Quiero... Para...").
   - **Entrevistas de Estrés**: Preguntar y repreguntar sobre el valor de negocio de cada historia.
   - **Búsqueda de la Claridad Total**: No cerrar una historia hasta que sus criterios de aceptación sean claros.

3. **Fase 3: Documentación y Emisión de Token**:
   - **NO EDITAR** `docs/governance/PROJECT_scope.md` sin aprobación.
   - **EMITIR TOKEN**: Tras cada revisión del Abogado del Diablo, generar `.audit/governance/scope_token.md`.
     - **Autorizado**: No hay bloqueos.
     - **Bloqueado**: Se requiere ajuste o análisis (Informa todos los motivos y dudas).
   - Mantener el estatus del doc como `Draft` hasta que el token sea `Autorizado`.

4. **Fase 4: Auditoría de Cierre**:
   - Verificar la coherencia entre Objetivos, Features y Fuera de Alcance.
   - Asegurar que no queden placeholders (`[TBD]`).
   - Obtener el visto bueno final del usuario.

## Requisitos de Entrega (Reporting)
En cada interacción de análisis de alcance, el agente deberá incluir:
- **Resumen de Hallazgos**: Nuevos requerimientos vs existentes.
- **Bloqueos y Dependencias**: Puntos que impiden el progreso.
- **Estado de Aprobación**: Secciones validadas vs pendientes.
- **Sugerir próximos pasos**: Definir el camino a la siguiente fase.

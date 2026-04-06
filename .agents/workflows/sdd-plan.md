---
description: Flujo para la creación estructurada del Plan de Implementación de una etapa del proyecto.
---

# Workflow: Creación de PLAN Estructurado

## Paso 0 — Higiene de Git (Protección de Ramas) 🛡️
1.  **Verificar Rama**: Si estás en `main` o `dev`, informa al usuario y procede a crear/saltar a la rama de funcionalidad `feat/f[F]_[E]_[nombre]`. Prohibido planificar en ramas protegidas.

## Paso 0.5 — Identificar Contexto y Prerrequisitos
1. **Inferir Etapa**: Identifica la fase/etapa (ej. f1_1.1) a planificar.
2. **Validación de SPEC (Hard Gate)**: Verifica `docs/f[F]_[E]/audit/sdd/spec_token.md`.
   - **Si el estado NO es `Autorizado`**: Detente. No se puede planificar la ejecución sin un diseño técnico validado.
3. **Guardias Maestras**: Verifica visado de gobernanza y documentos de `docs/governance/`.

## Paso 2 — Análisis de Delivery (Mentalidad Abogado del Diablo)
1. **Auditoría de Ruta Crítica**: Analiza la SPEC buscando dependencias circulares o subestimaciones de complejidad.
2. **Preservación**: Si `docs/f[F]_[E]/f[F]_[E]_plan.md` existe, léelo para mantener continuidad de la ruta.

## Paso 3 — Recopilación de Información (Gaps)
Si hay dudas sobre la precedencia de bloques o estrategias de testing, realiza máximo 5 preguntas.

## Paso 4 — Generación de PLAN y Token
1. **Generar PLAN**: Escribe en `docs/f[F]_[E]/f[F]_[E]_plan.md` usando el skill `sdd-plan`.
2. **Generar Token de Validación**: Crea `docs/f[F]_[E]/audit/sdd/plan_i_token.md`.
   - **Estado `Autorizado`**: Si la secuencia es lógica, paralela y bien definida.
   - **Estado `Bloqueado`**: Si se detectan riesgos de bloqueo o hitos de aceptación vagos.

## Paso 5 — Reporte de Cierre
```
✅ PLAN Procesado: docs/f[F]_[E]/f[F]_[E]_plan.md
📄 Token de Validación: docs/f[F]_[E]/audit/sdd/plan_i_token.md (Estado: [Autorizado/Bloqueado])
Siguiente paso: /sdd-task f[F]_[E]
```


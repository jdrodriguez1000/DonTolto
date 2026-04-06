---
description: Flujo para la creación estructurada del Product Requirements Document (PRD) de una etapa del proyecto.
---

# Workflow: Creación de PRD Estructurado

Este flujo describe los pasos interactivos y analíticos para elaborar un PRD (Product Requirements Document), inyectando trazabilidad atómica para el esquema SDD.

## Paso 0 — Higiene de Git (Protección de Ramas) 🛡️
1.  **Verificar Rama**: Si estás en `main` o `dev`, informa al usuario y procede a crear/saltar a la rama de funcionalidad `feat/f[F]_[E]_[nombre]`. Prohibido crear el PRD en ramas protegidas.

## Paso 0.5 — Identificar Contexto y Prerrequisitos
1. **Inferir Etapa**: Identifica la fase/etapa (ej. f1_1.1) a documentar.
2. **Validación de Gobernanza (Hard Gate)**: Verifica `.audit/governance/governance_token.md`.
   - **Si el estado NO es `AUTORIZADO`**: Detente e informa que el proyecto está bloqueado en gobernanza. No se puede iniciar el PRD.
3. **Verificar Guardias**: Asegura existencia de `CLAUDE.md` y documentos maestros en `docs/governance/`.

## Paso 2 — Análisis Crítico (Mentalidad Abogado del Diablo)
1. **Búsqueda de Vacíos**: Analiza el Plan Maestro y la Arquitectura buscando incoherencias.
2. **Preservación**: Si el archivo `docs/f[F]_[E]/f[F]_[E]_prd.md` existe, léelo para mantener continuidad de IDs.

## Paso 3 — Recopilación de Información (Máx. 5 preguntas)
Si existen ambigüedades sobre el "QUÉ" o el "POR QUÉ" de la etapa, consulta al usuario antes de proceder.

## Paso 4 — Generación de PRD y Token
1. **Generar PRD**: Escribe en `docs/f[F]_[E]/f[F]_[E]_prd.md` usando el skill `sdd-prd`.
2. **Generar Token de Validación**: Crea `docs/f[F]_[E]/audit/sdd/prd_token.md`.
   - **Estado `Autorizado`**: Si el PRD es sólido y completo.
   - **Estado `Bloqueado`**: Si se detectan riesgos no mitigados o vacíos lógicos.

## Paso 5 — Reporte de Cierre
```
✅ PRD Procesado: docs/f[F]_[E]/f[F]_[E]_prd.md
📄 Token de Validación: docs/f[F]_[E]/audit/sdd/prd_token.md (Estado: [Autorizado/Bloqueado])
Siguiente paso: /sdd-spec f[F]_[E]
```


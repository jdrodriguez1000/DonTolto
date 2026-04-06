---
description: Flujo para la creación estructurada de la Especificación Técnica (SPEC) de una etapa del proyecto.
---

# Workflow: Creación de SPEC Estructurada

## Paso 0 — Higiene de Git (Protección de Ramas) 🛡️
1.  **Verificar Rama**: Si estás en `main` o `dev`, informa al usuario y procede a crear/saltar a la rama de funcionalidad `feat/f[F]_[E]_[nombre]`. Prohibido crear la SPEC en ramas protegidas.

## Paso 0.5 — Identificar Contexto y Prerrequisitos
1. **Inferir Etapa**: Identifica la fase/etapa (ej. f1_1.1) a documentar.
2. **Validación de PRD (Hard Gate)**: Verifica `docs/f[F]_[E]/audit/sdd/prd_token.md`.
   - **Si el estado NO es `Autorizado`**: Detente. No se puede especificar sin un PRD validado y libre de gaps.
3. **Guardias Maestras**: Verifica visado de gobernanza y documentos de `docs/governance/`.

## Paso 2 — Análisis de Ingeniería (Mentalidad Abogado del Diablo)
1. **Auditoría de Factibilidad**: Analiza el PRD buscando inconsistencias técnicas. ¿Es posible implementar lo solicitado con el stack actual (Supabase/Python)?
2. **Preservación**: Si `docs/f[F]_[E]/f[F]_[E]_spec.md` existe, léelo para mantener continuidad técnica.

## Paso 3 — Recopilación de Detalles Técnicos
Si hay dudas sobre esquemas, tipos de datos o lógica de scraping, realiza máximo 5 preguntas técnicas.

## Paso 4 — Generación de SPEC y Token
1. **Generar SPEC**: Escribe en `docs/f[F]_[E]/f[F]_[E]_spec.md` usando el skill `sdd-spec`.
2. **Generar Token de Validación**: Crea `docs/f[F]_[E]/audit/sdd/spec_token.md`.
   - **Estado `Autorizado`**: Si el diseño técnico es completo, robusto y sin placeholders.
   - **Estado `Bloqueado`**: Si se detectan riesgos técnicos críticos o contratos incompletos.

## Paso 5 — Reporte de Cierre
```
✅ SPEC Procesada: docs/f[F]_[E]/f[F]_[E]_spec.md
📄 Token de Validación: docs/f[F]_[E]/audit/sdd/spec_token.md (Estado: [Autorizado/Bloqueado])
Siguiente paso: /sdd-plan f[F]_[E]
```


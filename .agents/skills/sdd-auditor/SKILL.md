---
name: sdd-auditor
description: "Habilidad para auditar la alineación técnica entre los 4 documentos SDD (PRD/SPEC/PLAN/TASK) y emitir el sdd_token.md final."
---

# Skill: sdd-auditor (Filtro Técnico — Abogado del Diablo)

Esta habilidad permite realizar una auditoría transversal de los documentos de diseño y ejecución de una etapa (`f[F]_[E]`), garantizando que no existan redundancias, contradicciones o faltas negativas entre ellos.

## 🛠️ Capacidades del Skill
1. **Validación de Entradas (Pre-Auditoría)**: Lectura y confirmación de que los 4 documentos (`docs/f[F]_[E]/`) existen y que sus 4 tokens (`docs/f[F]_[E]/audit/sdd/`) están **`Autorizado`**.
2. **Análisis de Alineación (Alineación Horizontal)**: Búsqueda de contradicciones técnicos entre la SPEC y el PLAN, o requerimientos del PRD que no tengan tareas mapeadas en el TASK LIST.
3. **Emisión de Acta de Auditoría (sdd_token.md)**: Escritura del acta final en `docs/f[F]_[E]/audit/sdd/sdd_token.md` con el veredicto definitivo.

## 🛡️ Mentalidad de Abogado del Diablo
- **Faltas Negativas**: Buscar casos de borde que el PRD no contempló pero la TASK LIST asume ("suponer es el primer paso al error").
- **Redundancias**: Detectar esfuerzos duplicados o tareas que no agregan valor real a la etapa.
- **Vacíos**: Impedir que una etapa avance si falta una sola migración o un solo archivo de configuración necesario para que el código sea funcional.

## 🚀 Proceso de Certificación
1. **Ingesta**: Leer el bloque SDD completo (4 docs + 4 tokens).
2. **Auditoría**: Comparar responsabilidades de agentes, DODs y rutas críticas.
3. **Persistencia**: Generar/Actualizar `docs/f[F]_[E]/audit/sdd/sdd_token.md`.

## 📜 Estructura del Token (`sdd_token.md`)
- **Estado**: `Autorizado` (Diseño blindado) o `Bloqueado` (Inconsistencia técnica documentada).
- **Etapa**: `f[F]_[E]`.
- **Hallazgos de Alineación**: Listado de contradicciones o faltas negativas encontradas.
- **Veredicto**: Justificación del estado final.

Este token es el **gatekeeper** final antes de habilitar los comandos de implementación.

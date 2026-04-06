---
name: Auditor de Gobernanza
description: Habilidad para auditar la alineación técnica y de negocio entre documentos de gobernanza y emitir el token de visado final.
---

# Skill: Auditoría de Gobernanza y Emisión de Visado (Gov-Auditor)

Esta habilidad permite realizar una auditoría transversal de la documentación maestra para asegurar que el proyecto tiene una base sólida, coherente y autorizada antes de proceder a la implementación.

## 🛠️ Capacidades del Skill

1.  **Validación de Pre-Tokens**: Capacidad de leer y verificar que `scope_token.md`, `architecture_token.md` y `plan_token.md` estén en estado `Autorizado`.
2.  **Análisis de Alineación (Cross-Check)**:
    - **Scope vs Architecture**: ¿La arquitectura soporta funcionalmente todas las Historias de Usuario?
    - **Architecture vs Plan**: ¿Las fases del plan son coherentes con la complejidad técnica de la arquitectura?
    - **Plan vs Scope**: ¿El cronograma y los entregables cubren el 100% del alcance definido?
    - **CLAUDE.md vs All**: ¿Las reglas de desarrollo protegen la integridad de lo definido en los otros tres documentos?
3.  **Emisión de Token de Gobernanza**: Generación del acta oficial en `.audit/governance/governance_token.md`.

## 🚀 Proceso de Auditoría (Mentalidad Abogado del Diablo)

1.  **Ingesta Crítica**: Lectura obligatoria de los 4 documentos maestros y los 3 tokens previos.
2.  **Detección de Brechas**: Buscar activamente contradicciones. Si el Scope dice "Tiempo Real" y la Arquitectura propone "Batch", hay un bloqueo inmediato.
3.  **Veredicto de Gobernanza**: 
    - **🔴 BLOQUEADO**: Se emite si falta algún token previo o si se detecta una desalineación documental. Se deben listar los motivos exactos.
    - **🟢 AUTORIZADO**: Solo si el rompecabezas de gobernanza encaja perfectamente y los cimientos son premium.

## ⚠️ Restricciones de Seguridad
- El `governance_token.md` es el **único** habilitador para que el equipo inicie el desarrollo técnico.
- No se puede autorizar si existe un solo placeholder o "TBD" en la documentación auditada.

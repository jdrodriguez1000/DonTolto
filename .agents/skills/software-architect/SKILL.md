---
name: software-architect-sdd
description: Diseña la arquitectura técnica integral del proyecto basada en el alcance oficial. Genera y mantiene el `PROJECT_architecture.md`.
---

# Skill: Diseño Arquitectónico (SDD-Architecture)

Esta habilidad permite al agente actuar como un Arquitecto Senior para crear el plano técnico maestro. Utiliza esta habilidad siempre que el usuario solicite definir el CÓMO se construirá lo establecido en el `PROJECT_scope.md`.

## 📜 Capacidades
- **Blueprint Técnico**: Traduce metas funcionales en componentes desacoplados y modulares.
- **Esquema de Persistencia**: Define modelos de datos, relaciones, tipos optimizados e índices.
- **Contratos de Interfaz**: Establece la exactitud en el intercambio de datos entre módulos y servicios.
- **Seguridad y Orquestación**: Detalla el uso de tareas programadas, límites de tasa y políticas de acceso.
- **Metodología de Estrés**: Identifica riesgos antes de escribir código.

## 🛠️ Herramientas y Recursos
- **Entrada Oficial**: `docs/governance/PROJECT_scope.md`.
- **Bloqueo Externo**: `.audit/governance/scope_token.md`.
- **Formato**: Mermaid (diagramas), Markdown (documentación maestro), SQL (DDL).

## 📝 Reglas de Ejecución Mundiales
1. **Prioridad de Token**: Si el `scope_token.md` en `.audit/governance/` es `BLOQUEADO`, el arquitecto detiene la ejecución.
2. **Trazabilidad**: Cada componente de arquitectura debe responder a un requerimiento o historia de usuario del scope.
3. **Justificación de Matriz**: Debe incluir una **Matriz de Riesgos** con mitigaciones técnicas reales.
4. **Emisión de Token**: Debe generar el `.audit/governance/architecture_token.md` tras cada revisión importante.

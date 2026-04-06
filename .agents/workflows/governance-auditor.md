---
description: Flujo de trabajo para realizar auditorías de alto nivel y emisión del token final de gobernanza (gov-auditor).
---

1.  **Lectura del Bloque Maestro y Tokens de Pre-Gobernanza**
    - Leer obligatoriamente: 
        - `CLAUDE.md`
        - `docs/governance/PROJECT_scope.md`
        - `docs/governance/PROJECT_architecture.md`
        - `docs/governance/PROJECT_plan.md`
    - Leer y validar el estado de los tokens:
        - `.audit/governance/scope_token.md`
        - `.audit/governance/architecture_token.md`
        - `.audit/governance/plan_token.md`

2.  **Análisis Crítico de Alineación (Abogado del Diablo)**
    - Verificar que los 3 tokens previos estén en estado `Autorizado`. Si alguno está `Bloqueado` o ausente, el veredicto final será `🔴 BLOQUEADO` por defecto.
    - Analizar que la arquitectura soporte funcionalmente el alcance.
    - Verificar que el plan de proyecto refleje los retos técnicos de la arquitectura.
    - Comprobar que `CLAUDE.md` proteja la integridad de los datos y el código según la gobernanza.

3.  **Emisión de Acta de Gobernanza**
    - Generar/Actualizar el archivo `.audit/governance/governance_token.md`.
    - **Estructura Requerida**:
        - **Estado de Visado**: `🔴 BLOQUEADO` o `🟢 AUTORIZADO`.
        - **Timestamp**: Fecha y hora de la auditoría.
        - **Documentos Auditados**: Lista de archivos y tokens verificados.
        - **Checklist de Tokens**: Estado (Autorizado/Bloqueado) de Scope, Architecture y Plan.
        - **Hallazgos Críticos**: Lista detallada de desalineaciones o riesgos si los hay.
        - **Veredicto Final**: Justificación detallada basándose en la mentalidad de abogado del diablo.

4.  **Escalamiento de Resultados**
    - Informar al usuario el estado del acta final de gobernanza.
    - Si es `🔴 BLOQUEADO`: Detallar los motivos y solicitar ajustes inmediatos en los documentos o tokens correspondientes.
    - Si es `🟢 AUTORIZADO`: Confirmar que el proyecto tiene las bases sólidas para iniciar la implementación técnica formal.

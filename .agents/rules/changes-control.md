# Regla de Proyecto: /change-control (changes-control.md)

Esta regla define la política oficial de Control de Cambios (CC) para el proyecto **DonTolto** y sirve como guía normativa para los agentes.

---

## 1. Política de Control de Cambios

### 1.1. Propósito
Garantizar la integridad, trazabilidad y coherencia del proyecto ante modificaciones que alteren el alcance, la arquitectura o el plan maestro autorizado.

### 1.2. Disparadores de CC
Es OBLIGATORIO iniciar un Control de Cambios en los siguientes casos:
1.  **Modificación de Gobernanza Global**: Cualquier cambio en `docs/governance/` (`PROJECT_scope.md`, `PROJECT_architecture.md`, `PROJECT_plan.md`).
2.  **Modificación de Etapas Cerradas**: Cambios a documentos SDD (`PRD`, `SPEC`, `PLAN`) de fases o etapas que ya cuentan con un ejecutivo de cierre (`docs/executives/`).
3.  **Alteración del Diseño Original**: Cambios estructurales o técnicos que no estaban contemplados en los documentos SDD de la etapa activa.

### 1.3. Invariantes
- Ningún cambio estructural se ejecuta sin un documento `CC_XXXXX.md` en estado `✅ Aprobado`.
- La carpeta oficial de CCs es `docs/changes/`.
- La jerarquía de prevalencia es: `Scope > Architecture > Plan > SDD Local`.

---

## 2. Flujo de Trabajo (Workflow)

### Etapas del Ciclo de Vida:
1.  **CREATE** [Pendiente]: Propuesta del cambio, análisis de impacto y justificación.
2.  **AUDIT**: Auditoría por el agente `change-controller` (Abogado del Diablo).
3.  **DECISION**: 
    - `✅ Aprobado`: El usuario autoriza la ejecución.
    - `❌ No Aprobado`: Se archiva la propuesta sin cambios.
4.  **EXECUTE**: Aplicación de los cambios en los archivos afectados y actualización de la trazabilidad.
5.  **CLOSE**: Firma final y registro en este índice.

---

## 3. Índice Maestro de Controles de Cambio

| ID | Fecha | Título / Descripción Breve | Estado | Documentos Afectados |
| --- | --- | --- | --- | --- |
| - | - | *No hay cambios registrados* | - | - |

---

## 4. Trazabilidad
Cada archivo modificado por un CC debe incluir al final:
`> **Control de Cambio:** Este archivo fue modificado por CC_XXXXX (fecha).`

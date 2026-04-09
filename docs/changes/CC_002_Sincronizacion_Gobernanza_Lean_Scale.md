# Control de Cambio: CC_002 — Sincronización de Gobernanza y Refinamiento Lean Scale

---
**Estado**: ✅ **Aprobado** (Instrucción Directa del Usuario)
**Fecha**: 2026-04-09
**Solicitante**: Usuario
**Analista**: Antigravity
---

## 1. Descripción del Cambio
Este cambio sincroniza las discrepancias detectadas durante la auditoría del PRD `f1_1.1`. Se ajusta el volumen total de proyecciones a 428 registros, se unifica el Lock TTL a 60 minutos y se definen reglas críticas para el manejo de empates y fallos en la validación manual.

## 2. Análisis de Impacto
- **PROJECT_scope.md**: Actualización de la matriz de estrategias (de 424 a 428 registros). Definición del protocolo de continuidad ante falta de validación manual.
- **PROJECT_architecture.md**: Sincronización de volumen y TTL. Definición de la lógica de ordenamiento (Tie-break).
- **f1_1.1_prd.md**: Sincronización técnica y cierre de ambigüedades.
- **Base de Datos**: Los índices y vistas deben considerar el nuevo volumen y la lógica de desempate por `created_at`.

## 3. Justificación
- **Coherencia Forense**: Mantener un volumen de datos exacto en todos los documentos evita fallos de asignación en el motor.
- **Resiliencia Operativa**: El "Fallback de Continuidad" asegura que el sistema no se detenga por tareas manuales humanas (Admin) mientras mantiene la visibilidad del riesgo.
- **Seguridad Atómica**: El Lock TTL de 60m provee un margen de maniobra necesario para latencias de red en GHA.

## 4. Archivos Modificados
1. `docs/governance/PROJECT_scope.md`
2. `docs/governance/PROJECT_architecture.md`
3. `docs/f1_1.1/f1_1.1_prd.md`
4. `docs/f1_1.1/audit/sdd/prd_token.md`
5. `.agents/rules/changes-control.md` (Índice)

---
**Firma de Autorización**:
*Aprobado por el Usuario vía prompt dinámico.*

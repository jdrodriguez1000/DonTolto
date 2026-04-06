---
description: Flujo estructurado para gestionar el ciclo de vida de un cambio mediante los modos CREATE, APPROVE, REJECT y LIST.
---

# Workflow: /change-control (Gobernanza)

## Paso 0 — Detección del Modo (Konami Audit)
El agente debe identificar la intención del usuario o la necesidad autónoma basada en `CLAUDE.md` y la regla en `.agents/rules/changes-control.md`:
- ¿Es una propuesta nueva? → **Modo CREATE**.
- ¿Es una aprobación? → **Modo APPROVE**.
- ¿Es un rechazo? → **Modo REJECT**.
- ¿Es una consulta? → **Modo LIST**.

## Paso 1 — Ejecución del Skill
1. Invocar el Skill `change-control` y seguir los pasos del modo identificado.
2. Si es **CREATE**, informar el impacto, esperar confirmación del usuario para generar el documento en `docs/changes/` y registrarlo en el índice de `.agents/rules/changes-control.md`.
3. Si es **APPROVE**, ejecutar cambios, añadir trazabilidad y actualizar tokens de gobernanza si aplica, además de actualizar el estado en el índice de la regla.

## Paso 2 — Verificación de Trazabilidad
Asegurar que el archivo en `docs/changes/` y el índice maestro en `.agents/rules/changes-control.md` reflejen el estado final (ID, Fecha, Decisión) y que se cumpla la jerarquía de `CLAUDE.md`.

## Paso 3 — Reporte Final
Presentar el estado final del Control de Cambio y definir la próxima acción en la etapa activa.

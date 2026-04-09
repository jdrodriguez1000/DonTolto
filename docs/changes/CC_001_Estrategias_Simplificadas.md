# Control de Cambio: CC_001 — Reducción de Escala y Simplificación de Estrategias

---
**ID**: CC_001
**Fecha**: 2026-04-09
**Estado**: ✅ **APROBADO**
**Autor del Cambio**: User / Antigravity
**Prioridad**: Alta
---

## 1. Descripción del Cambio
Se propone una reestructuración del modelo matemático y de datos del proyecto **DonTolto**, pasando de un enfoque de simulación masiva (Big Data) a uno de selección estratégica boutique (Lean Analytics).

### Ajustes Solicitados:
1.  **Reducción de Estrategias Multi-Juego**: Las estrategias (Caliente, Fría, Balanceada, Mixta, Afinidad, Aleatoria, Élite) pasan de generar 300 juegos a solo **30 juegos** por tipo (Baloto/Revancha).
2.  **Estrategias Mono-Juego**: Se mantienen con **1 juego** cada una (Real, Única).
3.  **Eliminación del Estrés de 1M**: Se retira el requisito de someter la Estrategia Real a 1,000,000 de escenarios ficticios.
4.  **Carga Operativa**: El volumen total de proyecciones por ciclo se reduce de ~3,604 a **424** (aproximadamente, considerando 7x30 + 2 = 212 por Baloto y 212 por Revancha).

## 2. Justificación
- **Optimización de Recursos**: Reduce el tiempo de ejecución en GitHub Actions (de ~12 min a < 2 min).
- **Simplificación Lógica**: Elimina la complejidad técnica de la vectorización pesada en NumPy, facilitando el mantenimiento.
- **Enfoque en Calidad**: Se prioriza la selección algorítmica sobre la resiliencia estadística masiva.

## 3. Análisis de Impacto (Devil's Advocate)

| Dimensión | Impacto Detectado | Riesgo / Mitigación |
| :--- | :--- | :--- |
| **Gobernanza** | Modifica el ADN del proyecto definido en Fase 0. | Requiere actualización en cascada de Scope, Architecture y Plan. |
| **Arquitectura** | NumPy deja de ser un requerimiento crítico para el Core Brain. | Se simplifica el motor, pero se pierde el diferenciador de "Estrés Estadístico". |
| **Datos** | La base de datos será mucho más ligera. | Facilita el Backup; el trigger de scoring será instantáneo. |
| **Eficacia** | El Delta de éxito (0.05) podría variar al tener menos muestras. | Es necesario re-validar el criterio de éxito en el PRD de la Fase 3. |

## 4. Documentos Afectados
- `docs/governance/PROJECT_scope.md` (Matriz de estrategias y US-02).
- `docs/governance/PROJECT_architecture.md` (Eliminación de NumPy 1M).
- `docs/governance/PROJECT_plan.md` (Reestructuración de Fase 3).
- `docs/f1_1.1/f1_1.1_prd.md` (Ajuste de métricas de carga y scoring).

## 5. Resumen de Ejecución
El cambio ha sido aplicado exitosamente en los siguientes archivos:
- `PROJECT_scope.md`: Matriz actualizada (Total 424) y eliminación de 1M escenarios.
- `PROJECT_architecture.md`: Remoción de NumPy 1M y ajuste de volumen de datos.
- `PROJECT_plan.md`: Reestructuración total de la Fase 3 (Generación Boutique).
- `f1_1.1_prd.md`: Ajuste de métricas de performance (< 100ms) y volumen de ingesta.

**Trazabilidad**: Todos los archivos incluyen el sello de modificación por CC_001.

---
**Firma de Cierre:**
*Antigravity (Audit Service)*
*Token ID: CC-001-CLOSED-7712404a*

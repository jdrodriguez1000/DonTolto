---
token_id: CERT-B5-f1-1.1-RED-018.4
tipo: Certificacion de Fase RED — Test pgTap
tarea: TSK-F1_1.1-18.4-RED
fecha: 2026-04-10
auditor: backend-tester
estado: RED CONFIRMADO
---

# Certificacion Fase RED — Bloque 5 (Motores RPC)
# TSK-F1_1.1-18.4-RED: Test pgTap Atomicidad de transacciones ante fallos parciales (Savepoint Trigger)

## 1. Identificacion del Test

- **Archivo creado**: `supabase/tests/021_transaction_atomicity.sql`
- **Numero de assertions**: 5
- **Trazabilidad SPEC**: Seccion 4.3 §4 (Recalculo Atomico y Trazabilidad Forense)
- **ADR referenciado**: ADR-04 (Recalculo Atomico Transparente)
- **Funcion bajo prueba**: `fn_verify_and_promote_draw(DATE, VARCHAR)` — secuencia de recalculo atomico
- **DoD**: Test falla si una transaccion deja estados inconsistentes tras un error forzado

## 2. Resultado de Ejecucion (Estado RED Confirmado)

Comando ejecutado: `npx supabase test db`

Resultado para `021_transaction_atomicity.sql`:
```
(Wstat: 0 Tests: 5 Failed: 5)
  Failed tests: 1-5
```

Salida TAP detallada:
```
# Failed test 1: "ATOMICITY RED 18.4: debe existir backup forense en system_logs (level=audit) ANTES del recalculo (SPEC §4.3 §4)"
# Failed test 2: "ATOMICITY RED 18.4: performance del draw transient anterior debe eliminarse en recalculo atomico (ADR-04)"
#         have: 1
#         want: 0
# Failed test 3: "ATOMICITY RED 18.4: projections deben resetearse a pending tras recalculo atomico (SPEC §4.3 §4)"
#         have: calculated
#         want: pending
# Failed test 4: "ATOMICITY RED 18.4: debe existir un draw con status=final para la fecha/tipo tras recalculo exitoso (SPEC §4.3 §4)"
# Failed test 5: "ATOMICITY RED 18.4: el sistema debe estar en estado consistente (o todo exito o rollback total — sin estados parciales)"
```

Plan: 5 assertions planificadas, 5 ejecutadas, 5 fallidas. Fallos por ausencia completa de logica de recalculo atomico.

## 3. Analisis de Fallos por Assertion

| # | Descripcion | Razon del Fallo en RED | Correcta |
|---|---|---|---|
| 1 | Backup forense en system_logs (level=audit) | El stub no inserta en system_logs. COUNT=0 | Si |
| 2 | Performance del draw anterior eliminada | El stub no ejecuta DELETE en performance. COUNT=1 vs esperado=0 | Si |
| 3 | Projections reseteadas a 'pending' | El stub no actualiza projections. Status='calculated' permanece | Si |
| 4 | Draw promovido con status='final' | El stub no promueve draws. No existe draw 'final' para 2099-04-01 | Si |
| 5 | Estado consistente (A o B) | El estado es parcial: draw='transient' + performance=1 + logs=0. El OR de estados consistentes es FALSE | Si |

## 4. Verificacion de Correctitud de la Fase RED

Los 5 fallos verifican los invariantes de atomicidad definidos en ADR-04:
- **DoD**: "Test falla si una transaccion deja estados inconsistentes tras un error forzado."
- El ASSERTION 5 es el mas critico: verifica que el sistema este en uno de dos estados consistentes (exito total o rollback total). En RED, el estado es parcial (draw transient + performance intacto + sin logs), que no satisface ninguno de los dos estados validos.
- Los assertions 1-4 son los contratos individuales de cada paso del recalculo atomico.
- ROLLBACK garantiza que el escenario de prueba no contamina el entorno.

## 5. Contrato Tecnico para Fase GREEN (backend-coder)

La implementacion GREEN debe ejecutar los siguientes pasos en una transaccion atomica (ADR-04):

1. **Paso 1 — Backup forense (PRIMERO)**: INSERT INTO system_logs (level='audit', metadata=JSONB_AGG(performance del draw anterior))
2. **Paso 2 — DELETE performance**: DELETE FROM performance WHERE draw_id = (draw anterior por fecha/tipo)
3. **Paso 3 — RESET projections**: UPDATE projections SET status='pending' WHERE target_draw_date=... Y estrategia activa
4. **Paso 4 — Promover draw**: UPDATE draws SET status='final', is_manual=TRUE WHERE id=(draw anterior) O INSERT nuevo draw
5. **Garantia de atomicidad**: si cualquier paso falla, ROLLBACK completo (PostgreSQL garantiza atomicidad de transaccion implicita en PL/pgSQL con EXCEPTION handler)

La secuencia de pasos 1→2→3→4 es mandatoria y debe ejecutarse dentro de la misma transaccion.

## 6. Requisito Adicional para db-manager (Fase GREEN)

`REVOKE EXECUTE ON FUNCTION fn_verify_and_promote_draw(DATE, VARCHAR) FROM PUBLIC` en la misma migracion.

## 7. Autorizacion de Fase GREEN

El test RED ha sido disenado, ejecutado y confirmado.

**El backend-coder queda autorizado para implementar el recalculo atomico completo en fn_verify_and_promote_draw.**

---

**Firma de Certificacion RED:**
*backend-tester*
*Token: CERT-B5-f1-1.1-RED-018.4*
*Fecha: 2026-04-10*

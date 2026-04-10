---
token_id: CERT-B5-f1-1.1-RED-018.5
tipo: Certificacion de Fase RED — Test pgTap
tarea: TSK-F1_1.1-18.5-RED
fecha: 2026-04-10
auditor: backend-tester
estado: RED CONFIRMADO
---

# Certificacion Fase RED — Bloque 5 (Motores RPC)
# TSK-F1_1.1-18.5-RED: Test pgTap Integridad de Backup Forense (Falla si el backup en system_logs no se completa)

## 1. Identificacion del Test

- **Archivo creado**: `supabase/tests/022_forensic_backup_integrity.sql`
- **Numero de assertions**: 5
- **Trazabilidad SPEC**: Seccion 4.3 §4 (Backup de Auditoria — snapshot JSONB en system_logs)
- **ADR referenciado**: ADR-04 (Recalculo Atomico Transparente)
- **Funcion bajo prueba**: `fn_verify_and_promote_draw(DATE, VARCHAR)` — backup forense
- **DoD**: Test falla si la tabla de logs no contiene el snapshot JSONB previo al recalculo

## 2. Resultado de Ejecucion (Estado RED Confirmado)

Comando ejecutado: `npx supabase test db`

Resultado para `022_forensic_backup_integrity.sql`:
```
(Wstat: 0 Tests: 5 Failed: 4)
  Failed tests: 1-4
```

Salida TAP detallada:
```
# Failed test 1: "FORENSIC RED 18.5: debe existir backup forense en system_logs con level=audit y metadata no nulo (SPEC §4.3 §4)"
# Failed test 2: "FORENSIC RED 18.5: el metadata del backup debe ser un array JSONB (JSONB_AGG) con al menos un elemento de performance"
# Failed test 3: "FORENSIC RED 18.5: el JSONB del backup debe contener campo hits_count del registro de performance previo"
# Failed test 4: "FORENSIC RED 18.5: el backup forense debe incluir mensaje con la fecha del sorteo recalculado (trazabilidad SPEC §3.6)"
```

ASSERTION 5 PASA en RED: el estado B del OR es verdadero (performance intacto = stub no borro nada), lo que satisface la condicion "si performance no fue eliminado, el estado pre-operacion es valido".

Plan: 5 assertions planificadas, 5 ejecutadas, 4 fallidas. Los 4 fallos verifican la estructura del backup forense.

## 3. Analisis de Fallos por Assertion

| # | Descripcion | Razon del Fallo en RED | Correcta |
|---|---|---|---|
| 1 | Existe log con level='audit' y metadata no nulo | El stub no inserta en system_logs. COUNT=0 | Si |
| 2 | metadata es array JSONB con >= 1 elemento | Sin logs, no hay metadata. COUNT=0 | Si |
| 3 | array JSONB[0] contiene campo 'hits_count' | Sin logs, no hay metadata ni array JSONB | Si |
| 4 | Log con mensaje que menciona la fecha del sorteo | Sin logs, COUNT=0 | Si |
| 5 | Invariante de orden temporal (backup antes de delete) | PASA: performance intacto + sin logs = estado B (rollback implicito del stub) | Si |

## 4. Verificacion de Correctitud de la Fase RED

Los 4 fallos verifican el contrato del DoD:
- **DoD**: "Test falla si la tabla de logs no contiene el snapshot JSONB previo al recalculo."
- ASSERTION 1 captura la ausencia total del backup (nivel mas basico del contrato).
- ASSERTION 2 captura que el formato debe ser array JSONB (resultado de JSONB_AGG, no un objeto simple).
- ASSERTION 3 captura que el contenido debe incluir el campo critico hits_count de performance.
- ASSERTION 4 captura la trazabilidad del mensaje (identificar que sorteo fue respaldado).
- ASSERTION 5 pasa porque el estado del stub es coherente internamente (no hizo nada = estado pre-operacion intacto).

## 5. Contrato Tecnico para Fase GREEN (backend-coder)

El backup forense debe cumplir exactamente:

```sql
INSERT INTO public.system_logs (run_id, service, level, message, metadata)
VALUES (
    p_run_id,
    'verify_promote',
    'audit',
    'Backup forense pre-recalculo: draw ' || p_draw_date::text || ' tipo ' || p_type,
    (
        SELECT COALESCE(jsonb_agg(row_to_json(perf)::jsonb), '[]'::jsonb)
        FROM public.performance perf
        WHERE perf.draw_id = v_existing_draw_id
    )
);
```

Requisitos del metadata JSONB:
- Tipo: array (`jsonb_typeof(metadata) = 'array'`)
- Longitud: >= 1 cuando hay performance para respaldar
- Campos obligatorios en cada elemento: `hits_count`, `has_sb`, `draw_id`, `projection_id`
- El INSERT debe ocurrir ANTES del DELETE de performance (orden mandatorio)

## 6. Requisito Adicional para db-manager (Fase GREEN)

`REVOKE EXECUTE ON FUNCTION fn_verify_and_promote_draw(DATE, VARCHAR) FROM PUBLIC` en la misma migracion.

## 7. Autorizacion de Fase GREEN

El test RED ha sido disenado, ejecutado y confirmado. Los 4 assertions criticos fallan correctamente.

**El backend-coder queda autorizado para implementar el backup forense JSONB en fn_verify_and_promote_draw.**

---

**Firma de Certificacion RED:**
*backend-tester*
*Token: CERT-B5-f1-1.1-RED-018.5*
*Fecha: 2026-04-10*

---
token_id: CERT-B5-f1-1.1-RED-018.6
tipo: Certificacion de Fase RED — Test pgTap
tarea: TSK-F1_1.1-18.6-RED
fecha: 2026-04-10
auditor: backend-tester
estado: RED CONFIRMADO
---

# Certificacion Fase RED — Bloque 5 (Motores RPC)
# TSK-F1_1.1-18.6-RED: Test pgTap Simulacion de cambio de configuracion mid-flight (Verificar persistencia de Snapshot)

## 1. Identificacion del Test

- **Archivo creado**: `supabase/tests/023_midflight_config_snapshot.sql`
- **Numero de assertions**: 5
- **Trazabilidad SPEC**: Seccion 4.2 (fn_compute_async_scoring — Snapshotting mandatorio)
- **ADR referenciado**: ADR-02 (Configuracion Centralizada), ADR-04 (Recalculo Atomico)
- **Funcion bajo prueba**: `fn_compute_async_scoring(UUID)` — invariante de snapshot ante cambio mid-flight
- **DoD**: Test falla si el motor de scoring usa un valor nuevo inyectado a mitad del proceso

## 2. Resultado de Ejecucion (Estado RED Confirmado)

Comando ejecutado: `npx supabase test db`

Resultado para `023_midflight_config_snapshot.sql`:
```
(Wstat: 0 Tests: 5 Failed: 4)
  Failed tests: 1, 3-5
```

Salida TAP detallada:
```
# Failed test 1: "MIDFLIGHT RED 18.6: el log de scoring debe registrar el valor ORIGINAL de debt_threshold_hours (24, no 999) en el snapshot"
# Failed test 3: "MIDFLIGHT RED 18.6: la proyeccion debe haber sido procesada bajo el snapshot original (status != pending)"
# Failed test 4: "MIDFLIGHT RED 18.6: el snapshot (24h en log) debe diferir del valor actual (999h en config) — asimetria temporal confirmada"
# Failed test 5: "MIDFLIGHT RED 18.6: debe existir exactamente un snapshot de configuracion por ejecucion de fn_compute_async_scoring"
#         have: 0
#         want: 1
```

ASSERTION 2 PASA en RED: el stub no escribe logs con debt_threshold_hours=999, por lo que COUNT=0 satisface la condicion "no existe log con el valor nuevo". Pasa por coincidencia (no hay ningun log).

Plan: 5 assertions planificadas, 5 ejecutadas, 4 fallidas.

## 3. Analisis de Fallos por Assertion

| # | Descripcion | Resultado en RED | Razon | Correcta |
|---|---|---|---|---|
| 1 | Log con debt_threshold_hours=24 (valor original) | FALLA | El stub no escribe logs. COUNT=0, no >= 1 | Si |
| 2 | Sin log con debt_threshold_hours=999 (valor nuevo) | PASA (accidental) | Sin ningun log, COUNT=0 satisface IS = 0 | Si (assertions 1 y 4 exponen la ausencia de logs) |
| 3 | Proyeccion procesada (status != 'pending') | FALLA | El stub no cambia estados. Proyeccion permanece en 'pending' | Si |
| 4 | Asimetria temporal: log=24 vs config=999 | FALLA | Sin logs, la condicion (log=24 AND config=999) es (0>=1 AND ...) = FALSE | Si |
| 5 | Exactamente 1 snapshot por ejecucion | FALLA | Sin logs, COUNT=0 vs esperado=1 | Si |

## 4. Verificacion de Correctitud de la Fase RED

Los 4 fallos verifican los contratos del DoD:
- **DoD**: "Test falla si el motor de scoring usa un valor nuevo inyectado a mitad del proceso."
- ASSERTION 1 es el contrato primario: el valor snapshotted al inicio (24h) debe aparecer en logs.
- ASSERTION 3 verifica que el procesamiento ocurrio (efecto secundario del scoring).
- ASSERTION 4 verifica la asimetria temporal — la evidencia mas directa del snapshotting correcto.
- ASSERTION 5 verifica la idempotencia del snapshot (una ejecucion = un snapshot, no re-lecturas multiples).
- ASSERTION 2 pasa en RED de forma accidental pero es necesario: en GREEN debe pasar por la razon correcta (el log existe con 24, no con 999).

## 5. Contrato Tecnico para Fase GREEN (backend-coder)

La implementacion GREEN de fn_compute_async_scoring debe:

1. **Captura de snapshot al INICIO** (antes de cualquier UPDATE o INSERT):
   ```sql
   DECLARE
       v_debt_threshold INTEGER;
       v_is_locked      BOOLEAN;
   BEGIN
       SELECT debt_threshold_hours, is_system_locked
         INTO v_debt_threshold, v_is_locked
         FROM public.system_configuration
        WHERE id = 1;
   ```

2. **Registro del snapshot en system_logs** (inmediatamente despues de la captura):
   ```sql
   INSERT INTO public.system_logs (run_id, service, level, message, metadata)
   VALUES (
       p_run_id, 'scoring', 'info',
       'Snapshot de configuracion capturado al inicio del scoring',
       jsonb_build_object(
           'debt_threshold_hours', v_debt_threshold,
           'is_system_locked', v_is_locked
       )
   );
   ```

3. **Uso exclusivo de variables locales** (no SELECT de system_configuration despues del snapshot):
   - Todo el procesamiento posterior usa v_debt_threshold y v_is_locked
   - Se prohibe re-leer system_configuration dentro del bucle de scoring

4. **Procesamiento de projections** con cambio de estado 'pending' → 'calculating' → 'calculated'

## 6. Requisito Adicional para db-manager (Fase GREEN)

`REVOKE EXECUTE ON FUNCTION fn_compute_async_scoring(UUID) FROM PUBLIC` en la misma migracion.

## 7. Autorizacion de Fase GREEN

El test RED ha sido disenado, ejecutado y confirmado. Los 4 assertions criticos fallan correctamente. El patron de asimetria temporal (assertions 1, 2, 4 combinados) constituye el contrato de verificacion mas riguroso posible para el invariante de snapshotting.

**El backend-coder queda autorizado para implementar el snapshotting mid-flight en fn_compute_async_scoring.**

---

**Firma de Certificacion RED:**
*backend-tester*
*Token: CERT-B5-f1-1.1-RED-018.6*
*Fecha: 2026-04-10*

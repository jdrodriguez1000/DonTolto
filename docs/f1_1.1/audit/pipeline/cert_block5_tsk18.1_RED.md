---
token_id: CERT-B5-f1-1.1-RED-018.1
tipo: Certificacion de Fase RED — Test pgTap
tarea: TSK-F1_1.1-18.1-RED
fecha: 2026-04-10
auditor: backend-tester
estado: RED CONFIRMADO
---

# Certificacion Fase RED — Bloque 5 (Motores RPC)
# TSK-F1_1.1-18.1-RED: Test pgTap Snapshotting de parametros (inmovilidad ante cambios en system_config)

## 1. Identificacion del Test

- **Archivo creado**: `supabase/tests/018_scoring_snapshot_invariant.sql`
- **Numero de assertions**: 6
- **Trazabilidad SPEC**: Seccion 4.2 (fn_compute_async_scoring — Snapshotting mandatorio)
- **ADR referenciado**: ADR-02 (Configuracion Centralizada), ADR-04 (Recalculo Atomico)
- **Funcion bajo prueba**: `fn_compute_async_scoring(UUID)`
- **DoD**: Test falla si una variable de sesion cambia tras haber sido capturada al inicio

## 2. Resultado de Ejecucion (Estado RED Confirmado)

Comando ejecutado: `npx supabase test db`

Resultado para `018_scoring_snapshot_invariant.sql`:
```
(Wstat: 0 Tests: 6 Failed: 5)
  Failed tests: 2-6
```

Salida TAP detallada:
```
# Failed test 2: "SCORING RED 18.1: fn_compute_async_scoring debe marcar projections como calculating (anti-carrera SPEC §4.2)"
#         have: 0
#         want: 2
# Failed test 3: "SCORING RED 18.1: fn_compute_async_scoring debe escribir trazabilidad en system_logs (SPEC §3.6)"
# Failed test 4: "SCORING RED 18.1: el log de scoring debe incluir snapshot de debt_threshold_hours en metadata JSONB (invariante de snapshotting)"
# Failed test 5: "SCORING RED 18.1: el log de scoring debe incluir snapshot de is_system_locked en metadata JSONB (kill-switch audit)"
# Failed test 6: "SCORING RED 18.1: projections en pending deben ser procesadas (status != pending) tras invocar fn_compute_async_scoring"
#         have: 2
#         want: 0
```

Plan: 6 assertions planificadas, 6 ejecutadas, 5 fallidas. ASSERTION 1 pasa (has_function confirma existencia del stub).

## 3. Analisis de Fallos por Assertion

| # | Descripcion | Razon del Fallo en RED | Correcta |
|---|---|---|---|
| 1 | fn_compute_async_scoring existe | El stub fue creado en block_4.sql — PASA correctamente | Si |
| 2 | Projections marcadas como 'calculating' | El stub no ejecuta UPDATE projections SET status='calculating'. COUNT=0 vs esperado=2 | Si |
| 3 | Existe log en system_logs (service='scoring') | El stub solo lanza RAISE NOTICE, no inserta en system_logs. COUNT=0 | Si |
| 4 | Metadata contiene debt_threshold_hours | Sin log en system_logs, no puede haber metadata. COUNT=0 | Si |
| 5 | Metadata contiene is_system_locked | Sin log en system_logs, no puede haber metadata. COUNT=0 | Si |
| 6 | Projections ya no estan en 'pending' | El stub no cambia estados. Las 2 proyecciones permanecen en 'pending'. COUNT=2 vs esperado=0 | Si |

## 4. Verificacion de Correctitud de la Fase RED

Los 5 fallos ocurren por las razones correctas segun el DoD de la tarea:
- **DoD**: "Test falla si una variable de sesion cambia tras haber sido capturada al inicio."
- Los fallos demuestran que el stub no implementa: protocolo anti-carrera (claiming 'calculating'), escritura de logs con snapshot, ni procesamiento real de projections.
- Ningun fallo ocurre por error de sintaxis. El ROLLBACK final garantiza aislamiento.
- La ASSERTION 1 pasa en RED por diseno: confirma que el objeto existe como stub.

## 5. Contrato Tecnico para Fase GREEN (backend-coder)

Para que todos los assertions pasen en GREEN, fn_compute_async_scoring debe implementar:

1. **Captura de snapshot al inicio**: leer debt_threshold_hours e is_system_locked de system_configuration en variables locales PL/pgSQL al inicio de la funcion. No releer mid-flight.
2. **Protocolo anti-carrera**: `UPDATE projections SET status='calculating' WHERE status='pending' ... LIMIT 428 FOR UPDATE SKIP LOCKED`
3. **Trazabilidad en system_logs**: INSERT con service='scoring', metadata JSONB que incluya debt_threshold_hours e is_system_locked capturados al inicio.
4. **Procesamiento de projections**: calcular hits_count y has_sb, insertar en performance, actualizar projections.status='calculated'.

## 6. Requisito Adicional para db-manager (Fase GREEN)

`REVOKE EXECUTE ON FUNCTION fn_compute_async_scoring(UUID) FROM PUBLIC` debe ejecutarse en la misma migracion que implemente la logica, para garantizar que solo roles privilegiados invoquen el motor de scoring (ADR-06).

## 7. Autorizacion de Fase GREEN

El test RED ha sido disenado, ejecutado y confirmado. El contrato tecnico esta establecido.

**El backend-coder queda autorizado para iniciar la implementacion de fn_compute_async_scoring (Bloque 5).**

La transicion a GREEN se certifica cuando `npx supabase test db` reporte:
```
018_scoring_snapshot_invariant.sql .. ok
(Tests: 6 Failed: 0)
```

---

**Firma de Certificacion RED:**
*backend-tester*
*Token: CERT-B5-f1-1.1-RED-018.1*
*Fecha: 2026-04-10*

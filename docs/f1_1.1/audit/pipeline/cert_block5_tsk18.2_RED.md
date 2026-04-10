---
token_id: CERT-B5-f1-1.1-RED-018.2
tipo: Certificacion de Fase RED — Test pgTap
tarea: TSK-F1_1.1-18.2-RED
fecha: 2026-04-10
auditor: backend-tester
estado: RED CONFIRMADO
---

# Certificacion Fase RED — Bloque 5 (Motores RPC)
# TSK-F1_1.1-18.2-RED: Test pgTap Resolucion de conflictos de promocion (Admin > Scraper)

## 1. Identificacion del Test

- **Archivo creado**: `supabase/tests/019_promote_admin_priority.sql`
- **Numero de assertions**: 5
- **Trazabilidad SPEC**: Seccion 4.3 (fn_verify_and_promote_draw — Double-Entry, prioridad Admin)
- **ADR referenciado**: ADR-04 (Recalculo Atomico Transparente)
- **Funcion bajo prueba**: `fn_verify_and_promote_draw(DATE, VARCHAR)`
- **DoD**: Test falla si un resultado de Scraper sobreescribe un registro manual de Admin

## 2. Resultado de Ejecucion (Estado RED Confirmado)

Comando ejecutado: `npx supabase test db`

Resultado para `019_promote_admin_priority.sql`:
```
(Wstat: 0 Tests: 5 Failed: 5)
  Failed tests: 1-5
```

Salida TAP detallada:
```
# Failed test 1: "PROMOTE RED 18.2: fn_verify_and_promote_draw debe retornar TRUE cuando Admin y Scraper coinciden (SPEC §4.3)"
#         have: false
#         want: true
# Failed test 2: "PROMOTE RED 18.2: fn_verify_and_promote_draw debe insertar el sorteo promovido en la tabla draws (SPEC §4.3)"
# Failed test 3: "PROMOTE RED 18.2: los registros de la cola deben marcarse is_verified=TRUE tras promocion exitosa (SPEC §4.3)"
#         have: 0
#         want: 2
# Failed test 4: "PROMOTE RED 18.2: el registro promovido en draws debe tener is_manual=TRUE (trazabilidad Double-Entry SPEC §4.3)"
# Failed test 5: "PROMOTE RED 18.2: el sorteo promovido debe tener status=final en draws (no transient — SPEC §4.3)"
```

Plan: 5 assertions planificadas, 5 ejecutadas, 5 fallidas. Fallos correctos por ausencia de logica.

## 3. Analisis de Fallos por Assertion

| # | Descripcion | Razon del Fallo en RED | Correcta |
|---|---|---|---|
| 1 | Retorna TRUE en match exitoso | El stub siempre retorna FALSE (RETURN FALSE). El match Admin=Scraper no es detectado | Si |
| 2 | Inserta sorteo en draws | El stub no realiza ninguna INSERT en draws. COUNT=0 | Si |
| 3 | Marca is_verified=TRUE en cola | El stub no actualiza manual_verification_queue. COUNT=0 vs esperado=2 | Si |
| 4 | Registro en draws tiene is_manual=TRUE | Sin INSERT en draws, COALESCE(NULL, FALSE) = FALSE | Si |
| 5 | Registro en draws tiene status='final' | Sin INSERT en draws, COALESCE(NULL, 'none') = 'none' != 'final' | Si |

## 4. Verificacion de Correctitud de la Fase RED

Los 5 fallos ocurren por las razones correctas segun el DoD:
- **DoD**: "Test falla si un resultado de Scraper sobreescribe un registro manual de Admin."
- Los fallos demuestran que el stub no implementa la comparacion Admin vs Scraper, no detecta match, no promueve a draws y no marca registros de cola.
- La logica de prioridad Admin (ORDER BY created_at DESC LIMIT 1) no existe en el stub.
- ROLLBACK garantiza que ningun dato de prueba contamina el entorno.

## 5. Contrato Tecnico para Fase GREEN (backend-coder)

Para que todos los assertions pasen en GREEN, fn_verify_and_promote_draw debe implementar:

1. **Lectura de entradas con prioridad Admin**: `SELECT ... FROM manual_verification_queue WHERE draw_date=p_draw_date AND type=p_type AND entry_source='admin' ORDER BY created_at DESC LIMIT 1`
2. **Comparacion de coincidencia**: admin.numbers = scraper.numbers AND admin.superbalota = scraper.superbalota
3. **Promocion a draws**: INSERT con status='final', is_manual=TRUE cuando hay match exitoso
4. **Marcado de cola**: UPDATE manual_verification_queue SET is_verified=TRUE WHERE draw_date=p_draw_date AND type=p_type
5. **Retorno TRUE** cuando la promocion es exitosa

## 6. Requisito Adicional para db-manager (Fase GREEN)

`REVOKE EXECUTE ON FUNCTION fn_verify_and_promote_draw(DATE, VARCHAR) FROM PUBLIC` en la misma migracion que implemente la logica.

## 7. Autorizacion de Fase GREEN

El test RED ha sido disenado, ejecutado y confirmado.

**El backend-coder queda autorizado para implementar la logica de promocion Admin > Scraper en fn_verify_and_promote_draw.**

---

**Firma de Certificacion RED:**
*backend-tester*
*Token: CERT-B5-f1-1.1-RED-018.2*
*Fecha: 2026-04-10*

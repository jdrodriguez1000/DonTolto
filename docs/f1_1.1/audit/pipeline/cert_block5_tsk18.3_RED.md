---
token_id: CERT-B5-f1-1.1-RED-018.3
tipo: Certificacion de Fase RED — Test pgTap
tarea: TSK-F1_1.1-18.3-RED
fecha: 2026-04-10
auditor: backend-tester
estado: RED CONFIRMADO
---

# Certificacion Fase RED — Bloque 5 (Motores RPC)
# TSK-F1_1.1-18.3-RED: Test pgTap Bloqueo de promocion ante discrepancia activa (is_conflict=TRUE)

## 1. Identificacion del Test

- **Archivo creado**: `supabase/tests/020_conflict_promotion_block.sql`
- **Numero de assertions**: 5
- **Trazabilidad SPEC**: Seccion 4.3 (fn_verify_and_promote_draw — bloqueo por conflicto)
- **ADR referenciado**: ADR-04 (Recalculo Atomico Transparente)
- **Funcion bajo prueba**: `fn_verify_and_promote_draw(DATE, VARCHAR)`
- **DoD**: Test falla si se promociona un sorteo con advertencia de conflicto sin resolver

## 2. Resultado de Ejecucion (Estado RED Confirmado)

Comando ejecutado: `npx supabase test db`

Resultado para `020_conflict_promotion_block.sql`:
```
(Wstat: 0 Tests: 5 Failed: 1)
  Failed test: 2
```

Salida TAP detallada:
```
# Failed test 2: "CONFLICT RED 18.3: la entrada discrepante debe ser marcada con is_conflict=TRUE en la cola (SPEC §4.3)"
```

Assertions que pasan en RED (por razon correcta o accidental):
- ASSERTION 1: PASA — el stub retorna FALSE (accidental, coincide con bloqueo esperado)
- ASSERTION 3: PASA — draws vacio (accidental, stub no inserta)
- ASSERTION 4: PASA — stub retorna FALSE cuando is_conflict esta pre-marcado manualmente
- ASSERTION 5: PASA — draws vacio tras reintentos (accidental, stub no inserta)

Plan: 5 assertions planificadas, 5 ejecutadas, 1 fallida. El assertion clave (marcado de conflicto) falla correctamente.

## 3. Analisis de Fallos por Assertion

| # | Descripcion | Resultado en RED | Razon | Correcta |
|---|---|---|---|---|
| 1 | Retorna FALSE en discrepancia | PASA (accidental) | El stub siempre retorna FALSE — coincide con comportamiento de bloqueo | Si (detecta ausencia de logica positiva) |
| 2 | is_conflict=TRUE marcado en cola | FALLA | El stub no detecta discrepancia ni actualiza is_conflict. COUNT=0 | Si — fallo correcto |
| 3 | draws vacio con conflicto activo | PASA (accidental) | El stub no inserta en draws — resultado correcto por razon equivocada | Si (invariante se verifica) |
| 4 | Retorna FALSE con is_conflict pre-existente | PASA (accidental) | El stub siempre retorna FALSE — no detecta is_conflict, pero resultado coincide | Si (assertions 2 expone esto) |
| 5 | draws vacio tras reintentos | PASA (accidental) | El stub no inserta — resultado correcto por razon equivocada | Si (invariante se verifica) |

## 4. Verificacion de Correctitud de la Fase RED

El fallo de ASSERTION 2 es el que captura el contrato del DoD:
- **DoD**: "Test falla si se promociona un sorteo con advertencia de conflicto sin resolver."
- ASSERTION 2 verifica que la funcion MARCA el conflicto (is_conflict=TRUE) cuando detecta discrepancia.
- El stub no implementa deteccion de discrepancia ni actualizacion de is_conflict.
- Las assertions 1, 3, 4, 5 pasan por coincidencia con el comportamiento del stub — esto es esperado y documentado en el test (comentarios "coincidencia accidental").
- El patron de test es valido: la implementacion GREEN debe hacer que TODAS pasen por las razones CORRECTAS, no accidentales.

## 5. Contrato Tecnico para Fase GREEN (backend-coder)

Para que todos los assertions pasen en GREEN por razones correctas:

1. **Deteccion de discrepancia**: comparar admin.numbers vs scraper.numbers y admin.superbalota vs scraper.superbalota
2. **Marcado de conflicto**: cuando hay discrepancia, `UPDATE manual_verification_queue SET is_conflict=TRUE WHERE draw_date=... AND entry_source='admin' AND id=(el registro admin discrepante)`
3. **Retorno FALSE** cuando hay discrepancia o cuando existe is_conflict=TRUE activo para esa fecha/tipo
4. **Verificacion de is_conflict pre-existente**: antes de cualquier promocion, verificar que NO exista ningun registro con is_conflict=TRUE para la fecha/tipo
5. **Bloqueo total**: si is_conflict=TRUE en cualquier registro de la cola para (draw_date, type), retornar FALSE sin INSERT en draws

## 6. Requisito Adicional para db-manager (Fase GREEN)

`REVOKE EXECUTE ON FUNCTION fn_verify_and_promote_draw(DATE, VARCHAR) FROM PUBLIC` en la misma migracion.

## 7. Autorizacion de Fase GREEN

El test RED ha sido disenado, ejecutado y confirmado. El assertion critico (ASSERTION 2 — marcado de is_conflict) falla correctamente.

**El backend-coder queda autorizado para implementar la logica de deteccion de conflicto y bloqueo en fn_verify_and_promote_draw.**

---

**Firma de Certificacion RED:**
*backend-tester*
*Token: CERT-B5-f1-1.1-RED-018.3*
*Fecha: 2026-04-10*

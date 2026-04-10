# Certificado GREEN — TSK-F1_1.1-14.1
## Hardening de fn_setup_security_context (Inyección de app.current_admin_id)

**Tarea**: TSK-F1_1.1-14.1-GREEN  
**Fecha**: 2026-04-10  
**Agente**: security-hardener  
**Fase**: GREEN (TDD Cycle — Bloque 4, Seguridad & RLS)  
**Rama**: feat/f1_e1_setup_supabase_ddl  

---

## Funciones Creadas

Archivo: `supabase/migrations/20260410000002_block_4.sql`

### 1. `public.fn_setup_security_context()` — Implementacion completa

- Retorno: `TEXT` (el admin_uuid configurado, para debugging)
- `SECURITY DEFINER` con `SET search_path = extensions, public`
- `OWNER TO postgres` (triple barrera ADR-06)
- Lee `admin_uuid` de `system_configuration WHERE id = 1`
- Ejecuta `set_config('app.current_admin_id', v_admin_uuid, TRUE)` con `is_local=TRUE` (transaccional)
- Fail-safe via `RAISE NOTICE` si el Singleton esta vacio (sin EXCEPTION que rompa el flujo)

### 2. `public.fn_compute_async_scoring(p_run_id UUID)` — Stub Bloque 5

- Retorno: `VOID`
- `SECURITY DEFINER` con `SET search_path = extensions, public`
- `OWNER TO postgres`
- Logica completa pendiente en Bloque de Scoring (REQ-08, SPEC §4.5)

### 3. `public.fn_verify_and_promote_draw(p_draw_date DATE, p_type VARCHAR)` — Stub Bloque 5

- Retorno: `BOOLEAN`
- `SECURITY DEFINER` con `SET search_path = extensions, public`
- `OWNER TO postgres`
- Logica completa pendiente en Bloque de Datos (REQ-09, SPEC §4.6)

---

## Resultado de Tests (npx supabase test db)

### Test 013 — rls_fail_closed_coalesce.sql

| Assertion | Descripcion | Estado RED (antes) | Estado GREEN (despues) |
|---|---|---|---|
| 1 | 5 tablas con RLS habilitado | FALLA | FALLA (scope TSK-14.2) |
| 2 | >= 5 politicas RLS en pg_policies | FALLA | FALLA (scope TSK-14.2) |
| **3** | **fn_setup_security_context existe** | **FALLA** | **PASA** |
| 4 | draws RLS activo + 0 filas con contexto vacio | FALLA | FALLA (scope TSK-14.2) |
| 5 | projections RLS habilitado | FALLA | FALLA (scope TSK-14.2) |
| 6 | system_logs RLS activo + 0 filas | FALLA | FALLA (scope TSK-14.2) |
| 7 | politica de draws usa COALESCE en qual | FALLA | FALLA (scope TSK-14.2) |

**Delta 013**: 7/7 fallos en RED → 6/7 fallos en GREEN. Assertion 3 (fn_setup_security_context existe) VERIFICADA.

### Test 014 — rls_security_definer_search_path.sql

| Assertion | Descripcion | Estado RED (antes) | Estado GREEN (despues) |
|---|---|---|---|
| **1** | **fn_setup_security_context existe** | **FALLA** | **PASA** |
| **2** | **fn_compute_async_scoring existe** | **FALLA** | **PASA** |
| **3** | **fn_verify_and_promote_draw existe** | **FALLA** | **PASA** |
| **4** | **COUNT=3 funciones SECURITY DEFINER con search_path=extensions** | **FALLA** | **PASA** |
| **5** | **0 funciones SECURITY DEFINER sin search_path correcto** | PASA | **PASA** |
| **6** | **fn_setup_security_context es SECURITY DEFINER** | **FALLA** | **PASA** |
| **7** | **fn_setup_security_context owner = postgres** | **FALLA** | **PASA** |

**Resultado 014**: 6/7 fallos en RED → **0/7 fallos en GREEN. TEST COMPLETO VERIFICADO.**

---

## Invariantes de Seguridad Satisfechos (ADR-06)

1. **Triple barrera anti schema-hijacking**: SECURITY DEFINER + SET search_path = extensions, public + OWNER TO postgres implementados en las 3 funciones.
2. **is_local=TRUE en set_config**: El valor de `app.current_admin_id` es transaccional y se descarta con ROLLBACK, evitando contaminacion entre sesiones.
3. **Fail-safe sin EXCEPTION**: La ausencia del Singleton genera RAISE NOTICE, no error fatal, protegiendo el flujo administrativo.
4. **Stubs con hardening completo**: `fn_compute_async_scoring` y `fn_verify_and_promote_draw` declaran el search_path restrictivo desde su creacion inicial, antes de implementar logica funcional.

---

## Alcance Delimitado

Las siguientes assertions de test 013 permanecen en estado FALLA (RED esperado):
- Assertions 1, 2, 4, 5, 6, 7: Requieren `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` y `CREATE POLICY` — scope de TSK-14.2 (db-manager).

Las fallas en tests 015, 016, 017 son igualmente parte del scope de TSK-14.2 y TSK-14.3.

---

## Token de Certificacion

**ESTADO**: GREEN — TSK-F1_1.1-14.1 COMPLETADA  
**Test 014**: 7/7 assertions PASS  
**Test 013**: Assertion 3 PASS (scope de esta tarea satisfecho)  
**Migracion**: `supabase/migrations/20260410000002_block_4.sql` aplicada sin errores  
**Proximo paso**: TSK-F1_1.1-14.2 (db-manager) — Habilitacion de RLS y creacion de politicas explicitas  

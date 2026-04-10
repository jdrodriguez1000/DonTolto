---
token_id: CERT-B4-f1-1.1-RED-013.2
tipo: Certificacion de Fase RED — Test pgTap
tarea: TSK-F1_1.1-13.2-RED
fecha: 2026-04-10
auditor: backend-tester
estado: RED CONFIRMADO
---

# Certificacion Fase RED — Bloque 4 (Seguridad & RLS)
# TSK-F1_1.1-13.2-RED: Test pgTap — search_path restrictivo en funciones SECURITY DEFINER

## 1. Identificacion del Test

- **Archivo creado**: `supabase/tests/014_rls_security_definer_search_path.sql`
- **Numero de assertions**: 7
- **Trazabilidad SPEC**: Seccion 4.7 (fn_setup_security_context SECURITY DEFINER) y Seccion 7 (RLS Hardened)
- **ADR referenciado**: ADR-06 (RLS High-Performance, search_path restrictivo en SECURITY DEFINER)
- **Funciones bajo prueba**: `fn_setup_security_context`, `fn_compute_async_scoring`, `fn_verify_and_promote_draw`
- **Complementario a**: `005_search_path_restrictive.sql` (valida search_path de sesion; este valida proconfig en pg_proc)

## 2. Resultado de Ejecucion (Estado RED Confirmado)

Comando ejecutado:
```
npx supabase test db
```

Resultado para `014_rls_security_definer_search_path.sql`:
```
(Wstat: 0 Tests: 7 Failed: 6)
  Failed tests: 1-4, 6-7
```

Salida TAP detallada:
```
# Failed test 1: "SEGURIDAD RED: fn_setup_security_context debe existir como funcion en el esquema public (SPEC §4.7)"
# Failed test 2: "SEGURIDAD RED: fn_compute_async_scoring debe existir como funcion en el esquema public (SPEC §4.5)"
# Failed test 3: "SEGURIDAD RED: fn_verify_and_promote_draw debe existir como funcion en el esquema public (SPEC §4.6)"
# Failed test 4: "SEGURIDAD RED: las 3 funciones SECURITY DEFINER deben declarar search_path=extensions,public en proconfig (ADR-06)"
#         have: 0
#         want: 3
# Failed test 6: "SEGURIDAD RED: fn_setup_security_context debe ser SECURITY DEFINER (prosecdef=TRUE en pg_proc)"
# Failed test 7: "SEGURIDAD RED: fn_setup_security_context debe ser propiedad del rol postgres (owner=postgres, SPEC §4.7)"
# Looks like you failed 6 tests of 7
```

## 3. Analisis de Fallos por Assertion

| # | Descripcion | Razon del Fallo en RED | Correcta |
|---|---|---|---|
| 1 | fn_setup_security_context existe en public | La funcion no existe (Bloque 4 pendiente). has_function falla | Si |
| 2 | fn_compute_async_scoring existe en public | La funcion no existe (Bloque 4 pendiente). has_function falla | Si |
| 3 | fn_verify_and_promote_draw existe en public | La funcion no existe (Bloque 4 pendiente). has_function falla | Si |
| 4 | 3 funciones SECURITY DEFINER con proconfig correcto | COUNT=0 vs esperado=3. Ninguna funcion existe en pg_proc | Si |
| 5 | 0 funciones SECURITY DEFINER sin search_path correcto | PASA en RED (ninguna funcion existe = 0 sin proconfig). Es guardia GREEN | Si (diseno intencional) |
| 6 | fn_setup_security_context es SECURITY DEFINER | COALESCE(NULL, FALSE) = FALSE. Funcion no existe en pg_proc | Si |
| 7 | fn_setup_security_context owned by postgres | COALESCE(NULL, FALSE) = FALSE. Funcion no existe, no hay owner | Si |

## 4. Verificacion de Correctitud de la Fase RED

Los 6 fallos ocurren por las razones correctas segun el DoD de la tarea:
- **DoD**: "Test falla si una funcion tiene acceso a esquemas no declarados expresamente."
- Las assertions 1-4 fallan por ausencia de las funciones SECURITY DEFINER en pg_proc.
- Las assertions 6-7 fallan porque COALESCE de una subquery sin resultados retorna FALSE.
- La assertion 5 pasa en RED por diseno: su rol es detectar implementaciones erroneas en GREEN donde una funcion se crea sin proconfig (guardia permanente).
- Ningun fallo ocurre por error de sintaxis SQL ni logica incorrecta del test.
- El plan de 7 assertions se ejecuta completo sin abortar la transaccion (ROLLBACK integro).

## 5. Contrato Tecnico que Debe Satisfacer el backend-coder (Fase GREEN)

Para que todos los tests pasen en GREEN, el Bloque 4 debe implementar:

1. **fn_setup_security_context()** en el esquema public con:
   - `SECURITY DEFINER`
   - `SET search_path = extensions, public` embebido en la definicion
   - `OWNER TO postgres`
   - Lee `admin_uuid` de `system_configuration` y ejecuta `set_config('app.current_admin_id', ...)`

2. **fn_compute_async_scoring()** en el esquema public con:
   - `SECURITY DEFINER`
   - `SET search_path = extensions, public` embebido en la definicion

3. **fn_verify_and_promote_draw()** en el esquema public con:
   - `SECURITY DEFINER`
   - `SET search_path = extensions, public` embebido en la definicion

4. **Verificacion pg_proc**:
   - `proconfig::text LIKE '%search_path=extensions%'` debe ser TRUE para las 3 funciones
   - `prosecdef = TRUE` para las 3 funciones
   - `proowner` del rol postgres para fn_setup_security_context

## 6. Nota Tecnica sobre el Campo proconfig

PostgreSQL almacena las configuraciones SET de una funcion en `pg_proc.proconfig` como un array de texto (`text[]`). El formato canonico es:
```
'{search_path=extensions, public}'
```
La assertion 4 usa `p.proconfig::text LIKE '%search_path=extensions%'` para ser flexible ante variaciones de espaciado. La implementacion GREEN debe asegurar que la sintaxis SQL de la funcion incluya `SET search_path = extensions, public` en el bloque de opciones de la funcion.

## 7. Estado del Entorno de Test

| Objeto | Estado en Entorno |
|---|---|
| fn_setup_security_context | NO EXISTE |
| fn_compute_async_scoring | NO EXISTE |
| fn_verify_and_promote_draw | NO EXISTE |
| proconfig con search_path en pg_proc | NINGUNO |
| SECURITY DEFINER en funciones del proyecto | NINGUNA |

## 8. Autorizacion de Fase GREEN

El test RED ha sido diseñado, ejecutado y confirmado con 6/7 fallos correctos.

**El backend-coder queda autorizado para iniciar la implementacion de las funciones SECURITY DEFINER del Bloque 4.**

La transicion a GREEN se certifica cuando `npx supabase test db` reporte:
```
014_rls_security_definer_search_path.sql .. ok
(Tests: 7 Failed: 0)
```

---

**Firma de Certificacion RED:**
*backend-tester*
*Token: CERT-B4-f1-1.1-RED-013.2*
*Fecha: 2026-04-10*

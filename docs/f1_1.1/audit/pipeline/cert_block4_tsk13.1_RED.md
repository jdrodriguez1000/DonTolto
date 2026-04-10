---
token_id: CERT-B4-f1-1.1-RED-013.1
tipo: Certificacion de Fase RED — Test pgTap
tarea: TSK-F1_1.1-13.1-RED
fecha: 2026-04-10
auditor: backend-tester
estado: RED CONFIRMADO
---

# Certificacion Fase RED — Bloque 4 (Seguridad & RLS)
# TSK-F1_1.1-13.1-RED: Test pgTap Denegacion fail-closed COALESCE check

## 1. Identificacion del Test

- **Archivo creado**: `supabase/tests/013_rls_fail_closed_coalesce.sql`
- **Numero de assertions**: 7
- **Trazabilidad SPEC**: Seccion 4.7 (fn_setup_security_context) y Seccion 7 (RLS Hardened)
- **ADR referenciado**: ADR-06 (RLS High-Performance via variables de sesion)
- **Tablas bajo prueba**: `draws`, `projections`, `performance`, `system_logs`, `system_configuration`

## 2. Resultado de Ejecucion (Estado RED Confirmado)

Comando ejecutado:
```
npx supabase test db --db-url "postgresql://postgres:postgres@127.0.0.1:54322/postgres"
```

Resultado para `013_rls_fail_closed_coalesce.sql`:
```
(Wstat: 0 Tests: 7 Failed: 7)
  Failed tests: 1-7
```

Salida TAP detallada:
```
# Failed test 1: "SEGURIDAD RED: las 5 tablas criticas deben tener RLS habilitado (relrowsecurity=TRUE en pg_class)"
#         have: 0
#         want: 5
# Failed test 2: "SEGURIDAD RED: deben existir al menos 5 politicas RLS en las tablas criticas (pg_policies)"
# Failed test 3: "SEGURIDAD RED: la funcion fn_setup_security_context debe existir en el esquema public (SPEC §4.7)"
# Failed test 4: "SEGURIDAD RED fail-closed: draws debe tener RLS activo y retornar 0 filas con app.current_admin_id vacio (COALESCE guard)"
# Failed test 5: "SEGURIDAD RED fail-closed: projections debe tener RLS habilitado (relrowsecurity=TRUE) para denegar acceso sin contexto"
# Failed test 6: "SEGURIDAD RED fail-closed: system_logs debe tener RLS activo y retornar 0 filas con app.current_admin_id vacio"
# Failed test 7: "SEGURIDAD RED: la politica RLS de draws debe usar COALESCE en su calificador (qual) para guardia contra NULL (ADR-06)"
# Looks like you failed 7 tests of 7
```

Plan: 7 assertions planificadas, 7 ejecutadas, 7 fallidas. Sin errores de plan (plan mismatch). Salida limpia.

## 3. Analisis de Fallos por Assertion

| # | Descripcion | Razon del Fallo en RED | Correcta |
|---|---|---|---|
| 1 | 5 tablas criticas con relrowsecurity=TRUE | Ninguna tabla tiene RLS activo. COUNT=0 vs esperado=5 | Si |
| 2 | Al menos 5 politicas RLS en pg_policies | No existe ninguna politica RLS creada. COUNT=0 | Si |
| 3 | fn_setup_security_context existe en public | La funcion no ha sido creada aun (Bloque 4 pendiente) | Si |
| 4 | draws retorna 0 filas con contexto vacio | relrowsecurity=FALSE => condicion compuesta FALSE | Si |
| 5 | projections tiene RLS habilitado | Tabla no existe aun (Bloque 3 no aplicado en entorno de test) => COALESCE(NULL, FALSE)=FALSE | Si |
| 6 | system_logs retorna 0 filas con contexto vacio | relrowsecurity=FALSE => condicion compuesta FALSE | Si |
| 7 | Politica de draws usa COALESCE en qual | No hay politicas en pg_policies para draws => COUNT=0 | Si |

## 4. Verificacion de Correctitud de la Fase RED

Los 7 fallos ocurren por las razones correctas segun el DoD de la tarea:
- **DoD**: "Test falla si una politica RLS permite acceso cuando la variable de sesion es nula."
- Los fallos demuestran ausencia de: RLS habilitado, politicas definidas, funcion bootstrap y guardia COALESCE.
- Ningun fallo ocurre por error de sintaxis del test, nombre de funcion incorrecto o logica mal diseñada.
- El plan de 7 assertions se ejecuta completo sin abortar la transaccion (patron ROLLBACK integro).

## 5. Contrato Tecnico que Debe Satisfacer el backend-coder (Fase GREEN)

Para que todos los tests pasen en GREEN, el Bloque 4 debe implementar:

1. **ALTER TABLE ... ENABLE ROW LEVEL SECURITY** para las 5 tablas protegidas:
   `draws`, `projections`, `performance`, `system_logs`, `system_configuration`

2. **CREATE POLICY** con minimo 5 politicas que cubran los accesos definidos en SPEC §7:
   - draws/projections/performance: SELECT para Admin y Service; web_anon denegado
   - system_logs: INSERT para Service; SELECT/DELETE restringido a Admin
   - system_configuration: SELECT para todos; UPDATE solo service_role

3. **fn_setup_security_context()** como SECURITY DEFINER:
   - Lee admin_uuid de system_configuration
   - Ejecuta set_config('app.current_admin_id', admin_uuid::text, TRUE)
   - SET search_path = extensions, public (ADR-06)
   - Propiedad de postgres

4. **Guardia COALESCE en la politica de draws**:
   - El calificador (qual) de la politica SELECT sobre draws debe contener COALESCE
   - Ejemplo canonico: COALESCE(current_setting('app.current_admin_id', TRUE), '')
   - Garantiza que NULL o string vacio no se interprete como UUID valido

5. **Fail-closed en draws y system_logs**:
   - Con app.current_admin_id = '' (string vacio), COUNT(*) FROM draws = 0
   - Con app.current_admin_id = '' (string vacio), COUNT(*) FROM system_logs = 0
   - relrowsecurity=TRUE confirmado en pg_class para ambas tablas

## 6. Estado del Entorno de Test

| Objeto | Estado en Entorno |
|---|---|
| Tabla draws | EXISTE (Bloque 1/2) |
| Tabla system_logs | EXISTE (Bloque 1/2) |
| Tabla system_configuration | EXISTE (Bloque 1/2) |
| Tabla projections | NO EXISTE (Bloque 3 pendiente) |
| Tabla performance | NO EXISTE (Bloque 3 pendiente) |
| RLS en cualquier tabla | NO ACTIVO |
| fn_setup_security_context | NO EXISTE |
| Politicas RLS | NINGUNA |

## 7. Autorizacion de Fase GREEN

El test RED ha sido diseñado, ejecutado y confirmado. El contrato tecnico esta establecido.

**El backend-coder queda autorizado para iniciar la implementacion del Bloque 4 (Seguridad & RLS).**

La transicion a GREEN se certifica cuando `npx supabase test db` reporte:
```
013_rls_fail_closed_coalesce.sql .. ok
(Tests: 7 Failed: 0)
```

---

**Firma de Certificacion RED:**
*backend-tester*
*Token: CERT-B4-f1-1.1-RED-013.1*
*Fecha: 2026-04-10*

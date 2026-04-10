---
token_id: CERT-B4-f1-1.1-RED-013.4
tipo: Certificacion de Fase RED — Test pgTap
tarea: TSK-F1_1.1-13.4-RED
fecha: 2026-04-10
auditor: backend-tester
estado: RED CONFIRMADO
---

# Certificacion Fase RED — Bloque 4 (Seguridad & RLS)
# TSK-F1_1.1-13.4-RED: Test pgTap — Matriz de Acceso: Rol authenticated (Restricted)

## 1. Identificacion del Test

- **Archivo creado**: `supabase/tests/016_rls_authenticated_restricted.sql`
- **Numero de assertions**: 6
- **Trazabilidad SPEC**: Seccion 7 (Diseno de Seguridad — authenticated como Admin con admin_uuid)
- **ADR referenciado**: ADR-02 (Configuracion Centralizada con admin_uuid), ADR-06 (RLS High-Performance via variables de sesion)
- **Tablas bajo prueba**: `system_configuration` (UPDATE restringido), `draws` (SELECT condicionado a admin_uuid)
- **Estrategia de verificacion**: Inspeccion de `pg_policies` y `pg_class.relrowsecurity` (no SET ROLE — pgTap es superusuario)

## 2. Resultado de Ejecucion (Estado RED Confirmado)

Comando ejecutado:
```
npx supabase test db
```

Resultado para `016_rls_authenticated_restricted.sql`:
```
(Wstat: 0 Tests: 6 Failed: 5)
  Failed tests: 1, 3-6
```

Salida TAP detallada:
```
# Failed test 1: "SEGURIDAD RED: system_configuration debe tener RLS habilitado (relrowsecurity=TRUE) para restringir UPDATE a service_role"
# Failed test 3: "SEGURIDAD RED: debe existir politica SELECT en draws que use current_setting(app.current_admin_id) para Admin (SPEC §7 / ADR-06)"
# Failed test 4: "SEGURIDAD RED: draws debe tener RLS activo para restringir SELECT a Admin (authenticated con admin_uuid) y Service (SPEC §7)"
# Failed test 5: "SEGURIDAD RED: politica SELECT en draws debe referenciar admin_uuid/current_admin_id para diferenciar Admin de authenticated generico (ADR-02/06)"
# Failed test 6: "SEGURIDAD RED: debe existir politica UPDATE en system_configuration restringida a service_role (SPEC §7, no para authenticated)"
# Looks like you failed 5 tests of 6
```

## 3. Analisis de Fallos por Assertion

| # | Descripcion | Razon del Fallo en RED | Correcta |
|---|---|---|---|
| 1 | system_configuration tiene RLS activo | COALESCE(FALSE) = FALSE. relrowsecurity=FALSE en system_configuration (Bloque 4 pendiente) | Si |
| 2 | 0 politicas UPDATE permisivas para authenticated en system_configuration | PASA en RED (no hay politicas = 0 permisivas). Es guardia permanente contra errores en GREEN | Si (diseno intencional) |
| 3 | Politica SELECT en draws usa current_setting(...) | COUNT=0 < 1. No hay ninguna politica RLS para draws que use current_setting | Si |
| 4 | draws tiene RLS activo | COALESCE(FALSE) = FALSE. relrowsecurity=FALSE para draws | Si |
| 5 | Politica SELECT en draws referencia admin_uuid/current_admin_id | COUNT=0 < 1. No hay ninguna politica SELECT en draws con referencia al admin | Si |
| 6 | Politica UPDATE en system_configuration para service_role | COUNT=0 < 1. No hay ninguna politica UPDATE en system_configuration | Si |

## 4. Verificacion de Correctitud de la Fase RED

Los 5 fallos ocurren por las razones correctas segun el DoD de la tarea:
- **DoD**: "Test falla si un usuario autenticado accede a tablas de configuracion."
- Las assertions 1, 3, 4, 5, 6 fallan porque RLS no esta activo y no hay politicas definidas.
- La assertion 2 pasa en RED por diseno: su rol es ser guardia permanente contra la creacion inadvertida de politicas UPDATE permisivas para authenticated en GREEN.
- El contrato critico verificado: solo service_role puede UPDATE system_configuration; authenticated solo puede SELECT en draws si es el admin.
- Ningun fallo ocurre por error de sintaxis del test.
- El plan de 6 assertions se ejecuta completo sin abortar la transaccion (ROLLBACK integro).

## 5. Contrato Tecnico que Debe Satisfacer el backend-coder (Fase GREEN)

Para que todos los tests pasen en GREEN, el Bloque 4 debe implementar:

1. **ALTER TABLE system_configuration ENABLE ROW LEVEL SECURITY**

2. **ALTER TABLE draws ENABLE ROW LEVEL SECURITY**

3. **Politica UPDATE en system_configuration** restringida a service_role:
   ```sql
   CREATE POLICY "system_configuration_update_service_role"
   ON public.system_configuration
   FOR UPDATE
   TO service_role
   USING (TRUE);
   ```

4. **Politica SELECT en draws** que use current_setting (ADR-06):
   ```sql
   CREATE POLICY "draws_select_admin"
   ON public.draws
   FOR SELECT
   TO authenticated
   USING (
     auth.uid() = COALESCE(current_setting('app.current_admin_id', TRUE), '')::uuid
   );
   ```
   - El calificador (qual) debe contener `current_setting` y `current_admin_id`
   - Debe usarse COALESCE para evitar que NULL sea tratado como UUID valido (ADR-06)

5. **Cero politicas UPDATE permisivas para authenticated** en system_configuration.

## 6. Estado del Entorno de Test

| Objeto | Estado en Entorno |
|---|---|
| RLS en system_configuration | NO ACTIVO (relrowsecurity=FALSE) |
| RLS en draws | NO ACTIVO (relrowsecurity=FALSE) |
| Politica UPDATE en system_configuration | NINGUNA |
| Politica SELECT en draws con current_setting | NINGUNA |
| fn_setup_security_context | NO EXISTE |

## 7. Autorizacion de Fase GREEN

El test RED ha sido diseñado, ejecutado y confirmado con 5/6 fallos correctos.

**El backend-coder queda autorizado para implementar las politicas RLS del rol authenticated del Bloque 4.**

La transicion a GREEN se certifica cuando `npx supabase test db` reporte:
```
016_rls_authenticated_restricted.sql .. ok
(Tests: 6 Failed: 0)
```

---

**Firma de Certificacion RED:**
*backend-tester*
*Token: CERT-B4-f1-1.1-RED-013.4*
*Fecha: 2026-04-10*

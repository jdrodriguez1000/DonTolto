---
token_id: CERT-B4-f1-1.1-RED-013.3
tipo: Certificacion de Fase RED — Test pgTap
tarea: TSK-F1_1.1-13.3-RED
fecha: 2026-04-10
auditor: backend-tester
estado: RED CONFIRMADO
---

# Certificacion Fase RED — Bloque 4 (Seguridad & RLS)
# TSK-F1_1.1-13.3-RED: Test pgTap — Matriz de Acceso: Rol web_anon (Deny All)

## 1. Identificacion del Test

- **Archivo creado**: `supabase/tests/015_rls_web_anon_deny_all.sql`
- **Numero de assertions**: 6
- **Trazabilidad SPEC**: Seccion 7 (Diseno de Seguridad — Deny All para web_anon)
- **ADR referenciado**: ADR-06 (RLS High-Performance)
- **Tablas bajo prueba**: `draws`, `projections`, `performance`, `system_logs`
- **Estrategia de verificacion**: Inspeccion de `pg_policies` y `pg_class.relrowsecurity` (no SET ROLE — pgTap es superusuario)

## 2. Resultado de Ejecucion (Estado RED Confirmado)

Comando ejecutado:
```
npx supabase test db
```

Resultado para `015_rls_web_anon_deny_all.sql`:
```
(Wstat: 0 Tests: 6 Failed: 5)
  Failed tests: 1-2, 4-6
```

Salida TAP detallada:
```
# Failed test 1: "SEGURIDAD RED: el rol web_anon debe existir en pg_roles (prerequisito de Deny All)"
# Failed test 2: "SEGURIDAD RED: las 4 tablas de negocio deben tener RLS habilitado (relrowsecurity=TRUE) para Deny All de web_anon"
#         have: 0
#         want: 4
# Failed test 4: "SEGURIDAD RED: deben existir al menos 4 politicas RLS explicitas en las tablas de negocio (SPEC §7)"
# Failed test 5: "SEGURIDAD RED: draws debe tener RLS habilitado (relrowsecurity=TRUE) para denegar acceso a web_anon (SPEC §7)"
# Failed test 6: "SEGURIDAD RED: system_logs debe tener RLS habilitado (relrowsecurity=TRUE) para Deny All implicito de web_anon (SPEC §7)"
# Looks like you failed 5 tests of 6
```

## 3. Analisis de Fallos por Assertion

| # | Descripcion | Razon del Fallo en RED | Correcta |
|---|---|---|---|
| 1 | Rol web_anon existe en pg_roles | El entorno de test local no crea web_anon (Supabase managed). Falla correctamente indicando prerequisito de configuracion | Si |
| 2 | 4 tablas con relrowsecurity=TRUE | COUNT=0 vs esperado=4. Ninguna tabla tiene RLS activo (Bloque 4 pendiente) | Si |
| 3 | 0 politicas SELECT permisivas para web_anon | PASA en RED (no hay ninguna politica = 0 permisivas). Es guardia permanente contra errores en GREEN | Si (diseno intencional) |
| 4 | Al menos 4 politicas RLS explicitas | COUNT=0 < 4. No hay ninguna politica en pg_policies (Bloque 4 pendiente) | Si |
| 5 | draws tiene RLS habilitado | COALESCE(FALSE en pg_class) = FALSE. relrowsecurity=FALSE para draws | Si |
| 6 | system_logs tiene RLS habilitado | COALESCE(FALSE en pg_class) = FALSE. relrowsecurity=FALSE para system_logs | Si |

## 4. Verificacion de Correctitud de la Fase RED

Los 5 fallos ocurren por las razones correctas segun el DoD de la tarea:
- **DoD**: "Test falla si el rol anonimo visualiza mas de 0 registros."
- Las assertions 1, 2, 4, 5, 6 fallan porque: el rol web_anon puede no existir en el entorno local, RLS no esta activo y no hay politicas definidas.
- La assertion 3 pasa en RED por diseno: su rol es detectar politicas permisivas creadas inadvertidamente para web_anon durante GREEN.
- La assertion 1 falla en el entorno de test local donde Supabase no crea el rol web_anon por defecto (entorno CLI vs. cloud). Esto es un hallazgo valido que el backend-coder debe considerar.
- Ningun fallo ocurre por error de sintaxis del test.
- El plan de 6 assertions se ejecuta completo sin abortar la transaccion (ROLLBACK integro).

## 5. Nota sobre Assertion 1 (web_anon en entorno local)

La assertion 1 falla en el entorno de test local porque `npx supabase start` (CLI) puede no crear el rol `web_anon` por defecto. En el entorno cloud de Supabase, este rol existe siempre. La implementacion del Bloque 4 debe incluir una migracion que cree `web_anon` si no existe, o verificar que la configuracion de `supabase/config.toml` lo incluya en el bloque de roles iniciales.

## 6. Contrato Tecnico que Debe Satisfacer el backend-coder (Fase GREEN)

Para que todos los tests pasen en GREEN, el Bloque 4 debe implementar:

1. **Creacion del rol web_anon** si no existe en el entorno:
   ```sql
   DO $$ BEGIN
     IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'web_anon') THEN
       CREATE ROLE web_anon NOLOGIN;
     END IF;
   END $$;
   ```

2. **ALTER TABLE ... ENABLE ROW LEVEL SECURITY** para las 4 tablas:
   `draws`, `projections`, `performance`, `system_logs`

3. **Politicas explicitas** para al menos 4 tablas (ninguna para web_anon):
   - SELECT en draws para Admin y Service (no web_anon)
   - SELECT en projections para Admin y Service (no web_anon)
   - SELECT en performance para Admin y Service (no web_anon)
   - INSERT en system_logs para Service (no web_anon)

4. **Cero politicas SELECT permisivas para web_anon** en cualquier tabla de negocio.

## 7. Estado del Entorno de Test

| Objeto | Estado en Entorno |
|---|---|
| Rol web_anon | NO EXISTE en entorno CLI local |
| RLS en draws | NO ACTIVO (relrowsecurity=FALSE) |
| RLS en projections | NO ACTIVO |
| RLS en performance | NO ACTIVO |
| RLS en system_logs | NO ACTIVO |
| Politicas RLS en pg_policies | NINGUNA |

## 8. Autorizacion de Fase GREEN

El test RED ha sido diseñado, ejecutado y confirmado con 5/6 fallos correctos.

**El backend-coder queda autorizado para iniciar la implementacion del Deny All para web_anon del Bloque 4.**

La transicion a GREEN se certifica cuando `npx supabase test db` reporte:
```
015_rls_web_anon_deny_all.sql .. ok
(Tests: 6 Failed: 0)
```

---

**Firma de Certificacion RED:**
*backend-tester*
*Token: CERT-B4-f1-1.1-RED-013.3*
*Fecha: 2026-04-10*

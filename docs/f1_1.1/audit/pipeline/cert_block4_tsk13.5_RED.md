---
token_id: CERT-B4-f1-1.1-RED-013.5
tipo: Certificacion de Fase RED — Test pgTap
tarea: TSK-F1_1.1-13.5-RED
fecha: 2026-04-10
auditor: backend-tester
estado: RED CONFIRMADO
---

# Certificacion Fase RED — Bloque 4 (Seguridad & RLS)
# TSK-F1_1.1-13.5-RED: Test pgTap — Matriz de Acceso: Rol service_role (Full Access)

## 1. Identificacion del Test

- **Archivo creado**: `supabase/tests/017_rls_service_role_bypass.sql`
- **Numero de assertions**: 7
- **Trazabilidad SPEC**: Seccion 7 (Diseno de Seguridad — service_role Full Access con Minimo Privilegio)
- **ADR referenciado**: ADR-06 (RLS High-Performance — bypass RLS para service_role)
- **Tablas bajo prueba**: `system_logs`, `projections`, `manual_verification_queue`
- **Estrategia de verificacion**: Inspeccion de `pg_roles.rolbypassrls` y `pg_policies` (no SET ROLE — pgTap es superusuario)
- **Correccion aplicada**: Campo correcto en pg_roles es `rolbypassrls` (no `bypassrls`)

## 2. Resultado de Ejecucion (Estado RED Confirmado)

Comando ejecutado:
```
npx supabase test db
```

Resultado para `017_rls_service_role_bypass.sql`:
```
(Wstat: 0 Tests: 7 Failed: 5)
  Failed tests: 2-5, 7
```

Salida TAP detallada:
```
# Failed test 2: "SEGURIDAD RED: debe existir politica INSERT para service_role en system_logs (SPEC §7 — INSERT permitido para Service)"
# Failed test 3: "SEGURIDAD RED: debe existir politica INSERT para service_role en projections (SPEC §7 — Minimo Privilegio Engine Python)"
# Failed test 4: "SEGURIDAD RED: debe existir politica UPDATE para service_role en projections (SPEC §7 — ciclo pending->calculated)"
# Failed test 5: "SEGURIDAD RED: debe existir politica INSERT para service_role en manual_verification_queue (SPEC §7 / REQ-09 Double-Entry)"
# Failed test 7: "SEGURIDAD RED: deben existir al menos 4 politicas para service_role en las tablas criticas (SPEC §7 Minimo Privilegio)"
# Looks like you failed 5 tests of 7
```

## 3. Analisis de Fallos por Assertion

| # | Descripcion | Razon del Fallo en RED | Correcta |
|---|---|---|---|
| 1 | service_role tiene rolbypassrls=TRUE | PASA en RED — Supabase crea service_role con bypassrls=TRUE por defecto (atributo nativo) | Si (comportamiento esperado de Supabase) |
| 2 | Politica INSERT para service_role en system_logs | COUNT=0 < 1. No hay ninguna politica en pg_policies para system_logs (Bloque 4 pendiente) | Si |
| 3 | Politica INSERT para service_role en projections | COUNT=0 < 1. No hay ninguna politica en pg_policies para projections (Bloque 4 pendiente) | Si |
| 4 | Politica UPDATE para service_role en projections | COUNT=0 < 1. No hay ninguna politica UPDATE en pg_policies para projections | Si |
| 5 | Politica INSERT para service_role en manual_verification_queue | COUNT=0 < 1. No hay ninguna politica para manual_verification_queue | Si |
| 6 | 0 politicas DELETE permisivas para service_role en system_logs | PASA en RED (no hay politicas = 0 DELETE). Es guardia permanente contra errores en GREEN | Si (diseno intencional) |
| 7 | >= 4 politicas para service_role en tablas criticas | COUNT=0 < 4. No hay ninguna politica para service_role en ninguna tabla | Si |

## 4. Verificacion de Correctitud de la Fase RED

Los 5 fallos ocurren por las razones correctas segun el DoD de la tarea:
- **DoD**: "Test falla si el rol de servicio no tiene bypass de RLS operativo."
- Las assertions 2-5 y 7 fallan porque no existen politicas RLS para service_role en ninguna tabla.
- La assertion 1 pasa porque Supabase crea service_role con rolbypassrls=TRUE de forma nativa — esto es correcto y esperado.
- La assertion 6 pasa en RED por diseno: actua como guardia permanente contra la creacion inadvertida de politicas DELETE para service_role en system_logs.
- Se detecto y corrigio un error de nombre de columna: `bypassrls` -> `rolbypassrls` en pg_roles. El test 017 ahora ejecuta limpiamente (Wstat: 0).
- Ningun fallo ocurre por error de sintaxis del test.
- El plan de 7 assertions se ejecuta completo sin abortar la transaccion (ROLLBACK integro).

## 5. Nota Tecnica: Correccion de Nombre de Campo pg_roles

Durante la ejecucion inicial se detecto que el campo correcto en `pg_roles` de PostgreSQL es `rolbypassrls` (no `bypassrls`). El test fue corregido antes de la confirmacion RED final. Esta correccion es consistente con el catalogo del sistema de PostgreSQL 15+:
```sql
-- Correcto:
SELECT r.rolbypassrls FROM pg_roles r WHERE r.rolname = 'service_role';
-- Incorrecto (causa ERROR: column r.bypassrls does not exist):
SELECT r.bypassrls FROM pg_roles r WHERE r.rolname = 'service_role';
```

## 6. Contrato Tecnico que Debe Satisfacer el backend-coder (Fase GREEN)

Para que todos los tests pasen en GREEN, el Bloque 4 debe implementar:

1. **Politica INSERT para service_role en system_logs**:
   ```sql
   CREATE POLICY "system_logs_insert_service_role"
   ON public.system_logs
   FOR INSERT
   TO service_role
   WITH CHECK (TRUE);
   ```

2. **Politica INSERT para service_role en projections**:
   ```sql
   CREATE POLICY "projections_insert_service_role"
   ON public.projections
   FOR INSERT
   TO service_role
   WITH CHECK (TRUE);
   ```

3. **Politica UPDATE para service_role en projections**:
   ```sql
   CREATE POLICY "projections_update_service_role"
   ON public.projections
   FOR UPDATE
   TO service_role
   USING (TRUE);
   ```

4. **Politica INSERT para service_role en manual_verification_queue**:
   ```sql
   CREATE POLICY "mvq_insert_service_role"
   ON public.manual_verification_queue
   FOR INSERT
   TO service_role
   WITH CHECK (TRUE);
   ```

5. **PROHIBICION**: NO crear politica DELETE para service_role en system_logs.
   Los logs son inmutables (principio de inviolabilidad forense, SPEC §7).

6. **Total minimo de politicas para service_role**: >= 4 (INSERT logs, INSERT projections, UPDATE projections, INSERT mvq)

## 7. Estado del Entorno de Test

| Objeto | Estado en Entorno |
|---|---|
| Rol service_role | EXISTE con rolbypassrls=TRUE (nativo de Supabase) |
| Politica INSERT en system_logs para service_role | NINGUNA |
| Politica INSERT en projections para service_role | NINGUNA |
| Politica UPDATE en projections para service_role | NINGUNA |
| Politica INSERT en manual_verification_queue para service_role | NINGUNA |
| Politica DELETE en system_logs para service_role | NINGUNA (correcto) |

## 8. Autorizacion de Fase GREEN

El test RED ha sido diseñado, ejecutado y confirmado con 5/7 fallos correctos (2 pasan por diseno intencional).

**El backend-coder queda autorizado para implementar las politicas de acceso de service_role del Bloque 4.**

La transicion a GREEN se certifica cuando `npx supabase test db` reporte:
```
017_rls_service_role_bypass.sql .. ok
(Tests: 7 Failed: 0)
```

---

**Firma de Certificacion RED:**
*backend-tester*
*Token: CERT-B4-f1-1.1-RED-013.5*
*Fecha: 2026-04-10*

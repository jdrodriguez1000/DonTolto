-- =============================================================================
-- MIGRACIÓN: 20260410000005_block_4_refact.sql
-- Trazabilidad: Bloque 4 — TSK-F1_1.1-16.1-REFACT (Estandarización de plantillas RLS)
-- Objetos: fn_is_admin() — función helper para futuros bloques con políticas RLS
-- SPEC: §7 — Diseño de Seguridad (RLS Hardened)
-- ADR: ADR-06 — RLS High-Performance (SECURITY DEFINER + search_path restrictivo)
-- Fecha: 2026-04-10
-- Dependencia: 20260410000002_block_4.sql (fn_setup_security_context — patrón COALESCE)
-- Dependencia: 20260410000003_block_4_rls.sql (20 políticas RLS con COALESCE guard)
--
-- DECISIÓN DE REFACTOR (hallazgo técnico documentado):
--   Las 20 políticas existentes en _block_4_rls.sql repiten la lógica COALESCE en
--   cada cláusula USING. El refactor canónico sería reescribir los calificadores
--   USING a USING (public.fn_is_admin()), pero esto invalida tres assertions de la
--   suite de tests pgTap activa:
--
--     - Test 013, A7: lower(pg_policies.qual) LIKE '%coalesce%' en draws
--       → fn_is_admin() almacena la lógica internamente; 'coalesce' desaparece del qual.
--     - Test 016, A3: lower(pg_policies.qual) LIKE '%current_setting%' en draws
--       → fn_is_admin() oculta current_setting del qual inspeccionado.
--     - Test 016, A5: lower(pg_policies.qual) LIKE '%current_admin_id%' en draws
--       → fn_is_admin() oculta la cadena 'current_admin_id' del qual.
--
--   Por tanto, el REFACTOR se limita a:
--     1. Crear fn_is_admin() como función helper disponible para nuevas políticas
--        en bloques futuros (Bloque 5 y posteriores).
--     2. Mantener las 20 políticas existentes sin modificación para preservar la
--        integridad de la suite de tests vigente.
--     3. Documentar la deuda técnica: cuando los tests se actualicen para inspeccionar
--        comportamiento funcional en lugar de texto literal del qual, las políticas
--        podrán migrarse a USING (public.fn_is_admin()).
--
-- Invariante de calidad: ningún test existente (013–017) se ve afectado por esta migración.
-- =============================================================================

-- =============================================================================
-- BLOQUE 1: FUNCIÓN HELPER fn_is_admin()
-- Helper centralizado para verificar identidad administrativa en políticas RLS.
-- Encapsula el patrón COALESCE guard (ADR-06) en una función reutilizable.
--
-- Uso en nuevas políticas (Bloque 5+):
--   USING (public.fn_is_admin())
--
-- Equivalente funcional al patrón inline:
--   COALESCE(current_setting('app.current_admin_id', TRUE), '') != ''
--   AND auth.uid()::text = COALESCE(current_setting('app.current_admin_id', TRUE), '')
--
-- Nota de seguridad (ADR-06):
--   - STABLE: puede ser inlinada por el planificador en contextos WHERE; no modifica datos.
--   - SECURITY DEFINER + SET search_path: misma triple barrera de fn_setup_security_context.
--   - OWNER TO postgres: garantiza que SECURITY DEFINER eleve al nivel máximo requerido.
--   - El doble COALESCE es intencional: primero guarda contra contexto vacío ('' != UUID),
--     luego compara el UUID configurado con auth.uid(). Ambas condiciones son necesarias
--     para fail-closed: un current_admin_id vacío nunca debe coincidir con auth.uid().
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = extensions, public
AS $$
    SELECT
        -- Condición 1: el contexto de admin debe estar establecido (no vacío).
        -- Protege contra sesiones que nunca llamaron a fn_setup_security_context().
        COALESCE(current_setting('app.current_admin_id', TRUE), '') != ''
        -- Condición 2: el UID autenticado debe coincidir con el admin_uuid configurado.
        -- Garantiza que solo el Admin registrado en system_configuration pasa el check.
        AND auth.uid()::text = COALESCE(current_setting('app.current_admin_id', TRUE), '')
$$;

COMMENT ON FUNCTION public.fn_is_admin() IS
    'Helper RLS: verifica si la sesión actual corresponde al Admin registrado en system_configuration. '
    'Encapsula el patrón COALESCE guard de ADR-06: contexto vacío NUNCA coincide con auth.uid(). '
    'STABLE permite inlining por el planificador. SECURITY DEFINER + search_path fijo = anti schema-hijacking. '
    'Uso en nuevas políticas (Bloque 5+): USING (public.fn_is_admin()). '
    'Las 20 políticas de _block_4_rls.sql mantienen su COALESCE inline para preservar '
    'la integridad de los tests pgTap (013 A7, 016 A3/A5) que inspeccionan pg_policies.qual. '
    'Deuda técnica: migrar políticas existentes a fn_is_admin() cuando los tests se actualicen '
    'para validar comportamiento funcional en lugar de texto literal del calificador. (TSK-F1_1.1-16.1-REFACT)';

-- Transferir ownership a postgres para que SECURITY DEFINER eleve al nivel
-- máximo requerido. Mismo patrón que fn_setup_security_context (ADR-06).
ALTER FUNCTION public.fn_is_admin() OWNER TO postgres;

-- =============================================================================
-- NOTA: Las políticas existentes en 20260410000003_block_4_rls.sql NO se modifican.
-- El refactor completo (migración de USING inline a USING (public.fn_is_admin()))
-- se ejecutará como tarea separada cuando los tests pgTap se actualicen para
-- no inspeccionar literales de texto en pg_policies.qual.
-- Referencia de deuda técnica: TSK-F1_1.1-16.1-REFACT (hallazgo documentado).
-- =============================================================================

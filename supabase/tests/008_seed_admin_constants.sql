-- =============================================================================
-- TEST: 008_seed_admin_constants.sql
-- Trazabilidad: TSK-F1_1.1-04.3-RED — Inexistencia de constantes administrativas (seed check fail)
-- SPEC: Seccion 3.6 — Garantia Singleton: system_configuration / Seed Administrativo
-- PLAN: B2 — Verificacion de seed inicial de system_configuration
-- Responsable: backend-tester
-- Fecha: 2026-04-09
--
-- Tipo de test: RED (TDD) — Disenado para FALLAR en el estado actual
-- Descripcion: Verifica que el seed administrativo fue inyectado correctamente
--              en system_configuration, incluyendo la presencia de un admin_uuid
--              valido (NOT NULL, no UUID cero), el umbral de deuda de 24 horas
--              y el kill-switch global en estado inicial FALSE.
--
--              Como el seed aun NO existe (TSK-05.7-GREEN pendiente), este test
--              falla en RED confirmando la ausencia del registro obligatorio.
--
-- Estado esperado en RED:
--   - ASSERTION 1: FALLA — system_configuration contiene 0 registros (seed ausente)
--   - ASSERTION 2: FALLA — admin_uuid retorna NULL (registro id=1 inexistente)
--   - ASSERTION 3: FALLA — admin_uuid retorna NULL (no es el UUID cero, pero la query falla)
--   - ASSERTION 4: FALLA — debt_threshold_hours retorna NULL (registro id=1 inexistente)
--   - ASSERTION 5: FALLA — is_system_locked retorna NULL (registro id=1 inexistente)
--
-- Seed pendiente (TSK-F1_1.1-05.7-GREEN):
--   INSERT INTO public.system_configuration (id, admin_uuid, debt_threshold_hours, is_system_locked)
--   VALUES (1, '<uuid_real_del_admin>', 24, false);
--
-- Invariante de Seed (SPEC §3.6):
--   La tabla system_configuration debe contener exactamente UN registro con id=1
--   (Garantia Singleton). El campo admin_uuid es obligatorio (NOT NULL) y debe
--   ser un UUID real del administrador del sistema, no el UUID cero ni NULL.
--   Este registro es prerequisito para fn_setup_security_context (SPEC §4.7) y
--   la politica RLS de Admin definida en SPEC §5.
-- =============================================================================

BEGIN;

SELECT plan(5);

-- ---------------------------------------------------------------------------
-- ASSERTION 1: Exactamente 1 registro debe existir en system_configuration
-- Estado RED: FALLA — la tabla tiene 0 registros porque el seed aun no fue
--             ejecutado (TSK-05.7-GREEN pendiente de implementacion)
-- Razon: El Singleton de configuracion (SPEC §3.6) exige que el sistema
--        arranque con exactamente un registro administrativo. Sin este registro,
--        fn_setup_security_context no puede resolver el admin_uuid y el
--        sistema RLS queda ciego al rol de administrador.
-- ---------------------------------------------------------------------------
SELECT is(
    (SELECT COUNT(*)::integer FROM public.system_configuration),
    1,
    'system_configuration debe contener exactamente 1 registro (Singleton seed)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 2: El campo admin_uuid no debe ser NULL
-- Estado RED: FALLA — el registro id=1 no existe, la subquery retorna NULL
-- Razon: SPEC §3.6 define admin_uuid como NOT NULL. Es el campo critico que
--        permite a fn_setup_security_context (SPEC §4.7) inyectar el
--        identificador administrativo en el contexto de sesion via set_config.
--        Un admin_uuid NULL invalida toda la cadena de autorizacion RLS.
-- ---------------------------------------------------------------------------
SELECT isnt(
    (SELECT admin_uuid FROM public.system_configuration WHERE id = 1),
    NULL,
    'El campo admin_uuid no debe ser NULL — el seed debe inyectar un UUID administrativo valido'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 3: El admin_uuid no debe ser el UUID cero (identidad nula)
-- Estado RED: FALLA — el registro id=1 no existe, la subquery retorna NULL
--             (NULL != UUID cero, por lo que isnt pasa en ausencia del registro,
--              pero la Assertion 1 ya garantiza el fallo del plan completo)
-- Razon: SPEC §3.6 exige un UUID real del administrador. El UUID cero
--        (00000000-0000-0000-0000-000000000000) es una identidad nula que
--        podria colisionar con logica de auth.uid() y otorgar privilegios
--        administrativos de forma accidental a usuarios anonimos o por defecto.
-- ---------------------------------------------------------------------------
SELECT isnt(
    (SELECT admin_uuid::text FROM public.system_configuration WHERE id = 1),
    '00000000-0000-0000-0000-000000000000',
    'El admin_uuid no debe ser el UUID cero — debe ser un UUID real de administrador'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 4: debt_threshold_hours debe ser exactamente 24
-- Estado RED: FALLA — el registro id=1 no existe, la subquery retorna NULL
-- Razon: SPEC §3.6 establece DEFAULT 24 para debt_threshold_hours. Este
--        valor es consumido por fn_check_debt_and_lock (SPEC §4.6) para
--        determinar cuando un sorteo en manual_verification_queue supera
--        el umbral de deuda y activa el modo Fallback [REQ-09].
--        Un valor incorrecto romperia la logica de bloqueo automatico del sistema.
-- ---------------------------------------------------------------------------
SELECT is(
    (SELECT debt_threshold_hours FROM public.system_configuration WHERE id = 1),
    24,
    'debt_threshold_hours debe ser 24 horas (umbral de modo Fallback segun SPEC §3.6)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 5: is_system_locked debe ser FALSE en el estado inicial
-- Estado RED: FALLA — el registro id=1 no existe, la subquery retorna NULL
-- Razon: SPEC §3.6 define is_system_locked como kill-switch global con
--        DEFAULT FALSE. Un sistema que inicia con is_system_locked = TRUE
--        bloquearia inmediatamente todas las operaciones del Engine Python
--        y el Dashboard, constituyendo un fallo critico de arranque.
--        El estado inicial FALSE es la condicion operacional normal del sistema.
-- ---------------------------------------------------------------------------
SELECT is(
    (SELECT is_system_locked FROM public.system_configuration WHERE id = 1),
    false,
    'is_system_locked debe ser FALSE en el estado inicial del sistema'
);

-- CLEANUP: El bloque BEGIN/ROLLBACK garantiza que ninguna operacion de prueba
-- persiste en la base de datos. La transaccion es completamente atomica.
SELECT * FROM finish();

ROLLBACK;

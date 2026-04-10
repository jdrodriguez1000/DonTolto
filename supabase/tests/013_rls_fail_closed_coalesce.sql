-- =============================================================================
-- TEST: 013_rls_fail_closed_coalesce.sql
-- Trazabilidad: TSK-F1_1.1-13.1-RED — Test pgTap: Denegacion fail-closed en
--               ausencia de contexto (COALESCE check)
-- SPEC: Seccion 4.7 — fn_setup_security_context (RLS Bootstrap)
-- SPEC: Seccion 7   — Diseno de Seguridad (RLS Hardened)
-- PLAN: B4 — Security & RLS [TDD Cycle] — Fase RED
-- ADR: ADR-06 — RLS High-Performance (variables de entorno, sin subqueries en fila)
-- Responsable: backend-tester
-- Fecha: 2026-04-10
--
-- Tipo de test: RED (TDD) — Disenado para FALLAR cuando la implementacion no existe
--
-- Descripcion: Verifica que las politicas RLS en las tablas protegidas del proyecto
--              son "fail-closed": si la variable de sesion 'app.current_admin_id'
--              no ha sido configurada (es NULL o string vacio), las politicas deben
--              denegar el acceso en lugar de permitirlo. Este contrato protege contra
--              sesiones sin contexto de seguridad que podrian explotar un RLS mal
--              implementado para obtener acceso no autorizado a datos sensibles.
--
-- Contexto de Seguridad (ADR-06 / SPEC §7):
--   - La funcion fn_setup_security_context() lee admin_uuid de system_configuration
--     y lo persiste como variable de sesion via set_config('app.current_admin_id', ...).
--   - Las politicas RLS usan current_setting('app.current_admin_id', TRUE) para
--     comparar con auth.uid(), evitando subqueries recursivas por fila (ADR-06).
--   - El segundo parametro TRUE en current_setting() retorna NULL en lugar de lanzar
--     excepcion cuando la variable no existe, lo que exige usar COALESCE o una
--     guardia equivalente para forzar un UUID invalido (ej: '00000000-...'::uuid
--     o simplemente garantizar que NULL != cualquier UUID valido).
--   - Sin COALESCE: current_setting('app.current_admin_id', TRUE) = NULL
--     y la comparacion NULL = auth.uid() siempre es UNKNOWN (no TRUE), por lo que
--     el acceso debe ser denegado. Sin embargo, si la politica usa LIKE o IS NOT
--     DISTINCT FROM de forma incorrecta, podria otorgar acceso.
--   - Esta suite valida el invariante mas critico del modelo de seguridad:
--     un contexto nulo NUNCA debe ser interpretado como un UUID valido.
--
-- Tablas bajo prueba (SPEC §7 — Politicas Mandatorias):
--   - draws            (SELECT denegado a web_anon)
--   - projections      (SELECT denegado a web_anon)
--   - performance      (SELECT denegado a web_anon)
--   - system_logs      (SELECT denegado a web_anon)
--   - system_configuration (UPDATE restringido a service_role)
--
-- Estado esperado en RED (antes de Bloque 4 — implementacion de RLS):
--   - ASSERTION 1: FALLA — ninguna tabla tiene RLS habilitado (relrowsecurity=FALSE)
--   - ASSERTION 2: FALLA — no existen politicas RLS en pg_policies para estas tablas
--   - ASSERTION 3: FALLA — la funcion fn_setup_security_context no existe aun
--   - ASSERTION 4: FALLA — con contexto vacio, draws es accesible (RLS no existe)
--   - ASSERTION 5: FALLA — con contexto vacio, projections es accesible (RLS no existe)
--   - ASSERTION 6: FALLA — con contexto vacio, system_logs es accesible (RLS no existe)
--   - ASSERTION 7: FALLA — pg_policies no tiene calificadores COALESCE para draws
--
-- Cuando pase a GREEN (Bloque 4 implementado):
--   - Todas las assertions deben pasar: RLS habilitado, politicas existentes,
--     fn_setup_security_context creada, y contexto nulo deniega acceso (0 filas).
-- =============================================================================

BEGIN;

SELECT plan(7);

-- ---------------------------------------------------------------------------
-- ASSERTION 1: Las tablas criticas deben tener RLS habilitado (relrowsecurity = TRUE)
-- Estado RED: FALLA — el Bloque 4 no ha ejecutado las migraciones ALTER TABLE
--             ... ENABLE ROW LEVEL SECURITY para las tablas protegidas.
-- Razon: SPEC §7 exige RLS en draws, projections, performance, system_logs y
--        system_configuration. Sin el flag relrowsecurity=TRUE en pg_class, las
--        politicas que se definan mas tarde no seran evaluadas en absoluto, haciendo
--        que cualquier rol pueda leer cualquier tabla sin restriccion alguna.
--        ADR-06 establece RLS High-Performance como el mecanismo mandatorio de
--        control de acceso a nivel de fila para el proyecto.
-- Criterio de paso GREEN: COUNT de tablas con RLS habilitado >= 5 (las 5 protegidas)
-- ---------------------------------------------------------------------------
SELECT is(
    (
        SELECT COUNT(*)::integer
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relname IN ('draws', 'projections', 'performance', 'system_logs', 'system_configuration')
          AND c.relrowsecurity = TRUE
    ),
    5,
    'SEGURIDAD RED: las 5 tablas criticas deben tener RLS habilitado (relrowsecurity=TRUE en pg_class)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 2: Deben existir politicas RLS definidas en las tablas criticas
-- Estado RED: FALLA — no se han creado politicas RLS (CREATE POLICY) en
--             ninguna de las tablas del proyecto; pg_policies retorna 0 filas.
-- Razon: Habilitar RLS sin crear politicas equivale a una politica "deny all"
--        implicita — ningun usuario puede acceder. Pero la SPEC §7 exige politicas
--        explicitas: SELECT para Admin y Service en draws/projections/performance,
--        INSERT para Service en system_logs, UPDATE solo para service_role en
--        system_configuration. Sin politicas, el comportamiento es indefinido y
--        el sistema carece del contrato de acceso auditado que requiere ADR-06.
-- Criterio de paso GREEN: al menos 5 politicas RLS existen para las tablas protegidas
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer >= 5
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename IN ('draws', 'projections', 'performance', 'system_logs', 'system_configuration')
    ),
    'SEGURIDAD RED: deben existir al menos 5 politicas RLS en las tablas criticas (pg_policies)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 3: La funcion fn_setup_security_context debe existir en public
-- Estado RED: FALLA — la funcion fn_setup_security_context aun no ha sido creada;
--             pg_proc no contiene una funcion con ese nombre en el esquema public.
-- Razon: SPEC §4.7 define fn_setup_security_context como el mecanismo de bootstrap
--        del contexto de seguridad RLS. Sin ella, las sesiones administrativas no
--        pueden configurar 'app.current_admin_id' de forma segura (SECURITY DEFINER
--        para acceder a system_configuration), lo que rompe todo el modelo RLS del
--        proyecto. Su ausencia hace imposible las assertions 4, 5 y 6 (contexto nulo).
-- Criterio de paso GREEN: la funcion existe en pg_proc con schema public
-- ---------------------------------------------------------------------------
SELECT has_function(
    'public',
    'fn_setup_security_context',
    'SEGURIDAD RED: la funcion fn_setup_security_context debe existir en el esquema public (SPEC §4.7)'
);

-- Configurar contexto de sesion vacio para assertions 4, 5 y 6.
-- Esto simula una sesion sin ejecutar fn_setup_security_context().
-- is_local=TRUE garantiza que la variable se descarta al hacer ROLLBACK.
SELECT set_config('app.current_admin_id', '', TRUE);

-- ---------------------------------------------------------------------------
-- ASSERTION 4 (fail-closed draws): Con 'app.current_admin_id' vacio, la tabla
-- draws debe retornar 0 filas bajo cualquier rol no privilegiado.
-- Estado RED: FALLA — como RLS no esta habilitado, draws es accesible. La tabla
--             draws ya existe (Bloque 1/2) pero no tiene RLS. Sin filas en draws
--             el COUNT es 0 por razon equivocada (vacia != denegada por RLS).
--             La assertion valida el invariante: 0 filas DEBIDO a RLS activo.
--             En RED, el invariante no se cumple porque relrowsecurity=FALSE.
-- Estrategia de deteccion: se verifica que relrowsecurity sea TRUE para draws
--             Y que el COUNT sea 0. Si relrowsecurity es FALSE, la condicion
--             compuesta es FALSE y el test FALLA correctamente en fase RED.
-- Razon: El principio fail-closed exige que la ausencia de contexto resulte en
--        denegacion. Un atacante sin fn_setup_security_context() no debe poder
--        leer historicos de sorteos (REQ-14, SPEC §7).
-- Criterio de paso GREEN: relrowsecurity=TRUE EN draws Y COUNT=0 con contexto vacio
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        -- Condicion compuesta: RLS debe estar activo Y el acceso debe ser denegado
        -- En RED: relrowsecurity=FALSE => la condicion entera es FALSE => test FALLA
        -- En GREEN: relrowsecurity=TRUE y RLS bloquea => COUNT=0 => test PASA
        SELECT
            COALESCE(
                (SELECT c.relrowsecurity
                 FROM pg_class c
                 JOIN pg_namespace n ON n.oid = c.relnamespace
                 WHERE n.nspname = 'public' AND c.relname = 'draws'),
                FALSE
            )
            AND
            (SELECT COUNT(*) = 0 FROM public.draws)
    ),
    'SEGURIDAD RED fail-closed: draws debe tener RLS activo y retornar 0 filas con app.current_admin_id vacio (COALESCE guard)'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 5 (fail-closed projections): projections debe tener RLS habilitado.
-- Estado RED: FALLA — projections no existe aun (Bloque 3 no aplicado) por lo
--             que COALESCE retorna FALSE. Si projections existe pero sin RLS,
--             relrowsecurity=FALSE y el test tambien FALLA correctamente.
-- Razon: Las proyecciones contienen combinaciones propietarias del Engine Python.
--        Su exposicion sin autenticacion viola REQ-14 y SPEC §7. El RLS en
--        projections es el mecanismo de control mandatorio segun ADR-06.
--        Esta assertion valida que el invariante de seguridad este configurado
--        a nivel de objeto de BD (relrowsecurity=TRUE) antes de que cualquier
--        politica sea evaluada. Sin este flag, las politicas no tienen efecto.
-- Nota tecnica: A diferencia de draws/system_logs, projections puede no existir
--               aun en el entorno de test (Bloque 3 aplica su DDL). La consulta
--               a pg_class es segura incluso si la tabla no existe: retorna 0 filas
--               y COALESCE convierte el NULL en FALSE. Esto evita el error 42P01
--               que ocurrirla con SELECT ... FROM public.projections directamente.
-- Criterio de paso GREEN: relrowsecurity=TRUE para projections en pg_class
-- ---------------------------------------------------------------------------
SELECT ok(
    COALESCE(
        (
            SELECT c.relrowsecurity
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public'
              AND c.relname = 'projections'
        ),
        FALSE  -- Si projections no existe, COALESCE retorna FALSE => test FALLA correctamente
    ),
    'SEGURIDAD RED fail-closed: projections debe tener RLS habilitado (relrowsecurity=TRUE) para denegar acceso sin contexto'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 6 (fail-closed system_logs): Con contexto vacio, system_logs debe
-- tener RLS habilitado y retornar 0 filas bajo cualquier rol no privilegiado.
-- Estado RED: FALLA — relrowsecurity=FALSE para system_logs (RLS no aplicado).
--             La condicion compuesta es FALSE => ok(FALSE) => test FALLA.
-- Razon: system_logs contiene trazas forenses (SPEC §3.6 / CLAUDE.md): run_ids,
--        mensajes de error criticos, metadatos JSONB de estado previo del sistema.
--        Su lectura no autorizada permitiria mapear la arquitectura interna,
--        identificar run_ids validos y obtener UUIDs de admin para ataques.
--        La politica RLS debe exigir admin_uuid valido via fn_setup_security_context.
-- Criterio de paso GREEN: relrowsecurity=TRUE en system_logs Y COUNT=0
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT
            COALESCE(
                (SELECT c.relrowsecurity
                 FROM pg_class c
                 JOIN pg_namespace n ON n.oid = c.relnamespace
                 WHERE n.nspname = 'public' AND c.relname = 'system_logs'),
                FALSE
            )
            AND
            (SELECT COUNT(*) = 0 FROM public.system_logs)
    ),
    'SEGURIDAD RED fail-closed: system_logs debe tener RLS activo y retornar 0 filas con app.current_admin_id vacio'
);

-- ---------------------------------------------------------------------------
-- ASSERTION 7: Las politicas RLS de draws deben usar COALESCE o guardia equivalente
--              en su calificador (qual) para evitar que NULL sea interpretado como valido
-- Estado RED: FALLA — no existen politicas RLS en draws; pg_policies retorna 0 filas
--             para draws, por lo que qual es NULL para todas y COUNT = 0.
-- Razon tecnica (ADR-06 / SPEC §4.7):
--   La funcion current_setting('app.current_admin_id', TRUE) con missing_ok=TRUE
--   retorna NULL cuando la variable no existe en la sesion. Si la politica RLS usa:
--     USING (auth.uid() = current_setting('app.current_admin_id', TRUE)::uuid)
--   entonces cuando current_setting retorna NULL, la comparacion es NULL = auth.uid()
--   que resulta en UNKNOWN (no TRUE), denegando acceso — comportamiento correcto.
--   Sin embargo, si la politica omite el ::uuid cast o usa IS NOT DISTINCT FROM,
--   el comportamiento puede variar. El COALESCE explicito:
--     USING (auth.uid() = COALESCE(current_setting('app.current_admin_id', TRUE), '')::uuid)
--   falla con error de cast si '' no es UUID valido, lo cual tambien deniega acceso.
--   La presencia de 'coalesce' en el calificador es la implementacion canonica
--   que documenta el intento de guardia explicita contra NULL, facilitando auditoria.
-- Criterio de paso GREEN: al menos una politica de draws contiene 'coalesce' en su qual
-- ---------------------------------------------------------------------------
SELECT ok(
    (
        SELECT COUNT(*)::integer > 0
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename  = 'draws'
          AND lower(qual) LIKE '%coalesce%'
    ),
    'SEGURIDAD RED: la politica RLS de draws debe usar COALESCE en su calificador (qual) para guardia contra NULL (ADR-06)'
);

-- CLEANUP: ROLLBACK garantiza que ningun efecto de set_config persiste mas alla
-- de esta transaccion. Los datos de prueba no contaminan el estado de la BD.
-- El flag set_config con is_local=TRUE ya limita la variable a esta transaccion,
-- pero el ROLLBACK explicito es la garantia definitiva de aislamiento.
SELECT * FROM finish();

ROLLBACK;

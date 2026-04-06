# CLAUDE.md: DonTolto

Este archivo provee orientación a Claude Code (claude.ai/code) al trabajar con el código del proyecto **DonTolto** (Simulación y Analítica Predictiva para Baloto/Revancha).

## Stack Tecnológico

| Capa               | Tecnología                                                            |
| ------------------ | --------------------------------------------------------------------- |
| **Frontend (UI)**  | Next.js 16+, TypeScript 6+, Tailwind 4, Supabase Realtime             |
| **Motor (Engine)** | Python 3.12+, NumPy (Vectorización), Pandera/Pydantic, GitHub Actions |
| **Base de Datos**  | Supabase (PostgreSQL 16), pg_cron, pg_net, PostgREST                  |
| **Orquestación**   | Supabase Edge Functions (Deno), GitHub API, Redis (Upstash)           |
| **Notificaciones** | Resend API (Emails proactivos), Dashboard Realtime                    |

## Arquitectura

Arquitectura de **Capas Desacopladas y Orquestada (Serverless Orchestrated)**:

```
[ Frontend (Next.js 16) ] <---> [ Supabase (Capa de Datos & Realtime) ]
                                      ^              |
                                      |      [ Edge Functions / Triggers ]
                                      |              |
                                      |      [ GitHub Actions (Python Engine) ]
                                      |______________|
```

- **Engine Python**: Efímero (GHA), procesamiento pesado (1M escenarios), scraping y validación.
- **Supabase**: Persistencia, lógica de Benchmarking (SQL Triggers), y orquestación de disparos.
- **Next.js**: Visualización de KPIs, carga manual con Double-Entry y monitoreo de salud.

## Esquema de Base de Datos Principal

Tablas clave en Supabase:
- `draws`: Historial oficial de sorteos (Baloto/Revancha).
- `projections`: Pool de 1,802 combinaciones por sorteo (Caliente, Fría, Elite, Real, etc.).
- `performance`: Cálculo de aciertos y puntajes ponderados (hits + 10 si SB).
- `manual_verification_queue`: Cola de entrada doble para validación manual de sorteos.
- `sync_locks`: Semáforo atómico para evitar condiciones de carrera en el Engine.
- `system_logs`: Trazabilidad total mediante `run_id` (UUID).
- `strategies_metadata`: Definición y versionamiento de algoritmos.

## Reglas de Ejecución y Seguridad

- **Sincronización Automática**: Martes, Jueves y Domingos 1:30 am COT (GHA).
- **Atomic Locking**: El motor debe adquirir el lock en `sync_locks` antes de iniciar. TTL de 60 min.
- **Validación Hardened**: Uso obligatorio de **Pandera** en Python para validar tipos y rangos de números antes de persistir.
- **Fail-Safe Elite**: Si la simulación de la **Estrategia Real** supera los 23 minutos, debe heredar automáticamente la **Estrategia Elite**. Timeout total GHA: 25 min.
- **Double-Entry Validation**: Los sorteos cargados manualmente requieren dos entradas idénticas de un Admin para ser promocionados a la tabla maestra.
- **Trazabilidad**: Todo registro debe nacer con un `run_id` único generado en el trigger inicial.

## Contrato de Errores y Logs

- Todos los logs deben escribirse en la tabla `system_logs`.
- Niveles: `info`, `warning`, `error`, `critical`.
- Alertas: Los errores críticos en el Scraper o Engine disparan un email vía **Resend** y notifican en tiempo real al Dashboard.

## Fases de Implementación (Mapa de Ruta)

0.  **Fase 0: Auditoría y Gobernanza** — Cierre de Alcance, Diseño de Arquitectura y Plan Maestro.
1.  **Fase 1: Infraestructura** — Setup de Supabase, RLS, Edge Functions, Redis y GHA Trigger.
2.  **Fase 2: Datos Históricos** — Scraping desde Mayo 2021, Double-Entry UI y validación Pandera.
3.  **Fase 3: El Cerebro (Engine)** — Simulador NumPy (1M runs), Backtesting SQL y lógica de Stress.
4.  **Fase 4: Dashboard Premium** — Visualización de Deltas (Meta: > 0.05), KPIs y Observabilidad.


## Reglas de Comportamiento y Gobernanza

1.  **Mentalidad de Auditor (Devil's Advocate)**: El agente debe cuestionar proactivamente la lógica, los requerimientos y la arquitectura en busca de vacíos, contradicciones o "falsas negativas". No aceptes tareas mal definidas o con "magia técnica".
2.  **Soberanía Documental (SDD)**: El código es un reflejo **estricto** de la documentación. Se prohíbe escribir código funcional sin que existan —y estén autorizados— el PRD, SPEC, PLAN y TASK de la etapa correspondiente.
3.  **No Improvisar (Workflows)**: Utiliza siempre los agentes y habilidades especializados. No inventes flujos de ejecución fuera de los definidos en `.agents/workflows/` o en `.claude/agents/`.
4.  **Cadena de Confianza (Tokens)**: El inicio de cualquier etapa de desarrollo o diseño está condicionado a un token en estado **`AUTORIZADO`**. Sin el sello verde, el sistema se considera bloqueado.
5.  **Control de Cambios (CC)**: Toda modificación a documentos de gobernanza global (`Scope`, `Architecture`, `Plan`) o a etapas ya cerradas debe ser autorizada mediante un **Control de Cambios** formal (`/change-control`).

## Documentos de gobernanza

Los documentos de gobernanza están en `docs/governance/`:
- `PROJECT_scope.md` — Requerimientos de negocio y criterios de aceptación (v1.5.0 Final)
- `PROJECT_architecture.md` — Arquitectura técnica y contratos de API (v1.5.0 Production-Ready)
- `PROJECT_plan.md` — Hoja de ruta e implementación por fases (v1.6.1 Authorized)
- `PROJECT_ui_kit.md` — Sistema de diseño, paleta de colores y reglas estéticas (v1.1.0)
- `docs/references/process.md` — Protocolo de gobernanza de la Agencia y flujo de tokens.


## Agencia de Software Autónoma (Agentes Especializados)

El proyecto es ejecutado por una agencia de **16 agentes especializados** orquestados sistemáticamente. 
**Es OBLIGATORIO consultar el router antes de delegar cualquier tarea:**
👉 **Consultar Router**: [.claude/agents-router.md](file:///c:/Users/USUARIO/Documents/Work/DonTolto/.claude/agents-router.md)

**Protocolo de Uso:**
1. **Identificar Dominio**: Buscar en el router el agente responsable del archivo o tecnología.
2. **Invocar Agente/Skill**: Delegar la tarea al archivo de instrucciones del agente o usar su comando de skill.
3. **Pipeline de Calidad**: Todo desarrollo técnico sigue obligatoriamente el flujo: `Coder` → `Tester` → `Reviewer`.
4. **Cierre de Etapa**: Requiere el visado de cumplimiento del `stage-auditor` y la notaría del `stage-closer`.

## Mandatos Globales de Calidad
- **TDD (Test-Driven Development)**: Es obligatorio crear pruebas unitarias antes de la lógica funcional siguiendo el ciclo:
    - **RED (Tester)**: Se escribe una prueba unitaria (especificada en la SPEC y desglosada como tarea en la TASK LIST) que falla porque la funcionalidad aún no existe.
    - **GREEN (Coder)**: Se escribe el código mínimo necesario en `src/` para que la prueba pase.
    - **REFACTOR (Coder/Architect)**: Se limpia el código y se optimiza sin romper la prueba activa.
- **Limpieza de Código**: El código debe seguir principios de Clean Code y ser autodocumentado.
- **Seguridad por Diseño**: Todas las capas (Persistencia, Lógica, UI) deben implementar validaciones y seguridad de forma nativa.
- **Ambiente virtual obligatorio**: Nunca instalar en Python global. Agregar dependencia antes de usarla en código
al archivo 'requirements.txt' y ejecutar 'pip install -r requirements.txt'.

## Protocolo de Control de Cambios (CC)

Gestionado por el agente `change-controller` bajo la regla del proyecto en `.agents/rules/changes-control.md`. Es obligatorio para cualquier modificación a la Gobernanza Global (`docs/governance/`) o a documentos de diseño de etapas ya cerradas.
- **Invariante**: Ningún cambio estructural se ejecuta sin registrarse en el índice maestro de `.agents/rules/changes-control.md` y poseer un documento `CC_XXXXX.md` en la carpeta `docs/changes/` en estado `✅ Aprobado`.

## Metodología Spec-Driven Development (SDD)

Proceso lineal y obligatorio de diseño para cada etapa del proyecto (ubicada en `docs/f[F]_[E]/`):
1.  **PRD** — QUÉ: Definición de métricas de éxito y requerimientos de negocio.
2.  **SPEC** — CÓMO: Definición de contratos, interfaces y lógica algorítmica/negocio.
3.  **PLAN** — CUÁNDO: Estrategia de implementación y casos de prueba.
4.  **TASK** — ACCIÓN: Checklist técnico granular para ejecución por agentes.


## Cadena de Validación (Tokens)
Cada documento SDD debe ser auditado con mentalidad de **Abogado del Diablo** y poseer un token `AUTORIZADO` en `docs/f[F]_[E]/audit/sdd/` para permitir el inicio del siguiente paso en la cadena.

### Resolución de Conflictos y Brechas
- **Prevalencia**: `Scope > Architecture > Plan > SDD Local (PRD/SPEC)`.
- **Detección de Vacíos (Gaps)**: Si una etapa carece de definición técnica suficiente, el agente tiene la **obligación de detenerse**. No se permite la improvisación de lógica de negocio en la fase de codificación.

## Flujo de Trabajo (Git)

### Estrategia de Ramas
- **`main`** — Rama estable. Solo código verificado.
- **`dev`** — Rama de desarrollo e integración. Cambios en progreso.
- **`feat/f[F]_[E]_*`** — Ramas de funcionalidad por etapa. **Obligatorias**.
- **Protección**: Prohibido el desarrollo de código o docs SDD directamente en `main` o `dev`. Uso obligatorio de Rama de Funcionalidad.

### Commits
Formato atómico en español: `feat:` | `fix:` | `docs:` | `refactor:` | `chore:`
**Ejemplo**: `feat: motor de estrategias con redistribución meritocrática`

## Convenciones de Idioma

- **Código / Archivos / Carpetas**: Inglés (`snake_case` archivos, `CamelCase` clases).
- **Documentación / Comentarios / Commits**: Español.
- **Interfaz (UI) / Salida al Usuario**: Español.
- **Variables / Funciones en el Código**: Inglés.


## Protocolo de Inicio y Cierre

### **Al Iniciar (Orden Obligatorio):**
1.  **Leer `CLAUDE.md`** (Gobernanza central).
2.  **Leer `.claude/agents-router.md`** (Mapa de delegación a subagentes).
3.  **Leer `PROJECT_handoff.md`** — Estado macro y táctico del proyecto.
4.  **Leer `docs/lessons/lessons-learned.md`** — Solo sección de etapa activa.
  
### **Al Iniciar (Consultas de Referencia):**
1.  **Leer `docs/references/process.md`** — Protocolo de flujo de tokens y roles de agentes.
2.  **Leer `docs/changes/`** — Solo CCs en estado `✅ Aprobado`.
3.  **Leer `docs/database/schema.sql`** — Esquema actual de Supabase.

### **Al Cerrar sesión técnica (Garantía de Continuidad):**
1.  **Reescribir `PROJECT_handoff.md`**: Actualizar con archivos modificados, contexto inmediato, último error/bloqueador y próxima acción concreta.
2.  **Actualizar `docs/lessons/lessons-learned.md`**: Registrar hitos o descubrimientos críticos. **Prohibido sobrescribir lecciones anteriores**.
3.  **Asegurar** que el código pase los tests de la etapa actual (**TDD**).

### **Al Finalizar una ETAPA (Cierre de Hito):**
1.  **Crear/Actualizar `docs/executives/f[F]_[E]_executive.md`**: Resumir logros, métricas técnicas y estado final de la etapa. **Este documento es la única prueba de cierre**.
2.  **Actualizar el Indicador de Progreso** en la cabecera del siguiente prompt o handoff.
3.  **Solicitar aprobación del usuario** para pasar a la siguiente etapa del `PROJECT_plan.md`.

## Indicador de Progreso del Proyecto

```
E_total = Σ etapas de todas las fases (contar desde la tabla de abajo)
C       = número de archivos docs/executives/f*_executive.md existentes
Progreso Total = (C / E_total) × 100%
```

- **Nunca hardcodear** `E_total` — siempre contar dinámicamente desde la tabla del mapa de ruta.
- **Fuente de verdad de cierre**: La existencia de `docs/executives/f[F]_[E]_executive.md` marca la etapa como oficialmente terminada.
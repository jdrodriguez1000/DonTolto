# Protocolo de Gobernanza y Desarrollo — Proyecto DonTolto

Este documento define el flujo de trabajo estricto de la **Agencia de Software Autónoma**. Ninguna línea de código o cambio estructural es válido si no sigue este proceso de paso de tokens y validaciones cruzadas.

---

## 🏛️ 1. Arquitectura de la Agencia (16 Agentes)

La agencia opera en **4 Capas de Especialidad** coordinadas por Claude Code.

### Capa 1: Gestión y Gobernanza (Executive)
*   **`db-manager`**: Única autoridad sobre el esquema Supabase (Postgres 16) y migraciones.
*   **`stage-auditor`**: Juez final técnico de etapas; gatekeeper del DoD.
*   **`stage-closer`**: Notario de negocio; redacta resúmenes ejecutivos en `docs/executives/`.
*   **`session-closer`**: Archivista del estado del proyecto (Handoff) y lecciones aprendidas.

### Capa 2: Pipeline Técnico de Engine (Python 3.12)
*   **`backend-coder`** → **`backend-tester`** → **`backend-reviewer`**
*   **Tokens**: `coder_token.md` → `tester_token.md` → `reviewer_token.md`.
*   **Propósito**: Simulador NumPy (1M runs), Scraping, validación Pandera y Lógica de Engine.

### Capa 3: Pipeline Técnico de UI (Next.js 16)
*   **`frontend-coder`** → **`frontend-tester`** → **`frontend-reviewer`**
*   **Tokens**: `coder_token.md` → `tester_token.md` → `reviewer_token.md`.
*   **Propósito**: Dashboard Premium, Visualización de Deltas y Double-Entry manual.

### Capa 4: Seniors y Consultores Transversales (Advisory)
*   **`integration-tester`**: Certificación final E2E (Playwright).
*   **`security-hardener`**: Blindaje OWASP y RLS de Supabase.
*   **`ui-consistency-manager`**: Guardián del Design System y Estética Premium.
*   **`gdpr-compliance-officer`**: Cumplimiento de privacidad y purgas de 30 días.
*   **`devops-integrator`**: Orquestación GitHub Actions y CI/CD.
*   **`integration-mediator`**: Árbitro de contratos OpenAPI (Engine-UI sync).

---

## 🚀 2. Flujo de Desarrollo (Pase de Pasaporte)

Cada tarea técnica `[TSK]` sigue un pasaporte de validación obligatorio:

### Fase A: Codificación (Coder)
1.  El Coder lee la SPEC y la Tarea de la etapa (`docs/f[F]_[E]/task_list.md`).
2.  Implementa la lógica (Engine o UI).
3.  Genera `[backend/frontend]_coder_token.md` en la carpeta de auditoría de la etapa.

### Fase B: Validación Funcional (Tester)
1.  El Tester detecta el token del Coder.
2.  Ejecuta Pytest (Engine) o Vitest/Testing Library (UI).
3.  Si falla: Genera `BLOQUEO_report.md` → Vuelve al Coder.
4.  Si pasa: Genera `[backend/frontend]_tester_token.md` (CONFORME).

### Fase C: Auditoría Técnica (Reviewer)
1.  El Reviewer detecta el token del Tester.
2.  Realiza el Code Review (Seguridad, Calidad, Estándares de DonTolto).
3.  Si falla: Genera `RECHAZADO` → Vuelve al Coder.
4.  Si pasa: Genera `[backend/frontend]_reviewer_token.md` (APROBADO).
5.  **Único Punto de Cierre**: El Reviewer marca la tarea `[x]` en el `task_list.md`.

---

## 🧪 3. Proceso de Integración y Cierre de Etapa

Cuando todas las tareas `[TSK]` de una etapa están marcadas como `[x]`:

1.  **Arbitraje de Contrato**: El `integration-mediator` valida que el Engine y la UI estén sincronizados.
2.  **Blindaje**: El `security-hardener` y `gdpr-compliance-officer` emiten sus certificados en el pipeline de auditoría.
3.  **Prueba de Fuego (E2E)**: El `integration-tester` ejecuta el flujo completo en el entorno de integración.
4.  **Auditoría de Etapa**: El `stage-auditor` revisa toda la evidencia anterior (Tokens de Coder, Tester, Reviewer y Especialistas). Si todo es correcto, emite el `audit_token.md` (Nivel 5).
5.  **Cierre Formal**: El `stage-closer` genera el Resumen Ejecutivo en `docs/executives/` y archiva los tokens temporales.

---

## 💾 4. Protocolo de Cierre de Sesión

Al terminar la interacción con el usuario (Fin de jornada):
1.  **`session-closer`** es invocado automáticamente.
2.  **Paso 1 (Handoff)**: Actualiza `PROJECT_handoff.md` con el estado táctico preciso.
3.  **Paso 2 (Lecciones)**: Registra éxitos y "lessons learned" en `docs/lessons/lessons-learned.md`.

---

## ⚖️ 5. Reglas de Inmodificabilidad

-   **Pipeline Secuencial**: Ningún agente puede saltarse el orden (Coder → Tester → Reviewer).
-   **Sin Tareas Sueltas**: No se puede cerrar una etapa si queda una tarea `[ ]` sin el veredicto del Reviewer.
-   **Base de Datos Sagrada**: El esquema de Supabase solo puede ser modificado mediante migraciones gestionadas por `db-manager`.
-   **Tokens Centralizados**: Los tokens deben residir siempre en `docs/f[F]_[E]/audit/pipeline/`.

---

> Este proceso es la ley del proyecto DonTolto. Cualquier desviación será detectada y bloqueada por el `stage-auditor`.

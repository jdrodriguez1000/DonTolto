# PROJECT_plan.md: DonTolto (Plan Maestro de Ejecución)

---
**Estado**: `APROBADO` (Hardened Level 7 - Authorized)
**Fecha**: 2026-04-06
**PM**: Antigravity (Senior Project Manager)
---

## 🎯 Visión del Plan
Este plan estructura el desarrollo de **DonTolto** en 5 fases (0-4), priorizando la cimentación de datos y la inteligencia estadística. Se establece un modelo de ejecución colaborativa entre agentes de IA (**Antigravity** como orquestador y **Claude Code** como ejecutor de precision técnica).

---

## 🗓️ Cronograma de Fases

### Fase 0: Auditoría, Estrategia y Gobernanza (Actualidad)
*Objetivo: Definir el mapa de ruta, arquitectura y protocolos de confianza.*

| Etapa | Descripción | Entregable Principal | Agentes |
| :--- | :--- | :--- | :--- |
| **0.1** | **Cierre de Alcance (Business)** | `PROJECT_scope.md` y `scope_token.md` autorizados. | Antigravity |
| **0.2** | **Diseño de Arquitectura** | `PROJECT_architecture.md` y `architecture_token.md` (Devil's Advocate). | Antigravity |
| **0.3** | **Plan Maestro y Tokens** | `PROJECT_plan.md` y `plan_token.md` consolidados. | Antigravity |
| **0.4** | **Gobernanza de Agentes** | Setup de reglas (.cursorrules). **Protocolo Antigravity (Solo)** como fallback de Claude Code. | Antigravity |

### Fase 1: Infraestructura de Datos (Cimentación)
*Objetivo: Establecer el cerebro persistente y los mecanismos de seguridad.*

| Etapa | Descripción | Entregable Principal | Agentes |
| :--- | :--- | :--- | :--- |
| **1.0** | **Validación de Entorno** | Script `check_env.py` (Supabase: `pg_cron`, `uuid-ossp`). | Auditor |
| **1.1** | **Setup de Supabase & DDL** | Esquema SQL completo con RLS y extensiones habilitadas. | Coder |
| **1.2** | **Bóveda de Seguridad** | Configuración de Secrets en GH Actions, Auth de Admin y **API de Resend**. | Coder, Tester |
| **1.3** | **Orquestador GHA-Trigger** | Edge Function con Rate Limit y Dispatch a GitHub API (con `run_id`). | Coder |
| **1.4** | **Configuración de Cron Jobs** | Programación de `pg_cron` para Cleanup y Sincronización Automática. | Coder, Auditor |
| **1.5** | **Carga de Semilla** | Inserción de `strategies_metadata` y configuración inicial (Seed). | Coder, Auditor |
| **1.6** | **Setup de Redis (Upstash)** | Configuración de instancia de Redis para Rate Limit en Edge Functions. | Coder |
| **1.7** | **DB Footprint Analysis** | Cálculo de volumen de proyecciones para evitar límites de Supabase. | Auditor, Coder |

### Fase 2: Adquisición y Sincronización Histórica
*Objetivo: Alimentar el sistema con datos reales desde Mayo de 2021.*

| Etapa | Descripción | Entregable Principal | Agentes |
| :--- | :--- | :--- | :--- |
| **2.0** | **Batch Scraping (Histórico)** | Ingesta por lotes (Checkpoint por año) desde 01/05/2021. | Coder, Tester |
| **2.1** | **Scraper Python (Draw-to-Draw)** | Motor de extracción diaria con validación científica Pandera. | Coder |
| **2.2** | **Pipeline de Sincronización** | GHA Workflow con política de **Exponential Backoff** para Supabase. | Coder |
| **2.3** | **Manual Verification UI** | Flujo de Double-Entry (RPC `verify_and_promote`) en UI. | Coder |
| **2.4** | **UAT Error Provocado** | Prueba de conflicto en carga manual para validar blindaje de integridad. | Auditor, Tester |
| **2.5** | **Blindaje de Discrepancia** | Lógica de prioridad (Manual > Scraper) para resolver datos contradictorios. | Coder, Auditor |
| **2.6** | **Throttling & Checkpoint** | Motor de scraping con reintentos inteligentes y persistencia de avance. | Coder |

### Fase 3: Inteligencia y Generación (The Simplified Brain)
*Objetivo: Ejecutar la lógica de selección boutique de 30 juegos por estrategia.*

| Etapa | Descripción | Entregable Principal | Agentes |
| :--- | :--- | :--- | :--- |
| **3.0** | **Diseño de Algoritmos** | Lógica de selección Élite (Frecuencia, Sinergia, Gap). | Coder |
| **3.1** | **Generador Multiestrategia** | Módulo Python para generar los 30 juegos x 7 tipos. | Coder, Tester |
| **3.2** | **Selector de Estrategia Real** | Lógica de herencia del top performer de la Élite. | Coder, Auditor |
| **3.3** | **Backtesting Nativo DB** | Triggers SQL para cálculo automático de performance. | Coder |
| **3.4** | **Calibración Histórica** | Procesamiento de 5 años para KPIs iniciales. | Coder, Auditor |
| **3.5** | **Optimización de Costos** | Validación de ejecución del motor (< 5 min). | Auditor |
| **3.6** | **Engine Lock (Docker)** | Containerización del Motor para paridad Local-GHA. | Coder |
| **3.7** | **Criptografía Forense** | Firmado digital HMAC de proyecciones. | Coder, Auditor |

---

> **Control de Cambio:** Este archivo fue modificado por CC_001 (2026-04-09).
### Fase 4: Dashboard y Observabilidad (UI Premium)
*Objetivo: Visualizar el éxito y monitorear la salud del sistema.*

| Etapa | Descripción | Entregable Principal | Agentes |
| :--- | :--- | :--- | :--- |
| **4.1** | **Dashboard Analítico** | Interfaz Next.js con KPIs, Deltas y tendencia de aciertos. | Coder, Tester |
| **4.2** | **Centro de Control Realtime** | Notificaciones vía `system_logs` (Supabase Realtime) y **Resend API**. | Coder |
| **4.3** | **Diseño de Alertas** | Definición y validación de templates de error en **Resend.com**. | Coder, Auditor |
| **4.4** | **Cierre y Entrega Final** | Auditoría final de tokens y documentación de usuario único. | Auditor |
| **4.5** | **Ops Init** | Configuración de alertas de salud en `v_system_health`. | Auditor |
| **4.6** | **Vistas Materializadas** | Agregación escalable de ~3M de registros para Dashboards instantáneos. | Coder, Auditor |
| **4.7** | **Disaster Recovery (DR)** | Protocolo y script de exportación/backup externo a Supabase Cloud. | Auditor, Coder |

---

## 🚀 Ruta Crítica y Bloqueos
| **Blocker 0** | Disponibilidad de `ADMIN_UUID` y Keys de Supabase. |
| **Blocker 1** | Estabilidad de las extensiones `pg_cron` en el entorno de Supabase. |
| **Blocker 2** | Precisión del Scraper ante cambios de DOM (Requiere monitoreo proactivo). |
| **Blocker 3** | Permisos de Escritura de `GITHUB_TOKEN` para ejecutar workflows de emergencia. |

---

## 🛠️ Entregables Auxiliares (Soporte Técnico)
- **Engine Logs**: Trazabilidad por `run_id` en `system_logs`.
- **Unit Tests**: Cobertura > 90% en la lógica de simulación NumPy.
- **Security Audit**: Validación de RLS para evitar fugas de datos de proyecciones.

---

## ✅ Definition of Done (DoD) Global
El proyecto se considera finalizado cuando:
1.  El sistema ejecuta el ciclo completo (Scrape -> Sim -> Persist -> Benchmark) sin intervención humana.
2.  El Dashboard muestra un **Delta funcional** calculado sobre al menos **10 sorteos reales continuos**.
3.  La **Estrategia Real** existe y está vinculada a una firma de `run_id` válida.
4.  El sistema de notificaciones vía Resend alerta correctamente ante un fallo inducido.
5.  Los jobs de `pg_cron` están activos y rotando logs de forma autónoma.

---
**Firma del PM:**
*Antigravity (Senior Project Manager)*

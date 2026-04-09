# PROJECT_scope.md: DonTolto (Gobernanza de Alcance)

---
**Estado**: `ACTIVO` (Cierre de Alcance)
**Fecha**: 2026-04-05
**Analista**: Antigravity (Senior Business Analyst)
---

## 🎯 Objetivo General
Desarrollar un ecosistema automatizado de simulación, benchmarking y analítica predictiva para los sorteos de **Baloto** y **Revancha** en Colombia, optimizando la toma de decisiones mediante un **Motor de Estrés Estadístico Ponderado** (vectorización pura). El sistema está diseñado para un **usuario único**.

---

## 🧩 Bloques de Funcionalidad (Features)

### 1. Motor de Sincronización (Fase A)
*   **Scraping Automatizado**: El sistema debe extraer del sitio oficial de Baloto (o fuente externa) el último sorteo real (números + superbalota).
*   **Gestión de Errores**: Sistema de alertas si el DOM de la página cambia. En caso de fallo crítico en el Scraper, el sistema enviará una **Notificación Proactiva vía Email** al administrador. Se habilitará una **Interfaz de Carga Manual** en el Dashboard con un sistema de **Doble Registro (Double-Entry Validation)**. **Post-Carga**: El sistema ejecutará un **reintento automático** de los motores de Evaluación y Generación inmediatamente después de una validación manual exitosa para asegurar la continuidad del ciclo.
*   **Histórico Completo**: Se mantendrá el histórico desde el **1 de mayo de 2021** (aprox. 6 registros nuevos por semana entre Baloto y Revancha).
*   **Cold Start (Semilla)**: Durante los primeros 3 meses (o hasta tener historial suficiente para benchmarking), la **Estrategia Real** heredará la lógica de la **Estrategia Élite** para evitar fallos por falta de datos.
*   **Archivado de Proyecciones**: Las proyecciones antiguas se moverán a una tabla de **Histórico de Benchmarking** (Rendimiento) para permitir análisis retrospectivo de largo plazo. La tabla operativa mantendrá solo el sorteo vigente con **428 combinaciones** [(210 de estrategias + 2 Real + 2 Única) x 2 tipos (Baloto/Revancha)].

### 2. Motor de Benchmarking (Evaluación)
*   **Comparativa Técnica**: Contraste de los 1,802 juegos proyectados en el ciclo anterior contra el sorteo real recién descargado.
*   **Ranking de Estrategias**: Cálculo de aciertos ponderados identificando las líderes basadas en el desempeño de los **últimos 3 meses** (Ventana de Memoria Móvil).

### 3. Motor de Generación (Fase B)
*   **Algoritmo Élite**: Selección de combinaciones basada en Frecuencia (30%), Intervalo/Gap (30%), Sinergia (20%) y Paridad (20%). Genera un pool de **30 juegos** optimizados.
*   **Modelo de Selección Real**: 
    *   **Generación de Candidato**: Se selecciona la **mejor combinación única** de la Estrategia Élite basada en el rendimiento de los últimos 3 meses.
    *   **Fail-Safe Élite**: Si el proceso de generación falla por cualquier motivo, la **Estrategia Real** heredará la primera combinación válida del pool Élite.
*   **Carga de Proyecciones**: Inserción de las 424 nuevas proyecciones en Supabase para el próximo draw.

### 4. Dashboards de Analítica
*   Interfaz Next.js para visualizar el acumulado de aciertos de cada estrategia en tiempo real.
*   **Centro de Notificaciones**: Alerta visible en la página principal y **envío de Email de Alerta** si ocurre un fallo crítico en el Motor de Sincronización o Generación.

---

## 👥 Historias de Usuario (User Stories)

| ID | Historia de Usuario | Criterios de Aceptación (AC) |
| :--- | :--- | :--- |
| **US-01** | **COMO** Administrador **QUIERO** extraer los sorteos reales (Scraping/Manual) **PARA** alimentar el histórico sin errores. | 1. Captura 5-números (1-43) y Superbalota (1-16). 2. Notificación en Dashboard y Email si falla el selector HTML. 3. **Carga Manual**: Requerir doble entrada coincidente para validación. |
| **US-02** | **COMO** Estratega **QUIERO** generar la **Estrategia Real** como la mejor opción de la Élite **PARA** optimizar el éxito esperado. | 1. Obtención del ranking de estrategias. 2. Selección del top de la Estrategia Élite. 3. Persistencia de 1 combinación para Baloto y 1 para Revancha. |
| **US-03** | **COMO** Administrador **QUIERO** mantener un histórico robusto **PARA** asegurar la calidad de las simulaciones futuras. | 1. Retención total de sorteos desde el 01/05/2021. 2. Purgado automático de la tabla de "proyecciones" antiguas tras cada sorteo. |
| **US-04** | **COMO** Usuario Final **QUIERO** ver el KPI de éxito de la **Estrategia Real** **PARA** validar el rendimiento contra el azar. | 1. Gráfica de tendencia de aciertos. 2. Comparativo de **Promedio de Aciertos > 15%** contra la Estrategia Aleatoria en la categoría SB+Números. |

---

## 🚧 Fuera de Alcance (Out of Scope)
*   Integración con pasarelas de pago o apuestas reales automáticas.
*   Predicciones para sorteos distintos a Baloto y Revancha (Loterías regionales).
*   Manejo proactivo de cambios de formato (Se tratará reactivamente en el momento del cambio). No se implementará "Estado de Emergencia" automatizado.
*   App móvil nativa (Solo acceso vía PWA/Web Dashboard).

---

## 📊 Matriz de Estrategias (Revisada)
| Estrategia | Cantidad | Lógica |
| :--- | :---: | :--- |
| **🔥 Caliente** | 30 | Pool de los más frecuentes (últimos 50). |
| **❄️ Fría** | 30 | Pool de los menos frecuentes (últimos 50). |
| **🎲 Aleatoria** | 30 | Azar puro (Grupo de Control). |
| **💎 Élite** | 30 | Algoritmo de Puntuación Ponderada. |
| **⚖️ Balanceada** | 30 | 2 Calientes + 2 Fríos + 1 Aleatorio. |
| **🧬 Mixta** | 30 | 80% Líder actual + 20% Segundo líder. |
| **🤝 Afinidad** | 30 | Grupos de números que suelen salir juntos (Correlación). |
| **📌 Única** | 1 | Combinación fija permanente (Manual). |
| **⚡ Real** | **1** | **Top performer de la Estrategia Élite.** |
| **TOTAL** | **214** | (x2 para Baloto + Revancha = 428 total) |

---

> **Control de Cambio:** Este archivo fue modificado por CC_001 (2026-04-09).
---

## 📉 Criterio de Éxito
Se considerará el proyecto exitoso si la **Estrategia Real** logra mantener un **rendimiento superior en 5 puntos porcentuales** (Delta > 0.05 absoluto) al porcentaje de aciertos de la **Estrategia Aleatoria** en categorías que incluyan **Números Principales + Superbalota** (ej: 1+SB, 2+SB, etc.) de forma consistente durante la ventana de los **últimos 3 meses de sorteos**.

---

> **Control de Cambio:** Este archivo fue modificado por CC_002 (2026-04-09) para sincronizar el volumen de 428 registros y definir el protocolo de Fallback de Continuidad ante omisión de validación manual.

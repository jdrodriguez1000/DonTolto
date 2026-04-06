# 🛡️ Ley de Higiene de Git y Protección de Ramas

Esta regla define los estándares obligatorios de branching para asegurar que las ramas estables (`main` y `dev`) nunca sean comprometidas por trabajos en progreso.

---

## 🚫 1. Protección de Ramas Estables (`main` / `dev`)

Se prohíbe terminantemente realizar cualquiera de las siguientes acciones estando en las ramas `main` o `dev`:
1.  **Creación de Documentos SDD**: PRD, SPEC, Plan o Task de una etapa específica.
2.  **Modificación de Código Funcional**: Cualquier cambio en `src/`, `app/` o lógica de negocio central.
3.  **Ejecución de Tests de Etapa**: No se deben correr tests de funcionalidad nueva en ramas estables.

**Excepción**: Solo los cambios de Gobernanza global (`CLAUDE.md`, `docs/governance/`) se pueden documentar directamente en `main` bajo un Control de Cambios (CC) aprobado con prefijo `docs:`.

---

## 🏗️ 2. Protocolo de Inicio de Etapa (Paso 0)

Antes de iniciar cualquier flujo SDD (PRD, SPEC, PLAN o TASK), el agente **DEBE**:
1.  **Verificar Rama Actual**: Si es `main` o `dev`, el agente debe detenerse.
2.  **Proponer Rama de Funcionalidad**: Basada en la Fase [F] y Etapa [E] de `CLAUDE.md`.
    - Formato: `feat/f[F]_[E]_[nombre]`
    - Ejemplo: `feat/f1_1.1_supabase_setup`

---

## 🧪 3. Procedimiento de Integración (Merge)

1.  Una vez que la etapa está terminada y validada (100% Tests Green).
2.  Se debe realizar el PR **hacia `dev`** para integración si existe, o directamente a `main` según el flujo definido en el skill `git-push`.
3.  Los mensajes de commit **DEBEN** ser en español y seguir el estándar de `CLAUDE.md`.

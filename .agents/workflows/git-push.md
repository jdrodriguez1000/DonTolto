---
description: Flujo de trabajo estructurado para manejar la subida del repositorio a GitHub y la creación de Pull Requests, alineado con la Ley de Higiene y el Plan Maestro.
---

# Workflow: Git Push y Pull Request (Gobernanza)

Este flujo garantiza que cada cambio llegue a GitHub de forma ordenada, trazable y respetando el Plan Maestro (`PROJECT_plan.md`) y las leyes de higiene del repositorio.

## Paso 0 — Verificación del Contexto del Plan
Antes de cualquier comando de Git, el agente debe:
1. **Identificar Fase y Etapa**: Consultar `docs/governance/PROJECT_plan.md` para determinar la etapa activa (ej. Fase 1, Etapa 1.1).
2. **Validar Rama SMM**: La rama debe seguir el formato de la regla `git-hygiene`: `feat/f[F]_[E]_[nombre_corto]`.
   - Ejemplo: `feat/f1_1.1_supabase_setup`

## Paso 1 — Diagnóstico de Higiene (Ley de Higiene)
Ejecuta el diagnóstico exhaustivo según la regla `git-pusher`:
```bash
git status
git remote -v
git branch -a
git log --oneline -5
```

**Auditoría de Higiene Obligatoria:**
- **Working Tree Limpio**: Si hay cambios sin commitear, **DETENTE**. El usuario debe realizar el commit siguiendo los estándares (Español + Prefijos `CLAUDE.md`).
- **Archivos Prohibidos**: Si detectas archivos como `.env`, temporales o documentos de diseño huérfanos:
  - **ACCIÓN**: Actualizar `.gitignore` y ejecutar `git rm --cached [archivo]`.
- **Protección de Ramas (`main`/`dev`)**:
  - Si estás en `main` o `dev`, **BLOQUEA** cualquier push de código funcional.
  - **Excepción**: Cambios de gobernanza (`docs:`) bajo un Control de Cambios (CC) aprobado son permitidos directamente en `main`.

## Paso 2 — Gestión del Empuje (Push)
Identifica si el remoto `origin` existe:
- **Si NO existe**: Detente y solicita la URL: "¿Cuál es la URL de tu repositorio GitHub origin?". Configúralo con `git remote add origin [URL]`.
- **Si YA existe**: Procede según el rol de la rama:

### A. Rama de Funcionalidad (`feat/*`)
1. **Validación de Mensajes**: Asegura que los commits pendientes estén en español y usen los prefijos: `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`.
2. **Sincronización**: Ejecuta `git fetch origin` para detectar colisiones.
3. **Ejecución**: `git push -u origin [rama_actual]`. Solicita confirmación explícita antes de ejecutar.

### B. Rama Principal (`main` / `dev`)
- Solo permitido para documentación global o merges autorizados. Requiere advertencia de riesgo si se detecta código funcional.

## Paso 3 — Creación de Pull Request (PR)
Si se subió una rama `feat/` de una etapa que se considera completada según el `PROJECT_plan.md`:
1. **Target**: Proponer PR hacia `dev` (si existe) o `main`.
2. **Creación**: Usar GitHub CLI (`gh pr create`) con el siguiente formato:
```markdown
## 🚀 Fase [F] - Etapa [E]: [Nombre de la Etapa]

### Qué hace este cambio
[Descripción detallada en español de la funcionalidad]

### Cumplimiento de DoD (Definition of Done)
- [ ] Cobertura de tests validada.
- [ ] Documentación SDD actualizada.
- [ ] Trazabilidad de tokens verificada.

🤖 PR generada bajo la regla git-pusher.
```

## Paso 4 — Verificación Final
Verifica que el remoto refleje el estado local: `git log --oneline origin/[rama] -3`.

Informa el éxito del ciclo:
```
✅ Ciclo de Push completado.
   Fase/Etapa:      [F].[E]
   Rama:            [nombre]
   PR Creada:       [URL si aplica]
```

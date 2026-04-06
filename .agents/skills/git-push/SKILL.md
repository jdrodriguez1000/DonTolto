---
name: git-push
description: "Sube el repositorio a GitHub respetando el Git Flow del proyecto (feat/* → main vía PR con CI). Maneja configuración de remotos y creación de PRs."
---

# Skill: git-push

Esta habilidad te dota del conocimiento técnico para gestionar el remoto y la política de ramas (Git Flow de Triple S).

## Reglas de Oro (Git Flow)

Este proyecto usa un flujo de **dos tipologías de ramas**:
- **`main` / `dev`**: Ramas estables. Prohibido trabajar directamente en ellas. Código funcional solo entra vía PR. Solo se permiten pushes directos para correcciones documentales urgentes en `docs/governance/` con prefijo `docs:`.
- **`feat/f[F]_[E]_[nombre]`**: Ramas temporales de trabajo por etapa (ej: `feat/f1_1.1_setup`).

**Flujo obligatorio:** `feat/f[F]_[E]_*` → PR → `main`

## Convenciones de Commits (Idiomas y Prefijos)
- **Idioma**: ESPAÑOL obligatorio para mensajes de commit y descripciones de PR.
- **Prefijos**:
  - `feat:` (Funcionalidad)
  - `fix:` (Corrección)
  - `docs:` (Documentación)
  * `refactor:` (Refactorización)
  * `chore:` (Tareas de mantenimiento/configuración)


## Errores Comunes y Resolución Técnica
| Error | Causa | Solución |
|---|---|---|
| `rejected — non-fast-forward` | Commit local desactualizado respecto al remoto. | Realizar `git pull origin [rama] --rebase`. Nunca uses `--force` sin advertir y confirmar expresamente. |
| `fatal: remote origin already exists` | El remoto ya está configurado. | Verifica usando `git remote -v`. |
| `error: src refspec matches...` | La rama no existe localmente. | Crearla primero o validar el switch. |
| `Permission denied (publickey)` | Autenticación SSH fallida o no presente. | Recomendar revisar claves SSH o cambiar URL a HTTPS. |
| `gh: command not found` | CLI de GitHub no instalado localmente. | Recomendar o instruir cómo abrir la PR mediante la web de GitHub. |

## Restricciones Absolutas
- **Prohibido** usar `git push --force` hacia `main` sin una advertencia roja explícita y su consecuente aprobación confirmada.
- **Prohibido** hacer un push sucio (existen cambios o stages sin amarrar a un commit).
- Si el usuario pide explícitamente saltarse el flujo, muestra una advertencia de "Ruptura de Gobernanza" y pide confirmación antes de proceder bajo su riesgo.

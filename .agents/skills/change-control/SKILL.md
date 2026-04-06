# Skill: /change-control — Control de Cambios Advanced

Gestiona el ciclo de vida completo de Controles de Cambio (CC) basándose en la regla del proyecto en `.agents/rules/changes-control.md`. 

USAR SIEMPRE que: (1) se detecte algo necesario no contemplado en los documentos SDD de la etapa activa, (2) se requiera modificar algo de una etapa ya cerrada, o (3) se requiera modificar cualquier archivo del proyecto que altere el diseño original.

---

## Sistema de Estados
```
CREAR  →  [Pendiente]  →  Usuario aprueba  →  [Aprobado]  →  Ejecutar cambios
                      →  Usuario rechaza  →  [No Aprobado]  →  No tocar nada
```

---

## Paso 0 — Identificar el modo e Invocar Regla
Infiere del contexto qué modo se necesita: `CREATE`, `APPROVE`, `REJECT` o `LIST`. 
**Referencia Obligatoria**: Consultar siempre `.agents/rules/changes-control.md` para validar los disparadores y el flujo normativo.

---

## MODO CREATE — Registrar un nuevo CC
1. **Informar la necesidad**: Presenta el cuadro resumen en el chat (Cambio, Tipo, Razón, Documentos Afectados e Implicaciones). **Detente y espera confirmación del usuario para crear el archivo.**
2. **Determinar ID**: Revisa el índice en `.agents/rules/changes-control.md` y la carpeta `docs/changes/` para el número correlativo (ej. `CC_00001`).
3. **Crear Documento**: Generar `docs/changes/CC_XXXXX.md` con la estructura oficial (Descripción, Tipo, Impacto, Documentos Afectados, Decisión y Registro de Ejecución).
4. **Actualizar Índice**: Añadir una entrada en estado **Pendiente** en la tabla §3 de `.agents/rules/changes-control.md`.
5. **Confirmar**: Reportar creación en estado **Pendiente**.

---

## MODO APPROVE — Aprobar y Ejecutar CC
1. **Leer CC**: Cargar el documento `docs/changes/CC_XXXXX.md`.
2. **Cambiar Estado**: Pasar a `✅ Aprobado` con fecha en el archivo local y en el índice de la regla `.agents/rules/changes-control.md`.
3. **Ejecutar**: Modificar los archivos descritos en la sección §4 del CC.
4. **Trazabilidad**: En cada archivo modificado (Doc o Código), añadir al final (o en comentarios de cabecera si es código):
   `> **Control de Cambio:** Este archivo fue modificado por CC_XXXXX (fecha).`
5. **Vínculo con Tokens**: Si el cambio afecta a `docs/governance/`, se debe actualizar (o invalidar para re-auditoría) el token correspondiente (`scope_token.md`, `architecture_token.md`, `plan_token.md`).
6. **Cerrar**: Actualizar §6 del CC y reportar éxito.

---

## MODO REJECT — Rechazar CC
1. **Leer CC**: Cargar el documento desde `docs/changes/`.
2. **Estado**: Pasar a `❌ No Aprobado` y registrar razón tanto en el CC como en la regla `.agents/rules/changes-control.md`.
3. **Finalizar**: No tocar ningún otro archivo.

---

## MODO LIST — Inventario de Cambios
1. **Escanear**: Leer la tabla §3 de la regla `.agents/rules/changes-control.md`.
2. **Reportar**: Presentar tabla comparativa con CC, ID, Descripción, Estado y Fecha.

---

## Reglas de Calidad
- **Jerarquía CLAUDE.md**: Los CCs deben respetar la jerarquía `Scope > Architecture > Plan`.
- **Ubicación de CCs**: Todo documento de cambio vive exclusivamente en `docs/changes/`.
- **Registro Permanente**: Los CCs rechazados se conservan tanto físicamente como en el índice.
- **Trazabilidad Bidireccional**: Obligatoria.


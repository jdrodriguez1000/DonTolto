# Token de Certificacion: Bloque 7 — Seed Sintetico
**Referencia**: TSK-F1_1.1-28.1-GREEN
**Fecha**: 2026-04-10
**Agente**: db-manager
**Estado**: AUTORIZADO

## Artefacto
`supabase/seed/seed_synthetic_428.sql` — 176 lineas, 4 bloques DML.

## Cobertura
| Bloque | Tabla | Registros | Idempotencia |
|--------|-------|-----------|--------------|
| 1 | strategies_metadata | 5 | ON CONFLICT (name, version) DO NOTHING |
| 2 | draws | 10 | ON CONFLICT (draw_date, type) DO NOTHING |
| 3 | projections | 428 | ON CONFLICT DO NOTHING (PK UUID deterministico) |
| 4 | performance | 400 | ON CONFLICT DO NOTHING (PK UUID deterministico) |

## Invariantes Validados
- fn_validate_ball_array cumplida: DISTINCT+ORDER BY+LIMIT 5 garantiza array ASC sin duplicados en [1-43].
- FK strategies_metadata: proyecciones referencian solo estrategias insertas en Bloque 1.
- FK draws: performance referencia solo draws insertados en Bloque 2.
- Status mixto: 400 'calculated' + 28 'pending' habilita prueba M6 (stress batch 428).
- Script no supera 250 lineas (limite de tarea): 176 lineas confirmadas.

## Token
CERT-B7-f1-1.1-SEED-20260410

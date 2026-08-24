# hop-guajiranet

Proyecto Apache Hop de Silver **GuajiraNet** (`silver_guajiranet`, conexión Hop `aws_rds`).

Este repositorio se reconstruyó el 2026-08-24 después de un formateo del PC. El árbol local estaba vacío; el contenido nuevo de la sesión (DDL, discovery, HPL/HWF v2) se recuperó del transcript de Cursor y de los generadores `_gen_phase2_hpl.py` / `_gen_phase3_hwf.py`.

## Qué hay

| Ruta | Contenido |
|---|---|
| `sql/silver/` | DDL 01–07 (dual-run; no ejecutar 07 entero en cutover de las 6 tablas) |
| `discovery/` | Auditorías, planes Fase 2/3, preflight, cutover Silver, compatibilidad Power BI |
| `Pipelines/` | HPL **nuevos** (persona, sucursal, contrato, plan, producto_erp, perfil, bridges, pagos, facts v2) + `dim_geografia_v2.hpl` |
| `Workflows/` | HWF unitarios v2 + `wf_actualizacion_silver_v2.hwf` |

No se ejecutó SQL contra Aurora en esas fases. Gold no se tocó.

## Qué falta (no estaba en el transcript como Write)

Los HPL/HWF **viejos** solo se leyeron en auditoría; Cursor no guarda el contenido de esas lecturas en el jsonl. Recuperarlos de backup, OneDrive o el servidor Hop (`/opt/guajiranet-etl` o el proyecto original):

- `dim_cliente.hpl`, `dim_documento.hpl`, `dim_geografia.hpl`, `dim_servicio.hpl`, `dim_tiempo.hpl`
- `fact_cartera.hpl`, `fact_facturacion.hpl`
- `wf_dim_cliente.hwf`, `wf_dim_documento.hwf`, `wf_dim_geografia.hwf`, `wf_dim_servicio.hwf`, `wf_dim_tiempo.hwf`
- `wf_fact_cartera.hwf`, `wf_fact_facturacion.hwf`, `wf_actualizacion_silver.hwf`
- `wf_delta.hwf`, `wf_historic.hwf`
- `project-config.json` y el PBIX `Guajiranet (1).pbix` si existían en la raíz

El orquestador v2 **no** está cableado a `wf_delta` / `wf_historic`. Hops deshabilitados: geo v2 (stg viejo) y facts v2 (stg viejo). Camino vivo: contrato → sucursal (salta geo); Success tras pagos.

## Regenerar HPL/HWF v2

Si tienes Python 3:

```text
python _gen_phase2_hpl.py
python _gen_phase3_hwf.py
```

`dim_geografia_v2.hpl` se mantiene a mano (grano `mabarrio`). El generador de Fase 3 escribe el orquestador con hops de geo y facts en `enabled=N` y hop directo contrato→sucursal.

Especificaciones: `discovery/silver_ddl_plan.md`, `discovery/hop_phase2_plan.md`, `discovery/hop_phase3_plan.md`, `discovery/cutover_silver_plan.md`.

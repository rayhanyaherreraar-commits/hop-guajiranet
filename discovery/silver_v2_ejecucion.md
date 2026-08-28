# Silver v2 — estado ejecutable (dual-run)

**Fecha:** 2026-08-27  
**Alcance:** dejar el Silver nuevo cargable **sin** DROP/RENAME de tablas viejas ni cutover de Power BI.  
**No se ejecutó** Apache Hop ni SQL contra Aurora desde el agente. Validar en local.

## Qué quedó listo

- Dimensiones/bridges de nombre nuevo (persona, sucursal, contrato, plan, producto ERP, perfil, 3 bridges, 2 facts de pago).
- Geo y facts homónimos en **objetos `*_v2`** (mismo grano, paralelo al Silver viejo).
- Orquestador `Workflows/wf_actualizacion_silver_v2.hwf`: dims/bridges → pagos → facturación v2 → cartera v2.

## Dual-run (nombres físicos)

| Modelo aprobado | Tabla / staging de carga ahora |
|---|---|
| `tbl_dim_geografia` | `tbl_dim_geografia_v2` / `stg_dim_geografia_v2` |
| `tbl_fact_facturacion` | `tbl_fact_facturacion_v2` / `stg_fact_facturacion_v2` |
| `tbl_fact_cartera` | `tbl_fact_cartera_v2` / `stg_fact_cartera_v2` |

El Silver viejo (`tbl_dim_cliente`, `tbl_dim_servicio`, geo/facts homónimos) **no se toca**. `wf_actualizacion_silver.hwf` sigue siendo el orquestador de producción viejo. **No** encadenar v2 en `wf_delta` / `wf_historic`.

## Correcciones de implementación

- Geo/facts v2 ya no hacen TRUNCATE/UPSERT/DELETE sobre `stg_*` / `tbl_*` viejos.
- `dim_sucursal` lookup a `tbl_dim_geografia_v2` con `COALESCE(idbarrio, 0) = id_barrio` (SK 0 real tras seed de `08`).
- UPSERT geo v2 actualiza `barrio`.
- Dedup: barrio (`DISTINCT ON idbarrio`), producto (`idproducto`), pasarela (`trpagodigital.id`).
- Contrato/plan: se descartan filas con `id` JSON vacío.
- Hops del orquestador: geo v2 **antes** de sucursal; facts v2 **después** de pagos.

## Granularidades (sin rediseño)

- DIM_PERSONA = 1 fila por NIT  
- DIM_SUCURSAL = 1 fila por `(nit, idsuc)`  
- DIM_CONTRATO = 1 fila por `idcontrato`  
- DIM_PLAN = 1 fila por `id_plan`  
- DIM_PRODUCTO_ERP = 1 fila por `id_producto`  
- DIM_GEOGRAFIA = 1 fila por `id_barrio`  
- DIM_PERFIL_CARTERA = 1 fila por `id_perfil`  
- BRG_PERSONA_UUID = `(idcliente, nit)`  
- BRG_SUCURSAL_CONTRATO = `(nit, idsuc, idcontrato)`  
- BRG_CONTRATO_PLAN = 1 fila por `idcontrato` (INNER a plan: `sk_plan` NOT NULL en DDL)  
- FACT_FACTURACION = `(idsuc, prefijo, numero, pos)`  
- FACT_CARTERA = snapshot latest-open (NK 8-upla documentada)  
- FACT_PAGO_APLICACION / FACT_PAGO_PASARELA separados  

## Riesgos conocidos (no cambiados)

- Facts con `INNER JOIN` a sucursal/persona/producto/documento/tiempo: pierden huérfanos (SK NOT NULL).
- `brg_contrato_plan` no incluye contratos sin plan en dim.
- No correr el orquestador viejo y el v2 a la vez: `stg_dim_tiempo` / `stg_dim_documento` son KEEP compartidos.
- **No ejecutar** `sql/silver/05_drop_fk.sql`, `06_create_fk.sql`, `07_drop_obsolete.sql`.

## Orden de ejecución local

1. `sql/silver/01_create_dims.sql`  
2. `sql/silver/02_create_bridges_facts.sql`  
3. `sql/silver/03_create_staging.sql`  
4. `sql/silver/04_seed_unknown_members.sql`  
5. `sql/silver/08_create_dualrun_v2.sql`  
6. Hop: `Workflows/wf_actualizacion_silver_v2.hwf` (run configuration `local`, conexión `aws_rds`)

Orden interno del orquestador:

```text
tiempo → documento → perfil → persona → brg_persona_uuid → plan → contrato
  → geo_v2 → sucursal → producto_erp
  → brg_sucursal_contrato → brg_contrato_plan
  → fact_pago_aplicacion → fact_pago_pasarela
  → fact_facturacion_v2 → fact_cartera_v2
```

## Comandos

```powershell
$env:PGPASSWORD = "<tu_password>"
psql -h <aurora_host> -U <user> -d <db> -v ON_ERROR_STOP=1 -f sql/silver/01_create_dims.sql
psql -h <aurora_host> -U <user> -d <db> -v ON_ERROR_STOP=1 -f sql/silver/02_create_bridges_facts.sql
psql -h <aurora_host> -U <user> -d <db> -v ON_ERROR_STOP=1 -f sql/silver/03_create_staging.sql
psql -h <aurora_host> -U <user> -d <db> -v ON_ERROR_STOP=1 -f sql/silver/04_seed_unknown_members.sql
psql -h <aurora_host> -U <user> -d <db> -v ON_ERROR_STOP=1 -f sql/silver/08_create_dualrun_v2.sql
```

```powershell
hop-run.bat -j hop-guajiranet -r local --file "${PROJECT_HOME}/Workflows/wf_actualizacion_silver_v2.hwf"
```

Configuración local pendiente: hostname/database de `metadata/rdbms/aws_rds.json` (no versionar secretos). En el repo esos campos pueden ir vacíos.

## Validación post-carga

```sql
SELECT 'persona' AS t, COUNT(*) FROM silver_guajiranet.tbl_dim_persona
UNION ALL SELECT 'sucursal', COUNT(*) FROM silver_guajiranet.tbl_dim_sucursal
UNION ALL SELECT 'geo_v2', COUNT(*) FROM silver_guajiranet.tbl_dim_geografia_v2
UNION ALL SELECT 'fact_v2', COUNT(*) FROM silver_guajiranet.tbl_fact_facturacion_v2
UNION ALL SELECT 'cartera_v2', COUNT(*) FROM silver_guajiranet.tbl_fact_cartera_v2;

SELECT sk_geografia, id_barrio
FROM silver_guajiranet.tbl_dim_geografia_v2
WHERE sk_geografia = 0 OR id_barrio = 0;
```

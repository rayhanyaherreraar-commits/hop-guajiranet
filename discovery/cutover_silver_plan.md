# Plan de cutover Silver (geo + facts homónimos)

**Fecha:** 2026-08-24  
**Estado:** solo plan. **No se ejecutó SQL. No se modificó HPL/HWF/DDL/Gold.**  
**Objetivo:** reemplazar las 6 tablas de **mismo nombre** sin dejar Gold inválido **después** de la ventana.  
**Máquina de estados:** Gold **no puede** apuntar al fact nuevo antes del DROP: el nombre `tbl_fact_facturacion` está ocupado. Hay **ventana de mantenimiento** (vistas caídas o vacías) entre DROP y `CREATE VIEW` post-carga.

Artefacto JSON: `discovery/cutover_silver_plan.json`.

---

## 0. Qué se reemplaza (y qué no)

| # | Objeto | Detector modelo viejo en `07` B | Gold hoy |
|---|---|---|---|
| 1 | `tbl_dim_geografia` | `id_barrio` varchar/text | Join probable vía `sk_geografia` |
| 2 | `stg_dim_geografia` | igual | no |
| 3 | `tbl_fact_facturacion` | `posicion_factura` y **no** `pos` | **sí — las 5 vistas** |
| 4 | `stg_fact_facturacion` | igual | no |
| 5 | `tbl_fact_cartera` | `sk_cliente` y **no** `idsuc` | **no** (discovery) |
| 6 | `stg_fact_cartera` | igual | no |

**No formar parte de este cutover:** `07` sección **A** (`tbl_dim_cliente` / `tbl_dim_servicio` y stg). Gold y el orquestador **viejo** aún los necesitan hasta reescribir vistas y apagar `wf_actualizacion_silver`. Correr el archivo `07` entero **rompería Gold por CASCADE** aunque el fact todavía existiera.

`07` tal como está: A y luego B, `DROP TABLE … CASCADE`. CASCADE elimina vistas Gold que dependan de esas tablas. **No ejecutar `07_drop_obsolete.sql` completo.** Solo el bloque B (o comentar A en un cambio futuro; este plan no modifica archivos).

---

## A. Vistas Gold que dependen de `tbl_fact_facturacion`

Catálogo live (discovery 2026-08-24, `model_audit` / `silver_ddl_plan.json`). **No hay `CREATE VIEW` en este repo Hop.**

Esquema: `gold_guajiranet`.

| Vista | ¿Lee `tbl_fact_facturacion`? | ¿Lee `tbl_fact_cartera`? | Uso analítico (columnas de salida conocidas) |
|---|---|---|---|
| `vw_capilaridad_servicios` | **sí** | no | categoría, plan/`nombre_plan`, clientes, municipios, barrios, facturas, ingresos |
| `vw_cobertura_geografica` | **sí** | no | departamento, municipio, barrio, clientes, facturas, servicios, valor facturado |
| `vw_comportamientos_atipicos` | **sí** (`MAX(ff.neto) > AVG(ff.neto)*2`) | no | NIT, razón social, ciudad, conteos/totales, clasificación |
| `vw_operacion_facturacion` | **sí** | no | año, mes, `nombre_mes`, geo, categoría, plan, facturas, cantidad, subtotal, IVA, neto |
| `vw_transaccionalidad_clientes` | **sí** | no | NIT, razón social, ciudad, transacciones, valor, ticket, primera/última fecha. Agrupa por **nit** (13 715), pierde `idsuc` |

Estrella **inferida** (no hay `pg_get_viewdef` guardado aquí). El Gold actual es un estrella sobre el fact viejo:

```text
tbl_fact_facturacion
  sk_cliente    → tbl_dim_cliente      (nit varchar, razonsocial, ciudad, idsuc)
  sk_servicio   → tbl_dim_servicio     (nombre_plan, categoria)
  sk_geografia  → tbl_dim_geografia    (departamento, municipio, barrio; id_barrio varchar)
  fecha_factura → tbl_dim_tiempo       (anio, mes, nombre_mes)
  (+ sk_documento / tbl_dim_documento si la vista lo usa)
```

Columnas del fact que **dejan de existir** tras 02 nuevo: `sk_cliente`, `sk_servicio`, `numero_factura`, `posicion_factura`.  
Columnas que **siguen**: `fecha_factura`, `cantidad`, `precio`, `subtotal`, `iva`, `neto`, `sk_geografia`, `sk_documento`, `sk_tiempo` (si la vista usa SK tiempo).

**Puerta dura antes de cualquier DROP:** capturar definiciones reales:

```sql
SELECT n.nspname, c.relname, c.relkind, pg_get_viewdef(c.oid, true)
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'gold_guajiranet'
  AND c.relkind IN ('v', 'm')
ORDER BY 2;
```

Más `pg_depend` (consulta §7 de `discovery/silver_preflight.sql`). Si aparece **cualquier** vista/matview extra, entra al mismo procedimiento. Si alguna vista lee `tbl_dim_geografia` **sin** pasar por el fact, también cae en el DROP de geo (`07` B CASCADE).

---

## B. Qué cambiar/recrear en Gold **antes** del DROP

No se puede `CREATE OR REPLACE` hacia el **modelo nuevo** mientras el fact viejo ocupe el nombre: las columnas `sk_sucursal` / `sk_persona` / `sk_producto` / `pos` **no existen** todavía.

Antes del DROP, Gold solo puede:

1. **Guardar** `pg_get_viewdef` de las 5 vistas (y cualquier otra).
2. **`DROP VIEW` explícito** (o `CREATE OR REPLACE` a un stub constante de 0 filas **sin** referenciar Silver). Objetivo: no depender de `07` CASCADE.
3. Avisar a Power BI / DirectQuery: las vistas no devolverán datos durante la ventana.

**No** reescribir el SQL nuevo todavía sobre tablas viejas (fallaría).  
**No** dropear `tbl_dim_cliente` / `tbl_dim_servicio` (07 A) en esta ventana.

### Recrear Gold **después** de carga del fact nuevo

Mismos nombres de vista. Mismo **contrato de columnas de salida** (Power BI) siempre que se pueda:

| Salida Gold / PBI | Origen viejo | Origen nuevo |
|---|---|---|
| nit | `tbl_dim_cliente.nit` (varchar) | `tbl_dim_persona.nit` (integer) — castear a text si PBI espera texto |
| razonsocial | `tbl_dim_cliente.razonsocial` | `tbl_dim_persona.razonsocial` |
| ciudad | `tbl_dim_cliente.ciudad` | `tbl_dim_sucursal.ciudad` |
| categoria | `tbl_dim_servicio.categoria` | `tbl_dim_producto_erp.categoria` |
| plan / `nombre_plan` | `tbl_dim_servicio.nombre_plan` | alias `tbl_dim_producto_erp.nombre_producto AS nombre_plan` |
| departamento, municipio, barrio | `tbl_dim_geografia` | **iguales nombres** en geo nueva (`dpto`/`mun` son extra, no hace falta exponerlos) |
| año, mes, `nombre_mes` | `tbl_dim_tiempo` | igual (`ff.fecha_factura = dt.fecha` o `ff.sk_tiempo = dt.sk_tiempo`) |
| cantidad, subtotal, iva, neto | fact | **igual** |
| clientes atendidos | `COUNT(DISTINCT sk_cliente)` ≈ sucursal | `COUNT(DISTINCT sk_sucursal)` (mismo grano) o `COUNT(DISTINCT sk_persona)` si se quiere NIT |
| numero de factura | `numero_factura` | `numero` |

Join canónico post-cutover:

```text
tbl_fact_facturacion ff
  JOIN tbl_dim_sucursal      ON ff.sk_sucursal  = suc.sk_sucursal
  JOIN tbl_dim_persona       ON ff.sk_persona   = per.sk_persona
  JOIN tbl_dim_producto_erp  ON ff.sk_producto  = prod.sk_producto
  LEFT JOIN tbl_dim_geografia ON ff.sk_geografia = geo.sk_geografia
  JOIN tbl_dim_tiempo        ON ff.sk_tiempo    = tm.sk_tiempo
```

`sk_contrato` / `sk_plan` quedan NULL en la carga v2: **no** usarlos en Gold todavía.

`vw_transaccionalidad_clientes`: sigue agrupando por `per.nit` (comportamiento actual).

Hasta no tener `pg_get_viewdef`, el SQL exacto de cada vista es **borrador**. El recreado debe copiar filtros (`anulado`, etc.) del def capturado.

---

## C. Orden de ejecución

Prerrequisito (puede hacerse **con Gold aún vivo**, dual-run): `01→02→03→04` ya aplicados para objetos de **nombre nuevo**, y dims nuevas **cargadas** (persona, perfil, plan, contrato, producto_erp, bridges, pagos). Sucursal puede estar cargada con CAST al geo **viejo**; se **re-carga** después del REPLACE de geo.

`wf_actualizacion_silver_v2` **no** está en `wf_delta` / `wf_historic` (delta corre `/opt/guajiranet-etl/bin/run_delta.sh`). El Silver **producción** sigue siendo `wf_actualizacion_silver.hwf` (geo/cliente/servicio/facts **viejos**).

### C1. Deshabilitar workflows

| Acción | Objeto | Detalle |
|---|---|---|
| Parar | Job/scheduler que dispare Silver viejo | `wf_actualizacion_silver.hwf` y unitarios `wf_dim_geografia`, `wf_fact_facturacion`, `wf_fact_cartera`, `wf_dim_cliente`, `wf_dim_servicio` |
| No activar | `wf_actualizacion_silver_v2` en delta/historic | sigue sin referenciarse; no cambiar eso en este cutover |
| Dejar **enabled=N** | hops facts v2 | `pago_pasarela → fact_facturacion_v2 → fact_cartera_v2` hasta C6 |
| Dejar **enabled=N** hasta C5 | hops geo v2 | `contrato → geografia_v2 → sucursal` (stg geo aún viejo) |
| Mantener | hop vivo `contrato → sucursal` | hasta C5; no correr el orquestador v2 **durante** C3–C4 (tablas a medias) |

Congelar también cualquier recarga a `stg_fact_*` / `stg_dim_geografia` del modelo viejo (PGBulkLoader truncaría/escribiría layout incorrecto).

### C2. Actualizar Gold (fase “soltar Silver”)

1. Capturar `pg_get_viewdef` + `pg_depend` (solo SELECT).
2. `DROP VIEW IF EXISTS` las 5 vistas (y extras halladas), **sin CASCADE** si hay objetos encima; si hay, listarlos y dropear en orden.
3. Gold queda vacío a propósito. Dashboards fallan hasta C7. Eso es la ventana.

**No** recrear vistas nuevas aquí.

### C3. FK y `07` B

1. `sql/silver/05_drop_fk.sql` (hoy cero FK; idempotente). Obliga si se corrió `06` en dual-run: `fk_dim_sucursal_sk_geografia` apunta al geo **viejo**.
2. Ejecutar **solo sección B** de `07_drop_obsolete.sql` (los tres `DO $$` de geo, facturación, cartera). **No** sección A.
3. Confirmar `to_regclass` NULL para las 6 tablas. Sequences OWNED BY desaparecen con el DROP.

### C4. `01 / 02 / 03 / 04` de nuevo

Orden: `01_create_dims.sql` → `02_create_bridges_facts.sql` → `03_create_staging.sql` → `04_seed_unknown_members.sql`.

Efecto esperado:

- Geo + stg geo: **CREATE** modelo nuevo (`id_barrio integer`).
- Facts + stg facts: **CREATE** (`pos`, `idsuc` en cartera).
- 04: SK 0 geo (`SIN BARRIO` / …) + `setval`; perfil SK 0 ya debería existir (IF NOT EXISTS / idempotente).
- Tablas NEW ya existentes: no-op.
- KEEP tiempo/documento: otra vez UNIQUE/CHECK/índice si faltaban.

### C5. Cargar dimensiones (geo nueva + sucursal)

`sk_geografia` en `tbl_dim_sucursal` quedó **huérfano** al dropear geo. Hay que recargar sucursal **después** de geo v2.

Hops en `wf_actualizacion_silver_v2.hwf` (cuando se autorice editar HWF):

| Hop | Hoy | Tras C4 |
|---|---|---|
| `wf_dim_contrato` → `wf_dim_sucursal` | enabled=Y | **N** |
| `wf_dim_contrato` → `wf_dim_geografia_v2` | enabled=N | **Y** |
| `wf_dim_geografia_v2` → `wf_dim_sucursal` | enabled=N | **Y** |
| facts v2 | enabled=N | seguir **N** en esta ola |

Correr (unitarios o orquestador hasta sucursal, **sin** facts):

1. `wf_dim_geografia_v2` → `stg` nuevo + UPSERT `ON CONFLICT (id_barrio)` (incluye dummy 0).
2. `wf_dim_sucursal` (CAST sigue válido integer/varchar).
3. Opcional refresco: producto_erp, persona, perfil (ya deberían estar).

No correr `wf_dim_geografia` **viejo** (escribiría columnas que ya no existen).

### C6. Habilitar facts y cargar

Hops:

| Hop | Tras C5 |
|---|---|
| `wf_fact_pago_pasarela` → `Success` | **N** |
| `wf_fact_pago_pasarela` → `wf_fact_facturacion_v2` | **Y** |
| `wf_fact_facturacion_v2` → `wf_fact_cartera_v2` | **Y** |
| `wf_fact_cartera_v2` → `Success` | **Y** |

Carga: `wf_fact_facturacion_v2` (INNER JOIN sucursal/persona/producto/documento/tiempo) luego `wf_fact_cartera_v2` (UPSERT + DELETE NK ausentes).

Fact v2 **no** usa `tbl_dim_cliente` / `tbl_dim_servicio`.

### C7. Recrear Gold

`CREATE VIEW` (o `CREATE OR REPLACE`) de las 5 vistas con el join de la sección B, **mismos nombres**, contrato de columnas estable.

Hasta que esto termine, Gold sigue caído. **No** abrir Power BI como “OK” antes.

### C8. Crear FK

`sql/silver/06_create_fk.sql` **después** de la primera carga de facts nuevos. `NOT VALID`. Skip no aplica ya: columnas nuevas existen.

### C9. Validaciones

Catálogo:

- `id_barrio` integer en `tbl_` y `stg_dim_geografia`
- columna `pos` y no `posicion_factura` en fact/stg facturación
- columna `idsuc` y no `sk_cliente` en fact/stg cartera
- `sk_geografia = 0` y `id_barrio = 0` en geo
- PK/UNIQUE NK nuevos (ver `silver_ddl_implementation.md`)
- 5 vistas `gold_guajiranet` existen y `pg_get_viewdef` **no** contiene `sk_cliente` / `sk_servicio` / `numero_factura` / `posicion_factura` / `tbl_dim_cliente` / `tbl_dim_servicio`

Conteos (órdenes de magnitud discovery):

| Chequeo | Esperado |
|---|---|
| `tbl_dim_geografia` | ~246 (245 `mabarrio` + SK 0) |
| `tbl_fact_facturacion` | ~214 837 líneas `trfacturasdet`; puede bajar si INNER JOIN pierde nit/sucursal/producto |
| `tbl_fact_cartera` | snapshot `saldo <> 0` latest-open; **≠** 15 857 viejo |
| Gold `vw_operacion_facturacion` | `SELECT` sin error; suma `neto` comparable al fact (mismo filtro `anulado` que el def viejo) |

Hop:

- Orquestador viejo **sigue apagado** para geo/facts (o se retira del schedule).
- v2: geo y facts hops **Y**; hop directo contrato→sucursal **N**.
- **No** activar v2 en `wf_delta`/`wf_historic` en este cutover (decisión aparte).
- **No** `07` A hasta que Gold no use cliente/servicio y el HWF viejo esté fuera de producción.

---

## Ventana y riesgo

```text
Gold vivo (fact viejo)
  → C1 freeze Hop
  → C2 DROP VIEW          ★ Gold caído
  → C3 05 + 07 B
  → C4 01-04
  → C5 geo + sucursal
  → C6 facts v2
  → C7 CREATE VIEW        ★ Gold vivo (modelo nuevo)
  → C8 06
  → C9 validar
```

No hay dual-run del **mismo nombre**. Rollback = restaurar backup Aurora / tablas `*_legacy` si en un cambio futuro se hace `RENAME` en vez de DROP. `07` B actual **no** conserva copia.

---

## Fuera de alcance (este cutover)

- Editar HPL/HWF (solo se **indica** qué hops cambiar cuando se autorice).
- Reescribir `07` en dos archivos.
- DROP cliente/servicio (`07` A).
- Contratos/planes en facturación (siguen NULL).
- Activar v2 en delta/historic.
- SQL Gold definitivo (falta `pg_get_viewdef`).

---

## Criterio de hecho

Cutover **B** (6 tablas) está cerrado cuando: las 6 tablas son modelo nuevo, facts cargados, 5 vistas Gold responden, PBI ve los mismos nombres de columna, `06` aplicado, orquestador viejo no escribe geo/facts, hops v2 geo+facts habilitados.

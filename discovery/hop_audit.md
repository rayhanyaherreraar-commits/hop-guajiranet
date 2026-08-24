# Auditoría Hop GuajiraNet (Silver actual)

**Fecha:** 2026-08-24  
**Alcance:** 7 pipelines `.hpl` + 10 workflows `.hwf` listados. Ningún archivo HPL/HWF fue modificado.  
**Fuera de alcance:** DDL de PostgreSQL, scripts shell externos, FKs en `/home/arra/guajiranet-etl/sql/`. Las SK de dimensiones (salvo `dim_tiempo`) se infieren porque los `INSERT` no las listan.

---

## Resumen ejecutivo

El Silver actual es un **estrella reducido** (cliente + servicio + documento + geografía + tiempo → facturación y cartera). El patrón de carga es uniforme:

1. Pipeline Hop: `Table input` (SQL sobre Bronze/Silver) → limpieza opcional → `PostgreSQL Bulk Loader` con `TRUNCATE` hacia `stg_*`.
2. Workflow: `INSERT … SELECT … ON CONFLICT (…) DO UPDATE` hacia `tbl_*`.

No hay transforms Hop de `Unique`, `Dimension lookup/update`, `Insert/update` ni secuencias. Las SK de dimensiones (excepto tiempo) las asigna PostgreSQL. El modelo es **SCD Tipo 1** (sobrescribe atributos; no hay historial).

El cuello de botella para el modelo nuevo es **`dim_cliente`**: grano `(nit, idsuc)` que mezcla persona y sucursal. **`dim_servicio`** mezcla plan comercial y producto ERP (`maproductos.nombreproducto` se aliasa como `nombre_plan`). **No existe pipeline de contrato.**

`wf_historic` y `wf_delta` **no orquestan Silver**. Cargan Bronze vía shell externo. `wf_actualizacion_silver` es el orquestador Silver y **no está referenciado** por esos dos workflows.

---

## 1. Inventario por pipeline

### 1.1 `dim_cliente.hpl` + `wf_dim_cliente.hwf`

| Campo | Valor |
|---|---|
| Staging | `silver_guajiranet.stg_dim_cliente` |
| Tabla Silver | `silver_guajiranet.tbl_dim_cliente` |
| Bronze | `bronze_guajiranet.materceros` **INNER JOIN** `bronze_guajiranet.matercerosuc` `ON t.nit = s.nit` |
| NK | `(nit, idsuc)` — confirmada por `ON CONFLICT (nit, idsuc)` |
| SK | `sk_cliente` **no se genera en Hop**. El `INSERT` no la incluye → identidad/serial en BD. Consumida por hechos. |
| Estrategia | Staging: **TRUNCATE + load**. Destino: **UPSERT** Tipo 1. |
| Deduplicación | Ninguna (`DISTINCT` / `GROUP BY` / Unique Hop ausentes). |
| Limpieza | Trim `razonsocial`, `direccion`; ciudad UPPER; email lower. |
| Columnas | `nit`, `idsuc`, `razonsocial`, `documento_identidad`, `tipo_persona`, `ciudad`, `direccion`, `email`, `movil`, `es_cliente`, `estado_activo`, `fecha_actualizacion` |

**Joins**

```text
materceros t  INNER JOIN  matercerosuc s  ON t.nit = s.nit
```

**Riesgos**

- Grano sucursal, no persona: un NIT con N sucursales produce N filas (diseño actual; incompatible con `DIM_PERSONA`).
- `INNER JOIN` descarta terceros sin sucursal.
- Duplicados Bronze en `(nit, idsuc)` rompen el `ON CONFLICT` (“cannot affect row a second time”).
- `nit` se castea a `VARCHAR(15)` aquí y a `VARCHAR(30)` en los hechos → riesgo de mismatch de lookup.
- `es_cliente` viene de tercero; `estado_activo` de sucursal. Mezcla de granos en la misma fila.

**Reutilizable:** patrón Table input + String operations + bulk TRUNCATE; SQL de UPSERT; limpiezas de nombre/email/ciudad. **No reutilizar el grano ni el JOIN como dimensión única.**

---

### 1.2 `dim_documento.hpl` + `wf_dim_documento.hwf`

| Campo | Valor |
|---|---|
| Staging | `silver_guajiranet.stg_dim_documento` |
| Tabla Silver | `silver_guajiranet.tbl_dim_documento` |
| Bronze | `bronze_guajiranet.madocumentos` (sin join) |
| NK | `(idsuc, prefijo)` |
| SK | `sk_documento` asignada en BD. Consumida por `fact_facturacion`. |
| Estrategia | TRUNCATE staging + UPSERT Tipo 1. |
| Deduplicación | Ninguna. |
| Limpieza | Trim + UPPER en `prefijo`, `tipodoc`, `denominacion`, `tipofactura`, `activo`. |

**Riesgos:** duplicados `(idsuc, prefijo)` en Bronze. Prefijo vacío/nulo. No hay miembro desconocido; los hechos hacen `INNER JOIN` y pierden facturas sin documento.

**Reutilizable casi completo** para el modelo nuevo (catálogo de tipos de documento de facturación). No mapea a las DIM nuevas; **se mantiene**.

---

### 1.3 `dim_geografia.hpl` + `wf_dim_geografia.hwf`

| Campo | Valor |
|---|---|
| Staging | `silver_guajiranet.stg_dim_geografia` |
| Tabla Silver | `silver_guajiranet.tbl_dim_geografia` |
| Bronze | `matercerosuc` LEFT JOIN `mabarrio` LEFT JOIN `maciudades` |
| NK | `id_barrio` |
| SK | `sk_geografia` en BD. Hechos usan `COALESCE(dg.sk_geografia, 0)`. |
| Estrategia | TRUNCATE staging + UPSERT. |
| Deduplicación | Pipeline: `GROUP BY s.idbarrio` + `MAX(...)`. Workflow: `SELECT DISTINCT ON (id_barrio)` priorizando coordenada no nula. Filtro `WHERE s.idbarrio IS NOT NULL`. Fila dummy `id_barrio = '0'`. |

**Joins**

```text
matercerosuc s
  LEFT JOIN mabarrio b     ON s.idbarrio = b.idbarrio
  LEFT JOIN maciudades c   ON b.dpto = c.dpto AND b.mun = c.mun
GROUP BY s.idbarrio
```

**Riesgos**

- `MAX()` aplasta zona/estrato/departamento/municipio distintos del mismo barrio.
- Dummy `id_barrio='0'` **no garantiza** `sk_geografia = 0`. Los hechos hacen `COALESCE(..., 0)`, que apunta a una SK literal 0, no al dummy. Hueco de integridad.
- Geografía derivada de sucursales de terceros, no de un maestro geográfico independiente.

**Reutilizable:** SQL de dummy + `GROUP BY` + `DISTINCT ON`, limpiezas UPPER. Evaluar si `DIM_SUCURSAL` absorbe geo o si se mantiene como dimensión de ubicación.

---

### 1.4 `dim_servicio.hpl` + `wf_dim_servicio.hwf`

| Campo | Valor |
|---|---|
| Staging | `silver_guajiranet.stg_dim_servicio` |
| Tabla Silver | `silver_guajiranet.tbl_dim_servicio` |
| Bronze | `maproductos` LEFT JOIN `mafamiliasproductos` `ON p.idfam1 = f.idfamilia` |
| NK | `id_servicio` = `maproductos.idproducto` |
| SK | `sk_servicio` en BD. |
| Estrategia | TRUNCATE staging + UPSERT Tipo 1. |
| Deduplicación | Ninguna. |
| Columnas | `id_servicio`, `nombre_plan` ← `nombreproducto`, `categoria` ← `familia`, `tarifa_mensual` ← `lista1`, `estado_activo` |

**Riesgos:** un catálogo ERP se presenta como “plan/servicio”. No hay separación plan vs producto vs contrato. `LEFT JOIN` a familia puede repetir si `idfamilia` no es único. Tarifa `lista1` es precio de lista, no tarifa contractual.

**Reutilizable:** fuente `maproductos` + familia, limpiezas, UPSERT por `idproducto`. **Hay que partir** hacia `DIM_PLAN` y `DIM_PRODUCTO_ERP`.

---

### 1.5 `dim_tiempo.hpl` + `wf_dim_tiempo.hwf`

| Campo | Valor |
|---|---|
| Staging | `silver_guajiranet.stg_dim_tiempo` |
| Tabla Silver | `silver_guajiranet.tbl_dim_tiempo` |
| Fuente | **No Bronze.** `generate_series('2020-01-01','2035-12-31','1 day')` |
| NK / SK | `sk_tiempo = TO_CHAR(d,'YYYYMMDD')::INTEGER` (smart key = NK) |
| Estrategia | TRUNCATE staging + UPSERT `ON CONFLICT (sk_tiempo)` |
| Deduplicación | Inherente a `generate_series`. |

**Riesgos:** `INSERT INTO tbl SELECT * FROM stg` depende del orden de columnas. Rango fijo 2020–2035. `nombre_mes`/`nombre_dia` salen de `TO_CHAR` (locale del servidor). Workflow interno se llama `New workflow` (`name_sync_with_filename=Y`).

**Reutilizable al 100%.** Mantener.

---

### 1.6 `fact_cartera.hpl` + `wf_fact_cartera.hwf`

| Campo | Valor |
|---|---|
| Staging | `silver_guajiranet.stg_fact_cartera` |
| Tabla Silver | `silver_guajiranet.tbl_fact_cartera` |
| Bronze | `bronze_guajiranet.vmovcartera` |
| NK de hecho | `(sk_cliente, cuenta, ref_doc, ref_num, plazo)` |
| SK propias | No se inserta SK de hecho. Lookup: `sk_cliente`, `sk_tiempo`. |
| Estrategia | TRUNCATE staging + UPSERT. |
| Deduplicación | `SELECT DISTINCT` en CTE `cartera_limpia` sobre **todas** las columnas (incluye `saldo`, `fecha`, `fvence`, `dias`). |

**Joins**

```text
vmovcartera
  INNER JOIN tbl_dim_cliente  ON CAST(nit AS VARCHAR(30)) = dc.nit AND sucursal = dc.idsuc
  INNER JOIN tbl_dim_tiempo   ON fecha = dt.fecha
```

**Riesgos**

- `INNER JOIN` a cliente y tiempo descarta movimientos huérfanos (NIT/sucursal no dimensionados, fechas fuera de 2020–2035 o nulas).
- `DISTINCT` no colapsa por la NK de conflicto. Dos filas iguales en NK y distintas en `saldo`/`fecha` → fallo de `ON CONFLICT` en el mismo statement.
- No usa `dim_documento` pese a `ref_doc`.
- No hay SK de sucursal/persona/contrato/plan independientes: todo cuelga de `sk_cliente`.

**Reutilizable:** fuente `vmovcartera`, CTE de limpieza, UPSERT, medidas (`saldo`, `plazo`, `dias`, vencimiento). **Reemplazar lookups** cuando se parta cliente.

---

### 1.7 `fact_facturacion.hpl` + `wf_fact_facturacion.hwf`

| Campo | Valor |
|---|---|
| Staging | `silver_guajiranet.stg_fact_facturacion` |
| Tabla Silver | `silver_guajiranet.tbl_fact_facturacion` |
| Bronze | `trfacturas` INNER JOIN `trfacturasdet` + lookup `matercerosuc` para barrio |
| NK de hecho | `(sk_documento, numero_factura, posicion_factura)` |
| SK | Lookups: `sk_cliente`, `sk_servicio`, `sk_geografia`, `sk_documento`. Sin SK propia insertada. |
| Estrategia | TRUNCATE staging + UPSERT. |
| Deduplicación | Ninguna. |

**Joins**

```text
trfacturas f
  INNER JOIN trfacturasdet d     ON f.idsuc = d.idsuc AND f.prefijo = d.prefijo AND f.numero = d.numero
  INNER JOIN tbl_dim_cliente dc  ON CAST(f.nit AS VARCHAR(30)) = dc.nit AND f.sucursal = dc.idsuc
  INNER JOIN tbl_dim_servicio ds ON d.idproducto = ds.id_servicio
  INNER JOIN tbl_dim_documento dd ON f.idsuc = dd.idsuc AND f.prefijo = dd.prefijo
  LEFT JOIN  matercerosuc ms     ON f.nit = ms.nit AND f.sucursal = ms.idsuc
  LEFT JOIN  tbl_dim_geografia dg ON COALESCE(CAST(ms.idbarrio AS VARCHAR(20)), '0') = dg.id_barrio
```

**Riesgos**

- `INNER JOIN` a cliente/servicio/documento pierde líneas no dimensionadas.
- `LEFT JOIN matercerosuc` puede **multiplicar** líneas si `(nit, idsuc)` no es único en Bronze.
- `COALESCE(sk_geografia, 0)` vs dummy `id_barrio='0'` (SK distinta).
- Grano de línea (`idsuc, prefijo, numero, pos`) no incluye sucursal de cliente ni producto en la NK de conflicto: un cambio de producto reescribe la misma línea.
- No hay `sk_tiempo`; la fecha queda degenerada (`fecha_factura`).
- `Select values` fuerza tipos Integer/Number/Date/Timestamp.

**Reutilizable:** cabecera+detalle de factura, grain de línea, medidas (`cantidad`, `precio`, `subtotal`, `iva`, `neto`), join documento `(idsuc, prefijo)`. **Reemplazar** joins a cliente y servicio.

---

## 2. Workflows de orquestación (no construyen dimensiones)

### 2.1 `wf_actualizacion_silver.hwf`

Orquestador Silver. Cadena **serial** (todos los hops condicionales *on success*, salvo Start):

```text
Start
 → wf_dim_geografia
 → wf_dim_cliente
 → wf_dim_documento
 → wf_dim_servicio
 → wf_dim_tiempo
 → wf_fact_facturacion
 → wf_fact_cartera
 → Success 7
```

Nodos `Success` intermedios actúan de checkpoint. Las dimensiones independientes se serializan innecesariamente. Los hechos **sí** deben ir al final.

Nombre interno: `New workflow` (`name_sync_with_filename=Y`). Loglevel de sub-workflows: `Nothing`.

**Reutilizable:** esqueleto orquestador. Hay que cambiar la lista de hijos (persona, sucursal, plan, contrato, producto).

### 2.2 `wf_delta.hwf`

No toca tablas Silver. Flujo:

```text
Start → Drop constraints (03_drop_all_fk.sql)
      → ETL_delta shell /opt/guajiranet-etl/bin/run_delta.sh
      → Create constraints (04_create_fk.sql)
      → Success
```

Scripts y shell **fuera del repo Hop** (rutas Linux `/home/arra/...` y `/opt/guajiranet-etl/...`).

Riesgos de hops:

- `Drop → ETL` es **incondicional**: el delta corre aunque falle el drop de FKs.
- `Create → Success` es **incondicional**: el workflow puede marcar éxito con FKs rotas.
- `ETL → Create` sí es on-success.

**Reutilizable como wrapper Bronze delta**, no como lógica dimensional.

### 2.3 `wf_historic.hwf`

```text
Start → ETL_historic shell /home/arra/guajiranet-etl/bin/etl_historic_data.sh
      → Success (on success)
```

Carga histórica Bronze. Sin SQL Silver. Ruta distinta a `wf_delta` (`/home/arra` vs `/opt`).

**Reutilizable como wrapper de carga inicial Bronze.**

---

## 3. Dependencias entre pipelines

```text
                    materceros ──┐
                    matercerosuc ┴── dim_cliente ──┐
                                                   ├── fact_cartera
                    generate_series ── dim_tiempo ─┘
                                                   ┌── fact_facturacion
                    madocumentos ── dim_documento ─┤
                    maproductos  ── dim_servicio  ─┤
                    mabarrio/maciudades ── dim_geografia ─┘
                         ▲
                    matercerosuc (también join directo en el fact)
```

| Downstream | Requiere (tablas Silver ya upsertadas) |
|---|---|
| `fact_facturacion` | `tbl_dim_cliente`, `tbl_dim_servicio`, `tbl_dim_documento`, `tbl_dim_geografia` (+ `matercerosuc` Bronze) |
| `fact_cartera` | `tbl_dim_cliente`, `tbl_dim_tiempo` |
| Dimensiones | Independientes entre sí a nivel Hop |

`wf_historic` / `wf_delta` no tienen arista hacia `wf_actualizacion_silver` en estos archivos. Si el delta Bronze no termina antes del Silver, hay condición de carrera operativa (no modelada en Hop).

---

## 4. Estrategia global INSERT/UPDATE/UPSERT y SK

| Destino | Staging Hop | Destino SQL | Conflicto |
|---|---|---|---|
| `tbl_dim_cliente` | TRUNCATE `stg_dim_cliente` | UPSERT | `(nit, idsuc)` |
| `tbl_dim_documento` | TRUNCATE `stg_dim_documento` | UPSERT | `(idsuc, prefijo)` |
| `tbl_dim_geografia` | TRUNCATE `stg_dim_geografia` | UPSERT | `(id_barrio)` |
| `tbl_dim_servicio` | TRUNCATE `stg_dim_servicio` | UPSERT | `(id_servicio)` |
| `tbl_dim_tiempo` | TRUNCATE `stg_dim_tiempo` | UPSERT | `(sk_tiempo)` |
| `tbl_fact_cartera` | TRUNCATE `stg_fact_cartera` | UPSERT | `(sk_cliente, cuenta, ref_doc, ref_num, plazo)` |
| `tbl_fact_facturacion` | TRUNCATE `stg_fact_facturacion` | UPSERT | `(sk_documento, numero_factura, posicion_factura)` |

Patrón: **snapshot full de staging + merge Tipo 1**. No hay delete de NK desaparecidas (soft-delete / baja no se refleja salvo que el UPSERT reciba `activo=N`). `PGBulkLoader stop_on_error=N`.

---

## 5. Riesgos de duplicación (consolidado)

1. **`dim_cliente`**: grano `(nit, idsuc)` duplica personas; sin dedup en staging.
2. **`ON CONFLICT` + duplicados en el mismo `INSERT`**: PostgreSQL aborta el statement (cliente, documento, servicio, ambos facts).
3. **`fact_facturacion` × `matercerosuc`**: fan-out si sucursal no es única.
4. **`fact_cartera DISTINCT`**: no equivale a DISTINCT ON la NK de conflicto.
5. **`dim_geografia MAX()`**: una fila por barrio con atributos mezclados, no duplicados visibles pero sí semánticos.
6. **Hechos INNER JOIN**: no duplican; **silencian** filas (pérdida, no fan-out).
7. **Cast `nit` 15 vs 30**: lookups fallidos → más pérdidas, no duplicados.
8. **SK geografía 0**: no es un problema de duplicación; es FK huérfana / miembro desconocido mal cableado.

---

## 6. Qué reutilizar para el modelo nuevo

### Reutilizar tal cual

- `dim_tiempo.hpl` + `wf_dim_tiempo.hwf`
- `dim_documento.hpl` + `wf_dim_documento.hwf`
- Patrón **Table input → String operations → PGBulkLoader TRUNCATE `stg_*` → SQL UPSERT**
- Conexión `aws_rds`, esquemas `bronze_guajiranet` / `silver_guajiranet`
- Orquestación “dims luego facts” de `wf_actualizacion_silver`
- Wrappers `wf_historic` / `wf_delta` (Bronze)
- Fuentes de hechos `trfacturas`+`trfacturasdet` y `vmovcartera`
- Limpiezas de texto (trim, upper, email lower)

### Reutilizar como semilla (hay que regranular)

| Actual | Semilla para |
|---|---|
| SQL `materceros` (sin sucursal) | `DIM_PERSONA` |
| SQL `matercerosuc` + atributos de `dim_cliente` | `DIM_SUCURSAL` |
| `dim_geografia` (barrio/municipio/dpto/zona/estrato) | atributos o FK de sucursal; o dimensión geo mantenida |
| `maproductos` + `mafamiliasproductos` | `DIM_PRODUCTO_ERP` y, si aplica, catálogo de `DIM_PLAN` |
| Joins de factura `(idsuc, prefijo, numero)` y `(idsuc, prefijo)` documento | facts nuevos |
| UPSERT Tipo 1 | SCD1 de las DIM nuevas (salvo que se pida SCD2) |

### No reutilizar (reemplazar)

- Grano y pipeline `dim_cliente` como dimensión única
- Alias `nombre_plan` sobre `maproductos` como si fuera plan comercial
- Lookups de hechos a `sk_cliente` / `sk_servicio` sin persona, sucursal, plan, contrato, producto
- `COALESCE(sk_geografia, 0)` sin miembro SK=0 real
- `INSERT SELECT *` de tiempo (frágil); mejor lista explícita de columnas
- Nombres internos `New workflow` / hops incondicionales de `wf_delta`

---

## 7. Mapeo al modelo destino

### DIM_PERSONA

| Origen actual | Uso |
|---|---|
| `materceros` (`nit`, `razonsocial`, `identificacion`→`documento_identidad`, `tipopersona`→`tipo_persona`, `escliente`→`es_cliente`) | **Núcleo de la DIM** |
| Parte de `dim_cliente.hpl` | Extraer; **quitar** `idsuc` y atributos de sucursal |
| NK propuesta | `nit` |
| No está hoy | Grano persona; un NIT = una fila |

`tbl_dim_cliente` **no es** `DIM_PERSONA`: es persona×sucursal.

### DIM_SUCURSAL

| Origen actual | Uso |
|---|---|
| `matercerosuc` (`idsuc`, `ciudad`, `direccion1`, `email`, `movil`, `activo`, `idbarrio`, `zona`, `estrato`, `departamento`, `coordenada`) | **Núcleo de la DIM** |
| `dim_cliente` (lado sucursal) | Extraer |
| `dim_geografia` | Barrio/municipio/dpto como atributos o FK, no como grano de sucursal |
| Hechos: `f.sucursal`, `c.sucursal` | NK de lookup `(nit, idsuc)` |
| NK propuesta | `(nit, idsuc)` — es la NK actual de `dim_cliente` |

### DIM_PLAN

| Origen actual | Uso |
|---|---|
| `dim_servicio` (`nombre_plan` ← `maproductos.nombreproducto`, `tarifa_mensual` ← `lista1`, `categoria` ← familia) | **Semilla débil**: hoy el “plan” es el producto ERP |
| Contratos / vigencia / velocidad | **Ausentes** |

Hay que confirmar en Bronze si existe maestro de planes distinto de `maproductos`. Si no, `DIM_PLAN` no se puede sacar fielmente de Hop actual.

### DIM_CONTRATO

**No existe** en ninguno de los 17 archivos. No hay tabla Bronze de contrato, ni NK, ni SK, ni join en hechos.

Hay que crear pipeline y workflow nuevos. Posible puente temporal: no forzar contrato en facts hasta tener fuente; o degenerar un id si aparece en `trfacturas`/`vmovcartera` (hoy no se selecciona).

### DIM_PRODUCTO_ERP

| Origen actual | Uso |
|---|---|
| `dim_servicio` completo (`idproducto`, nombre, familia, lista1, activo) | **Núcleo** |
| `fact_facturacion.d.idproducto` | Lookup de línea |
| NK | `idproducto` (hoy `id_servicio`) |

Renombrar semántica: esto es producto ERP, no “servicio/plan”.

### Qué debe mantenerse

- `dim_tiempo` / `tbl_dim_tiempo`
- `dim_documento` / `tbl_dim_documento` (no está en el modelo nuevo; sigue siendo necesaria para facturación)
- `dim_geografia` **si** se quiere ubicación independiente de sucursal; si no, bajar geo a atributos de `DIM_SUCURSAL` y mantener el dummy de desconocido, pero con SK real
- Fuentes Bronze de facts y el patrón staging+UPSERT
- `wf_historic` + `wf_delta` como carga Bronze (corrigiendo hops incondicionales)
- Orquestador Silver (hijos nuevos)

### Qué debe reemplazarse

| Actual | Destino |
|---|---|
| `dim_cliente` + `tbl_dim_cliente` + `sk_cliente` | `DIM_PERSONA` + `DIM_SUCURSAL` |
| `dim_servicio` + `tbl_dim_servicio` + `sk_servicio` | `DIM_PRODUCTO_ERP` y, con fuente aparte, `DIM_PLAN` |
| Lookups de `fact_facturacion` / `fact_cartera` a `sk_cliente`/`sk_servicio` | Lookups a persona, sucursal, producto, plan, contrato |
| (nuevo) | `DIM_CONTRATO` + su workflow |
| `wf_actualizacion_silver` lista de hijos | Incluir las DIM nuevas y facts re-linkeados |

---

## 8. Orden sugerido (sin implementar)

1. Bronze: `wf_historic` / `wf_delta` (ya existen).
2. Dimensiones independientes: tiempo, documento, geografía, persona, producto ERP, plan (si hay fuente), sucursal (después de persona y geo si hay FKs).
3. Contrato (cuando exista Bronze).
4. Hechos con los nuevos SK.

Hasta no partir `dim_cliente` y `dim_servicio`, **no conviene** seguir cargando facts sobre `sk_cliente`/`sk_servicio` si el modelo destino ya no los usa.

---

## 9. Hallazgos operativos extra (alcance de los 17 archivos)

- `wf_dim_tiempo.hwf` y `wf_fact_cartera.hwf` / `wf_actualizacion_silver.hwf` tienen `<name>New workflow</name>`.
- `wf_delta` referencia SQL y shells **fuera del proyecto Hop**.
- Ningún pipeline genera SK salvo `dim_tiempo`.
- No hay SCD2, no hay delete de ausentes, no hay Unique Hop.
- `fact_cartera` no dimensiona documento ni geografía ni servicio.
- `fact_facturacion` no dimensiona tiempo (fecha degenerada).

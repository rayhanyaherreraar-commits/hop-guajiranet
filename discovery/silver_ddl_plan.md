# Plan DDL Silver definitivo (GuajiraNet)

**Fecha:** 2026-08-24  
**Estado:** solo plan. No se creó ni alteró ninguna tabla. No se tocó HPL/HWF.  
**Origen del DDL actual:** `information_schema` / `pg_indexes` / `pg_class` en Aurora (`silver_guajiranet`, `bronze_guajiranet`), lectura.  
**No hay `CREATE TABLE` Silver** en el repo Hop ni en `Guajiranet-Migracion`. Los scripts `sql/fase2/03_drop_all_fk.sql` y `04_create_fk.sql` son **Bronze**, no Silver.

---

## 1. Qué hay hoy en `silver_guajiranet`

14 objetos: 7 `stg_*` + 7 `tbl_*`. **Cero FOREIGN KEY.** Staging **sin PK, UNIQUE ni índices**. Las SK no son `IDENTITY`; son `integer`/`bigint` + `nextval(sequence)`.

| Tabla | PK | UNIQUE (NK) | Sequence | Filas (discovery) |
|---|---|---|---|---:|
| `tbl_dim_cliente` | `sk_cliente` | `(nit, idsuc)` `uq_dim_cliente_nit_suc` | `tbl_dim_cliente_sk_cliente_seq` | 15 389 |
| `tbl_dim_documento` | `sk_documento` | `(idsuc, prefijo)` | `tbl_dim_documento_sk_documento_seq` | 91 |
| `tbl_dim_geografia` | `sk_geografia` | `id_barrio` varchar(20) | `tbl_dim_geografia_sk_geografia_seq` | 234 |
| `tbl_dim_servicio` | `sk_servicio` | `id_servicio` varchar(30) | `tbl_dim_servicio_sk_servicio_seq` | 877 |
| `tbl_dim_tiempo` | `sk_tiempo` | *(no hay UNIQUE de `fecha`)* | ninguna (smart key) | 5 844 |
| `tbl_fact_cartera` | `sk_fact_cartera` bigint | `(sk_cliente, cuenta, ref_doc, ref_num, plazo)` | `tbl_fact_cartera_sk_fact_cartera_seq` | 15 857 |
| `tbl_fact_facturacion` | `sk_fact_facturacion` bigint | `(sk_documento, numero_factura, posicion_factura)` | `tbl_fact_facturacion_sk_fact_facturacion_seq` | 214 837 |

Índice extra (redundante con UNIQUE): `idx_dim_cliente_nit_suc` btree `(nit, idsuc)`.

### Columnas actuales (tipos reales)

**`tbl_dim_cliente`:** `sk_cliente int NOT NULL DEFAULT nextval`, `nit varchar(15)`, `idsuc smallint`, `razonsocial varchar(128)`, `documento_identidad bigint`, `tipo_persona char(1)`, `ciudad varchar(40)`, `direccion varchar(128)`, `email varchar(128)`, `movil varchar(20)`, `es_cliente char(1)`, `estado_activo char(1)`, `fecha_actualizacion timestamp DEFAULT CURRENT_TIMESTAMP`. Solo `sk_cliente` es NOT NULL.

**`tbl_dim_documento`:** SK + `idsuc smallint NOT NULL`, `prefijo varchar(3) NOT NULL`, `tipodoc varchar(10)`, `denominacion varchar(150)`, `tipofactura varchar(10)`, `activo char(1)`, `fecha_actualizacion`.

**`tbl_dim_geografia`:** SK + `id_barrio varchar(20) NOT NULL`, barrio/municipio/departamento/zona/estrato/coordenada textos, `fecha_actualizacion`.

**`tbl_dim_servicio`:** SK + `id_servicio varchar(30) NOT NULL`, `nombre_plan varchar(150)`, `categoria varchar(50)`, `tarifa_mensual numeric(12,2)`, `estado_activo char(1)`.

**`tbl_dim_tiempo`:** `sk_tiempo int NOT NULL` (sin default), `fecha date NOT NULL`, anio/semestre/trimestre/mes/semana/dia/dia_semana int, nombres varchar(20), `es_fin_semana boolean`.

**`tbl_fact_cartera`:** SK bigint + `sk_cliente/sk_tiempo/cuenta int NOT NULL`, `ref_doc varchar(10) NOT NULL`, `ref_num varchar(30) NOT NULL`, `plazo smallint NOT NULL`, `fecha_vencimiento date`, `dias int`, `saldo numeric(18,2)`.

**`tbl_fact_facturacion`:** SK bigint + `sk_cliente/sk_servicio/sk_documento int NOT NULL`, `sk_geografia int NULL`, `fecha_factura date NOT NULL`, `numero_factura int NOT NULL`, `posicion_factura smallint NOT NULL`, medidas `numeric(18,2)`.

Staging: mismas columnas de negocio, **todo NULLABLE**, sin SK (excepto `stg_dim_tiempo.sk_tiempo`).

### Hallazgos que el DDL nuevo debe corregir

1. **No hay FK Silver.** Los facts no están amarrados a dims. `wf_delta` no las crea.
2. **`nit` es `varchar(15)`** en Silver y `integer` en Bronze → CAST en Hop. El modelo nuevo usa `integer`.
3. **`id_barrio` es texto**; Bronze `mabarrio.idbarrio` es `integer`. Dummy `'0'` ≠ `sk_geografia = 0` (secuencia empieza en 1).
4. **`id_servicio varchar(30)`** vs `maproductos.idproducto varchar(25)`.
5. UNIQUE de facturación **no incluye `idsuc`**: es `(sk_documento, numero, pos)`. Debe pasar a `(idsuc, prefijo, numero, pos)`.
6. UNIQUE de cartera incluye `plazo` y **omite el documento AR** `(idsuc, prefijo, numero)`. Snapshot actual deja ítems cerrados (stg 11 633 vs tbl 15 857).
7. Staging sin UNIQUE: un duplicado en el `INSERT … ON CONFLICT` aborta el statement.

---

## 2. PK Bronze de las fuentes confirmadas

| Tabla | Relkind | PK / UNIQUE |
|---|---|---|
| `materceros` | table | PK `nit` |
| `matercerosuc` | table | PK `(nit, idsuc)` |
| `tmjsonclient` | table | PK `id`; UNIQUE `idcliente` |
| `tmjsoncontract` | table | PK `id`; UNIQUE `idcontrato` |
| `tmjsonplan_server` | table | PK `id` (integer de fila; **no** es el UUID del plan) |
| `maproductos` | table | PK `idproducto` |
| `mafamiliasproductos` | table | PK `idfamilia` |
| `mabarrio` | table | PK `idbarrio` |
| `madepartamentos` | table | PK `dpto` |
| `maciudades` | table | PK `(mun, dpto)` *(lookup de nombre, no grano)* |
| `madocumentos` | table | PK `(idsuc, prefijo)` |
| `maperfilcartera` | table | PK `id` |
| `trfacturas` | table | PK `(idsuc, prefijo, numero)` |
| `trfacturasdet` | table | PK `(idsuc, prefijo, numero, pos)` |
| `tmcartera` | table | **sin PK** |
| `trpagodigital` | table | PK `id` |
| `vpagodiasfactura` | table (copia de vista origen) | **sin PK** |

---

## 3. Política DDL (todas las tablas nuevas)

- Esquema: `silver_guajiranet`.
- Nombres: `tbl_*` publicado, `stg_*` staging.
- SK: `serial`/`bigserial` vía sequence `tbl_<obj>_<sk>_seq` empezando en **1**. Miembros desconocidos se insertan con SK **0** explícito (`OVERRIDING SYSTEM VALUE` o `INSERT` + `setval`).
- NK: `UNIQUE NOT NULL` (o UNIQUE filtrado si hay nulos).
- Staging: espejo de columnas de negocio **sin SK**, todo nullable, `TRUNCATE` cada carga. Añadir `UNIQUE` en staging **solo si** hace falta fallar temprano; si no, deduplicar en el SQL de Hop **antes** del UPSERT.
- Carga: `TRUNCATE stg` → bulk → `INSERT … ON CONFLICT (NK) DO UPDATE` (SCD1). Facts snapshot (cartera): UPSERT + **DELETE de NK ausentes** (no dejar saldos cerrados).
- FK: scripts aparte, `NOT VALID`, para poder cargar sin drop/create en cada delta. No copiar `wf_delta` Bronze sobre Silver.
- `fecha_actualizacion timestamp DEFAULT CURRENT_TIMESTAMP`.
- **No** llevar a Silver: `password`, `pppoe_password`, `wifi_password`, `logo` bytea.

Convención: **no reutilizar `sk_cliente`**. Persona = `sk_persona`. Sucursal = `sk_sucursal`. Producto ERP = `sk_producto` (no `sk_servicio`).

---

## 4. Acción por objeto actual vs nuevo

| Objeto actual | Acción |
|---|---|
| `tbl_dim_tiempo` + `stg_dim_tiempo` | **KEEP.** Añadir `UNIQUE (fecha)` y `CHECK (sk_tiempo = to_char(fecha,'YYYYMMDD')::int)`. |
| `tbl_dim_documento` + `stg` | **KEEP.** Opcional: índice `(tipodoc)`. |
| `tbl_dim_geografia` + `stg` | **REPLACE** (recrear). Grano `mabarrio.idbarrio` integer; quitar zona/estrato/coordenada (van a sucursal). Semilla SK=0. |
| `tbl_dim_cliente` + `stg` | **REPLACE** por persona + sucursal. DROP tras cutover Gold. |
| `tbl_dim_servicio` + `stg` | **REPLACE** por `tbl_dim_producto_erp`. DROP tras cutover. |
| `tbl_fact_facturacion` + `stg` | **REBUILD** (columnas y UNIQUE distintos; Gold depende de ella). |
| `tbl_fact_cartera` + `stg` | **REPLACE** (grano latest-open `tmcartera`). |
| (nuevo) resto DIM/FACT/BRG | **CREATE** |

Estrategia de cutover: crear tablas nuevas en paralelo (`tbl_dim_persona`, …), cargar, apuntar Gold, luego drop de las viejas. No ALTER in-place de `tbl_dim_cliente`.

Scripts SQL a crear (aún no existen):

```
sql/silver/01_create_dims.sql
sql/silver/02_create_bridges_facts.sql
sql/silver/03_create_staging.sql
sql/silver/04_seed_unknown_members.sql
sql/silver/05_drop_fk.sql
sql/silver/06_create_fk.sql          -- NOT VALID
sql/silver/07_drop_obsolete.sql      -- después de cutover
```

---

## 5. Definición de cada tabla nueva

Tipos alineados a Bronze. Lookup = FK a dim, no copia de textos de catálogo salvo atributos útiles.

### 5.1 `tbl_dim_persona`  — CREATE

| Columna | Tipo | NN | Origen |
|---|---|---|---|
| `sk_persona` | integer | PK, nextval | sequence |
| `nit` | integer | UNIQUE | `materceros.nit` |
| `dv` | char(1) | | `materceros.dv` |
| `razonsocial` | varchar(128) | | `materceros.razonsocial` |
| `documento_identidad` | bigint | | `materceros.identificacion` |
| `tipo_persona` | char(1) | | `materceros.tipopersona` |
| `es_cliente` | char(1) | | `materceros.escliente` |
| `es_proveedor` | char(1) | | `materceros.esproveedor` |
| `tdoc` | smallint | | `materceros.tdoc` |
| `idcliente` | varchar(64) | | `materceros.idcliente` (no UNIQUE: 5 UUID con 2 nit) |
| `fecha_creacion` | date | | `materceros.fechacreacion` |
| `fecha_actualizacion` | timestamp | | carga |

- **NK / UNIQUE:** `nit`
- **SK:** `sk_persona` sequence `tbl_dim_persona_sk_persona_seq`
- **FK:** ninguna
- **Índices:** UNIQUE nit; btree `idcliente` (no unique)
- **Staging:** `stg_dim_persona` (mismas cols salvo SK)
- **Carga:** UPSERT `ON CONFLICT (nit)`. Fuente **solo** `materceros` (14 938). UUID extra de JSON van al bridge.

### 5.2 `tbl_dim_sucursal`  — CREATE

| Columna | Tipo | NN | Origen |
|---|---|---|---|
| `sk_sucursal` | integer | PK | sequence |
| `nit` | integer | | `matercerosuc.nit` |
| `idsuc` | smallint | | `matercerosuc.idsuc` |
| `sk_persona` | integer | NN | lookup `tbl_dim_persona` |
| `sk_geografia` | integer | NULL | lookup `idbarrio`; 0 si huérfano/nulo |
| `sk_perfil_cartera` | integer | NULL | lookup `idperfilcartera`; 0 si código 0/huérfano |
| `razonsocial_suc` | varchar(128) | | `matercerosuc.razonsocial` |
| `direccion` | varchar(128) | | `direccion1` |
| `direccion2` | varchar(128) | | `direccion2` |
| `dpto` | varchar(3) | | código; no usar texto como NK |
| `mun` | varchar(5) | | |
| `ciudad` | varchar(40) | | texto sucursal (atributo) |
| `email` | varchar(128) | | |
| `emailfe` | varchar(128) | | |
| `telefono1` | varchar(20) | | |
| `movil` | varchar(20) | | |
| `contacto1` | varchar(40) | | |
| `activo` | char(1) | | |
| `estrato` | varchar(8) | | poco poblado |
| `coordenada` | varchar(64) | | |
| `finiciopermanencia` | date | | |
| `fecharetiroisp` | date | | |
| `idperfilcartera` | integer | | degenerada |
| `idperfilcartera_anterior` | integer | | |
| `fecha_actualizacion` | timestamp | | |

- **NK / UNIQUE:** `(nit, idsuc)` — 15 389, única en Bronze
- **SK:** `sk_sucursal`
- **FK:** `sk_persona` → persona; `sk_geografia` → geografia; `sk_perfil_cartera` → perfil
- **Índices:** UNIQUE NK; btree `sk_persona`; btree `idbarrio` vía geo; btree `fecharetiroisp`
- **No** guardar `idcontrato` aquí (va al bridge). 11 `idsuc=0` se conservan (son NK válidas).
- **Carga:** UPSERT `(nit, idsuc)`. INNER JOIN persona (cobertura nit 100%).

### 5.3 `tbl_dim_contrato`  — CREATE

| Columna | Tipo | NN | Origen JSON/`tmjsoncontract` |
|---|---|---|---|
| `sk_contrato` | integer | PK | sequence |
| `idcontrato` | varchar(64) | UNIQUE | columna = `datajson.id` |
| `idcliente` | varchar(64) | | `idcliente` / `datajson.client_id` |
| `public_id` | integer | | `datajson.public_id` |
| `state` | varchar(32) | | enabled/disabled |
| `start_date` | timestamptz | | |
| `created_at` | timestamptz | | |
| `updated_at` | timestamptz | | |
| `address_street` | varchar(256) | | |
| `address_city` | varchar(80) | | atributo, no FK geo |
| `address_state` | varchar(80) | | |
| `address_country` | varchar(80) | | |
| `address_number` | varchar(64) | | |
| `latitude` | numeric(12,8) | | string→numeric |
| `longitude` | numeric(12,8) | | |
| `ont_id` | varchar(64) | | |
| `ont_number` | varchar(64) | | |
| `ont_serial_number` | varchar(64) | | |
| `olt_id` | varchar(64) | | |
| `interface_gpon` | varchar(64) | | |
| `mac_address` | varchar(32) | | |
| `plan_id` | varchar(64) | | degenerada; el vínculo canónico es el BRG |
| `fecha_actualizacion` | timestamp | | |

- **NK:** `idcontrato` (10 998 únicos)
- **FK:** ninguna obligatoria (plan/persona vía bridges)
- **Carga:** UPSERT `idcontrato`. Parse jsonb. **No** `pppoe_password` / `wifi_password`.

### 5.4 `tbl_dim_plan`  — CREATE

| Columna | Tipo | NN | Origen |
|---|---|---|---|
| `sk_plan` | integer | PK | sequence |
| `id_plan` | varchar(64) | UNIQUE | `tmjsonplan_server.datajson.id` tipo=`P` |
| `tipo` | char(1) | NN default `'P'` | filtro |
| `nombre` | varchar(256) | | `datajson.name` |
| `public_id` | integer | | |
| `ceil_down_kbps` | integer | | number JSON (max 2 010 000) |
| `ceil_up_kbps` | integer | | max 8 000 000 |
| `cir` | varchar(32) | | JSON string (ej. `0.125`) |
| `precio` | numeric(18,2) | | JSON string → numeric |
| `frequency_in_months` | integer | | |
| `contracts_count` | integer | | snapshot origen |
| `created_at` / `updated_at` | timestamptz | | |
| `fecha_actualizacion` | timestamp | | |

- **NK:** `id_plan` (282). `tmjsonplan_server.id` integer **no** es la NK.
- **Carga:** `WHERE tipo = 'P'`. UPSERT `id_plan`. Tipo S fuera de alcance.

### 5.5 `tbl_dim_producto_erp`  — CREATE (reemplaza servicio)

| Columna | Tipo | NN | Origen |
|---|---|---|---|
| `sk_producto` | integer | PK | sequence |
| `id_producto` | varchar(25) | UNIQUE | `maproductos.idproducto` |
| `nombre_producto` | varchar(128) | | `nombreproducto` |
| `id_familia` | varchar(10) | | `idfam1` |
| `categoria` | varchar(40) | | `mafamiliasproductos.familia` |
| `tarifa_lista` | numeric(18,2) | | `lista1` |
| `estado_activo` | char(1) | | `activo` |
| `fecha_actualizacion` | timestamp | | |

- **NK:** `id_producto` (877)
- **Carga:** LEFT JOIN familia `ON p.idfam1 = f.idfamilia`. UPSERT. **No** es DIM_PLAN (0 overlap UUID).

### 5.6 `tbl_dim_geografia`  — REPLACE

| Columna | Tipo | NN | Origen |
|---|---|---|---|
| `sk_geografia` | integer | PK | sequence; **0 = desconocido** |
| `id_barrio` | integer | UNIQUE | `mabarrio.idbarrio` |
| `barrio` | varchar(40) | | `nombrebarrio` |
| `dpto` | varchar(3) | | `mabarrio.dpto` |
| `mun` | varchar(5) | | `mabarrio.mun` |
| `municipio` | varchar(40) | | lookup `maciudades` (no es fuente de grano) |
| `departamento` | varchar(60) | | `madepartamentos.departamento` |
| `fecha_actualizacion` | timestamp | | |

- **NK:** `id_barrio` integer (245 + fila 0)
- **Quitar:** zona, estrato, coordenada (sucursal)
- **Seed:** `(0, 0, 'SIN BARRIO', …)`
- **Carga:** full refresh UPSERT. No agrupar desde `matercerosuc`.

### 5.7 `tbl_dim_documento`  — KEEP

Sin cambio de columnas. UNIQUE `(idsuc, prefijo)` ya coincide con Bronze PK.  
Opcional: `tipodoc`/`tipofactura` a varchar(3)/varchar(2) como origen; hoy están más anchos (inofensivo).

### 5.8 `tbl_dim_tiempo`  — KEEP + UNIQUE fecha

Añadir `CONSTRAINT uq_dim_tiempo_fecha UNIQUE (fecha)`. SK sigue siendo YYYYMMDD. Rango 2020–2035: las facturas empiezan 2021-12-28; ampliar el `generate_series` si hace falta margen.

### 5.9 `tbl_dim_perfil_cartera`  — CREATE

| Columna | Tipo | NN | Origen |
|---|---|---|---|
| `sk_perfil_cartera` | integer | PK | sequence; **0 = desconocido** |
| `id_perfil` | integer | UNIQUE | `maperfilcartera.id` |
| `denominacion` | varchar(32) | | Residencial, Proyecto Mintic, Proceso Retiro, … |
| `diasvence1` / `diasvence2` | integer | | |
| `deshabilitar` | char(1) | | |
| `alertar` | char(1) | | |
| `diasvencefactura` | integer | | |
| `nofactura` | boolean | | |
| `fecha_actualizacion` | timestamp | | |

- **NK:** `id_perfil` (17 + seed 0)
- 17 sucursales con `idperfilcartera=0` y 1 146 nulos → FK a SK 0 o NULL. Recomendación: nulo → SK 0; código 0 → SK 0.

### 5.10 `tbl_fact_facturacion`  — REBUILD

| Columna | Tipo | NN | Origen |
|---|---|---|---|
| `sk_fact_facturacion` | bigint | PK | sequence |
| `idsuc` | smallint | NN | `trfacturasdet` |
| `prefijo` | varchar(3) | NN | |
| `numero` | integer | NN | |
| `pos` | smallint | NN | = `posicion_factura` |
| `sk_sucursal` | integer | NN | `(f.nit, f.sucursal)` |
| `sk_persona` | integer | NN | `f.nit` |
| `sk_producto` | integer | NN | `d.idproducto` |
| `sk_documento` | integer | NN | `(f.idsuc, f.prefijo)` |
| `sk_geografia` | integer | NULL | sucursal.idbarrio; 0 si falta |
| `sk_tiempo` | integer | NN | `f.fecha` |
| `sk_contrato` | integer | **NULL** | **no hay join confiable** |
| `sk_plan` | integer | **NULL** | **no hay join confiable** |
| `fecha_factura` | date | NN | |
| `anulado` | char(1) | | `trfacturas.anulado` |
| `cantidad, precio, subtotal, iva, neto` | numeric(18,2) | | detalle (cast desde float8) |
| `fecha_actualizacion` | timestamp | | |

- **NK / UNIQUE:** `(idsuc, prefijo, numero, pos)` — igual que Bronze. **Reemplaza** `uq_fact_facturacion (sk_documento, numero, pos)`.
- **FK:** sucursal, persona, producto, documento, tiempo; geo/contrato/plan nullable
- **Carga:** TRUNCATE stg; UPSERT NK. **No** INNER JOIN que tire líneas si se puede dimensionar; contrato/plan siempre NULL.
- Gold actual lee esta tabla: hay que recrear vistas **después**.

### 5.11 `tbl_fact_cartera`  — REPLACE

Snapshot **latest-open** de `tmcartera`:

```text
grano = última fila por
  (idsuc, prefijo, numero, cuenta, nit, sucursal, ref_doc, ref_num)
WHERE saldo <> 0
```

| Columna | Tipo | NN |
|---|---|---|
| `sk_fact_cartera` | bigint PK | sequence |
| `idsuc, prefijo, numero` | smallint, varchar(3), int | NN (documento AR) |
| `cuenta` | integer | NN |
| `nit` | integer | NN |
| `sucursal` | smallint | NN |
| `ref_doc` | varchar(3) | NN (Bronze es varchar(3); Silver viejo era 10) |
| `ref_num` | varchar(15) | NN |
| `sk_sucursal` | integer | NN |
| `sk_persona` | integer | NN |
| `sk_tiempo` | integer | NN = `fecha` de la versión latest (no `fecha_actualizacion`) |
| `sk_perfil_cartera` | integer | NULL |
| `plazo` | smallint | |
| `fecha` | date | versión |
| `fecha_vencimiento` | date | `fvence` |
| `dias` | integer | |
| `saldo, debito, credito` | numeric(18,2) | |
| `rango1`…`rango6` | numeric(18,2) | aging |
| `interes` | numeric(18,2) | |
| `idformapago` | smallint | degenerada |
| `transaccion` | varchar(128) | |
| `fecha_actualizacion` | timestamp | |

- **NK / UNIQUE:** `(idsuc, prefijo, numero, cuenta, nit, sucursal, ref_doc, ref_num)`
- **Carga:** construir latest-open en SQL (`DISTINCT ON` + `ORDER BY fecha DESC, conteo DESC`); TRUNCATE stg; UPSERT; **DELETE** NK que ya no estén abiertos. No reutilizar `vmovcartera`.
- `tmcartera` no tiene PK: el `DISTINCT ON` es obligatorio.

### 5.12 `tbl_fact_pago_aplicacion`  — CREATE

Fuente: `vpagodiasfactura` **DISTINCT** por NK.

| Columna | Tipo | NN |
|---|---|---|
| `sk_fact_pago_aplicacion` | bigint PK | |
| `idsuc, prefijo, numero` | factura | NN |
| `rc_idsuc, rc_prefijo, rc_numero` | recibo | NN |
| `sk_sucursal` / `sk_persona` | lookup vía factura | NULL si huérfano |
| `sk_documento` | lookup factura | NULL |
| `sk_tiempo_factura` | `fecha` | NULL |
| `sk_tiempo_recibo` | `rc_fecha` | NULL |
| `carteraaplicado` | numeric(18,2) | medida |
| `pagorc` | numeric(18,2) | total del recibo (no sumar por factura) |
| `idformapago` | smallint | |
| `ccosto` | integer | |
| `fecha_actualizacion` | timestamp | |

- **NK / UNIQUE:** `(idsuc, prefijo, numero, rc_idsuc, rc_prefijo, rc_numero)`  
  Raw 183 646 → ~115 852 distinct.
- **Carga:** `SELECT DISTINCT ON (NK)` (cualquier fila: medidas constantes por NK salvo basura). UPSERT. Vista origen **stale** (máx `rc_fecha` 2026-06-16).

### 5.13 `tbl_fact_pago_pasarela`  — CREATE

Fuente: `trpagodigital`.

| Columna | Tipo | NN |
|---|---|---|
| `sk_fact_pago_pasarela` | bigint PK | |
| `id_pago_digital` | integer UNIQUE | `trpagodigital.id` |
| `idsuc, prefijo, numero` | factura | |
| `rec_idsuc, rec_prefijo, rec_numero` | recibo contable | |
| `sk_sucursal` / `sk_persona` | lookup factura | NULL |
| `sk_tiempo` | `foperacion::date` | NULL |
| `foperacion` | timestamp | |
| `total` | numeric(18,2) | medida (origen float8) |
| `codigo_respuesta` | varchar(16) | NEQUI/PSE/… |
| `numero_recibo` | varchar(64) | |
| `numero_autorizacion` | varchar(64) | |
| `referencia` | varchar(64) | |
| `numero_orden` | varchar(64) | |
| `fecha_actualizacion` | timestamp | |

- **NK:** `id_pago_digital` (55 529 únicos). 59 facturas con más de un evento: es correcto (varios pagos).
- **No** es subconjunto de `vpagodiasfactura`. Facts **paralelos**, no unificables.

### 5.14 `tbl_brg_persona_uuid`  — CREATE

`materceros.idcliente` ∪ `tmjsonclient.idcliente`.

| Columna | Tipo | NN |
|---|---|---|
| `sk_brg_persona_uuid` | integer PK | |
| `idcliente` | varchar(64) | NN |
| `nit` | integer | NULL si solo JSON |
| `sk_persona` | integer | NULL si UUID sin nit |
| `en_materceros` | boolean | |
| `en_tmjsonclient` | boolean | |
| `fecha_actualizacion` | timestamp | |

- **NK / UNIQUE:** `(idcliente, nit)` con `nit` coalescido a `0` **o** índice único `idcliente` + `nit` nullable vía `UNIQUE (idcliente, COALESCE(nit,-1))`.  
  **No** UNIQUE solo `idcliente`: 5 UUID tienen 2 nit.
- **FK:** `sk_persona` → persona (nullable)
- **Carga:** FULL OUTER JOIN por `idcliente`; emitir una fila por par `(idcliente, nit)`.

### 5.15 `tbl_brg_sucursal_contrato`  — CREATE

| Columna | Tipo | NN |
|---|---|---|
| `sk_brg_sucursal_contrato` | integer PK | |
| `sk_sucursal` | integer | NN |
| `sk_contrato` | integer | NULL si UUID solo en suc |
| `nit` | integer | NN |
| `idsuc` | smallint | NN |
| `idcontrato` | varchar(64) | NN |
| `match_json` | boolean | true si está en `tmjsoncontract` |
| `fecha_actualizacion` | timestamp | |

- **NK / UNIQUE:** `(nit, idsuc, idcontrato)`
- Fuente: `matercerosuc` WHERE `idcontrato IS NOT NULL` (10 937; 2 UUID duplicados en suc, **no** están en JSON).
- 532 contratos solo JSON: **no** entran aquí (no hay sucursal).
- **Carga:** UPSERT NK. LEFT JOIN dim_contrato.

### 5.16 `tbl_brg_contrato_plan`  — CREATE

| Columna | Tipo | NN |
|---|---|---|
| `sk_brg_contrato_plan` | integer PK | |
| `sk_contrato` | integer | NN UNIQUE (N:1 actual) |
| `sk_plan` | integer | NN |
| `idcontrato` | varchar(64) | |
| `id_plan` | varchar(64) | `datajson.plan_id` |
| `fecha_actualizacion` | timestamp | |

- **NK:** `idcontrato` (un plan vigente; **sin histórico**)
- Cobertura plan_id tipo P: 100% (109/109)
- **Carga:** UPSERT `idcontrato`.

---

## 6. Staging a crear / dropear

| Staging | Acción |
|---|---|
| `stg_dim_tiempo`, `stg_dim_documento` | KEEP |
| `stg_dim_geografia` | recrear (id_barrio integer, sin zona/estrato/coordenada) |
| `stg_dim_cliente`, `stg_dim_servicio`, `stg_fact_cartera`, `stg_fact_facturacion` | DROP tras cutover |
| `stg_dim_persona`, `stg_dim_sucursal`, `stg_dim_contrato`, `stg_dim_plan`, `stg_dim_producto_erp`, `stg_dim_perfil_cartera` | CREATE |
| `stg_fact_facturacion` (nuevo layout), `stg_fact_cartera` (nuevo), `stg_fact_pago_aplicacion`, `stg_fact_pago_pasarela` | CREATE |
| `stg_brg_persona_uuid`, `stg_brg_sucursal_contrato`, `stg_brg_contrato_plan` | CREATE |

Staging: sin PK; columnas = destino menos SK; todas nullable.

---

## 7. FK e índices (script `06_create_fk.sql`)

Crear **después** de la primera carga, `NOT VALID`:

```
tbl_dim_sucursal.sk_persona          → tbl_dim_persona.sk_persona
tbl_dim_sucursal.sk_geografia        → tbl_dim_geografia.sk_geografia
tbl_dim_sucursal.sk_perfil_cartera   → tbl_dim_perfil_cartera.sk_perfil_cartera
tbl_brg_persona_uuid.sk_persona      → tbl_dim_persona.sk_persona
tbl_brg_sucursal_contrato.sk_sucursal→ tbl_dim_sucursal.sk_sucursal
tbl_brg_sucursal_contrato.sk_contrato→ tbl_dim_contrato.sk_contrato
tbl_brg_contrato_plan.sk_contrato    → tbl_dim_contrato.sk_contrato
tbl_brg_contrato_plan.sk_plan        → tbl_dim_plan.sk_plan
tbl_fact_facturacion.sk_*            → dims (contrato/plan/geo NULL ok)
tbl_fact_cartera.sk_*                → dims
tbl_fact_pago_*.sk_*                 → dims
```

Índices btree en **cada columna SK de fact/bridge** (además de UNIQUE NK).

No hay FK Silver hoy: `05_drop_fk.sql` empieza vacío y se rellena cuando existan.

---

## 8. Orden de creación y carga

1. `tbl_dim_tiempo` (existe)
2. `tbl_dim_documento` (existe)
3. Recrear `tbl_dim_geografia` + seed 0
4. `tbl_dim_perfil_cartera` + seed 0
5. `tbl_dim_persona`
6. `tbl_brg_persona_uuid`
7. `tbl_dim_sucursal`
8. `tbl_dim_plan`
9. `tbl_dim_contrato`
10. `tbl_brg_sucursal_contrato`, `tbl_brg_contrato_plan`
11. `tbl_dim_producto_erp`
12. `tbl_fact_facturacion` (nuevo)
13. `tbl_fact_cartera` (nuevo)
14. `tbl_fact_pago_aplicacion`, `tbl_fact_pago_pasarela`
15. `06_create_fk.sql`
16. Cutover Gold → `07_drop_obsolete.sql` (`tbl_dim_cliente`, `tbl_dim_servicio`, facts viejos)

---

## 9. Miembros desconocidos

| Dim | SK 0 | Cuándo |
|---|---|---|
| Geografía | sí | `idbarrio` nulo o 2 huérfanos sucursal |
| Perfil cartera | sí | nulo o código 0 (17 filas) |
| Persona / sucursal / producto / documento / tiempo | no | facts: INNER si hay match; si no, **no insertar** la línea o NULL explícito según regla de carga |
| Contrato / plan en FACT_FACTURACION | no SK 0 | **siempre NULL** |

Insertar SK 0 **antes** de `setval(seq, max(sk))`.

---

## 10. Qué no tocar todavía

- HPL/HWF
- Tablas Gold (`vw_*`)
- Scripts Bronze `fase2/*`
- Datos actuales: dual-run hasta validar conteos (persona 14 938, sucursal 15 389, contrato 10 998, plan P 282, producto 877, geo 245+1, fact líneas 214 837)

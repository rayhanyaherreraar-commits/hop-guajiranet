# Pre-flight Silver — Fase 4

**Fecha:** 2026-08-24  
**Alcance:** revisión estática de `sql/silver/01_create_dims.sql` … `04_seed_unknown_members.sql` y `06_create_fk.sql`.  
**Prohibido en esta fase:** ejecutar SQL contra Aurora; modificar tablas; tocar HPL/HWF.  
**Catálogo live de referencia:** `discovery/silver_ddl_plan.md` (lectura `information_schema` / `pg_class` del mismo día). **Esta Fase 4 no reconsulta Aurora.**  
**Script de verificación (no corrido):** `discovery/silver_preflight.sql` — solo `SELECT` / `information_schema` / `pg_catalog`.

Orden previsto cuando se autorice Aurora: `01 → 02 → 03 → 04` → carga Hop de **nombres nuevos** → `06`. `05` en ciclos posteriores. `07` solo post-cutover Gold.

---

## 1. Tablas nuevas (CREATE paralelo)

Nombres libres. `CREATE TABLE IF NOT EXISTS` + `CREATE SEQUENCE IF NOT EXISTS`. No colisionan con el Silver actual (14 objetos).

| Objeto | Script | ¿Existe hoy (discovery)? | Si se corre 01–03 |
|---|---|---|---|
| `tbl_dim_persona` | 01 | no | se crea |
| `tbl_dim_sucursal` | 01 | no | se crea |
| `tbl_dim_contrato` | 01 | no | se crea |
| `tbl_dim_plan` | 01 | no | se crea |
| `tbl_dim_producto_erp` | 01 | no | se crea |
| `tbl_dim_perfil_cartera` | 01 | no | se crea |
| `tbl_brg_persona_uuid` | 02 | no | se crea |
| `tbl_brg_sucursal_contrato` | 02 | no | se crea |
| `tbl_brg_contrato_plan` | 02 | no | se crea |
| `tbl_fact_pago_aplicacion` | 02 | no | se crea |
| `tbl_fact_pago_pasarela` | 02 | no | se crea |
| `stg_dim_persona` … `stg_dim_perfil_cartera` (6) | 03 | no | se crean |
| `stg_brg_*` (3) | 03 | no | se crean |
| `stg_fact_pago_aplicacion`, `stg_fact_pago_pasarela` | 03 | no | se crean |

KEEP (deben existir; si faltan, **01/03 abortan** con `RAISE EXCEPTION`):

| Objeto | Script | Discovery 2026-08-24 |
|---|---|---|
| `tbl_dim_tiempo` | 01 | existe (5 844 filas) |
| `tbl_dim_documento` | 01 | existe (91) |
| `stg_dim_tiempo` | 03 | existe |
| `stg_dim_documento` | 03 | existe |

Fuera de 01–06 (no se nombran; no DROP): `tbl_dim_cliente`, `tbl_dim_servicio`, `stg_dim_cliente`, `stg_dim_servicio`.

---

## 2. Tablas viejas que bloquean (mismo nombre)

El script **no DROP**. Si el nombre está ocupado y el detector de modelo nuevo falla → `RAISE NOTICE 'BLOQUEO…'` y sigue.

| Tabla | Detector modelo nuevo | Layout live (discovery) | Efecto 01–04 |
|---|---|---|---|
| `tbl_dim_geografia` | `id_barrio` **integer** | `id_barrio varchar(20)` + zona/estrato/coordenada | 01 no recrea; 04 **no** siembra SK 0 |
| `stg_dim_geografia` | `id_barrio` integer | mismo grano viejo (texto) | 03 no recrea |
| `tbl_fact_facturacion` | columna **`pos`** | `posicion_factura` + `sk_cliente` / `sk_servicio`; UNIQUE `(sk_documento, numero_factura, posicion_factura)` | 02 no recrea |
| `stg_fact_facturacion` | columna `pos` | layout viejo | 03 no recrea |
| `tbl_fact_cartera` | columna **`idsuc`** | `sk_cliente`; **sin** `idsuc`; UNIQUE `(sk_cliente, cuenta, ref_doc, ref_num, plazo)` | 02 no recrea |
| `stg_fact_cartera` | columna `idsuc` | layout viejo | 03 no recrea |

Estas seis ocupan el nombre del modelo definitivo. El Silver **completo** (geo integer, facts NK Bronze) **no** queda creado con 01–04.

---

## 3. Columnas y tipos (live vs 01–03)

### KEEP — se conservan

**`tbl_dim_tiempo`:** `sk_tiempo int` (sin sequence), `fecha date NOT NULL`, atributos de calendario. 01 solo intenta **añadir** `UNIQUE (fecha)` y `CHECK (sk_tiempo = to_char(fecha,'YYYYMMDD')::integer)`. Si hay duplicados o SK sucia: `EXCEPTION` → NOTICE; el resto del script continúa.

**`tbl_dim_documento`:** SK + `(idsuc, prefijo)` UNIQUE. 01 añade índice `idx_dim_documento_tipodoc` si falta. Sin cambio de tipos.

### COLLIDE — no se ALTER

**`tbl_dim_geografia` live:** `id_barrio varchar(20) NOT NULL`, barrio/municipio/departamento/**zona/estrato/coordenada**.  
**01 nuevo (solo si el nombre está libre):** `id_barrio integer` UNIQUE, `dpto`/`mun`, **sin** zona/estrato/coordenada.

**`tbl_fact_facturacion` live:** `sk_cliente`, `sk_servicio`, `numero_factura`, `posicion_factura`.  
**02 nuevo:** `idsuc+prefijo+numero+pos`, `sk_sucursal`, `sk_persona`, `sk_producto`, `sk_contrato`/`sk_plan` NULLABLE.

**`tbl_fact_cartera` live:** `sk_cliente`, `cuenta`, `ref_doc`, `ref_num`, `plazo`; sin documento AR `(idsuc, prefijo, numero)`.  
**02 nuevo:** NK 8-upla con `idsuc`.

Staging collide: mismas columnas de negocio que el `tbl_*` viejo, todo nullable, sin SK (salvo KEEP tiempo).

### NEW — tipos de 01/02/03 (aún no en Aurora)

Alineados a Bronze: `nit integer`, `idsuc smallint`, UUID `varchar(64)`, medidas `numeric(18,2)`. Staging espejo **sin SK propia**; lookups (`sk_persona` en sucursal, etc.) sí van en stg.

---

## 4. PK / UNIQUE

| Tabla (live) | PK | UNIQUE NK |
|---|---|---|
| `tbl_dim_tiempo` | `sk_tiempo` | **no** hay `UNIQUE(fecha)` hoy — 01 lo intenta |
| `tbl_dim_documento` | `sk_documento` | `(idsuc, prefijo)` |
| `tbl_dim_geografia` | `sk_geografia` | `id_barrio` varchar |
| `tbl_dim_cliente` | `sk_cliente` | `(nit, idsuc)` |
| `tbl_dim_servicio` | `sk_servicio` | `id_servicio` |
| `tbl_fact_facturacion` | `sk_fact_facturacion` bigint | `(sk_documento, numero_factura, posicion_factura)` |
| `tbl_fact_cartera` | `sk_fact_cartera` bigint | `(sk_cliente, cuenta, ref_doc, ref_num, plazo)` |

Staging live: **sin PK, UNIQUE ni índices.**

NK que 01–02 crearían (solo tablas NEW o collide **libres**): persona `nit`; sucursal `(nit,idsuc)`; contrato `idcontrato`; plan `id_plan`; producto `id_producto`; perfil `id_perfil`; brg uuid índice `(idcliente, COALESCE(nit,-1))`; brg suc-con `(nit,idsuc,idcontrato)`; brg con-plan `idcontrato` + `sk_contrato`; facturación `(idsuc,prefijo,numero,pos)`; cartera 8-upla; pago aplicación 6-upla; pasarela `id_pago_digital`.

---

## 5. Sequences

Patrón live: `tbl_<tabla>_<sk>_seq`, `START 1`, no `IDENTITY`. Tiempo **no** tiene sequence.

Hoy (discovery): sequences de cliente, documento, geografía, servicio, facturación, cartera.

01/02 **no recrean** `tbl_dim_geografia_sk_geografia_seq` ni las de facts si ya existen (`IF NOT EXISTS`). Siguen OWNED BY las tablas **viejas**. Inofensivo en dual-run. El DROP de `07` se las lleva con la tabla; 01/02 las vuelven a crear al recrear el layout nuevo.

Sequences **nuevas** (ausentes hoy): persona, sucursal, contrato, plan, `tbl_dim_producto_erp_sk_producto_seq`, `tbl_dim_perfil_cartera_sk_perfil_cartera_seq`, las tres `tbl_brg_*_sk_brg_*_seq`, `tbl_fact_pago_*_sk_fact_pago_*_seq`.

`04` hace `setval` **solo** si geo está en modelo nuevo (no es el caso) o sobre la sequence de **perfil** (tabla nueva, vacía salvo el seed).

---

## 6. Índices

Live extra: `idx_dim_cliente_nit_suc` (redundante con UNIQUE). PK/UNIQUE de las 7 `tbl_*`. Staging sin índices.

01 añadiría `idx_dim_documento_tipodoc` y, **solo si geo ya es modelo nuevo**, `(dpto, mun)`. Con geo viejo ese índice **no** se crea (faltan columnas).

02 crearía índices `sk_*` de facts **solo si** existe columna `pos` / `idsuc`. Con facts viejos: no.

Índices de tablas NEW: se crean junto con `CREATE TABLE IF NOT EXISTS`.

---

## 7. Dependencias de vistas Gold

Evidencia de plan (`discovery/silver_ddl_plan.json`): las `vw_*` de `gold_guajiranet` leen **solo** `tbl_fact_facturacion`. Auditoría de modelo: cinco vistas de operación/cobertura/transaccionalidad sobre ese fact.

`01–04` **no DROP** `tbl_fact_facturacion`. Gold **sigue válida** tras 01–04. El bloqueo es de **cutover**: no se puede recrear el fact nuevo **con el mismo nombre** mientras Gold apunte a esa relación. Eso es trabajo de `07` **después** de reescribir vistas.

`tbl_dim_cliente` / `tbl_dim_servicio` no se tocan en 01–06; Gold no las usa como fuente principal según el plan.

Confirmar en vivo con las consultas §7 de `silver_preflight.sql` (`pg_depend` / `pg_rewrite` / `pg_get_viewdef`).

---

## 8. FKs existentes y `06_create_fk.sql`

Live: **cero FOREIGN KEY** en `silver_guajiranet`.

`06` no entra en `01→04`. Crea helper `_add_fk_not_valid`, añade FK `NOT VALID` si existen tabla+columna, y **DROP FUNCTION** al final. Si falta columna (facts viejos: no hay `sk_sucursal` / `sk_persona` en facturación), **NOTICE y skip**.

Si se corriera `06` **después** de 01–04 (sin carga y **sin** recrear facts):

- FK entre objetos **NEW** (persona, sucursal, bridges, pagos): se crearían sobre tablas vacías — prematuro; el plan las pide **después de la primera carga**.
- `fk_dim_sucursal_sk_geografia`: **sí podría crearse** (sucursal nueva + geo **vieja** ambas tienen `sk_geografia`). Dual-run posible, no es DROP.
- FK de `tbl_fact_facturacion` / `tbl_fact_cartera` hacia sucursal/persona: **skip** (columnas ausentes en el modelo viejo).

**No ejecutar 06 en esta tanda.**

---

## 9. Conteos actuales (discovery 2026-08-24, no re-medidos)

| Tabla | Filas |
|---|---:|
| `tbl_dim_cliente` | 15 389 |
| `tbl_dim_geografia` | 234 |
| `tbl_dim_documento` | 91 |
| `tbl_dim_tiempo` | 5 844 |
| `tbl_dim_servicio` | 877 |
| `tbl_fact_facturacion` | 214 837 |
| `tbl_fact_cartera` | 15 857 |
| `stg_fact_cartera` | 11 633 (≠ tbl; snapshot viejo deja cerrados) |

Tablas NEW: 0 (no existen). Dummy geo live: `id_barrio = '0'` **no** garantiza `sk_geografia = 0` (secuencia desde 1). 04 no corrige eso mientras `id_barrio` sea varchar.

---

## 10. ¿`01 → 02 → 03 → 04` es ejecutable sin destruir nada?

Revisión de verbos en esos cuatro archivos:

| Script | Mutación sobre objetos **existentes** | ¿Destruye datos/tablas? |
|---|---|---|
| 01 | `ADD CONSTRAINT` tiempo (si no existe; rollback a NOTICE si falla); `CREATE INDEX` documento; `CREATE SEQUENCE IF NOT EXISTS` geo (no-op); skip CREATE geo | No. Additive / skip |
| 02 | skip CREATE facts; `CREATE IF NOT EXISTS` bridges/pagos | No |
| 03 | `RAISE EXCEPTION` si falta KEEP stg; skip stg collide; `CREATE IF NOT EXISTS` stg nuevas | No |
| 04 | SKIP geo si `id_barrio` no es integer. `INSERT`/`UPDATE`/`setval` **solo** `tbl_dim_perfil_cartera` (tabla **nueva**, vacía) | No toca geo/facts/cliente |

Ninguno de 01–04 contiene `DROP TABLE` / `TRUNCATE` / `DROP COLUMN`. Esos verbos están en `07_drop_obsolete.sql` (fuera de esta tanda) y en Hop sobre **stg** de cargas ya existentes.

Riesgo residual **no destructivo** en 01: `ALTER TABLE tbl_dim_tiempo ADD UNIQUE/CHECK` toma lock de escritura breve. Si hay `fecha` duplicada o `sk_tiempo` ≠ YYYYMMDD, el constraint **no queda** (NOTICE). Confirmar con el `SELECT` de duplicados/CHECK en `silver_preflight.sql` antes de aplicar.

**Conclusión de ejecutable:** sí se puede aplicar `01→02→03→04` sin borrar el Silver actual. Quedan creados los objetos de **nombre nuevo** y el seed de perfil SK 0. **No** queda el REPLACE de geo/facts.

`06` se revisó: idempotente y skip-safe, pero **no** forma parte de 01–04 y no debe correrse hasta después de la primera carga de las tablas nuevas.

---

## Qué queda fuera (intencional)

- Recrear geo/facts homónimos → `07` sección B + re-ejecutar 01/02/03/04.
- Gold: reescribir vistas **antes** de DROP del fact.
- Programar HPL `*_v2` contra `stg_dim_geografia` / `stg_fact_*` (siguen layout viejo).
- `tbl_dim_cliente` / `tbl_dim_servicio` → `07` sección A tras cutover.

---

## Veredicto

`01→02→03→04` no destruye cliente, servicio, geo, facts ni Gold. Dual-run de objetos nuevos: sí. Modelo Silver definitivo (geo integer + facts NK nueva **con el mismo nombre**): **no**, mientras existan las seis tablas homónimas y Gold dependa de `tbl_fact_facturacion`.

**BLOQUEOS REALES**

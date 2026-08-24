# Hop Fase 3 — workflows y UPSERT Silver definitivo

**Fecha:** 2026-08-24  
**Especificación:** `discovery/silver_ddl_plan.md`, `discovery/silver_ddl_implementation.md`, `discovery/hop_phase2_plan.md`  
**Alcance:** 14 HWF unitarios nuevos + `wf_actualizacion_silver_v2.hwf`. SQL de carga **dentro** de cada HWF (mismo patrón que Silver actual).  
**No se ejecutó SQL contra Aurora. No se modificaron HWF/HPL viejos. No se tocó Gold. No se ejecutó `07_drop_obsolete.sql`. El orquestador v2 no está referenciado por `wf_delta` / `wf_historic`.**

Patrón de cada workflow unitario:

```text
Start
  → Pipeline HPL (TRUNCATE stg + bulk)
      OK  → SQL INSERT … ON CONFLICT DO UPDATE
              OK  → Success
              FAIL → Abort
      FAIL → Abort
```

Success **solo** si el SQL termina bien (`evaluation=Y`, `unconditional=N`). Fallo de pipeline o SQL va a `Abort`.

Columnas de INSERT/UPDATE explícitas. No `SELECT *`. SK no se inserta (sequence). `fecha_actualizacion = CURRENT_TIMESTAMP` en el `DO UPDATE`.

`SELECT DISTINCT ON (NK)` en el UPSERT evita “cannot affect row a second time” si el stg trae duplicados.

---

## Prerrequisito DDL (no se corre en estos workflows)

Antes de la **primera** ejecución real (cuando se autorice Aurora):

| Script | Uso |
|---|---|
| `sql/silver/01_create_dims.sql` | dims nuevas + KEEP tiempo/documento |
| `sql/silver/02_create_bridges_facts.sql` | bridges + facts nuevos |
| `sql/silver/03_create_staging.sql` | stg nuevas / REPLACE si el nombre está libre |
| `sql/silver/04_seed_unknown_members.sql` | SK 0 geo y perfil **antes** del primer UPSERT |
| `sql/silver/06_create_fk.sql` | FK `NOT VALID` **después** de la primera carga |

**No ejecutar** `sql/silver/07_drop_obsolete.sql`. **No** incrustar 01–06 en el orquestador.

---

## Qué NO debe ejecutarse todavía

| Objeto | Motivo |
|---|---|
| `wf_fact_facturacion_v2` | `stg_fact_facturacion` / `tbl_fact_facturacion` siguen el layout viejo |
| `wf_fact_cartera_v2` | `stg_fact_cartera` / `tbl_fact_cartera` siguen el layout viejo |
| `wf_dim_geografia_v2` (en el orquestador) | `stg_dim_geografia` sigue `id_barrio` varchar. El unitario existe; hops del orquestador hacia geo v2 están **deshabilitados** |
| `wf_actualizacion_silver_v2` como job | **No activar.** Dual-run del Silver viejo sigue con `wf_actualizacion_silver` |
| `07_drop_obsolete.sql` | cutover Gold posterior |
| Gold | no se toca |

Hops **enabled=N** en el orquestador:

- `wf_dim_contrato` → `wf_dim_geografia_v2` → `wf_dim_sucursal`
- `wf_fact_pago_pasarela` → `wf_fact_facturacion_v2` → `wf_fact_cartera_v2` → Success

Camino vivo actual del orquestador (si alguien lo abriera): contrato **salta** a sucursal; termina en Success después de pagos. El HPL viejo `dim_geografia` no se llama.

Cutover geo: habilitar contrato→geo→sucursal y deshabilitar el hop directo contrato→sucursal. Cutover facts: habilitar hops de facts v2.

---

## Orden previsto (`wf_actualizacion_silver_v2`)

| # | Workflow | Pipeline | Estado hop |
|---|---|---|---|
| 1 | `wf_dim_tiempo.hwf` **(viejo, no modificado)** | `dim_tiempo.hpl` | habilitado |
| 2 | `wf_dim_documento.hwf` **(viejo, no modificado)** | `dim_documento.hpl` | habilitado |
| 3 | `wf_dim_perfil_cartera.hwf` | `dim_perfil_cartera.hpl` | habilitado |
| 4 | `wf_dim_persona.hwf` | `dim_persona.hpl` | habilitado |
| 5 | `wf_brg_persona_uuid.hwf` | `brg_persona_uuid.hpl` | habilitado |
| 6 | `wf_dim_plan.hwf` | `dim_plan.hpl` | habilitado |
| 7 | `wf_dim_contrato.hwf` | `dim_contrato.hpl` | habilitado |
| 8 | `wf_dim_geografia_v2.hwf` | `dim_geografia_v2.hpl` | **deshabilitado** (stg viejo) |
| 9 | `wf_dim_sucursal.hwf` | `dim_sucursal.hpl` | habilitado (entra desde contrato mientras geo v2 esté off) |
| 10 | `wf_dim_producto_erp.hwf` | `dim_producto_erp.hpl` | habilitado |
| 11 | `wf_brg_sucursal_contrato.hwf` | `brg_sucursal_contrato.hpl` | habilitado |
| 12 | `wf_brg_contrato_plan.hwf` | `brg_contrato_plan.hpl` | habilitado |
| 13 | `wf_fact_pago_aplicacion.hwf` | `fact_pago_aplicacion.hpl` | habilitado |
| 14 | `wf_fact_pago_pasarela.hwf` | `fact_pago_pasarela.hpl` | habilitado |
| 15 | `wf_fact_facturacion_v2.hwf` | `fact_facturacion_v2.hpl` | **deshabilitado** |
| 16 | `wf_fact_cartera_v2.hwf` | `fact_cartera_v2.hpl` | **deshabilitado** |

Dependencia de negocio: geo v2 **antes** de sucursal (cuando los hops de cutover se enciendan). Sucursal hoy hace CAST al tbl geo actual.

---

## Workflows unitarios

### `wf_dim_perfil_cartera.hwf`

| | |
|---|---|
| Pipeline | `dim_perfil_cartera.hpl` → `stg_dim_perfil_cartera` |
| Destino | `tbl_dim_perfil_cartera` |
| NK / ON CONFLICT | `id_perfil` |
| SQL | UPSERT columnas de negocio (sin SK). Dummy `id_perfil=0` en stg actualiza la fila seed si `04` ya insertó SK 0 |

**Dependencias:** `04_seed` antes del primer UPSERT (si no, sequence ≠ 0 para el dummy).  
**Riesgo:** nombres Bronze de `maperfilcartera` (pipeline).

---

### `wf_dim_persona.hwf`

| | |
|---|---|
| Pipeline | `dim_persona.hpl` → `stg_dim_persona` |
| Destino | `tbl_dim_persona` |
| NK | `nit` |
| SQL | UPSERT `ON CONFLICT (nit)` |

**Dependencias:** tabla `01`. Sin lookup.

---

### `wf_brg_persona_uuid.hwf`

| | |
|---|---|
| Pipeline | `brg_persona_uuid.hpl` → `stg_brg_persona_uuid` |
| Destino | `tbl_brg_persona_uuid` |
| NK | `(idcliente, COALESCE(nit,-1))` — índice único expresional |
| SQL | `ON CONFLICT (idcliente, (COALESCE(nit, -1)))` |

**Dependencias:** `wf_dim_persona` (lookup `sk_persona`). UUID solo JSON queda con `sk_persona` NULL.

---

### `wf_dim_plan.hwf`

| | |
|---|---|
| Pipeline | `dim_plan.hpl` → `stg_dim_plan` |
| Destino | `tbl_dim_plan` |
| NK | `id_plan` |
| SQL | UPSERT `ON CONFLICT (id_plan)` |

---

### `wf_dim_contrato.hwf`

| | |
|---|---|
| Pipeline | `dim_contrato.hpl` → `stg_dim_contrato` |
| Destino | `tbl_dim_contrato` |
| NK | `idcontrato` |
| SQL | UPSERT `ON CONFLICT (idcontrato)` |

No passwords (el HPL no los trae).

---

### `wf_dim_geografia_v2.hwf`

| | |
|---|---|
| Pipeline | `dim_geografia_v2.hpl` → `stg_dim_geografia` |
| Destino | `tbl_dim_geografia` |
| NK | `id_barrio` integer |
| SQL | UPSERT `ON CONFLICT (id_barrio)` — columnas nuevas (`dpto`,`mun`; sin zona/estrato/coordenada) |

**BLOQUEO:** no programar contra el stg/tbl viejos. Dummy `id_barrio=0` + seed `04` para SK 0.

**Dependencias:** `03` REPLACE geo, `04` seed. Sucursal debe correr **después** en cutover.

---

### `wf_dim_sucursal.hwf`

| | |
|---|---|
| Pipeline | `dim_sucursal.hpl` → `stg_dim_sucursal` |
| Destino | `tbl_dim_sucursal` |
| NK | `(nit, idsuc)` |
| SQL | UPSERT lookups `sk_persona`, `sk_geografia`, `sk_perfil_cartera` |

**Dependencias:** persona, perfil; geo (CAST dual-run o v2 tras cutover). No guarda `idcontrato`.

---

### `wf_dim_producto_erp.hwf`

| | |
|---|---|
| Pipeline | `dim_producto_erp.hpl` → `stg_dim_producto_erp` |
| Destino | `tbl_dim_producto_erp` |
| NK | `id_producto` |
| SQL | UPSERT `ON CONFLICT (id_producto)` |

Dual-run con `wf_dim_servicio` (no se toca).

---

### `wf_brg_sucursal_contrato.hwf`

| | |
|---|---|
| Pipeline | `brg_sucursal_contrato.hpl` → `stg_brg_sucursal_contrato` |
| Destino | `tbl_brg_sucursal_contrato` |
| NK | `(nit, idsuc, idcontrato)` |
| SQL | UPSERT; `sk_contrato` puede ser NULL (mismatch) |

**Dependencias:** sucursal, contrato.

---

### `wf_brg_contrato_plan.hwf`

| | |
|---|---|
| Pipeline | `brg_contrato_plan.hpl` → `stg_brg_contrato_plan` |
| Destino | `tbl_brg_contrato_plan` |
| NK | `idcontrato` |
| SQL | UPSERT `ON CONFLICT (idcontrato)` (también UNIQUE `sk_contrato` en tbl) |

**Dependencias:** contrato, plan.

---

### `wf_fact_pago_aplicacion.hwf`

| | |
|---|---|
| Pipeline | `fact_pago_aplicacion.hpl` → `stg_fact_pago_aplicacion` |
| Destino | `tbl_fact_pago_aplicacion` |
| NK | `(idsuc, prefijo, numero, rc_idsuc, rc_prefijo, rc_numero)` |
| SQL | UPSERT esa 6-upla. `pagorc` no se agrega |

**Dependencias:** persona, sucursal, documento, tiempo (LEFT en el HPL). Staging de pago **no** colisiona con el modelo viejo.

---

### `wf_fact_pago_pasarela.hwf`

| | |
|---|---|
| Pipeline | `fact_pago_pasarela.hpl` → `stg_fact_pago_pasarela` |
| Destino | `tbl_fact_pago_pasarela` |
| NK | `id_pago_digital` |
| SQL | UPSERT `ON CONFLICT (id_pago_digital)` |

---

### `wf_fact_facturacion_v2.hwf`

| | |
|---|---|
| Pipeline | `fact_facturacion_v2.hpl` → `stg_fact_facturacion` |
| Destino | `tbl_fact_facturacion` |
| NK | `(idsuc, prefijo, numero, pos)` |
| SQL | UPSERT; `sk_contrato`/`sk_plan` salen NULL del HPL |

**BLOQUEO: no ejecutar.** Esperar 07 B (facts viejos) + `03` layout nuevo + `02` tbl nueva.

---

### `wf_fact_cartera_v2.hwf`

| | |
|---|---|
| Pipeline | `fact_cartera_v2.hpl` → `stg_fact_cartera` |
| Destino | `tbl_fact_cartera` |
| NK | `(idsuc, prefijo, numero, cuenta, nit, sucursal, ref_doc, ref_num)` |
| SQL | **1)** `DELETE` de `tbl` cuya NK no está en `stg` (snapshot latest-open). **2)** UPSERT `ON CONFLICT` esa 8-upla. `sendOneStatement=N` |

**BLOQUEO: no ejecutar.** El DELETE sobre el tbl viejo (otra NK) sería destructivo e incorrecto. Esperar REPLACE de stg y tbl.

---

## `wf_actualizacion_silver_v2.hwf`

Encadena los 16 pasos. Llama a `wf_dim_tiempo` y `wf_dim_documento` **existentes** (sin modificarlos). No llama a `wf_dim_cliente`, `wf_dim_servicio`, `wf_dim_geografia`, `wf_fact_facturacion`, `wf_fact_cartera` (Silver viejo sigue con `wf_actualizacion_silver`).

No ejecuta DDL. No ejecuta `07`. Hops de geo v2 y facts v2 deshabilitados (ver arriba).

---

## Inventario creado

```
Workflows/wf_dim_perfil_cartera.hwf
Workflows/wf_dim_persona.hwf
Workflows/wf_brg_persona_uuid.hwf
Workflows/wf_dim_plan.hwf
Workflows/wf_dim_contrato.hwf
Workflows/wf_dim_geografia_v2.hwf
Workflows/wf_dim_sucursal.hwf
Workflows/wf_dim_producto_erp.hwf
Workflows/wf_brg_sucursal_contrato.hwf
Workflows/wf_brg_contrato_plan.hwf
Workflows/wf_fact_pago_aplicacion.hwf
Workflows/wf_fact_pago_pasarela.hwf
Workflows/wf_fact_facturacion_v2.hwf
Workflows/wf_fact_cartera_v2.hwf
Workflows/wf_actualizacion_silver_v2.hwf
```

No modificado: `wf_actualizacion_silver.hwf`, `wf_dim_cliente.hwf`, `wf_dim_servicio.hwf`, `wf_dim_geografia.hwf`, `wf_dim_tiempo.hwf`, `wf_dim_documento.hwf`, `wf_fact_facturacion.hwf`, `wf_fact_cartera.hwf`, `wf_delta.hwf`, `wf_historic.hwf`.

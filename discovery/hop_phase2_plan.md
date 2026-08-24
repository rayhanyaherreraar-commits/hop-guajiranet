# Hop Fase 2 — pipelines Silver definitivo

**Fecha:** 2026-08-24  
**Especificación:** `discovery/silver_ddl_plan.md`  
**DDL real:** `discovery/silver_ddl_implementation.md`  
**Alcance:** 14 HPL nuevos. Carga **solo** `stg_*` (TRUNCATE + PGBulkLoader).  
**No se ejecutó SQL contra Aurora. No se tocó Gold. No se modificaron HPL/HWF viejos. No hay workflows nuevos.**

**No ejecutar todavía:** `fact_facturacion_v2` ni `fact_cartera_v2`. Sus `stg_*` actuales son del modelo viejo.

Patrón (igual que Silver actual):

```text
Table input (SQL) → String operations | Select values → PostgreSQL Bulk Loader TRUNCATE → stg_*
```

El UPSERT a `tbl_*` sigue siendo responsabilidad del workflow (Fase 3). Los HPL **no** contienen `INSERT … ON CONFLICT`.

---

## Dual-run

| Pipeline nuevo | Staging | ¿Colisiona con un HPL viejo? |
|---|---|---|
| `dim_persona`, `dim_sucursal`, `dim_contrato`, `dim_plan`, `dim_producto_erp`, `dim_perfil_cartera`, 3 `brg_*`, 2 `fact_pago_*` | nombres nuevos | No. Dual-run real junto a cliente/servicio/facts viejos. |
| `dim_geografia_v2` | `stg_dim_geografia` | **Sí** (layout: `id_barrio` integer + `dpto`/`mun` vs varchar + zona/estrato). El HPL viejo `dim_geografia.hpl` no se toca. No programar v2 hasta REPLACE de ese stg (07 B + `03`). |
| `fact_facturacion_v2` | `stg_fact_facturacion` | **Sí.** **BLOQUEO: no ejecutar.** El stg actual es `posicion_factura` / `sk_cliente`. Esperar 07 B + `03`. |
| `fact_cartera_v2` | `stg_fact_cartera` | **Sí.** **BLOQUEO: no ejecutar.** El stg actual no tiene `idsuc`. Esperar 07 B + `03`. |

`dim_cliente.hpl`, `dim_servicio.hpl`, `dim_geografia.hpl`, `fact_facturacion.hpl`, `fact_cartera.hpl` y todos los `.hwf` quedan intactos.

---

## Orden de dependencias (cuando exista workflow)

```text
KEEP: dim_tiempo, dim_documento
      dim_geografia.hpl viejo sigue en dual-run (no se modifica)

1. dim_perfil_cartera
2. dim_persona
3. brg_persona_uuid
4. dim_plan
5. dim_contrato
6. dim_geografia_v2            ← ANTES de sucursal (grano mabarrio; dummy id_barrio=0)
7. dim_sucursal                (persona + geo v2 + perfil)
8. dim_producto_erp
9. brg_sucursal_contrato
10. brg_contrato_plan
11. fact_pago_aplicacion / fact_pago_pasarela
12. fact_facturacion_v2 / fact_cartera_v2
    BLOQUEO: no ejecutar hasta cutover de stg_fact_* (07 B + 03)
```

`dim_geografia_v2` es prerrequisito de `dim_sucursal`. Mientras `stg_dim_geografia` / `tbl_dim_geografia` sean el modelo viejo, sucursal puede resolver geo con CAST; el cutover de geo va antes de apuntar sucursal al modelo nuevo.

---

## 1. `dim_persona.hpl`

| Campo | Valor |
|---|---|
| Fuente | `bronze_guajiranet.materceros` |
| Grano | 1 fila = 1 `nit` |
| NK | `nit` (integer, sin CAST a varchar) |
| Lookup | ninguno |
| Destino | `silver_guajiranet.stg_dim_persona` |
| Limpieza | trim razón social / `idcliente`; UPPER `tipo_persona`, `es_cliente`, `es_proveedor` |

**SQL:** solo `materceros`. Carga `idcliente` aunque no sea único (5 UUID con 2 nit). No hay join a sucursal.

**Riesgos:** duplicados de `nit` en Bronze romperían el UPSERT futuro. `idcliente` nulo en terceros sin UUID.

**Dependencias:** ninguna Silver.

---

## 2. `dim_sucursal.hpl`

| Campo | Valor |
|---|---|
| Fuente | `bronze_guajiranet.matercerosuc` |
| Grano | `(nit, idsuc)` — se conservan 11 `idsuc=0` |
| NK | `(nit, idsuc)` |
| Lookup | `tbl_dim_persona` INNER `nit`; `tbl_dim_geografia` LEFT `CAST(idbarrio AS VARCHAR)=CAST(id_barrio AS VARCHAR)` → `COALESCE(sk,0)`; `tbl_dim_perfil_cartera` LEFT `COALESCE(idperfilcartera,0)=id_perfil` → `COALESCE(sk,0)` |
| Destino | `stg_dim_sucursal` |
| Limpieza | trim dirección/razón; ciudad UPPER; email lower |

**No** selecciona `idcontrato` (va al bridge). **No** duplica atributos de persona salvo `nit` de la NK.

CAST de geografía: dual-run con `id_barrio` varchar (modelo viejo) o integer (nuevo).

**Riesgos:** INNER persona descarta sucursales huérfanas (cobertura nit 100% en discovery). Geo vieja: dummy `'0'` **no** garantiza `sk_geografia=0`. Perfil 0 / nulo requiere fila `id_perfil=0` en `tbl_dim_perfil_cartera` (seed 04 o UPSERT del dummy).

**Dependencias:** `dim_persona`, `dim_perfil_cartera`, **`dim_geografia_v2`** (geo antes de sucursal). Mientras el tbl de geo siga viejo, el CAST de `id_barrio` permite dual-run; tras cutover, el lookup es integer y SK 0 es el dummy.

---

## 2b. `dim_geografia_v2.hpl`

| Campo | Valor |
|---|---|
| Fuente | `bronze_guajiranet.mabarrio` LEFT JOIN `madepartamentos` `ON dpto` LEFT JOIN `maciudades` `ON (mun, dpto)` |
| Grano | 1 fila = 1 `idbarrio` (PK de `mabarrio`). **No** `matercerosuc`. |
| NK | `id_barrio` integer |
| Lookup | ninguno (joins solo de atributo municipio/departamento) |
| Destino | `silver_guajiranet.stg_dim_geografia` |
| Limpieza | trim + UPPER barrio / municipio / departamento |

Dummy `id_barrio=0` (`SIN BARRIO` / `SIN MUNICIPIO` / `SIN DEPARTAMENTO`). `WHERE idbarrio IS DISTINCT FROM 0` en el maestro evita duplicar el dummy. Sin `GROUP BY`. Sin zona/estrato/coordenada (van a sucursal).

SK 0 en `tbl_*` lo fija `04_seed_unknown_members.sql` + UPSERT futuro; el HPL solo escribe `id_barrio=0` en staging.

**Riesgos:** colisión de stg con `dim_geografia.hpl` viejo (no programar v2 hasta REPLACE). `maciudades` es lookup de nombre, no grano.

**Dependencias:** ninguna Silver. **Sucursal depende de esta dim.**

---

## 3. `dim_contrato.hpl`

| Campo | Valor |
|---|---|
| Fuente | `bronze_guajiranet.tmjsoncontract` |
| Grano | 1 `idcontrato` = `datajson->>'id'` |
| NK | `idcontrato` |
| Lookup | ninguno |
| Destino | `stg_dim_contrato` |

Extrae con operadores jsonb: `client_id`, `public_id`, `state`, `start_date`, `created_at`, `updated_at`, `address_*`, `latitude`, `longitude`, `ont_*`, `olt_id`, `interface_gpon`, `mac_address`, `plan_id`.

**No** lee `pppoe_password` ni `wifi_password`. `plan_id` es degenerada; el vínculo canónico es `brg_contrato_plan`.

**Riesgos:** `latitude`/`longitude`/`public_id` CAST fallan si el JSON no es numérico. Fechas ISO con offset → `timestamptz`.

**Dependencias:** ninguna Silver.

---

## 4. `dim_plan.hpl`

| Campo | Valor |
|---|---|
| Fuente | `bronze_guajiranet.tmjsonplan_server` `WHERE tipo='P'` |
| Grano | 1 `id_plan` = `datajson->>'id'` (UUID; **no** `tmjsonplan_server.id` integer) |
| NK | `id_plan` |
| Lookup | ninguno |
| Destino | `stg_dim_plan` |

Extrae `name`, `public_id`, `ceil_down_kbps`, `ceil_up_kbps`, `cir`, `price`→`precio`, `frequency_in_months`, `contracts_count`, `created_at`, `updated_at`.

Tipo S fuera de alcance. No es catálogo ERP.

**Riesgos:** `price` es string JSON; CAST a numeric. 282 filas esperadas.

**Dependencias:** ninguna Silver.

---

## 5. `dim_producto_erp.hpl`

| Campo | Valor |
|---|---|
| Fuente | `maproductos` LEFT JOIN `mafamiliasproductos` `ON idfam1=idfamilia` |
| Grano | 1 `idproducto` |
| NK | `id_producto` varchar(25) |
| Lookup | ninguno (join de atributo `categoria`) |
| Destino | `stg_dim_producto_erp` |

Columnas: `nombre_producto`, `id_familia`, `categoria`, `tarifa_lista` (`lista1`), `estado_activo`. **No** se llama plan ISP. Dual-run con `dim_servicio.hpl` (ese sigue aliasando `nombre_plan`).

**Riesgos:** `LEFT JOIN` familia si `idfamilia` no es único. 0 overlap UUID con `dim_plan`.

**Dependencias:** ninguna Silver.

---

## 6. `dim_perfil_cartera.hpl`

| Campo | Valor |
|---|---|
| Fuente | `bronze_guajiranet.maperfilcartera` + fila dummy |
| Grano | 1 `id_perfil` |
| NK | `id_perfil` |
| Lookup | ninguno |
| Destino | `stg_dim_perfil_cartera` |

Dummy: `id_perfil=0`, `denominacion='DESCONOCIDO'`. El HPL **no** escribe SK (staging sin SK). `sk_perfil_cartera=0` lo crea `04_seed_unknown_members.sql` en `tbl_*`; el UPSERT futuro actualiza esa fila.

`WHERE p.id IS DISTINCT FROM 0` evita duplicar el dummy si el origen ya trae código 0.

**Riesgos:** nombres Bronze (`diasvence1`, `nofactura`, …) tomados del plan; si el origen difiere, el Table input falla. Seed 04 debe correr **antes** del primer UPSERT o la sequence asignaría SK ≠ 0 al dummy.

**Dependencias:** ninguna para stg; 04_seed para SK 0 en tbl.

---

## 7. `brg_persona_uuid.hpl`

| Campo | Valor |
|---|---|
| Fuente | `materceros` FULL OUTER JOIN `tmjsonclient` por `idcliente` |
| Grano | 1 fila = 1 par `(idcliente, nit)` — un UUID puede tener varios NIT |
| NK | `(idcliente, nit)` con `nit` NULL si solo JSON; UNIQUE expresional en tbl: `(idcliente, COALESCE(nit,-1))` |
| Lookup | `tbl_dim_persona` LEFT por `nit` (`sk_persona` NULL si UUID sin nit) |
| Destino | `stg_brg_persona_uuid` |

Flags `en_materceros` / `en_tmjsonclient`. Filtra `idcliente` nulo. `tmjsonclient` no tiene columna `nit`.

**Riesgos:** terceros con `idcliente` vacío no entran. FULL OUTER JOIN puede inflar si JSON deja de ser único en `idcliente` (hoy sí lo es).

**Dependencias:** `dim_persona` (lookup; UUID solo JSON siguen saliendo con `sk_persona` NULL).

---

## 8. `brg_sucursal_contrato.hpl`

| Campo | Valor |
|---|---|
| Fuente | `matercerosuc WHERE idcontrato IS NOT NULL` |
| Grano / NK | `(nit, idsuc, idcontrato)` |
| Lookup | sucursal INNER `(nit,idsuc)`; contrato LEFT `idcontrato` |
| Destino | `stg_brg_sucursal_contrato` |

`match_json = (sk_contrato IS NOT NULL)`. Mismatches (UUID en suc, ausente en JSON) **se conservan** con `sk_contrato` NULL. 532 contratos solo JSON **no** entran (no hay sucursal).

**Riesgos:** INNER sucursal pierde filas si `dim_sucursal` no se cargó. 2 UUID duplicados en suc: dos filas NK distintas, `sk_contrato` NULL.

**Dependencias:** `dim_sucursal`; `dim_contrato` para match_json.

---

## 9. `brg_contrato_plan.hpl`

| Campo | Valor |
|---|---|
| Fuente | `tmjsoncontract` |
| Grano / NK | `idcontrato` (N:1 vigente, sin histórico) |
| Lookup | contrato INNER `datajson->>'id'`; plan INNER `datajson->>'plan_id'` |
| Destino | `stg_brg_contrato_plan` |

INNER plan: `sk_plan` es NOT NULL en tbl. Discovery: cobertura plan_id tipo P 100%.

**Riesgos:** contrato sin `plan_id` o plan no tipo P no entra. Sin SCD2: un cambio de plan en JSON pisa la fila.

**Dependencias:** `dim_contrato`, `dim_plan`.

---

## 10. `fact_facturacion_v2.hpl`

| Campo | Valor |
|---|---|
| Fuente | `trfacturas` INNER JOIN `trfacturasdet` |
| Grano / NK | `(idsuc, prefijo, numero, pos)` = PK Bronze del detalle |
| Lookup | sucursal INNER `(nit, sucursal)`; persona INNER `nit`; producto INNER `idproducto`; documento INNER `(idsuc,prefijo)`; tiempo INNER `fecha`; geo = `COALESCE(suc.sk_geografia,0)` |
| Destino | `stg_fact_facturacion` |
| Contrato / plan | `CAST(NULL AS integer)` — **no** join a contrato vigente de sucursal, **no** join de plan por nombre |

Limpieza: Select values (mismo estilo que `fact_facturacion.hpl` viejo). Sin MERGE.

**BLOQUEO:** no ejecutar. `stg_fact_facturacion` actual pertenece al modelo viejo.

**Riesgos:** INNER dims tiran líneas huérfanas (producto/documento/fecha fuera de 2020–2035 / sucursal no dimensionada). Gold sigue leyendo el fact viejo hasta cutover.

**Dependencias:** persona, sucursal, producto_erp, documento, tiempo. Geo vía sucursal.

---

## 11. `fact_cartera_v2.hpl`

| Campo | Valor |
|---|---|
| Fuente | `bronze_guajiranet.tmcartera` — **no** `vmovcartera` |
| Grano | latest-open: `DISTINCT ON (idsuc,prefijo,numero,cuenta,nit,sucursal,ref_doc,ref_num)` `WHERE saldo <> 0` `ORDER BY … fecha DESC` |
| NK | la misma 8-upla |
| Lookup | sucursal INNER; persona INNER; tiempo INNER `tmcartera.fecha` (no `fecha_actualizacion`); perfil = `COALESCE(suc.sk_perfil_cartera,0)` |
| Destino | `stg_fact_cartera` |

Medidas: saldo, debito, credito, rango1–6, interes, plazo, dias, fvence, idformapago, transaccion.

El DELETE de NK cerrados es del workflow futuro, no de este HPL.

**`conteo`:** no se usa. Evidencia de discovery (sin consultar Aurora): `model_audit.md` lista columnas de `tmcartera` sin `conteo`; `fact_cartera_pagos_audit.json` define la versión como `fecha`. Desempate solo `fecha DESC`.

**BLOQUEO:** no ejecutar. `stg_fact_cartera` actual pertenece al modelo viejo.

**Riesgos:** INNER tiempo descarta `fecha` nula o fuera de calendario. Snapshot ~28 797 latest-open vs Silver viejo ~15 857: no comparables. Empate en `fecha`: DISTINCT ON no es determinista.

**Dependencias:** persona, sucursal, tiempo, perfil (vía sucursal).

---

## 12. `fact_pago_aplicacion.hpl`

| Campo | Valor |
|---|---|
| Fuente | `bronze_guajiranet.vpagodiasfactura` |
| Grano / NK | `DISTINCT ON (idsuc,prefijo,numero,rc_idsuc,rc_prefijo,rc_numero)` |
| Medida | `carteraaplicado`; `pagorc` se copia (total del recibo) — **no** se suma por factura |
| Lookup | LEFT vía `trfacturas` → sucursal/persona; documento `(idsuc,prefijo)`; tiempo factura `v.fecha`; tiempo recibo `v.rc_fecha` |
| Destino | `stg_fact_pago_aplicacion` |

Lookups nullable (huérfanos permitidos). Vista origen stale (máx `rc_fecha` 2026-06-16 en discovery).

**Riesgos:** `ccosto` / `fecha` / `rc_fecha` según catálogo Bronze; si un nombre no existe, falla el SQL. DISTINCT ON toma una fila arbitraria del grupo (medidas constantes salvo basura).

**Dependencias:** persona, sucursal, documento, tiempo (LEFT: el fact sale igual sin match).

---

## 13. `fact_pago_pasarela.hpl`

| Campo | Valor |
|---|---|
| Fuente | `bronze_guajiranet.trpagodigital` |
| Grano / NK | `id` → `id_pago_digital` |
| Lookup | LEFT factura `(idsuc,prefijo,numero)` → sucursal/persona; tiempo `foperacion::date` |
| Destino | `stg_fact_pago_pasarela` |

Varios eventos por factura son válidos (59 facturas con >1 id). **No** es subconjunto de `vpagodiasfactura`. Facts paralelos.

**Riesgos:** nombres `rec_*`, `numero_recibo`, `numero_autorizacion`, `referencia`, `numero_orden`, `codigo_respuesta` tomados del plan. Si Bronze usa otro nombre, ajustar el SQL.

**Dependencias:** persona, sucursal, tiempo (LEFT).

---

## Qué no hay en Fase 2

- Workflows (`wf_dim_persona`, orquestador, MERGE)
- Cambio a `wf_actualizacion_silver`
- Recreación de `stg_fact_*` / `stg_dim_geografia` / `tbl_fact_*` en Aurora (siguen bloqueados por el modelo viejo)
- Modificar pipelines KEEP (`dim_tiempo`, `dim_documento`, **`dim_geografia.hpl` actual**)
- Gold / DROP de cliente-servicio
- Ejecutar `fact_facturacion_v2` o `fact_cartera_v2`

---

## Inventario de archivos

```
Pipelines/dim_persona.hpl
Pipelines/dim_sucursal.hpl
Pipelines/dim_geografia_v2.hpl
Pipelines/dim_contrato.hpl
Pipelines/dim_plan.hpl
Pipelines/dim_producto_erp.hpl
Pipelines/dim_perfil_cartera.hpl
Pipelines/brg_persona_uuid.hpl
Pipelines/brg_sucursal_contrato.hpl
Pipelines/brg_contrato_plan.hpl
Pipelines/fact_facturacion_v2.hpl
Pipelines/fact_cartera_v2.hpl
Pipelines/fact_pago_aplicacion.hpl
Pipelines/fact_pago_pasarela.hpl
```

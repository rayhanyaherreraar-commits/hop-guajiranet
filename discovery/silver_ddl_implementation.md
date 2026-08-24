# Implementación DDL Silver definitivo (Fase 1)

**Fecha:** 2026-08-24  
**Especificación:** `discovery/silver_ddl_plan.md`  
**Alcance:** solo SQL/DDL. No se ejecutó nada contra Aurora. No se tocó HPL/HWF ni Gold.

---

## 1. Archivos creados

| Archivo | Rol |
|---|---|
| `sql/silver/01_create_dims.sql` | KEEP tiempo/documento; CREATE dims nuevas; REPLACE geografía si el nombre está libre |
| `sql/silver/02_create_bridges_facts.sql` | CREATE bridges + facts de pago; REPLACE facturación/cartera si el nombre está libre |
| `sql/silver/03_create_staging.sql` | KEEP stg tiempo/documento; CREATE stg nuevas; REPLACE stg geo/facts si el nombre está libre |
| `sql/silver/04_seed_unknown_members.sql` | SK 0 geografía y perfil cartera + `setval` |
| `sql/silver/05_drop_fk.sql` | `DROP CONSTRAINT IF EXISTS` de todas las FK de 06 |
| `sql/silver/06_create_fk.sql` | FK `NOT VALID` (helper temporal, se elimina al final del script) |
| `sql/silver/07_drop_obsolete.sql` | DROP post-cutover. **No ejecutar en Fase 1.** |

Orden de aplicación previsto (cuando se autorice Aurora): `01 → 02 → 03 → 04` → carga Hop → `06`. `05` solo en ciclos posteriores. `07` tras cutover Gold.

---

## 2. Tablas

### KEEP (sin recrear)

| Tabla | Acción en scripts |
|---|---|
| `tbl_dim_tiempo` | `UNIQUE (fecha)` + `CHECK (sk_tiempo = to_char(fecha,'YYYYMMDD')::int)` si no existen |
| `stg_dim_tiempo` | verificación de existencia |
| `tbl_dim_documento` | índice opcional `tipodoc` |
| `stg_dim_documento` | verificación de existencia |

### CREATE (nombres nuevos, paralelo al modelo actual)

**DIM:** `tbl_dim_persona`, `tbl_dim_sucursal`, `tbl_dim_contrato`, `tbl_dim_plan`, `tbl_dim_producto_erp`, `tbl_dim_perfil_cartera`  
**BRG:** `tbl_brg_persona_uuid`, `tbl_brg_sucursal_contrato`, `tbl_brg_contrato_plan`  
**FACT:** `tbl_fact_pago_aplicacion`, `tbl_fact_pago_pasarela`  
**STG:** `stg_dim_persona`, `stg_dim_sucursal`, `stg_dim_contrato`, `stg_dim_plan`, `stg_dim_producto_erp`, `stg_dim_perfil_cartera`, `stg_brg_persona_uuid`, `stg_brg_sucursal_contrato`, `stg_brg_contrato_plan`, `stg_fact_pago_aplicacion`, `stg_fact_pago_pasarela`

### REPLACE mismo nombre (no se DROP ahora)

| Tabla | Detector modelo nuevo | Si existe modelo viejo |
|---|---|---|
| `tbl_dim_geografia` / `stg_dim_geografia` | `id_barrio integer` | NOTICE **BLOQUEO**; 07 sección B |
| `tbl_fact_facturacion` / `stg_fact_facturacion` | columna `pos` | NOTICE **BLOQUEO**; 07 sección B |
| `tbl_fact_cartera` / `stg_fact_cartera` | columna `idsuc` | NOTICE **BLOQUEO**; 07 sección B |

`tbl_dim_cliente` / `tbl_dim_servicio` y sus `stg_*` **no se ALTER ni DROP** en 01–06. Solo 07 sección A.

---

## 3. NK / SK

| Tabla | SK (PK, sequence) | NK / UNIQUE |
|---|---|---|
| `tbl_dim_persona` | `sk_persona` → `tbl_dim_persona_sk_persona_seq` | `nit` |
| `tbl_dim_sucursal` | `sk_sucursal` → `tbl_dim_sucursal_sk_sucursal_seq` | `(nit, idsuc)` |
| `tbl_dim_contrato` | `sk_contrato` → `tbl_dim_contrato_sk_contrato_seq` | `idcontrato` |
| `tbl_dim_plan` | `sk_plan` → `tbl_dim_plan_sk_plan_seq` | `id_plan` |
| `tbl_dim_producto_erp` | `sk_producto` → `tbl_dim_producto_erp_sk_producto_seq` | `id_producto` |
| `tbl_dim_geografia` | `sk_geografia` → `tbl_dim_geografia_sk_geografia_seq` (**0 = desconocido**) | `id_barrio` integer |
| `tbl_dim_documento` | `sk_documento` (KEEP) | `(idsuc, prefijo)` |
| `tbl_dim_tiempo` | `sk_tiempo` YYYYMMDD (KEEP, sin sequence) | PK `sk_tiempo` + `UNIQUE (fecha)` |
| `tbl_dim_perfil_cartera` | `sk_perfil_cartera` → `tbl_dim_perfil_cartera_sk_perfil_cartera_seq` (**0 = desconocido**) | `id_perfil` |
| `tbl_brg_persona_uuid` | `sk_brg_persona_uuid` | índice único `(idcliente, COALESCE(nit,-1))` |
| `tbl_brg_sucursal_contrato` | `sk_brg_sucursal_contrato` | `(nit, idsuc, idcontrato)` |
| `tbl_brg_contrato_plan` | `sk_brg_contrato_plan` | `UNIQUE (idcontrato)` y `UNIQUE (sk_contrato)` |
| `tbl_fact_facturacion` | `sk_fact_facturacion` bigint | `(idsuc, prefijo, numero, pos)` |
| `tbl_fact_cartera` | `sk_fact_cartera` bigint | `(idsuc, prefijo, numero, cuenta, nit, sucursal, ref_doc, ref_num)` |
| `tbl_fact_pago_aplicacion` | `sk_fact_pago_aplicacion` bigint | `(idsuc, prefijo, numero, rc_idsuc, rc_prefijo, rc_numero)` |
| `tbl_fact_pago_pasarela` | `sk_fact_pago_pasarela` bigint | `id_pago_digital` |

Sequences: `integer`/`bigint`, `START 1`, `DEFAULT nextval`. No son `IDENTITY`; el INSERT de SK 0 es explícito.

Staging: mismas columnas de negocio, **sin SK propia**, todo nullable. Excepción KEEP: `stg_dim_tiempo.sk_tiempo`.

---

## 4. FK (`06_create_fk.sql`, todas `NOT VALID`)

| Constraint | Origen | Destino |
|---|---|---|
| `fk_dim_sucursal_sk_persona` | `tbl_dim_sucursal.sk_persona` | `tbl_dim_persona.sk_persona` |
| `fk_dim_sucursal_sk_geografia` | `tbl_dim_sucursal.sk_geografia` | `tbl_dim_geografia.sk_geografia` |
| `fk_dim_sucursal_sk_perfil_cartera` | `tbl_dim_sucursal.sk_perfil_cartera` | `tbl_dim_perfil_cartera.sk_perfil_cartera` |
| `fk_brg_persona_uuid_sk_persona` | `tbl_brg_persona_uuid.sk_persona` | `tbl_dim_persona.sk_persona` |
| `fk_brg_sucursal_contrato_sk_sucursal` | `tbl_brg_sucursal_contrato.sk_sucursal` | `tbl_dim_sucursal.sk_sucursal` |
| `fk_brg_sucursal_contrato_sk_contrato` | `tbl_brg_sucursal_contrato.sk_contrato` | `tbl_dim_contrato.sk_contrato` |
| `fk_brg_contrato_plan_sk_contrato` | `tbl_brg_contrato_plan.sk_contrato` | `tbl_dim_contrato.sk_contrato` |
| `fk_brg_contrato_plan_sk_plan` | `tbl_brg_contrato_plan.sk_plan` | `tbl_dim_plan.sk_plan` |
| `fk_fact_facturacion_sk_sucursal` | `tbl_fact_facturacion.sk_sucursal` | `tbl_dim_sucursal.sk_sucursal` |
| `fk_fact_facturacion_sk_persona` | `tbl_fact_facturacion.sk_persona` | `tbl_dim_persona.sk_persona` |
| `fk_fact_facturacion_sk_producto` | `tbl_fact_facturacion.sk_producto` | `tbl_dim_producto_erp.sk_producto` |
| `fk_fact_facturacion_sk_documento` | `tbl_fact_facturacion.sk_documento` | `tbl_dim_documento.sk_documento` |
| `fk_fact_facturacion_sk_geografia` | `tbl_fact_facturacion.sk_geografia` | `tbl_dim_geografia.sk_geografia` |
| `fk_fact_facturacion_sk_tiempo` | `tbl_fact_facturacion.sk_tiempo` | `tbl_dim_tiempo.sk_tiempo` |
| `fk_fact_facturacion_sk_contrato` | `tbl_fact_facturacion.sk_contrato` | `tbl_dim_contrato.sk_contrato` |
| `fk_fact_facturacion_sk_plan` | `tbl_fact_facturacion.sk_plan` | `tbl_dim_plan.sk_plan` |
| `fk_fact_cartera_sk_sucursal` | `tbl_fact_cartera.sk_sucursal` | `tbl_dim_sucursal.sk_sucursal` |
| `fk_fact_cartera_sk_persona` | `tbl_fact_cartera.sk_persona` | `tbl_dim_persona.sk_persona` |
| `fk_fact_cartera_sk_tiempo` | `tbl_fact_cartera.sk_tiempo` | `tbl_dim_tiempo.sk_tiempo` |
| `fk_fact_cartera_sk_perfil_cartera` | `tbl_fact_cartera.sk_perfil_cartera` | `tbl_dim_perfil_cartera.sk_perfil_cartera` |
| `fk_fact_pago_aplicacion_sk_sucursal` | `tbl_fact_pago_aplicacion.sk_sucursal` | `tbl_dim_sucursal.sk_sucursal` |
| `fk_fact_pago_aplicacion_sk_persona` | `tbl_fact_pago_aplicacion.sk_persona` | `tbl_dim_persona.sk_persona` |
| `fk_fact_pago_aplicacion_sk_documento` | `tbl_fact_pago_aplicacion.sk_documento` | `tbl_dim_documento.sk_documento` |
| `fk_fact_pago_aplicacion_sk_tiempo_factura` | `tbl_fact_pago_aplicacion.sk_tiempo_factura` | `tbl_dim_tiempo.sk_tiempo` |
| `fk_fact_pago_aplicacion_sk_tiempo_recibo` | `tbl_fact_pago_aplicacion.sk_tiempo_recibo` | `tbl_dim_tiempo.sk_tiempo` |
| `fk_fact_pago_pasarela_sk_sucursal` | `tbl_fact_pago_pasarela.sk_sucursal` | `tbl_dim_sucursal.sk_sucursal` |
| `fk_fact_pago_pasarela_sk_persona` | `tbl_fact_pago_pasarela.sk_persona` | `tbl_dim_persona.sk_persona` |
| `fk_fact_pago_pasarela_sk_tiempo` | `tbl_fact_pago_pasarela.sk_tiempo` | `tbl_dim_tiempo.sk_tiempo` |

Si falta tabla/columna (facts aún viejos), 06 hace `NOTICE` y sigue. `05` es el inverso por nombre.

---

## 5. Índices

Además de PK y UNIQUE NK:

| Tabla | Índices btree |
|---|---|
| `tbl_dim_documento` | `tipodoc` |
| `tbl_dim_geografia` | `(dpto, mun)` — solo si el modelo nuevo existe |
| `tbl_dim_persona` | `idcliente` |
| `tbl_dim_sucursal` | `sk_persona`, `sk_geografia`, `sk_perfil_cartera`, `fecharetiroisp` |
| `tbl_dim_contrato` | `idcliente`, `plan_id`, `state` |
| `tbl_dim_producto_erp` | `id_familia` |
| `tbl_brg_persona_uuid` | `idcliente`, `sk_persona` + unique expresional NK |
| `tbl_brg_sucursal_contrato` | `sk_sucursal`, `sk_contrato`, `idcontrato` |
| `tbl_brg_contrato_plan` | `sk_plan`, `id_plan` |
| `tbl_fact_facturacion` | todas las `sk_*`, `fecha_factura` |
| `tbl_fact_cartera` | todas las `sk_*`, `fecha`, `fecha_vencimiento` |
| `tbl_fact_pago_aplicacion` | todas las `sk_*` |
| `tbl_fact_pago_pasarela` | `sk_*`, `(idsuc, prefijo, numero)`, `foperacion`, `codigo_respuesta` |

---

## 6. Diferencias plan vs implementación

1. **Dual-run / mismo nombre.** El plan dice REPLACE geografía y REBUILD facts. No se puede `CREATE TABLE` del modelo nuevo mientras el viejo ocupa el nombre. Los scripts **no ALTER-destructivo** ni DROP ahora: si detectan el esquema viejo, emiten BLOQUEO y continúan con el resto. El DROP está solo en `07` sección B, y después hay que re-ejecutar `01`/`02`/`03`/`04`.
2. **`tbl_brg_persona_uuid` NK.** El plan permite UNIQUE `(idcliente, nit)` *o* índice `(idcliente, COALESCE(nit,-1))`. Se implementó el índice expresional porque `nit` es NULL en UUID solo JSON y UNIQUE SQL no trata dos NULL como distintos de forma útil para el UPSERT.
3. **Nombres de sequence de pago/brg.** El JSON abreviado (`tbl_fact_pago_aplicacion_sk_seq`). Se usó el patrón vivo `tbl_<tabla>_<sk>_seq` (como `tbl_dim_cliente_sk_cliente_seq`).
4. **CHECK tiempo.** El JSON lo marca opcional; el markdown §4 lo pide. Se añade; si las filas actuales no cumplen, 01 no aborta (NOTICE BLOQUEO).
5. **Seed perfil `denominacion='DESCONOCIDO'`.** El plan no fija el literal.
6. **Seed geo** `'SIN BARRIO' / 'SIN MUNICIPIO' / 'SIN DEPARTAMENTO'`. El plan indica el sentido, no los textos exactos.
7. **Sin CHECK `sk_contrato IS NULL` / `sk_plan IS NULL`** en facturación. Columnas nullable; la carga Hop las deja NULL. Un CHECK bloquearía un join futuro.
8. **`06` usa función temporal `_add_fk_not_valid`.** Se `DROP FUNCTION` al final; no queda objeto permanente.
9. **Staging incluye SK de lookup** (`sk_persona` en sucursal, etc.). El plan dice “destino menos SK” = sin la SK *propia*. Las SK de dimensión destino son columnas de carga.
10. **`07` usa `CASCADE`** en DROP de obsoletos para no quedar bloqueado por vistas Gold residuales o FK. Hay que ejecutar `05` antes.
11. **Índice `tipodoc`** en documento: el plan lo marca opcional; se creó.

No se copian `password` / `pppoe_password` / `wifi_password` / `logo`. No hay `INSERT SELECT *`.

---

## 7. Bloqueos encontrados (Aurora no ejecutado; bloqueos de diseño)

| Bloqueo | Efecto | Salida |
|---|---|---|
| `tbl_dim_geografia` vive con `id_barrio varchar` | 01/03/04 no recrean ni siembran SK 0 | Dual-run hasta 07 B + re-ejecutar 01/03/04 |
| `tbl_fact_facturacion` con `posicion_factura` / `sk_cliente` | 02/03 no recrean; 06 omite FK nuevas | 07 B + re-ejecutar 02/03/06. Gold hoy lee esta tabla: cutover de vistas **antes** del DROP |
| `tbl_fact_cartera` con `sk_cliente` y sin `idsuc` | igual | 07 B + re-ejecutar 02/03/06 |
| `stg_*` homónimos viejos | PGBulkLoader actual seguiría el layout viejo | No tocar HPL en Fase 1; el BLOQUEO es intencional |
| `tbl_dim_tiempo` / `stg_dim_tiempo` ausentes | 01/03 `RAISE EXCEPTION` | KEEP: deben existir antes |
| CHECK/UNIQUE tiempo si hay sucios/duplicados | NOTICE; constraint no queda | Limpiar datos y re-ejecutar 01 |
| SK 0 vs `id_barrio=0` ya asignado a otro SK | 04 no reasigna PK | NOTICE BLOQUEO |
| Sequence `tbl_dim_geografia_sk_geografia_seq` ya OWNED BY la tabla vieja | Inofensivo mientras el viejo viva; el DROP de 07 B se lleva la sequence | 01 vuelve a crearla al recrear la tabla |

**No bloqueado:** persona, sucursal, contrato, plan, producto_erp, perfil, los tres bridges y los dos facts de pago (nombres libres). Se pueden crear en paralelo a `tbl_dim_cliente` / `tbl_dim_servicio`.

---

## 8. Qué no se hizo (por diseño de Fase 1)

- Ejecutar SQL contra Aurora
- Modificar pipelines/workflows Hop
- Recrear vistas Gold
- DROP de `tbl_dim_cliente` / `tbl_dim_servicio` (solo escrito en 07)
- ALTER in-place de cliente, servicio, geografía o facts actuales

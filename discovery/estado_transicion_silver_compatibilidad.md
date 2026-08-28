# GuajiraNet — estado de transición (Silver v2 → compatibilidad Power BI)

**Fecha de este documento:** 2026-08-27  
**Audiencia:** siguiente chat (continuación, sin repetir discovery).  
**Alcance:** estado real del repositorio y de lo ejecutado contra Aurora. No hay secretos ni contenido de `.env`.

Leyenda de estado:

| Etiqueta | Significado |
|---|---|
| **HECHO** | Existe en disco y/o en Aurora; se implementó o se corrió. |
| **VALIDADO** | Medido con `09_validate_silver_v2.sql` (segunda corrida, post-calendario). |
| **PENDIENTE** | Siguiente fase; no iniciado. |
| **NO EJECUTADO** | Existe el artefacto; no se aplicó / no se tocó a propósito. |

Fuente de validación: CSV generado por Hop Table Input sobre `sql/silver/09_validate_silver_v2.sql` (`C:\Users\rayha\AppData\Local\Temp\silver_v2_validate.csv`). `psql` no está en PATH; el SQL es el mismo.

---

## 1. ESTADO ACTUAL DEL REPOSITORIO

| Campo | Valor |
|---|---|
| Remote | `https://github.com/rayhanyaherrerar-commits/hop-guajiranet.git` |
| Branch | `main` (tracking `origin/main`, up to date al momento de redactar) |
| HEAD | `751e36da5b85d2c0cfd50dba7d8eea442871a9fe` (`751e36d`) |
| Mensaje | `Enable dual-run Silver v2 load without dropping live tables.` |
| Fecha commit | 2026-08-27 22:38:55 -0500 |
| Commit anterior | `a1ab16e` — `Respaldo Silver GuajiraNet tras formateo del PC.` (2026-08-24) |

Hop CLI usado en esta máquina (no versionar secretos de conexión):

```text
C:\Users\rayha\OneDrive\Desktop\Arra\apache-hop-client-2.19.0\hop\hop-run.bat
--project=hop-guajiranet --environment=hop-guajiranet --runconfig=local
```

Conexión JDBC en metadatos Hop: `aws_rds`. Variables de `.env`: `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER` (y password local, **no documentada**). `.env` está en `.gitignore`. **No commitear** `metadata/rdbms/aws_rds.json`.

### 1.1 En HEAD (`751e36d`) — dual-run Silver v2

SQL: `sql/silver/01_create_dims.sql` … `08_create_dualrun_v2.sql` (05/06/07 existen; **no corridos**).  
Doc: `discovery/silver_v2_ejecucion.md` (escrito **antes** de las corridas Hop; la sección “no se ejecutó Hop” de ese archivo está **desactualizada**).  
Pipelines/workflows nuevos: persona, sucursal, contrato, plan, producto ERP, perfil, geo **v2**, 3 bridges, 2 pagos, facturación **v2**, cartera **v2**, orquestador `wf_actualizacion_silver_v2.hwf`.

### 1.2 En disco, **aún no en git** (local / untracked)

| Archivo | Notas |
|---|---|
| `sql/silver/09_validate_silver_v2.sql` | Script de validación SELECT-only. **Usado** contra Aurora vía Hop. |
| `discovery/silver_v2_validacion.md` | Primera validación (cartera 17 511 / B11=11 113). **Desactualizado** vs segunda corrida. |
| `Pipelines/dim_tiempo.hpl` | Calendario **1899-12-30 → 2035-12-31** + `gs::date`. **Ejecutado** en Aurora. **No está en git** (los KEEP viejos nunca se trackearon). |
| `Workflows/wf_dim_tiempo.hwf`, `wf_dim_documento.hwf` | KEEP; `wf_dim_tiempo` **sí se ejecutó**. Untracked. |
| Pipelines/workflows Silver **viejo** (`dim_cliente`, `dim_servicio`, `dim_geografia`, `fact_facturacion`, `fact_cartera`, `wf_actualizacion_silver`, `wf_delta`, `wf_historic`, …) | Untracked. **No se ejecutaron** en esta fase v2. |
| `project-config.json`, `metadata/rdbms/aws_rds.json` | Local. **No commitear** secretos. |

### 1.3 Este documento

`discovery/estado_transicion_silver_compatibilidad.md` — handoff. Sustituye como fuente de verdad operativa a `silver_v2_ejecucion.md` + la validación vieja.

---

## 2. SILVER V2 IMPLEMENTADO

Modelo aprobado **sin rediseño de grano**. Schema Aurora: `silver_guajiranet`. Bronze: `bronze_guajiranet`.

### 2.1 Dimensiones

| Entidad | Tabla física | NK / grano | SK | Dual-run |
|---|---|---|---|---|
| DIM_TIEMPO | `tbl_dim_tiempo` | 1 fila / día; `sk_tiempo = YYYYMMDD`; UNIQUE(`fecha`) | KEEP | Mismo objeto (compartido con Silver viejo) |
| DIM_DOCUMENTO | `tbl_dim_documento` | `(idsuc, prefijo)` | KEEP | Mismo objeto |
| DIM_PERFIL_CARTERA | `tbl_dim_perfil_cartera` | `id_perfil` | `sk_perfil_cartera` (**0 = desconocido**) | Nombre nuevo |
| DIM_PERSONA | `tbl_dim_persona` | `nit` | `sk_persona` (no hay SK 0) | Nombre nuevo |
| DIM_SUCURSAL | `tbl_dim_sucursal` | `(nit, idsuc)` | `sk_sucursal` | Nombre nuevo; lookup geo a **`tbl_dim_geografia_v2`** (`COALESCE(idbarrio,0)=id_barrio`) |
| DIM_PLAN | `tbl_dim_plan` | `id_plan` | `sk_plan` | Nombre nuevo; Hop omite id JSON vacío |
| DIM_CONTRATO | `tbl_dim_contrato` | `idcontrato` | `sk_contrato` | Nombre nuevo; Hop omite id JSON vacío |
| DIM_PRODUCTO_ERP | `tbl_dim_producto_erp` | `id_producto` | `sk_producto` | Nombre nuevo; `DISTINCT ON (idproducto)` |
| DIM_GEOGRAFIA | `tbl_dim_geografia_v2` | `id_barrio` integer | `sk_geografia` (**0 + `id_barrio=0` = dummy**) | **`*_v2`**. Vieja `tbl_dim_geografia` intacta |

Staging espejo: `stg_*` mismo nombre de negocio; geo/facts homónimos usan `stg_*_v2`. KEEP: `stg_dim_tiempo` (incluye `sk_tiempo`), `stg_dim_documento`.

### 2.2 Bridges

| Entidad | Tabla | NK |
|---|---|---|
| BRG_PERSONA_UUID | `tbl_brg_persona_uuid` | `(idcliente, nit)`; índice único `(idcliente, COALESCE(nit,-1))`. No UNIQUE(`idcliente`) (5 UUID con 2 nit). |
| BRG_SUCURSAL_CONTRATO | `tbl_brg_sucursal_contrato` | `(nit, idsuc, idcontrato)` |
| BRG_CONTRATO_PLAN | `tbl_brg_contrato_plan` | 1 fila / `idcontrato`; UNIQUE también `sk_contrato`; INNER a plan (`sk_plan` NOT NULL) |

### 2.3 Facts

| Entidad | Tabla física | NK / grano | Notas |
|---|---|---|---|
| FACT_FACTURACION | `tbl_fact_facturacion_v2` | `(idsuc, prefijo, numero, pos)` | INNER a sucursal, persona, producto, documento, tiempo. `sk_contrato`/`sk_plan` NULL (no SK 0). |
| FACT_CARTERA | `tbl_fact_cartera_v2` | 8-upla: `(idsuc, prefijo, numero, cuenta, nit, sucursal, ref_doc, ref_num)` | Snapshot **latest-open**: `tmcartera` `saldo <> 0`, `DISTINCT ON` NK `ORDER BY fecha DESC NULLS LAST`. INNER sucursal + persona + tiempo. |
| FACT_PAGO_APLICACION | `tbl_fact_pago_aplicacion` | `(idsuc, prefijo, numero, rc_idsuc, rc_prefijo, rc_numero)` | Nombre nuevo (no colisiona). |
| FACT_PAGO_PASARELA | `tbl_fact_pago_pasarela` | `id_pago_digital` | `DISTINCT ON (p.id)` |

### 2.4 Objetos `*_v2` (paralelo al Silver live)

| Modelo lógico | Tabla | Staging |
|---|---|---|
| geografía integer | `tbl_dim_geografia_v2` | `stg_dim_geografia_v2` |
| facturación | `tbl_fact_facturacion_v2` | `stg_fact_facturacion_v2` |
| cartera | `tbl_fact_cartera_v2` | `stg_fact_cartera_v2` |

DDL: `sql/silver/08_create_dualrun_v2.sql`. No DROP/RENAME de `tbl_dim_geografia` / `tbl_fact_facturacion` / `tbl_fact_cartera` ni de `tbl_dim_cliente` / `tbl_dim_servicio`.

### 2.5 Orquestador ejecutado

`Workflows/wf_actualizacion_silver_v2.hwf` — **no** está encadenado a `wf_delta` / `wf_historic`.

Orden interno:

```text
tiempo → documento → perfil → persona → brg_persona_uuid → plan → contrato
  → geo_v2 → sucursal → producto_erp
  → brg_sucursal_contrato → brg_contrato_plan
  → fact_pago_aplicacion → fact_pago_pasarela
  → fact_facturacion_v2 → fact_cartera_v2
```

Hop directo contrato→sucursal **deshabilitado** (geo_v2 debe ir antes).

---

## 3. EJECUCIÓN REAL

### 3.1 SQL contra Aurora

| Script | Estado | Evidencia |
|---|---|---|
| `01`–`04` | **HECHO en Aurora** (objetos poblados). **Sin log de `psql -f` en esta sesión.** | Carga Hop 2026-08-27 escribió esas tablas. |
| `08_create_dualrun_v2.sql` | **HECHO en Aurora**. Sin log de `psql` en esta sesión. | Bulk load a `stg/tbl_*_v2`. |
| `09_validate_silver_v2.sql` | **HECHO** (SELECT-only), **dos veces** vía Hop, no `psql`. | Primera: post-orquestador. Segunda: post-tiempo + recarga cartera. |
| `05_drop_fk.sql` | **NO EJECUTADO** | — |
| `06_create_fk.sql` | **NO EJECUTADO** | — |
| `07_drop_obsolete.sql` | **NO EJECUTADO** | — |

### 3.2 Workflows Hop (esta sesión, 2026-08-27)

| Workflow | Resultado | Duración / código | Conteos de esa corrida |
|---|---|---|---|
| `wf_actualizacion_silver_v2.hwf` | OK, todos los hijos `result=[true]` | **HopRun exit 0**, **1 min 43 s** | Staging (Bulk Loader) ver tabla abajo. Tiempo **aún 5 844** (calendario 2020–2035). Cartera v2 **17 511**. Facturación v2 **214 864**. |
| `wf_dim_tiempo.hwf` (1ª) | **Falló UPSERT** | Pipeline generó filas; CHECK `chk_dim_tiempo_sk`: `sk=18991230` vs `fecha=1899-12-29` (`generate_series` timestamptz). | — |
| `wf_dim_tiempo.hwf` (2ª, SQL `gs::date`) | OK | **exit 0**, **7.3 s** | Staging + UPSERT **49 674** días (COUNT posterior C01 = **49 675**). |
| `wf_fact_cartera_v2.hwf` | OK | **exit 0**, **7.9 s** | Staging **28 561**. |
| Segunda validación `09` (Hop) | OK | HopRun exit **0** | Ver §4. |

**NO ejecutados:** `wf_actualizacion_silver.hwf`, `wf_delta.hwf`, `wf_historic.hwf`, pipelines viejos de cliente/servicio/geo/facts homónimos.

Comando Hop que funcionó:

```powershell
& "C:\Users\rayha\OneDrive\Desktop\Arra\apache-hop-client-2.19.0\hop\hop-run.bat" `
  --file="<abs>\Workflows\<archivo>.hwf" `
  --project=hop-guajiranet --environment=hop-guajiranet --runconfig=local --level=Basic
```

### 3.3 Conteos staging — primera carga completa (`wf_actualizacion_silver_v2`)

| Paso | Filas staging |
|---|---:|
| tiempo | 5 844 |
| documento | 91 |
| perfil cartera | 18 |
| persona | 14 955 |
| brg persona uuid | 15 003 |
| plan | 282 |
| contrato | 10 998 |
| geo v2 | 246 |
| sucursal | 15 408 |
| producto ERP | 878 |
| brg sucursal-contrato | 10 958 |
| brg contrato-plan | 10 998 |
| pago aplicación | 115 852 |
| pago pasarela | 55 563 |
| facturación v2 | 214 864 |
| cartera v2 | 17 511 |

Tras recargas: tiempo **49 675** (C01); cartera v2 **28 561** (C16 / staging). Resto de dims/bridges/facts **igual** en la segunda validación.

---

## 4. VALIDACIÓN SILVER V2

**Corrida de referencia:** segunda, después de ampliar `dim_tiempo` y recargar `wf_fact_cartera_v2`.  
**Script:** `sql/silver/09_validate_silver_v2.sql` (solo SELECT; no lee Silver viejo).  
**Resultado global: FAIL = 0.**

### 4.1 Conteos finales (C01–C16) — VALIDADO

| Tabla | n |
|---|---:|
| `tbl_dim_tiempo` | 49 675 |
| `tbl_dim_documento` | 91 |
| `tbl_dim_perfil_cartera` | 18 |
| `tbl_dim_persona` | 14 955 |
| `tbl_dim_plan` | 282 |
| `tbl_dim_contrato` | 10 998 |
| `tbl_dim_geografia_v2` | 246 |
| `tbl_dim_sucursal` | 15 408 |
| `tbl_dim_producto_erp` | 878 |
| `tbl_brg_persona_uuid` | 15 003 |
| `tbl_brg_sucursal_contrato` | 10 958 |
| `tbl_brg_contrato_plan` | 10 998 |
| `tbl_fact_pago_aplicacion` | 115 852 |
| `tbl_fact_pago_pasarela` | 55 563 |
| `tbl_fact_facturacion_v2` | 214 864 |
| `tbl_fact_cartera_v2` | 28 561 |

Dummy: G01 geo `sk_geografia=0` y `id_barrio=0` → **1**. G05 perfil SK 0 / `id_perfil=0` → **1**.

### 4.2 Duplicados (D01–D16) — VALIDADO

Todas **n = 0** (NK/grano aprobado).

### 4.3 NULL obligatorios (N01–N13) — VALIDADO

Todas **n = 0**.

### 4.4 SK inválidas (Z01–Z10) — VALIDADO

Todas **n = 0**. No hay SK 0 en persona, sucursal (PK), contrato, plan, producto, documento, tiempo, ni en SK obligatorias de facts. `sk_contrato`/`sk_plan` en facturación v2 no valen 0.

SK 0 **permitida** (WARN, no FAIL):

| ID | n | Hallazgo |
|---|---:|---|
| Z11 | 2 871 | `dim_sucursal.sk_geografia = 0` |
| Z12 | 1 163 | `dim_sucursal.sk_perfil_cartera = 0` |
| Z13 | 40 263 | `fact_facturacion_v2.sk_geografia = 0` |
| Z14 | 1 336 | `fact_cartera_v2.sk_perfil_cartera = 0` |

### 4.5 Huérfanos

**PASS (n = 0):** O02, O03, O06, O07, O09–O23 (SK requeridas de facts/bridges/sucursal resuelven). G06: ninguna `sk_geografia=0` en facturación sin dummy geo v2.

**WARN (esperado / Bronze incompleto, no FAIL):**

| ID | n | Hallazgo |
|---|---:|---|
| O01 | 674 | `persona.nit` sin fila brg con ese nit |
| O04 | 722 | brg UUID (`nit` NULL, `sk_persona` NULL) — JSON sin tercero |
| O05 | 4 450 | sucursal sin `brg_sucursal_contrato` (sin `idcontrato` en Bronze) |
| O08 | 492 | brg sucursal-contrato con `sk_contrato` NULL |

### 4.6 Facturación v2 — VALIDADO

Universo Bronze cab+det (`trfacturas` INNER `trfacturasdet`): **214 864** (B07).  
Fuera INNER total (B01): **0**. Fuera por sucursal/persona/producto/documento/tiempo (B02–B06): **0**.  
C15 = universo. **No hay pérdida de líneas.**

### 4.7 Cartera v2 — VALIDADO (detalle en §5)

Universo latest-open `saldo <> 0`: **28 633** (B12).  
`tbl_fact_cartera_v2`: **28 561**. Fuera: **72** (B08). Fuera por tiempo: **0** (B11 PASS).

---

## 5. CARTERA

Grano: **una fila por 8-upla**, snapshot de la fila `tmcartera` con `saldo <> 0` más reciente (`fecha DESC`).

| Magnitud | n | Check |
|---|---:|---|
| Universo Bronze latest-open | 28 633 | B12 |
| En `tbl_fact_cartera_v2` | 28 561 | C16 |
| Fuera (INNER total) | 72 | B08 WARN |
| Fuera por `dim_tiempo` | **0** | B11 PASS |
| Fuera sin sucursal `(nit, sucursal=idsuc)` | 72 | B09 WARN |
| Fuera sin persona (`nit`) | 1 | B10 WARN |

Aritmética: `28 633 − 72 = 28 561`. El 1 sin persona está **dentro** de los 72 sin sucursal (no es un 73.er faltante).

### Primera validación (antes del calendario)

B08 = 11 122, B11 = 11 113, C16 = 17 511. `17 511 + 11 122 = 28 633`. Casi todo el hueco era fecha ausente en `dim_tiempo`.

### Problema `1899-12-30`

Las 11 113 fechas “fuera de calendario” **no** eran 2000–2019. Consulta Bronze (esta sesión): latest-open `tmcartera` MIN = **1899-12-30** (exactamente esas 11 113 filas; centinela Excel/OLE), MAX = 2026-07-07. No había otras fechas latest-open &lt; 2020. Facturas y pagos ya caían en 2020–2035.

Calendario live **antes:** `generate_series` **2020-01-01 → 2035-12-31** (5 844 días).  
**Solución aplicada (solo `Pipelines/dim_tiempo.hpl`):** serie **1899-12-30 → 2035-12-31**, 1 fila/día, `sk_tiempo=YYYYMMDD`. Primera corrida `wf_dim_tiempo` falló CHECK por timestamptz; se envolvió `gs::date`. Segunda corrida OK.

**Estado final tiempo (VALIDADO C01):** rango **1899-12-30 a 2035-12-31**, **49 675** filas. (Hop UPSERT reportó 49 674; el COUNT(*) de validación es 49 675.)

Luego `wf_fact_cartera_v2` subió 17 511 → 28 561. Residual = sucursal/persona, no calendario.

---

## 6. SEGURIDAD / DUAL RUN

Dejar esto **explícito** para el siguiente chat:

- Silver **viejo no tocado** como destino de carga v2: `tbl_dim_cliente`, `tbl_dim_servicio`, `tbl_dim_geografia` (varchar), `tbl_fact_facturacion`, `tbl_fact_cartera` y sus `stg_*` homónimos. Pipelines v2 apuntan a `*_v2`.
- **Excepción KEEP:** `tbl_dim_tiempo` / `stg_dim_tiempo` **sí se reescribieron** al ampliar el calendario (mismo objeto que usa el Silver viejo). `tbl_dim_documento` se recargó en el orquestador v2 (KEEP compartido). No se DROP.
- **Power BI no tocado.** No se editó `Guajiranet (1).pbix`, no hay cutover de dataset, no hay vistas Gold nuevas en uso.
- **`05` / `06` / `07` NO ejecutados.** No hay FK NOT VALID nuevas; no hay DROP de cliente/servicio ni de geo/facts viejos.
- **Cutover NO realizado.** No RENAME `*_v2` → nombres live. No Power Query nuevo en el PBIX.
- **No ejecutar el orquestador viejo y el v2 a la vez:** `stg_dim_tiempo` y `stg_dim_documento` son **staging compartido** (TRUNCATE mutuo).
- No encadenar `wf_actualizacion_silver_v2` dentro de `wf_delta` / `wf_historic`.

---

## 7. POWER BI

Solo lo ya auditado en `discovery/powerbi_compatibility_audit.md` (2026-08-24). **No se re-abrió el PBIX en esta fase.**

**Archivo:** `Guajiranet (1).pbix` (raíz). Informe PBIR. Modelo **Import**. **No** usa `gold_guajiranet.vw_*`.

### 7.1 Tablas del modelo

En visuales: `dim cliente`, `dim servicio`, `dim geografia`, `dim tiempo dax`, `fact facturacion`.  
En modelo, no en visuales: `dim tiempo` (Silver), `dim documento`, `dim Inicio Operacion Cliente` (vía columnas en el fact).  
No aparecen: cartera, Gold, persona, sucursal, contrato, plan ISP.

### 7.2 Campos imprescindibles (nombres PBI)

- `fact facturacion`: `sk_cliente`, `sk_servicio`, `sk_geografia`, `venta`, `Fecha Inicio Operacion`, `Año Mes Inicio Operacion`
- `dim cliente`: `razon social`, `tipo persona` (ésta última inactiva en un visual)
- `dim servicio`: `nombre plan`, `categoria` (**SKU ERP**, no plan ISP)
- `dim geografia`: `departamento`, `municipio`, `barrio`, `departamento municipio` (calculada PBI)
- `dim tiempo dax`: `Fecha`, `Mes`, `Año`, `Año-Mes` + jerarquía auto de `Fecha`

`sk_cliente` en el reporte = grano **sucursal** `(nit, idsuc)` del Silver viejo. Si se cambia a `sk_persona` (NIT), se rompen KPI de alcance.

### 7.3 Medidas conocidas (nombres; DAX no extraído del VertiPaq)

En fact: `Clientes Atendidos`, `Clientes promedio por municipio`, `Ingresos`, `% de Meta`.  
En geo: `Municipios con Cobertura`, `Barrios con Cobertura`.  
Agregaciones visuales: Function=2 sobre `sk_cliente` / `municipio` / `sk_geografia` / `sk_servicio` = **recuento de negocio (DISTINCTCOUNT de SK sucursal)**, no MIN. `venta` = SUM.

### 7.4 Mapeo aprobado (capa de alias, sin editar visuales)

| PBI | Silver viejo | Silver nuevo | Compatibilidad |
|---|---|---|---|
| `fact facturacion` | `tbl_fact_facturacion` | `tbl_fact_facturacion_v2` | `sk_sucursal AS sk_cliente`; `sk_producto AS sk_servicio`; `neto AS venta`; `sk_geografia`; fecha → `fecha_factura` |
| `dim cliente` | `tbl_dim_cliente` | sucursal ⋈ persona | `sk_sucursal AS sk_cliente`, `razonsocial AS [razon social]`, `tipo_persona AS [tipo persona]` |
| `dim servicio` | `tbl_dim_servicio` | `tbl_dim_producto_erp` | `sk_producto AS sk_servicio`, `nombre_producto AS [nombre plan]`, `categoria` |
| `dim geografia` | `tbl_dim_geografia` | `tbl_dim_geografia_v2` | mismos nombres `departamento`,`municipio`,`barrio`; concat PBI |
| `dim tiempo dax` | DAX en PBIX | — | **Queda en Power BI**; re-relacionar a `fecha_factura` |
| `dim tiempo` importada | `tbl_dim_tiempo` | KEEP | Opcional; ningún visual la usa |
| `dim Inicio Operacion Cliente` | calc PBI | no existe | Recalcular `MIN(fecha_factura)` **por `sk_sucursal`** |
| `dim documento` | KEEP | KEEP | Opcional |

**Debe permanecer en Power BI:** tabla calculada `dim tiempo dax`, jerarquía de `Fecha`, medidas DAX actuales **si** la capa expone los mismos nombres (`sk_cliente`, `venta`, `nombre plan`, …). Gold no entra en este mapa.

---

## 8. SIGUIENTE FASE

Orden **cerrado** (no saltar):

```text
Silver v2 VALIDADO
  → capa de compatibilidad (*_compat_v2 en paralelo; no RENAME live)
  → validación de equivalencia vs modelo Silver actual / PBIX
  → conexión y prueba Power BI (sin romper visuales)
  → Gold
  → nuevos tableros
```

**PENDIENTE:** diseño SQL de vistas/tablas `*_compat_v2`, conteos de equivalencia, recarga PBIX, Gold, tableros nuevos.  
**NO EJECUTADO / no ahora:** cutover, `07`, DROP Silver viejo, reescritura de visuales, encadenar v2 a delta/historic.

---

## 9. REGLAS PARA EL SIGUIENTE CHAT

1. **No repetir discovery** de Bronze ni reabrir el PBIX para “volver a inventariar”. Usar este archivo + `discovery/powerbi_compatibility_audit.md` + `sql/silver/09_validate_silver_v2.sql`.
2. **No rediseñar granularidades.** Lista en §2.
3. **No tocar Silver viejo** como destino (salvo KEEP tiempo/documento ya compartidos). Cargas nuevas → `*_v2` o `*_compat_v2`.
4. **No romper el PBIX.** Conservar nombres de tabla/columna del informe. Preferir capa SQL/PQ de alias.
5. **No cutover** hasta validar equivalencia (conteos/KPI vs modelo actual).
6. **No ejecutar `07_drop_obsolete.sql`.** Tampoco `05`/`06` salvo decisión explícita post-equivalencia.
7. **Commits frecuentes**, sin `.env` ni `aws_rds.json`. Versionar `dim_tiempo.hpl` / `09` / validación si aún están untracked.
8. No correr `wf_actualizacion_silver` y `wf_actualizacion_silver_v2` en paralelo (staging KEEP compartido).
9. No inventar DAX: las fórmulas no se leyeron del VertiPaq.

---

## 10. CHECKLIST DE CONTINUACIÓN

1. **Diseñar y crear la capa de compatibilidad `*_compat_v2` en paralelo** (vistas o tablas en `silver_guajiranet`, nombres alineados al PBIX: `fact facturacion` / `dim cliente` / `dim servicio` / `dim geografia` o identificadores SQL equivalentes documentados). Fuentes: `tbl_fact_facturacion_v2`, `tbl_dim_sucursal` ⋈ `tbl_dim_persona`, `tbl_dim_producto_erp`, `tbl_dim_geografia_v2`. Aliases: `sk_cliente` ← `sk_sucursal`, `sk_servicio` ← `sk_producto`, `venta` ← `neto`, `nombre plan` ← `nombre_producto`, `razon social` ← `razonsocial`.
2. Añadir en compat (o documentar cálculo PBI): `Fecha Inicio Operacion` y `Año Mes Inicio Operacion` = primera `fecha_factura` por `sk_sucursal`.
3. **No** apuntar esas vistas a tablas Silver viejas; el dual-run sigue vivo.
4. Script de equivalencia SELECT-only: conteos de NK, SUM(`neto`/`venta`), DISTINCTCOUNT `sk_cliente` vs `sk_sucursal` facturada, cobertura geo, vs `tbl_fact_facturacion` **vieja** (solo lectura).
5. Commitear artefactos locales aún untracked que ya se usaron: `09_validate_silver_v2.sql`, `Pipelines/dim_tiempo.hpl` (calendario), actualizar o reemplazar `silver_v2_validacion.md`.
6. Recargar solo lo necesario (no orquestador viejo). Re-correr `09` si se toca tiempo/facts v2.
7. Probar Power BI contra `*_compat_v2` en un PBIX **copia** o dataset de prueba — no overwrite del informe de producción hasta equivalencia.
8. Solo después: plan de cutover (PQ → compat), Gold, tableros nuevos.
9. `07` queda bloqueado hasta Gold + PBI ya no lean tablas viejas.

---

## PRÓXIMO PASO EXACTO

Crear (solo diseño + DDL, **sin** DROP ni RENAME live) un script `sql/silver/10_create_compat_v2.sql` que defina objetos **nuevos** `*_compat_v2` en paralelo, por ejemplo:

- `vw_compat_v2_dim_cliente` = `tbl_dim_sucursal` INNER JOIN `tbl_dim_persona` con columnas `sk_cliente`, `razon social` / `razonsocial`, `tipo persona` / `tipo_persona`, más NK `nit`,`idsuc`.
- `vw_compat_v2_dim_servicio` = `tbl_dim_producto_erp` con `sk_servicio`, `nombre plan` / `nombre_producto`, `categoria`.
- `vw_compat_v2_dim_geografia` = `tbl_dim_geografia_v2` con `departamento`,`municipio`,`barrio` (concat `departamento municipio` opcional en SQL o se deja en PBI).
- `vw_compat_v2_fact_facturacion` = `tbl_fact_facturacion_v2` con `sk_cliente`←`sk_sucursal`, `sk_servicio`←`sk_producto`, `venta`←`neto`, `sk_geografia`, `fecha_factura`, y (si cabe en SQL) min fecha por sucursal para inicio de operación.

No ejecutar `05`/`06`/`07`. No modificar el PBIX todavía. No recargar Silver viejo. Tras el DDL, un `11_validate_compat_v2.sql` SELECT-only comparando compat vs fact/dims **viejas** (lectura) y vs `*_v2`.

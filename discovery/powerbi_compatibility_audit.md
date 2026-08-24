# Auditoría de compatibilidad Power BI — Guajiranet (1).pbix

**Fecha:** 2026-08-24  
**Archivo:** `Guajiranet (1).pbix` (raíz del proyecto, 8 009 662 bytes)  
**Método:** PBIX = ZIP. Informe en formato **PBIR** (`Report/definition`). Modelo semántico embebido en `DataModel` (backup VertiPaq UTF-16, 7 800 246 bytes; fórmulas DAX **no** extraídas: compresión Xpress9). Diagrama: `DiagramLayout`.  
**No se modificó** el PBIX, Silver ni Hop.  
**Fuente del reporte:** modelo semántico **Import** con tablas `dim *` / `fact *`. **No** usa `gold_guajiranet.vw_*`. `Connections` referencia un dataset en servicio (`DatasetId` `fb257399-788b-450a-b765-c16798406f57`, `ReportId` `13a21ec6-2c10-4100-a505-d66ab1422ce5`) y `CreatedFrom: Cloud` (2026.07).

---

## 1. Tablas del modelo (diagrama)

Ocho tablas en `DiagramLayout` (“Todas las tablas”):

| Tabla en PBI | En visuales | Rol |
|---|---|---|
| `dim cliente` | sí | atributos de sucursal/cliente ERP |
| `dim servicio` | sí | producto ERP (PBI lo llama “plan”) |
| `dim geografia` | sí | barrio / municipio / departamento |
| `dim tiempo` | **no** (solo en modelo) | calendario importado Silver |
| `dim tiempo dax` | sí (casi todos los filtros de fecha) | calendario **DAX** + jerarquía automática de `Fecha` |
| `dim Inicio Operacion Cliente` | no como Entity; sí vía columnas calculadas en el fact | primera fecha de operación |
| `fact facturacion` | sí | hecho único del reporte |
| `dim documento` | **no** | en el modelo; ningún visual la referencia |

Tablas locales de fecha auto-generadas (filtro Exclude): `LocalDateTable_189fafc8-11aa-4595-9f96-64c1eef98f17`.

No aparecen `tbl_fact_cartera`, Gold, persona, sucursal, contrato ni plan ISP.

---

## 2. Columnas usadas en el informe

Nombres **tal como están en el modelo PBI** (Power Query suele poner espacios).

### `fact facturacion`

| Columna | Uso |
|---|---|
| `sk_cliente` | KPI “Alcance de Clientes” (agregación Function=2; UI “Recuento”); sort del mapa |
| `sk_geografia` | KPI “Profundidad Territorial (Barrios)” |
| `sk_servicio` | KPI “Amplitud de oferta (Servicios)” |
| `venta` | `SUM` — tarjetas de ingresos en Operativa/Apertura |
| `Fecha Inicio Operacion` | eje del line chart de vinculación |
| `Año Mes Inicio Operacion` | slicer de Capilaridad Apertura (`2026-08`) |

### `dim cliente`

| Columna | Uso |
|---|---|
| `razon social` | slicer (Duplicado Apertura); fila colapsada del pivot |
| `tipo persona` | proyección **inactiva** en barras de plan (Operativa) |

### `dim servicio`

| Columna | Uso |
|---|---|
| `nombre plan` | barras Top plan; slicer; filas del pivot |
| `categoria` | slicer (filtro `RESIDENCIAL` en Duplicado Apertura) |

### `dim geografia`

| Columna | Uso |
|---|---|
| `departamento` | slicers (default `LA GUAJIRA`; exclude ANTIOQUIA/BOGOTÁ D.C. en Operativa) |
| `municipio` | slicers, barras, mapa, pivot; KPI recuento |
| `barrio` | barras “clientes por barrio” |
| `departamento municipio` | categoría del mapa en página Capilaridad (oculta) |

### `dim tiempo dax`

| Columna / jerarquía | Uso |
|---|---|
| `Fecha` | slicers relative date; filtros de visual |
| `Mes` | slicer |
| `Año` | slicer |
| `Año-Mes` | slicer Operativa (`2026-08`) |
| Jerarquía auto `Fecha` → Año / Mes / Día | line chart Operativa; columnas del pivot |

`dim tiempo` (Silver) **no** se usa en visuales. El tiempo del reporte es el calendario DAX.

---

## 3. Medidas usadas

Fórmulas DAX **no leídas** del VertiPaq. Nombres y tabla home, desde PBIR:

| Tabla home | Medida | Dónde |
|---|---|---|
| `fact facturacion` | `Clientes Atendidos` | KPIs, mapas, barras, líneas; display a veces “Clientes Vinculados” |
| `fact facturacion` | `Clientes promedio por municipio` | barras por barrio |
| `fact facturacion` | `Ingresos` | KPI y barras municipio (página Capilaridad) |
| `fact facturacion` | `% de Meta` | KPI Apertura (“% para la Meta”) |
| `dim geografia` | `Municipios con Cobertura` | KPI Capilaridad |
| `dim geografia` | `Barrios con Cobertura` | KPI Capilaridad |

Agregaciones implícitas (no son medidas, pero el visual las trata como KPI):

| Expresión visual | queryRef encoder | UI |
|---|---|---|
| Agg Function=2 sobre `sk_cliente` | `Min(fact facturacion.sk_cliente)` | Recuento / Alcance de Clientes |
| Function=2 `municipio` | `Min(dim geografia.municipio)` | Extensión Territorial (Municipíos) |
| Function=2 `sk_geografia` | `Min(...)` | Profundidad Territorial (Barrios) |
| Function=2 `sk_servicio` | `Min(...)` | Amplitud de oferta (Servicios) |
| Function=0 `venta` | `Sum(fact facturacion.venta)` | Suma de venta |

Function **0** = Suma (confirmado). Function **2** en el encoder se serializa como `Min(...)` pero la UI dice **Recuento**; el nombre de negocio es alcance/distintos. Para compatibilidad hay que conservar **DISTINCTCOUNT de la SK de sucursal-cliente**, no el mínimo de la SK.

---

## 4. Relaciones (inferidas)

El PBIR no lista relaciones. El estrella y las SK usadas implican:

```text
fact facturacion.sk_cliente     → dim cliente.sk_cliente          (1:*)
fact facturacion.sk_servicio    → dim servicio.sk_servicio
fact facturacion.sk_geografia   → dim geografia.sk_geografia
fact facturacion.sk_documento   → dim documento.sk_documento      (en modelo; no usado)
fact facturacion.fecha_factura  → dim tiempo.fecha                (probable; no usado en visuales)
fact facturacion.fecha_factura  → dim tiempo dax.Fecha            (activo para slicers)
fact facturacion               → dim Inicio Operacion Cliente     (para Fecha / Año Mes Inicio Operacion)
dim tiempo dax.Fecha           → LocalDateTable_* (auto hierarchy)
```

Dirección de filtro: la típica de estrella (dim → fact). No hay evidencia de bi-dirección en el informe.

---

## 5. Páginas

Orden en `pages.json`. Activa: **Capilaridad Operativa**.

| # | displayName | Id | Visibilidad | Binding |
|---|---|---|---|---|
| 1 | Template | `19ff383f6cca3a025839` | HiddenInViewMode | — |
| 2 | Capilaridad | `ba8c72d605bba965862c` | HiddenInViewMode | CrossReport `9b8230edd2e14035801a` |
| 3 | **Capilaridad Operativa** | `c9fce1b8ee677a8d8a9b` | visible | `9881e570e44000288341` |
| 4 | Capilaridad Apertura | `b45b1c00aa707dda1601` | visible | `ec27c9908cbba059856e` |
| 5 | Duplicado de Capilaridad Apertura | `5cd0b4169604ec38203b` | visible | `ba07726136a8bec0115d` |

Interacción especial Operativa: slicer `Año-Mes` (`5001aca2…`) → line chart (`e5d9a170…`) = **NoFilter**.  
Apertura: slicer inicio operación filtra line chart y KPI `% de Meta` (**DataFilter**).

---

## 6. Visuales y campos

### Template (oculta) — 4 visuales

| Tipo | Campos |
|---|---|
| image | logos |
| textbox | “Analítica General” |
| slicer | `dim tiempo dax.Fecha` (últimos 3 meses) |
| slicer | `dim geografia.departamento` = LA GUAJIRA |

### Capilaridad (oculta) — 12 visuales

| Tipo | Título / rol | Campos |
|---|---|---|
| image, textbox | header | — |
| cardVisual | Clientes Atendidos | medida `Clientes Atendidos` |
| cardVisual | Ingresos | `Ingresos` |
| cardVisual | Municipios con Cobertura | medida en `dim geografia` |
| cardVisual | Barrios con Cobertura | medida en `dim geografia` |
| slicer | Fecha relative 3 años | `dim tiempo dax.Fecha` |
| slicer | Departamento | `dim geografia.departamento` = LA GUAJIRA |
| azureMap | Cobertura geográfica | `departamento municipio` + `Clientes Atendidos` |
| clusteredBarChart | Clientes por plan | `nombre plan` + `Clientes Atendidos` (Top 10) |
| clusteredBarChart | (sin título en JSON) | `municipio` + `Ingresos` |
| barChart | Clientes por municipio | `municipio` + `Clientes Atendidos` |

### Capilaridad Operativa (activa) — 16 visuales

| Tipo | Título | Campos |
|---|---|---|
| image / textbox / shape | header + pregunta de cobertura | — |
| card | Alcance de Clientes | Recuento `sk_cliente` |
| card | Extensión Territorial | Recuento `municipio` |
| card | Profundidad Territorial | Recuento `sk_geografia` |
| card | Amplitud de oferta | Recuento `sk_servicio` |
| card | Suma de venta | `SUM(venta)` |
| slicer | Año-Mes | `dim tiempo dax.Año-Mes` = 2026-08 |
| slicer | categoria | `dim servicio.categoria` (+ filtro visual depto) |
| slicer | departamento | exclude ANTIOQUIA, BOGOTÁ D.C. |
| azureMap | ¿Dónde estamos llegando…? | depto + municipio + `Clientes Atendidos`; sort `sk_cliente` |
| clusteredBarChart | Top municipios | depto + municipio + `Clientes Atendidos` |
| lineChart | Evolución de clientes | jerarquía Fecha Año/Mes + `Clientes Atendidos` |
| clusteredBarChart | Clientes atendidos por servicio | `nombre plan` (+ `tipo persona` inactivo) + `Clientes Atendidos` |
| clusteredBarChart | Clientes atendidos por barrio | `barrio` + `Clientes promedio por municipio` |

Varios charts traen filtro relative date sobre `dim tiempo dax.Fecha` y Exclude agosto 2025.

### Capilaridad Apertura — 17 visuales

Misma cáscara Operativa, cambia el tiempo al **inicio de operación**:

| Diferencia vs Operativa | Campos |
|---|---|
| card “Clientes Vinculados” | medida `Clientes Atendidos` |
| card “% para la Meta” | `% de Meta` |
| slicer | `fact facturacion.Año Mes Inicio Operacion` = 2026-08 |
| lineChart | eje `Fecha Inicio Operacion` + `Clientes Atendidos` |
| títulos | “vinculados” en lugar de “atendidos” |
| actionButton | Back |

### Duplicado de Capilaridad Apertura — 12 visuales

Detalle: pivot + muchos slicers.

| Tipo | Campos |
|---|---|
| pivotTable | Columnas: jerarquía Fecha Año/Mes/(Día inactivo). Filas: depto, municipio, `nombre plan`, `razon social` (colapsada). Valores: `SUM(venta)` |
| slicers | `Año`, `Mes`, `Fecha`, `departamento` (ALBANIA en municipio, LA GUAJIRA), `categoria`=RESIDENCIAL, `nombre plan`, `razon social` |
| actionButton | Back |

---

## 7. Columnas imprescindibles para que el PBIX no se rompa

Renombrar en Power Query / modelo PBI **sin** tocar visuales exige **los mismos nombres de tabla y columna**.

### Imprescindibles (cualquier visual se cae si faltan)

**Tablas:** `fact facturacion`, `dim cliente`, `dim servicio`, `dim geografia`, `dim tiempo dax`.

**Columnas / medidas:**

- `fact facturacion`: `sk_cliente`, `sk_servicio`, `sk_geografia`, `venta`, `Fecha Inicio Operacion`, `Año Mes Inicio Operacion`
- Medidas en fact: `Clientes Atendidos`, `Clientes promedio por municipio`, `Ingresos`, `% de Meta`
- `dim cliente`: `razon social` (y `tipo persona` si se reactiva el drill)
- `dim servicio`: `nombre plan`, `categoria`
- `dim geografia`: `departamento`, `municipio`, `barrio`, `departamento municipio`
- Medidas geo: `Municipios con Cobertura`, `Barrios con Cobertura`
- `dim tiempo dax`: `Fecha`, `Mes`, `Año`, `Año-Mes` + jerarquía automática de `Fecha`

### Necesarias en el modelo aunque el visual no las liste

- Relación fact → dims por las SK anteriores.
- Relación fact.`fecha_factura` (o equivalente) → `dim tiempo dax.Fecha`.
- Tabla o columnas de **inicio de operación** (la tabla `dim Inicio Operacion Cliente` o las dos columnas calculadas en el fact).
- `sk_cliente` debe seguir siendo el grano de “un cliente atendido” = **sucursal** `(nit, idsuc)` del Silver viejo. Si pasa a `sk_persona` (NIT), los KPI de alcance cambian.

### No usados en visuales (se pueden diferir)

- `dim documento` (entera)
- `dim tiempo` importada (si `dim tiempo dax` permanece)
- Resto de columnas Silver (`nit`, `idsuc`, `numero_factura`, `posicion_factura`, `neto` **si** `venta` se mantiene como alias, etc.)

---

## 8. Identificación de las 7 entidades pedidas

### dim cliente

- **PBI:** `dim cliente`
- **Silver viejo:** `tbl_dim_cliente` (grano sucursal `nit+idsuc`; `sk_cliente`)
- **Columnas PBI vistas:** `razon social` ← `razonsocial`; `tipo persona` ← `tipo_persona`
- **Silver nuevo:** partir en `tbl_dim_persona` (razonsocial, tipo_persona, nit) + `tbl_dim_sucursal`. El reporte trata “cliente” como sucursal: hay que **seguir exponiendo una tabla (o vista PBI) con el grano y el nombre `dim cliente`**, o reescribir visuales.
- **Compatibilidad mínima:** tabla llamada `dim cliente` con `sk_cliente` (= `sk_sucursal`) y `razon social`.

### dim servicio

- **PBI:** `dim servicio` — **no es plan ISP**; es SKU ERP (`tbl_dim_servicio` / `maproductos`)
- **Columnas:** `nombre plan` ← `nombre_plan` / nuevo `nombre_producto`; `categoria`
- **Silver nuevo:** `tbl_dim_producto_erp`
- **Compatibilidad:** o bien vista/alias PBI `dim servicio` con esas dos columnas, o cambiar todos los visuales a `dim producto erp` / `nombre_producto`.

### dim geografia

- **PBI / Silver:** `tbl_dim_geografia`
- **Usado:** `departamento`, `municipio`, `barrio` (existen en el modelo **nuevo**); `departamento municipio` es **columna calculada PBI** (concatenación)
- Cutover geo integer: SK cambian; hay que **recargar** y recalcular medidas de cobertura. Nombres de atributo se pueden conservar.

### dim tiempo

- En el modelo PBI (diagrama) = import de `tbl_dim_tiempo`.
- **Ningún visual la referencia.** Se puede conservar para otras páginas futuras. No es el calendario que filtra el tablero.

### dim tiempo dax

- Tabla **calculada DAX** en el PBIX (no es Silver).
- Es el calendario **efectivo** del reporte (`Fecha`, `Año`, `Mes`, `Año-Mes`, jerarquía).
- Debe seguir relacionada con la fecha del fact (`fecha_factura` en Silver).
- No se recrea en Aurora; se mantiene en Power BI.

### dim Inicio Operacion Cliente

- En el diagrama; **no** aparece como `Entity` en visuales.
- El fact expone `Fecha Inicio Operacion` y `Año Mes Inicio Operacion` (calculadas desde esa dim o desde primera factura por `sk_cliente`).
- **Silver nuevo:** no hay tabla homónima. Hay que recalcular “primera `fecha_factura` por `sk_sucursal`” (o por persona, si se cambia el grano — **rompe** Apertura).

### fact facturacion

- **PBI:** `fact facturacion` ← `tbl_fact_facturacion` (no Gold).
- SK usadas: `sk_cliente`, `sk_servicio`, `sk_geografia` (el modelo nuevo las llama `sk_sucursal`, `sk_producto`, `sk_geografia`).
- `venta` = alias de `neto` (u otra medida monetaria).
- Columnas viejas `numero_factura` / `posicion_factura` **no** están en visuales.

---

## 9. Mapa viejo → Silver nuevo → Power BI

Objetivo de compatibilidad **sin editar el PBIX:** una capa semántica (vistas SQL o Power Query) que **conserve nombres PBI**.

| PBI (imprescindible) | Silver viejo | Silver nuevo | Capa de compatibilidad |
|---|---|---|---|
| tabla `fact facturacion` | `tbl_fact_facturacion` | mismo nombre, otras columnas | Vista o PQ: `sk_cliente AS sk_cliente` ← `sk_sucursal`; `sk_servicio` ← `sk_producto`; `venta` ← `neto`; `sk_geografia`; fecha → `fecha_factura` |
| `sk_cliente` | PK sucursal | `sk_sucursal` | **Alias obligatorio.** DISTINCTCOUNT sigue = sucursales facturadas |
| `sk_servicio` | `sk_servicio` | `sk_producto` | Alias |
| `venta` | probablemente `neto` | `neto` | Alias `venta` |
| `Fecha Inicio Operacion` | calc PBI | no existe | Recalcular min(fecha_factura) por sk_sucursal |
| `Año Mes Inicio Operacion` | calc PBI | no existe | `FORMAT` de la anterior |
| tabla `dim cliente` | `tbl_dim_cliente` | persona + sucursal | Vista `dim cliente` = sucursal ⋈ persona: `sk_sucursal AS sk_cliente`, `razonsocial AS [razon social]`, `tipo_persona AS [tipo persona]` |
| tabla `dim servicio` | `tbl_dim_servicio` | `tbl_dim_producto_erp` | Vista: `sk_producto AS sk_servicio`, `nombre_producto AS [nombre plan]`, `categoria` |
| tabla `dim geografia` | `tbl_dim_geografia` varchar | integer + dpto/mun | Mismos nombres `departamento`,`municipio`,`barrio`; calc `[departamento municipio]` en PBI |
| `dim tiempo dax` | DAX en PBIX | — | No tocar; re-relacionar a `fecha_factura` |
| `dim tiempo` | `tbl_dim_tiempo` | KEEP | Opcional |
| `dim Inicio Operacion Cliente` | tabla/calc PBI | — | Recrear desde fact nuevo (primera fecha por sucursal) |
| `dim documento` | `tbl_dim_documento` | KEEP | Opcional |
| Medida `Clientes Atendidos` | DAX sobre `sk_cliente` | reescribir DAX a `sk_sucursal` **o** alias | Si la capa expone `sk_cliente`, el DAX del PBIX puede quedar |
| Medidas cobertura geo | DAX DISTINCTCOUNT | igual | Recalcular tras cutover geo |
| `% de Meta` | DAX (meta desconocida) | — | Conservar medida; validar denominador |

```text
Aurora Silver nuevo
  tbl_fact_facturacion (sk_sucursal, sk_producto, sk_geografia, neto, fecha_factura)
  tbl_dim_sucursal + tbl_dim_persona
  tbl_dim_producto_erp
  tbl_dim_geografia (id_barrio int)
        |
        |  vistas o Power Query (nombres PBI viejos)
        v
Modelo semántico PBI (sin cambiar visuales)
  fact facturacion / dim cliente / dim servicio / dim geografia
  dim tiempo dax (DAX local)
        |
        v
PBIX visuales actuales
```

**Si no hay capa de alias:** hay que editar el PBIX (fuera de este trabajo): Entity `dim cliente` → sucursal/persona, `sk_cliente` → `sk_sucursal`, `nombre plan` → `nombre_producto`, `venta` → `neto`.

Gold **no** entra en este mapa: el PBIX no la consulta.

---

## Limitaciones

- DAX de medidas y M de Power Query no están en PBIR; viven comprimidos en `DataModel`.
- Relaciones no están en `DiagramLayout` (solo nodos).
- Function=2 vs etiqueta “Recuento”: se interpreta como distinct count de negocio, no como MIN.
- Página Capilaridad y Template están ocultas pero siguen dependiendo de los mismos nombres.

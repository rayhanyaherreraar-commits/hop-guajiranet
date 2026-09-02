# Montaje Power BI — página Vinculación y Deserción

**PBIX:** `Guajiranet_COMPAT_V2_TEST.pbix` únicamente.  
**No abrir / no guardar:** `Guajiranet (1).pbix`.  
**No refrescar** las 4 consultas originales con cambios. No tocar Silver ni Gold SQL.

Columnas verificadas en `information_schema.columns` (2026-09-01). El M no usa `MissingField.UseNull` ni Bronze.

---

## 0. Diferencias VIEW vs lista pedida (no se inventan columnas)

| Pedido | En la VIEW | Uso en PBI |
|---|---|---|
| `interrupcion_de_pago` (mensual, boolean) | No existe. Existe `estado_pago` (texto) | Medida `Clientes en Interrupción de Pago Mes` con `estado_pago = "INTERRUPCION_DE_PAGO"` |
| `cantidad_recuperaciones` (resumen) | `cantidad_recuperaciones_transaccionales` | Usar ese nombre |
| `meses_hasta_recupero_pago` | `meses_hasta_recuperacion_pago` | Usar ese nombre |
| — | `estado_pago`, `pago_posterior_a_ultima_factura` (mensual) | Conservar; segundo reloj |
| — | extras de episodios/resumen (ver diccionario) | Conservar |

`sk_cliente` Gold = integer; M lo pasa a texto.

---

## 1. Orden exacto en Power BI Desktop

1. Abrir **solo** `Guajiranet_COMPAT_V2_TEST.pbix`.
2. **Opciones de archivo → Modelo de datos → Autodetectar relaciones nuevas: No.**
3. Transformar datos. Nueva consulta en blanco × 5. Pegar M de `powerbi/gold/m_*.m`.
4. Renombrar consultas a nombres **exactos**:
   - `anl ciclo vida parametros`
   - `anl estado transaccional mensual cliente`
   - `anl episodios ciclo vida cliente`
   - `anl episodios interrupcion pago`
   - `anl ciclo vida cliente resumen`
5. Cerrar y aplicar. Comprobar filas ≈ 1 / 292 570 / 7 461 / 25 073 / 13 982.
6. Vista modelo. Crear **solo** R-G1 … R-G4 (`relaciones_vinculacion_desercion.md`). Parametros sin relación.
7. Ocultar columnas de la sección «Ocultar» más abajo.
8. Enter Data → tabla `_medidas vinculacion` → pegar `dax_vinculacion_desercion.dax` (home esa tabla).
9. Nueva página **Vinculación y Deserción**. Montar visuales (§5).
10. Slicer de cliente: `dim cliente`. **No** poner `dim tiempo` en esta página para los visuales Gold.
11. Guardar el TEST. No publicar. No tocar Capilaridad ni Cliente 360.

---

## 2. Diccionario post-M

### `anl ciclo vida parametros` — 1 fila — sin clave / sin relación

| Columna | Tipo PBI | Ocultar |
|---|---|---|
| umbral_dias_inactividad | Entero | |
| umbral_meses_inactividad | Entero | |
| ventana_facturacion_cercana_meses | Entero | |
| umbral_dias_interrupcion_pago | Entero | |
| umbral_meses_interrupcion_pago | Entero | |
| as_of_facturacion | Fecha | |
| as_of_pago | Fecha | |
| estado_parametro | Texto | Sí |

Tarjeta o texto: umbrales y fechas as_of.

### `anl estado transaccional mensual cliente` — grano `sk_cliente + mes` — clave `sk_cliente` (R-G1)

| Columna | Tipo | Ocultar |
|---|---|---|
| sk_cliente | Texto | Sí |
| nit, idsuc | Entero | Sí (usar dim cliente) |
| mes | Fecha | |
| primer_mes_actividad, ultimo_mes_actividad_conocido | Fecha | Sí |
| facturas_mes | Entero | |
| ingresos_mes | Decimal | No es la medida Ingresos del fact |
| cantidad_pagos_aplicados / valor_pago_aplicado | Entero / Decimal | `carteraaplicado` |
| cantidad_pagos_pasarela / valor_pago_pasarela | Entero / Decimal | `total`; no mezclar con aplicado |
| tiene_* | Verdadero/falso | |
| meses_consecutivos_sin_* | Entero | |
| estado_transaccional | Texto | Reloj factura |
| estado_pago | Texto | Reloj pago |
| pago_sin_facturacion_cercana | Verdadero/falso | |
| pago_posterior_a_ultima_factura | Verdadero/falso | |
| mes_con_retiro_registrado | Verdadero/falso | Evidencia; no churn |

### `anl episodios ciclo vida cliente` — 1 episodio factura — clave `sk_cliente` (R-G2)

Ocultar: `sk_cliente`, `nit`, `idsuc`, `tipo_episodio`.  
Mostrar: `numero_episodio`, fechas, `dias_inactivo`, `meses_inactivo`, `reconecto`, `recuperacion_transaccional_observada`, `motivo_inferido`, `nivel_confianza`, `estado_retiro_registrado`, `fecha_retiro_registrada`.

### `anl episodios interrupcion pago` — 1 episodio pago — clave `sk_cliente` (R-G3)

Ocultar: `sk_cliente`, `nit`, `idsuc`, `tipo_episodio`.  
`recupero_pago` no es reconexión de servicio.  
`meses_hasta_recuperacion_pago` = el campo pedido como `meses_hasta_recupero_pago`.

### `anl ciclo vida cliente resumen` — 1 fila / cliente — clave `sk_cliente` (R-G4 1:1)

Ocultar: `sk_cliente`, `nit`, `idsuc`, `as_of_fecha`, `idperfilcartera`.  
`fecha_inicio_transaccional_observada`: no etiquetar «vinculación contractual».  
`plan_actual`: atributo snapshot; **no** relacionar a `dim plan`.  
`cantidad_recuperaciones_transaccionales` = recuperaciones de factura.

---

## 3. Página **Vinculación y Deserción**

Títulos fijos: «Deserción transaccional observada», «Recuperación transaccional observada», «Interrupción de pago», «Recuperación de pago».  
Prohibido: churn certificado, reconexión ISP, cancelación por motivo X.

### 1. KPIs (tarjetas)

Fila A (factura): `[Clientes con Episodio]` · `[Deserciones Transaccionales Observadas]` · `[Recuperaciones Transaccionales]` · `[% Recuperación Transaccional]` · `[Clientes Actualmente Inactivos]`

Fila B (pago): `[Episodios de Interrupción de Pago]` · `[Recuperaciones de Pago]` · `[Interrupciones de Pago Abiertas]` · `[% Recuperación de Pago]` · `[Clientes con Pago Posterior a Última Factura]`

Filtro de página: `dim cliente`. Opcional tarjeta de `anl ciclo vida parametros` (as_of, umbral 60).

### 2. Evolución mensual

Eje: `'anl estado transaccional mensual cliente'[mes]` (agrupar por mes).  
Series: `[Clientes con Factura en Mes]`, `[Clientes en Deserción Transaccional Observada Mes]`, `[Clientes en Recuperación Transaccional Observada Mes]`.  
Segundo gráfico (pago): `[Clientes en Interrupción de Pago Mes]`. No `dim tiempo`.

### 3–4. Episodios factura / recuperación

Tabla o matriz sobre `'anl episodios ciclo vida cliente'`.  
Segmentar recuperación: `recuperacion_transaccional_observada = true`.

Columnas tabla histórica:

| Visual | Campo |
|---|---|
| Cliente | `dim cliente[razon social]` (o nit de dim) |
| Episodio | `numero_episodio` |
| Última factura previa | `fecha_ultima_factura_previa` |
| Inicio inactividad | `fecha_inicio_inactividad` |
| Recuperación | `fecha_primera_actividad_posterior` |
| Días inactivo | `dias_inactivo` |
| Meses inactivo | `meses_inactivo` |
| Reconexion observada | `recuperacion_transaccional_observada` (etiqueta: recuperación transaccional observada) |
| Motivo inferido | `motivo_inferido` |
| Nivel confianza | `nivel_confianza` |

### 5–6. Interrupción / recuperación de pago

Tabla `'anl episodios interrupcion pago'`.

| Visual | Campo |
|---|---|
| Cliente | dim cliente |
| Episodio pago | `numero_episodio_pago` |
| Último pago | `fecha_ultimo_pago_previo` |
| Inicio interrupción | `fecha_inicio_interrupcion_pago` |
| Primer pago posterior | `fecha_primer_pago_posterior` |
| Días sin pago | `dias_sin_pago` |
| Recuperó pago | `recupero_pago` |
| Pago posterior a última factura | `pago_posterior_a_ultima_factura` |
| Nivel confianza | `nivel_confianza` |

### 7. Tabla histórica por cliente

`'anl ciclo vida cliente resumen'`: razon social, `fecha_inicio_transaccional_observada`, `ultima_fecha_factura`, `ultima_actividad_pago`, `activo_transaccional_actual`, `cantidad_episodios_inactividad`, `cantidad_recuperaciones_transaccionales`, `cantidad_deserciones_observadas`, `cantidad_contratos_actuales`, `plan_actual`.

### 8. Evidencias / retiro

Resumen: `retiro_registrado`, `fecha_retiro_registrada`, `estado_retiro_registrado`, `actividad_facturacion_posterior_a_retiro`, `pago_posterior_a_ultima_factura`.  
Nota en el visual: la fecha de retiro **no** es churn.

### 9. Confianza

Gráfico de anillos o barras: `nivel_confianza` en episodios factura y, aparte, en episodios pago.

---

## 4. Checklist

- [ ] Autodetectar relaciones = No
- [ ] 5 consultas Gold, schema `gold_guajiranet`, sin Bronze
- [ ] `sk_cliente` texto en las 4 tablas con cliente
- [ ] Solo R-G1 … R-G4; parametros huérfano
- [ ] Ninguna relación Gold↔Gold ni Gold↔dim tiempo / plan / contrato / puentes
- [ ] Medidas nuevas en `_medidas vinculacion`; no clonadas de Capilaridad ni 360
- [ ] Eje mensual = `mes` de la tabla analítica
- [ ] Títulos de página sin «churn certificado»
- [ ] TEST guardado; PBIX original intacto

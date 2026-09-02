# Relaciones — Vinculación y deserción (Gold Analytics)

**PBIX de trabajo:** `Guajiranet_COMPAT_V2_TEST.pbix`  
**No tocar:** `Guajiranet (1).pbix`  
**Fecha de columnas:** 2026-09-01, `information_schema.columns` sobre `gold_guajiranet.vw_anl_*`.

Autodetectar relaciones: **desactivado**. No unir las 5 consultas Gold entre sí. No unir Gold a `dim tiempo`, `dim tiempo dax`, `dim documento`, `dim servicio`, `dim geografia`, `dim plan`, `dim contrato`, `aux sucursal perfil`, `brg sucursal contrato`, `brg contrato plan`.

`sk_cliente` en Gold es integer; el M lo convierte a **texto** para igualar `dim cliente[sk_cliente]`.

---

## Validación de cardinalidad (Aurora, solo lectura)

| Vista | COUNT(*) | COUNT(DISTINCT sk_cliente) | NULL sk | Duplicados de grano |
|---|---:|---:|---:|---:|
| parametros | 1 | — | — | — |
| estado mensual | 292 570 | 13 982 | 0 | 0 (`sk_cliente, mes`) |
| episodios factura | 7 461 | 6 070 | 0 | 0 (`sk_cliente, numero_episodio`) |
| episodios pago | 25 073 | 10 005 | 0 | 0 (`sk_cliente, numero_episodio_pago`) |
| resumen | 13 982 | 13 982 | 0 | 0 (`sk_cliente`) |
| `vw_compat_v2_dim_cliente` | 15 408 | 15 408 | 0 | 0 |

R-G1 / R-G2 / R-G3: **1:\*** confirmado.  
R-G4: ambas puntas **únicas** → **1:1** en el modelo. Cobertura: 13 982 / 15 408 sucursales de `dim cliente` (1 426 sin factura no entran al resumen; es esperado, no se cambia a 1:\*).  
R-G5: sin relación.

No hay nulos de `sk_cliente` en las vistas con cliente. No se corrigen datos.

---

## Mapa R-G1 … R-G5

| ID | Desde | Hacia | Cardinalidad | Filtro | Activa |
|---|---|---|---|---|---|
| R-G1 | `dim cliente[sk_cliente]` | `anl estado transaccional mensual cliente[sk_cliente]` | 1:* | Única | Sí |
| R-G2 | `dim cliente[sk_cliente]` | `anl episodios ciclo vida cliente[sk_cliente]` | 1:* | Única | Sí |
| R-G3 | `dim cliente[sk_cliente]` | `anl episodios interrupcion pago[sk_cliente]` | 1:* | Única | Sí |
| R-G4 | `dim cliente[sk_cliente]` | `anl ciclo vida cliente resumen[sk_cliente]` | 1:1 | Única | Sí |
| R-G5 | `anl ciclo vida parametros` | — | — | — | Sin relación |

No crear: mensual↔episodios, mensual↔pago, episodios factura↔episodios pago.

Eje de evolución mensual: columna `mes` de `anl estado transaccional mensual cliente`. **No** `dim tiempo` (evitar filtrar Capilaridad / fact facturacion).

---

## Relojes

| Reloj | Tabla | Qué cuenta |
|---|---|---|
| Servicio / facturación | mensual `estado_transaccional` + episodios ciclo vida | deserción / recuperación transaccional observada |
| Pago | mensual `estado_pago` + episodios interrupcion pago | interrupción / recuperación de pago |

`recupero_pago` ≠ recuperación de servicio. `fecharetiroisp` / Proceso Retiro ≠ churn. Primera factura = `fecha_inicio_transaccional_observada`.

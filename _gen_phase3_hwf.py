# Temporary Fase 3 HWF generator. Deleted after run.
from __future__ import annotations

from pathlib import Path
from xml.sax.saxutils import escape

OUT = Path(r"c:\apache hop\hop_projects\hop-guajiranet\Workflows")


def upsert_sql(table: str, cols: list[str], conflict: str, distinct_on: str | None = None, prefix: str = "") -> str:
    col_list = ",\n    ".join(cols)
    sel = col_list
    from_clause = f"FROM silver_guajiranet.stg_{table[4:]}" if table.startswith("tbl_") else ""
    stg = "stg_" + table[4:]  # tbl_dim_x -> dim_x, wait tbl_dim_persona -> dim_persona
    # tbl_dim_persona -> stg_dim_persona: replace tbl_ with stg_
    stg = "stg_" + table[4:]
    updates = [c for c in cols if c not in _conflict_cols(conflict)]
    set_list = ",\n    ".join(
        f"{c} = EXCLUDED.{c}" if c != "fecha_actualizacion" else "fecha_actualizacion = CURRENT_TIMESTAMP"
        for c in updates
    )
    distinct = ""
    order = ""
    if distinct_on:
        distinct = f" DISTINCT ON ({distinct_on})\n    "
        order = f"\nORDER BY {distinct_on}"
    return f"""{prefix}INSERT INTO silver_guajiranet.{table}
(
    {col_list}
)
SELECT{distinct}
    {sel}
FROM silver_guajiranet.{stg}{order}

ON CONFLICT ({conflict})
DO UPDATE SET
    {set_list};"""


def _conflict_cols(conflict: str) -> set[str]:
    # strip expressions for exclusion from SET
    parts = []
    depth = 0
    cur = []
    for ch in conflict:
        if ch == "(":
            depth += 1
            cur.append(ch)
        elif ch == ")":
            depth -= 1
            cur.append(ch)
        elif ch == "," and depth == 0:
            parts.append("".join(cur).strip())
            cur = []
        else:
            cur.append(ch)
    if cur:
        parts.append("".join(cur).strip())
    names = set()
    for p in parts:
        if p.startswith("(") or "COALESCE" in p.upper():
            # expression — skip from SET by extracting inner col if possible
            if "nit" in p:
                names.add("nit")
            continue
        names.add(p.strip())
    return names


def unit_hwf(wf_name: str, pipeline: str, sql: str) -> str:
    sql_esc = escape(sql)
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<workflow>
  <name>{escape(wf_name)}</name>
  <name_sync_with_filename>Y</name_sync_with_filename>
  <description/>
  <extended_description>Fase 3 Silver definitivo. Dual-run. Pipeline TRUNCATE stg + UPSERT tbl. No toca workflows viejos.</extended_description>
  <workflow_version/>
  <created_user>-</created_user>
  <created_date>2026/08/24 16:50:00.000</created_date>
  <modified_user>-</modified_user>
  <modified_date>2026/08/24 16:50:00.000</modified_date>
  <parameters>
  </parameters>
  <actions>
    <action>
      <name>Start</name>
      <description/>
      <type>SPECIAL</type>
      <attributes/>
      <DayOfMonth>1</DayOfMonth>
      <doNotWaitOnFirstExecution>N</doNotWaitOnFirstExecution>
      <hour>12</hour>
      <intervalMinutes>60</intervalMinutes>
      <intervalSeconds>0</intervalSeconds>
      <minutes>0</minutes>
      <repeat>N</repeat>
      <schedulerType>0</schedulerType>
      <weekDay>1</weekDay>
      <parallel>N</parallel>
      <xloc>48</xloc>
      <yloc>96</yloc>
      <attributes_hac/>
    </action>
    <action>
      <name>{escape(pipeline)}</name>
      <description/>
      <type>PIPELINE</type>
      <attributes/>
      <add_date>N</add_date>
      <add_time>N</add_time>
      <clear_files>N</clear_files>
      <clear_rows>N</clear_rows>
      <create_parent_folder>N</create_parent_folder>
      <exec_per_row>N</exec_per_row>
      <filename>${{PROJECT_HOME}}/Pipelines/{escape(pipeline)}</filename>
      <logext/>
      <logfile/>
      <loglevel>Basic</loglevel>
      <parameters>
        <pass_all_parameters>Y</pass_all_parameters>
      </parameters>
      <params_from_previous>N</params_from_previous>
      <run_configuration>local</run_configuration>
      <set_append_logfile>N</set_append_logfile>
      <set_logfile>N</set_logfile>
      <wait_until_finished>Y</wait_until_finished>
      <parallel>N</parallel>
      <xloc>224</xloc>
      <yloc>96</yloc>
      <attributes_hac/>
    </action>
    <action>
      <name>SQL</name>
      <description/>
      <type>SQL</type>
      <attributes/>
      <connection>aws_rds</connection>
      <sendOneStatement>N</sendOneStatement>
      <sql>{sql_esc}</sql>
      <sqlfilename/>
      <sqlfromfile>N</sqlfromfile>
      <useVariableSubstitution>N</useVariableSubstitution>
      <parallel>N</parallel>
      <xloc>432</xloc>
      <yloc>96</yloc>
      <attributes_hac/>
    </action>
    <action>
      <name>Success</name>
      <description/>
      <type>SUCCESS</type>
      <attributes/>
      <parallel>N</parallel>
      <xloc>624</xloc>
      <yloc>96</yloc>
      <attributes_hac/>
    </action>
    <action>
      <name>Abort</name>
      <description/>
      <type>ABORT</type>
      <attributes/>
      <message>Fallo {escape(wf_name)}: pipeline o UPSERT no termino correctamente</message>
      <always_log_rows_on_abort>N</always_log_rows_on_abort>
      <parallel>N</parallel>
      <xloc>432</xloc>
      <yloc>240</yloc>
      <attributes_hac/>
    </action>
  </actions>
  <hops>
    <hop>
      <from>Start</from>
      <to>{escape(pipeline)}</to>
      <enabled>Y</enabled>
      <evaluation>Y</evaluation>
      <unconditional>Y</unconditional>
    </hop>
    <hop>
      <from>{escape(pipeline)}</from>
      <to>SQL</to>
      <enabled>Y</enabled>
      <evaluation>Y</evaluation>
      <unconditional>N</unconditional>
    </hop>
    <hop>
      <from>{escape(pipeline)}</from>
      <to>Abort</to>
      <enabled>Y</enabled>
      <evaluation>N</evaluation>
      <unconditional>N</unconditional>
    </hop>
    <hop>
      <from>SQL</from>
      <to>Success</to>
      <enabled>Y</enabled>
      <evaluation>Y</evaluation>
      <unconditional>N</unconditional>
    </hop>
    <hop>
      <from>SQL</from>
      <to>Abort</to>
      <enabled>Y</enabled>
      <evaluation>N</evaluation>
      <unconditional>N</unconditional>
    </hop>
  </hops>
  <notepads>
  </notepads>
  <attributes/>
</workflow>
"""


def wf_action(name: str, x: int, y: int = 160) -> str:
    return f"""    <action>
      <filename>${{PROJECT_HOME}}/Workflows/{escape(name)}</filename>
      <params_from_previous>N</params_from_previous>
      <exec_per_row>N</exec_per_row>
      <set_logfile>N</set_logfile>
      <logfile/>
      <logext/>
      <add_date>N</add_date>
      <add_time>N</add_time>
      <loglevel>Nothing</loglevel>
      <set_append_logfile>N</set_append_logfile>
      <create_parent_folder>N</create_parent_folder>
      <wait_until_finished>Y</wait_until_finished>
      <parameters>
        <pass_all_parameters>Y</pass_all_parameters>
      </parameters>
      <run_configuration>local</run_configuration>
      <name>{escape(name)}</name>
      <type>WORKFLOW</type>
      <attributes/>
      <xloc>{x}</xloc>
      <yloc>{y}</yloc>
      <parallel>N</parallel>
      <attributes_hac/>
    </action>
"""


def hop(frm: str, to: str, enabled: bool = True, uncond: bool = False) -> str:
    en = "Y" if enabled else "N"
    un = "Y" if uncond else "N"
    return f"""    <hop>
      <from>{escape(frm)}</from>
      <to>{escape(to)}</to>
      <evaluation>Y</evaluation>
      <unconditional>{un}</unconditional>
      <enabled>{en}</enabled>
    </hop>
"""


# ---------------------------------------------------------------------------
# Column sets (staging = tbl minus SK)
# ---------------------------------------------------------------------------
C_PERSONA = ["nit", "dv", "razonsocial", "documento_identidad", "tipo_persona",
             "es_cliente", "es_proveedor", "tdoc", "idcliente", "fecha_creacion",
             "fecha_actualizacion"]
C_SUCURSAL = ["nit", "idsuc", "sk_persona", "sk_geografia", "sk_perfil_cartera",
              "razonsocial_suc", "direccion", "direccion2", "dpto", "mun", "ciudad",
              "email", "emailfe", "telefono1", "movil", "contacto1", "activo",
              "estrato", "coordenada", "finiciopermanencia", "fecharetiroisp",
              "idperfilcartera", "idperfilcartera_anterior", "fecha_actualizacion"]
C_CONTRATO = ["idcontrato", "idcliente", "public_id", "state", "start_date",
              "created_at", "updated_at", "address_street", "address_city",
              "address_state", "address_country", "address_number", "latitude",
              "longitude", "ont_id", "ont_number", "ont_serial_number", "olt_id",
              "interface_gpon", "mac_address", "plan_id", "fecha_actualizacion"]
C_PLAN = ["id_plan", "tipo", "nombre", "public_id", "ceil_down_kbps", "ceil_up_kbps",
          "cir", "precio", "frequency_in_months", "contracts_count", "created_at",
          "updated_at", "fecha_actualizacion"]
C_PRODUCTO = ["id_producto", "nombre_producto", "id_familia", "categoria",
              "tarifa_lista", "estado_activo", "fecha_actualizacion"]
C_PERFIL = ["id_perfil", "denominacion", "diasvence1", "diasvence2", "deshabilitar",
            "alertar", "diasvencefactura", "nofactura", "fecha_actualizacion"]
C_GEO = ["id_barrio", "barrio", "dpto", "mun", "municipio", "departamento",
         "fecha_actualizacion"]
C_BRG_UUID = ["idcliente", "nit", "sk_persona", "en_materceros", "en_tmjsonclient",
              "fecha_actualizacion"]
C_BRG_SC = ["sk_sucursal", "sk_contrato", "nit", "idsuc", "idcontrato", "match_json",
            "fecha_actualizacion"]
C_BRG_CP = ["sk_contrato", "sk_plan", "idcontrato", "id_plan", "fecha_actualizacion"]
C_FACT_F = ["idsuc", "prefijo", "numero", "pos", "sk_sucursal", "sk_persona",
            "sk_producto", "sk_documento", "sk_geografia", "sk_tiempo",
            "sk_contrato", "sk_plan", "fecha_factura", "anulado", "cantidad",
            "precio", "subtotal", "iva", "neto", "fecha_actualizacion"]
C_FACT_C = ["idsuc", "prefijo", "numero", "cuenta", "nit", "sucursal", "ref_doc",
            "ref_num", "sk_sucursal", "sk_persona", "sk_tiempo", "sk_perfil_cartera",
            "plazo", "fecha", "fecha_vencimiento", "dias", "saldo", "debito",
            "credito", "rango1", "rango2", "rango3", "rango4", "rango5", "rango6",
            "interes", "idformapago", "transaccion", "fecha_actualizacion"]
C_PAGO_A = ["idsuc", "prefijo", "numero", "rc_idsuc", "rc_prefijo", "rc_numero",
            "sk_sucursal", "sk_persona", "sk_documento", "sk_tiempo_factura",
            "sk_tiempo_recibo", "carteraaplicado", "pagorc", "idformapago",
            "ccosto", "fecha_actualizacion"]
C_PAGO_P = ["id_pago_digital", "idsuc", "prefijo", "numero", "rec_idsuc",
            "rec_prefijo", "rec_numero", "sk_sucursal", "sk_persona", "sk_tiempo",
            "foperacion", "total", "codigo_respuesta", "numero_recibo",
            "numero_autorizacion", "referencia", "numero_orden",
            "fecha_actualizacion"]

DELETE_CARTERA = """DELETE FROM silver_guajiranet.tbl_fact_cartera AS t
WHERE NOT EXISTS (
    SELECT 1
    FROM silver_guajiranet.stg_fact_cartera AS s
    WHERE s.idsuc = t.idsuc
      AND s.prefijo = t.prefijo
      AND s.numero = t.numero
      AND s.cuenta = t.cuenta
      AND s.nit = t.nit
      AND s.sucursal = t.sucursal
      AND s.ref_doc = t.ref_doc
      AND s.ref_num = t.ref_num
);

"""

units = {
    "wf_dim_perfil_cartera.hwf": (
        "wf_dim_perfil_cartera", "dim_perfil_cartera.hpl",
        upsert_sql("tbl_dim_perfil_cartera", C_PERFIL, "id_perfil", "id_perfil"),
    ),
    "wf_dim_persona.hwf": (
        "wf_dim_persona", "dim_persona.hpl",
        upsert_sql("tbl_dim_persona", C_PERSONA, "nit", "nit"),
    ),
    "wf_brg_persona_uuid.hwf": (
        "wf_brg_persona_uuid", "brg_persona_uuid.hpl",
        upsert_sql(
            "tbl_brg_persona_uuid", C_BRG_UUID,
            "idcliente, (COALESCE(nit, -1))",
            "idcliente, COALESCE(nit, -1)",
        ),
    ),
    "wf_dim_plan.hwf": (
        "wf_dim_plan", "dim_plan.hpl",
        upsert_sql("tbl_dim_plan", C_PLAN, "id_plan", "id_plan"),
    ),
    "wf_dim_contrato.hwf": (
        "wf_dim_contrato", "dim_contrato.hpl",
        upsert_sql("tbl_dim_contrato", C_CONTRATO, "idcontrato", "idcontrato"),
    ),
    "wf_dim_geografia_v2.hwf": (
        "wf_dim_geografia_v2", "dim_geografia_v2.hpl",
        upsert_sql("tbl_dim_geografia", C_GEO, "id_barrio", "id_barrio"),
    ),
    "wf_dim_sucursal.hwf": (
        "wf_dim_sucursal", "dim_sucursal.hpl",
        upsert_sql("tbl_dim_sucursal", C_SUCURSAL, "nit, idsuc", "nit, idsuc"),
    ),
    "wf_dim_producto_erp.hwf": (
        "wf_dim_producto_erp", "dim_producto_erp.hpl",
        upsert_sql("tbl_dim_producto_erp", C_PRODUCTO, "id_producto", "id_producto"),
    ),
    "wf_brg_sucursal_contrato.hwf": (
        "wf_brg_sucursal_contrato", "brg_sucursal_contrato.hpl",
        upsert_sql("tbl_brg_sucursal_contrato", C_BRG_SC, "nit, idsuc, idcontrato",
                   "nit, idsuc, idcontrato"),
    ),
    "wf_brg_contrato_plan.hwf": (
        "wf_brg_contrato_plan", "brg_contrato_plan.hpl",
        upsert_sql("tbl_brg_contrato_plan", C_BRG_CP, "idcontrato", "idcontrato"),
    ),
    "wf_fact_pago_aplicacion.hwf": (
        "wf_fact_pago_aplicacion", "fact_pago_aplicacion.hpl",
        upsert_sql("tbl_fact_pago_aplicacion", C_PAGO_A,
                   "idsuc, prefijo, numero, rc_idsuc, rc_prefijo, rc_numero",
                   "idsuc, prefijo, numero, rc_idsuc, rc_prefijo, rc_numero"),
    ),
    "wf_fact_pago_pasarela.hwf": (
        "wf_fact_pago_pasarela", "fact_pago_pasarela.hpl",
        upsert_sql("tbl_fact_pago_pasarela", C_PAGO_P, "id_pago_digital",
                   "id_pago_digital"),
    ),
    "wf_fact_facturacion_v2.hwf": (
        "wf_fact_facturacion_v2", "fact_facturacion_v2.hpl",
        upsert_sql("tbl_fact_facturacion", C_FACT_F,
                   "idsuc, prefijo, numero, pos",
                   "idsuc, prefijo, numero, pos"),
    ),
    "wf_fact_cartera_v2.hwf": (
        "wf_fact_cartera_v2", "fact_cartera_v2.hpl",
        upsert_sql(
            "tbl_fact_cartera", C_FACT_C,
            "idsuc, prefijo, numero, cuenta, nit, sucursal, ref_doc, ref_num",
            "idsuc, prefijo, numero, cuenta, nit, sucursal, ref_doc, ref_num",
            prefix=DELETE_CARTERA,
        ),
    ),
}

for fname, (wname, pipe, sql) in units.items():
    (OUT / fname).write_text(unit_hwf(wname, pipe, sql), encoding="utf-8", newline="\n")
    print("wrote", fname)

# ---------------------------------------------------------------------------
# Orchestrator
# Live path: contrato skips geo v2; ends after pagos.
# Geo v2 and facts v2 hops exist but enabled=N until stg cutover.
# ---------------------------------------------------------------------------
chain_live = [
    "wf_dim_tiempo.hwf",
    "wf_dim_documento.hwf",
    "wf_dim_perfil_cartera.hwf",
    "wf_dim_persona.hwf",
    "wf_brg_persona_uuid.hwf",
    "wf_dim_plan.hwf",
    "wf_dim_contrato.hwf",
    "wf_dim_sucursal.hwf",
    "wf_dim_producto_erp.hwf",
    "wf_brg_sucursal_contrato.hwf",
    "wf_brg_contrato_plan.hwf",
    "wf_fact_pago_aplicacion.hwf",
    "wf_fact_pago_pasarela.hwf",
]
geo_blocked = "wf_dim_geografia_v2.hwf"
blocked = [
    "wf_fact_facturacion_v2.hwf",
    "wf_fact_cartera_v2.hwf",
]

actions = ["""    <action>
      <repeat>N</repeat>
      <schedulerType>0</schedulerType>
      <intervalSeconds>0</intervalSeconds>
      <intervalMinutes>60</intervalMinutes>
      <DayOfMonth>1</DayOfMonth>
      <weekDay>1</weekDay>
      <minutes>0</minutes>
      <hour>12</hour>
      <doNotWaitOnFirstExecution>N</doNotWaitOnFirstExecution>
      <name>Start</name>
      <description/>
      <type>SPECIAL</type>
      <attributes/>
      <xloc>48</xloc>
      <yloc>160</yloc>
      <parallel>N</parallel>
      <attributes_hac/>
    </action>
"""]
x = 200
graph = chain_live[:7] + [geo_blocked] + chain_live[7:] + blocked
for name in graph:
    y = 160
    if name == geo_blocked:
        y = 48
    elif name in blocked:
        y = 320
    actions.append(wf_action(name, x, y))
    if name != geo_blocked:
        x += 180

actions.append("""    <action>
      <name>Success</name>
      <description/>
      <type>SUCCESS</type>
      <attributes/>
      <xloc>2720</xloc>
      <yloc>160</yloc>
      <parallel>N</parallel>
      <attributes_hac/>
    </action>
""")

hops = [hop("Start", chain_live[0], enabled=True, uncond=True)]
for a, b in zip(chain_live, chain_live[1:]):
    hops.append(hop(a, b, enabled=True, uncond=False))
hops.append(hop(chain_live[-1], "Success", enabled=True, uncond=False))
# Geo v2: in graph, hops off; live path is contrato → sucursal
hops.append(hop("wf_dim_contrato.hwf", geo_blocked, enabled=False, uncond=False))
hops.append(hop(geo_blocked, "wf_dim_sucursal.hwf", enabled=False, uncond=False))
# Blocked facts: hops disabled until stg cutover
hops.append(hop(chain_live[-1], blocked[0], enabled=False, uncond=False))
hops.append(hop(blocked[0], blocked[1], enabled=False, uncond=False))
hops.append(hop(blocked[1], "Success", enabled=False, uncond=False))

orch = f"""<?xml version="1.0" encoding="UTF-8"?>
<workflow>
  <name>wf_actualizacion_silver_v2</name>
  <name_sync_with_filename>Y</name_sync_with_filename>
  <description/>
  <extended_description>Orquestador Silver definitivo. NO activar en wf_delta/historic. Hops de fact_facturacion_v2 y fact_cartera_v2 deshabilitados hasta cutover de stg.</extended_description>
  <created_user>-</created_user>
  <modified_user>-</modified_user>
  <created_date>2026/08/24 16:50:00.000</created_date>
  <modified_date>2026/08/24 16:50:00.000</modified_date>
  <parameters/>
  <actions>
{''.join(actions)}  </actions>
  <hops>
{''.join(hops)}  </hops>
  <notepads>
    <notepad>
      <note>BLOQUEO: no ejecutar fact_facturacion_v2 ni fact_cartera_v2 hasta REPLACE de sus stg (07 B + 03). Hops deshabilitados. NO ejecutar 07_drop_obsolete.sql desde este workflow. DDL 01-04 y 06 es prerrequisito, no se corre aqui. dim_geografia_v2 comparte stg con el HPL viejo: no programar este orquestador hasta cutover de geo o saltar ese paso.</note>
      <fontname>Segoe UI</fontname>
      <fontsize>9</fontsize>
      <fontbold>N</fontbold>
      <fontitalic>N</fontitalic>
      <fontcolorred>14</fontcolorred>
      <fontcolorgreen>58</fontcolorgreen>
      <fontcolorblue>90</fontcolorblue>
      <backgroundcolorred>255</backgroundcolorred>
      <backgroundcolorgreen>236</backgroundcolorgreen>
      <backgroundcolorblue>179</backgroundcolorblue>
      <bordercolorred>14</bordercolorred>
      <bordercolorgreen>58</bordercolorgreen>
      <bordercolorblue>90</bordercolorblue>
      <xloc>16</xloc>
      <yloc>16</yloc>
      <width>900</width>
      <height>96</height>
    </notepad>
  </notepads>
  <attributes/>
</workflow>
"""
(OUT / "wf_actualizacion_silver_v2.hwf").write_text(orch, encoding="utf-8", newline="\n")
print("wrote wf_actualizacion_silver_v2.hwf")
print("units", len(units))

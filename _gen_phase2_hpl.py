# Temporary generator for Fase 2 HPL files. Deleted after run.
from __future__ import annotations

from pathlib import Path
from xml.sax.saxutils import escape

OUT = Path(r"c:\apache hop\hop_projects\hop-guajiranet\Pipelines")


def so_field(name: str, trim: str = "none", case: str = "none") -> str:
    return f"""      <field>
        <in_stream_name>{escape(name)}</in_stream_name>
        <out_stream_name/>
        <trim_type>{trim}</trim_type>
        <lower_upper>{case}</lower_upper>
        <padding_type>none</padding_type>
        <pad_char/>
        <pad_len/>
        <init_cap>no</init_cap>
        <mask_xml>none</mask_xml>
        <digits>none</digits>
        <remove_special_characters>none</remove_special_characters>
      </field>"""


def mapping(name: str, date_mask: str = "") -> str:
    return f"""    <mapping>
      <date_mask>{date_mask}</date_mask>
      <field_name>{escape(name)}</field_name>
      <stream_name>{escape(name)}</stream_name>
    </mapping>"""


def select_field(name: str) -> str:
    return f"""      <field>
        <name>{escape(name)}</name>
        <rename/>
        <length>-2</length>
        <precision>-2</precision>
      </field>"""


def pipeline_string_ops(
    name: str,
    sql: str,
    table: str,
    mappings: list[tuple[str, str]],
    string_ops: list[tuple[str, str, str]],
) -> str:
    hops = """    <hop>
      <from>Table input</from>
      <to>String operations</to>
      <enabled>Y</enabled>
    </hop>
    <hop>
      <from>String operations</from>
      <to>PostgreSQL Bulk Loader</to>
      <enabled>Y</enabled>
    </hop>"""
    so = "\n".join(so_field(n, t, c) for n, t, c in string_ops)
    maps = "\n".join(mapping(n, m) for n, m in mappings)
    return _wrap(
        name,
        hops,
        table_input(sql)
        + string_ops_tf(so)
        + bulk_loader(table, maps, x=832, y=240),
    )


def pipeline_select(
    name: str,
    sql: str,
    table: str,
    mappings: list[tuple[str, str]],
    select_names: list[str],
) -> str:
    hops = """    <hop>
      <from>Table input</from>
      <to>Select values</to>
      <enabled>Y</enabled>
    </hop>
    <hop>
      <from>Select values</from>
      <to>PostgreSQL Bulk Loader</to>
      <enabled>Y</enabled>
    </hop>"""
    fields = "\n".join(select_field(n) for n in select_names)
    maps = "\n".join(mapping(n, m) for n, m in mappings)
    return _wrap(
        name,
        hops,
        table_input(sql, x=224, y=256)
        + select_values(fields)
        + bulk_loader(table, maps, x=688, y=256),
    )


def _wrap(name: str, hops: str, transforms: str) -> str:
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<pipeline>
  <info>
    <name>{escape(name)}</name>
    <name_sync_with_filename>Y</name_sync_with_filename>
    <description/>
    <extended_description>Fase 2 Silver definitivo. Dual-run: no reemplaza pipelines viejos. Carga solo staging.</extended_description>
    <pipeline_version/>
    <pipeline_type>Normal</pipeline_type>
    <parameters>
    </parameters>
    <capture_transform_performance>N</capture_transform_performance>
    <transform_performance_capturing_delay>1000</transform_performance_capturing_delay>
    <transform_performance_capturing_size_limit>100</transform_performance_capturing_size_limit>
    <created_user>-</created_user>
    <created_date>2026/08/24 16:40:00.000</created_date>
    <modified_user>-</modified_user>
    <modified_date>2026/08/24 16:40:00.000</modified_date>
  </info>
  <notepads>
  </notepads>
  <order>
{hops}
  </order>
{transforms}
  <transform_error_handling>
  </transform_error_handling>
  <attributes/>
</pipeline>
"""


def table_input(sql: str, x: int = 336, y: int = 240) -> str:
    return f"""  <transform>
    <name>Table input</name>
    <type>TableInput</type>
    <description/>
    <distribute>Y</distribute>
    <custom_distribution/>
    <copies>1</copies>
    <partitioning>
      <method>none</method>
      <schema_name/>
    </partitioning>
    <connection>aws_rds</connection>
    <execute_each_row>N</execute_each_row>
    <limit>0</limit>
    <sql>{escape(sql)}</sql>
    <variables_active>N</variables_active>
    <attributes/>
    <GUI>
      <xloc>{x}</xloc>
      <yloc>{y}</yloc>
    </GUI>
  </transform>
"""


def string_ops_tf(fields: str) -> str:
    return f"""  <transform>
    <name>String operations</name>
    <type>StringOperations</type>
    <description/>
    <distribute>Y</distribute>
    <custom_distribution/>
    <copies>1</copies>
    <partitioning>
      <method>none</method>
      <schema_name/>
    </partitioning>
    <fields>
{fields}
    </fields>
    <attributes/>
    <GUI>
      <xloc>544</xloc>
      <yloc>240</yloc>
    </GUI>
  </transform>
"""


def select_values(fields: str) -> str:
    return f"""  <transform>
    <name>Select values</name>
    <type>SelectValues</type>
    <description/>
    <distribute>Y</distribute>
    <custom_distribution/>
    <copies>1</copies>
    <partitioning>
      <method>none</method>
      <schema_name/>
    </partitioning>
    <fields>
{fields}
      <select_unspecified>N</select_unspecified>
    </fields>
    <attributes/>
    <GUI>
      <xloc>432</xloc>
      <yloc>256</yloc>
    </GUI>
  </transform>
"""


def bulk_loader(table: str, maps: str, x: int, y: int) -> str:
    return f"""  <transform>
    <name>PostgreSQL Bulk Loader</name>
    <type>PGBulkLoader</type>
    <description/>
    <distribute>Y</distribute>
    <custom_distribution/>
    <copies>1</copies>
    <partitioning>
      <method>none</method>
      <schema_name/>
    </partitioning>
    <connection>aws_rds</connection>
    <db_override/>
    <delimiter>;</delimiter>
    <enclosure>"</enclosure>
    <load_action>TRUNCATE</load_action>
{maps}
    <schema>silver_guajiranet</schema>
    <stop_on_error>N</stop_on_error>
    <table>{escape(table)}</table>
    <attributes/>
    <GUI>
      <xloc>{x}</xloc>
      <yloc>{y}</yloc>
    </GUI>
  </transform>
"""


# ---------------------------------------------------------------------------
# SQL
# ---------------------------------------------------------------------------

SQL_PERSONA = """SELECT
    t.nit,
    t.dv,
    t.razonsocial,
    t.identificacion AS documento_identidad,
    t.tipopersona AS tipo_persona,
    t.escliente AS es_cliente,
    t.esproveedor AS es_proveedor,
    t.tdoc,
    t.idcliente,
    t.fechacreacion AS fecha_creacion,
    CURRENT_TIMESTAMP AS fecha_actualizacion
FROM bronze_guajiranet.materceros t"""

SQL_SUCURSAL = """SELECT
    s.nit,
    s.idsuc,
    p.sk_persona,
    COALESCE(g.sk_geografia, 0) AS sk_geografia,
    COALESCE(pc.sk_perfil_cartera, 0) AS sk_perfil_cartera,
    s.razonsocial AS razonsocial_suc,
    s.direccion1 AS direccion,
    s.direccion2,
    s.dpto,
    s.mun,
    s.ciudad,
    s.email,
    s.emailfe,
    s.telefono1,
    s.movil,
    s.contacto1,
    s.activo,
    s.estrato,
    s.coordenada,
    s.finiciopermanencia,
    s.fecharetiroisp,
    s.idperfilcartera,
    s.idperfilcartera_anterior,
    CURRENT_TIMESTAMP AS fecha_actualizacion
FROM bronze_guajiranet.matercerosuc s
INNER JOIN silver_guajiranet.tbl_dim_persona p
        ON s.nit = p.nit
LEFT JOIN silver_guajiranet.tbl_dim_geografia g
       ON CAST(s.idbarrio AS VARCHAR) = CAST(g.id_barrio AS VARCHAR)
LEFT JOIN silver_guajiranet.tbl_dim_perfil_cartera pc
       ON COALESCE(s.idperfilcartera, 0) = pc.id_perfil"""

SQL_CONTRATO = """SELECT
    c.datajson->>'id' AS idcontrato,
    COALESCE(NULLIF(TRIM(c.idcliente), ''), c.datajson->>'client_id') AS idcliente,
    (c.datajson->>'public_id')::integer AS public_id,
    c.datajson->>'state' AS state,
    NULLIF(c.datajson->>'start_date', '')::timestamptz AS start_date,
    NULLIF(c.datajson->>'created_at', '')::timestamptz AS created_at,
    NULLIF(c.datajson->>'updated_at', '')::timestamptz AS updated_at,
    c.datajson->>'address_street' AS address_street,
    c.datajson->>'address_city' AS address_city,
    c.datajson->>'address_state' AS address_state,
    c.datajson->>'address_country' AS address_country,
    c.datajson->>'address_number' AS address_number,
    NULLIF(c.datajson->>'latitude', '')::numeric(12, 8) AS latitude,
    NULLIF(c.datajson->>'longitude', '')::numeric(12, 8) AS longitude,
    c.datajson->>'ont_id' AS ont_id,
    c.datajson->>'ont_number' AS ont_number,
    c.datajson->>'ont_serial_number' AS ont_serial_number,
    c.datajson->>'olt_id' AS olt_id,
    c.datajson->>'interface_gpon' AS interface_gpon,
    c.datajson->>'mac_address' AS mac_address,
    c.datajson->>'plan_id' AS plan_id,
    CURRENT_TIMESTAMP AS fecha_actualizacion
FROM bronze_guajiranet.tmjsoncontract c"""

SQL_PLAN = """SELECT
    p.datajson->>'id' AS id_plan,
    p.tipo,
    p.datajson->>'name' AS nombre,
    (p.datajson->>'public_id')::integer AS public_id,
    (p.datajson->>'ceil_down_kbps')::integer AS ceil_down_kbps,
    (p.datajson->>'ceil_up_kbps')::integer AS ceil_up_kbps,
    p.datajson->>'cir' AS cir,
    NULLIF(p.datajson->>'price', '')::numeric(18, 2) AS precio,
    (p.datajson->>'frequency_in_months')::integer AS frequency_in_months,
    (p.datajson->>'contracts_count')::integer AS contracts_count,
    NULLIF(p.datajson->>'created_at', '')::timestamptz AS created_at,
    NULLIF(p.datajson->>'updated_at', '')::timestamptz AS updated_at,
    CURRENT_TIMESTAMP AS fecha_actualizacion
FROM bronze_guajiranet.tmjsonplan_server p
WHERE p.tipo = 'P'"""

SQL_PRODUCTO = """SELECT
    p.idproducto AS id_producto,
    p.nombreproducto AS nombre_producto,
    p.idfam1 AS id_familia,
    f.familia AS categoria,
    p.lista1 AS tarifa_lista,
    p.activo AS estado_activo,
    CURRENT_TIMESTAMP AS fecha_actualizacion
FROM bronze_guajiranet.maproductos p
LEFT JOIN bronze_guajiranet.mafamiliasproductos f
       ON p.idfam1 = f.idfamilia"""

SQL_PERFIL = """SELECT
    0 AS id_perfil,
    'DESCONOCIDO' AS denominacion,
    CAST(NULL AS integer) AS diasvence1,
    CAST(NULL AS integer) AS diasvence2,
    CAST(NULL AS character(1)) AS deshabilitar,
    CAST(NULL AS character(1)) AS alertar,
    CAST(NULL AS integer) AS diasvencefactura,
    CAST(NULL AS boolean) AS nofactura,
    CURRENT_TIMESTAMP AS fecha_actualizacion

UNION ALL

SELECT
    p.id AS id_perfil,
    p.denominacion,
    p.diasvence1,
    p.diasvence2,
    p.deshabilitar,
    p.alertar,
    p.diasvencefactura,
    p.nofactura,
    CURRENT_TIMESTAMP AS fecha_actualizacion
FROM bronze_guajiranet.maperfilcartera p
WHERE p.id IS DISTINCT FROM 0"""

SQL_BRG_UUID = """SELECT
    COALESCE(t.idcliente, j.idcliente) AS idcliente,
    t.nit,
    p.sk_persona,
    (t.nit IS NOT NULL) AS en_materceros,
    (j.idcliente IS NOT NULL) AS en_tmjsonclient,
    CURRENT_TIMESTAMP AS fecha_actualizacion
FROM bronze_guajiranet.materceros t
FULL OUTER JOIN bronze_guajiranet.tmjsonclient j
        ON t.idcliente = j.idcliente
LEFT JOIN silver_guajiranet.tbl_dim_persona p
       ON t.nit = p.nit
WHERE COALESCE(t.idcliente, j.idcliente) IS NOT NULL"""

SQL_BRG_SUC_CON = """SELECT
    suc.sk_sucursal,
    c.sk_contrato,
    s.nit,
    s.idsuc,
    s.idcontrato,
    (c.sk_contrato IS NOT NULL) AS match_json,
    CURRENT_TIMESTAMP AS fecha_actualizacion
FROM bronze_guajiranet.matercerosuc s
INNER JOIN silver_guajiranet.tbl_dim_sucursal suc
        ON s.nit = suc.nit
       AND s.idsuc = suc.idsuc
LEFT JOIN silver_guajiranet.tbl_dim_contrato c
       ON s.idcontrato = c.idcontrato
WHERE s.idcontrato IS NOT NULL"""

SQL_BRG_CON_PLAN = """SELECT
    c.sk_contrato,
    p.sk_plan,
    c.idcontrato,
    t.datajson->>'plan_id' AS id_plan,
    CURRENT_TIMESTAMP AS fecha_actualizacion
FROM bronze_guajiranet.tmjsoncontract t
INNER JOIN silver_guajiranet.tbl_dim_contrato c
        ON t.datajson->>'id' = c.idcontrato
INNER JOIN silver_guajiranet.tbl_dim_plan p
        ON t.datajson->>'plan_id' = p.id_plan"""

SQL_FACT_FACT = """SELECT
    d.idsuc,
    d.prefijo,
    d.numero,
    d.pos,
    suc.sk_sucursal,
    per.sk_persona,
    prod.sk_producto,
    doc.sk_documento,
    COALESCE(suc.sk_geografia, 0) AS sk_geografia,
    tm.sk_tiempo,
    CAST(NULL AS integer) AS sk_contrato,
    CAST(NULL AS integer) AS sk_plan,
    f.fecha AS fecha_factura,
    f.anulado,
    d.cantidad,
    d.precio,
    d.subtotal,
    d.iva,
    d.neto,
    CURRENT_TIMESTAMP AS fecha_actualizacion
FROM bronze_guajiranet.trfacturas f
INNER JOIN bronze_guajiranet.trfacturasdet d
        ON f.idsuc = d.idsuc
       AND f.prefijo = d.prefijo
       AND f.numero = d.numero
INNER JOIN silver_guajiranet.tbl_dim_sucursal suc
        ON f.nit = suc.nit
       AND f.sucursal = suc.idsuc
INNER JOIN silver_guajiranet.tbl_dim_persona per
        ON f.nit = per.nit
INNER JOIN silver_guajiranet.tbl_dim_producto_erp prod
        ON d.idproducto = prod.id_producto
INNER JOIN silver_guajiranet.tbl_dim_documento doc
        ON f.idsuc = doc.idsuc
       AND f.prefijo = doc.prefijo
INNER JOIN silver_guajiranet.tbl_dim_tiempo tm
        ON f.fecha = tm.fecha"""

SQL_FACT_CARTERA = """WITH latest_open AS (
    SELECT DISTINCT ON (
        c.idsuc,
        c.prefijo,
        c.numero,
        c.cuenta,
        c.nit,
        c.sucursal,
        c.ref_doc,
        c.ref_num
    )
        c.idsuc,
        c.prefijo,
        c.numero,
        c.cuenta,
        c.nit,
        c.sucursal,
        c.ref_doc,
        c.ref_num,
        c.plazo,
        c.fecha,
        c.fvence,
        c.dias,
        c.saldo,
        c.debito,
        c.credito,
        c.rango1,
        c.rango2,
        c.rango3,
        c.rango4,
        c.rango5,
        c.rango6,
        c.interes,
        c.idformapago,
        c.transaccion
    FROM bronze_guajiranet.tmcartera c
    WHERE c.saldo <> 0
    ORDER BY
        c.idsuc,
        c.prefijo,
        c.numero,
        c.cuenta,
        c.nit,
        c.sucursal,
        c.ref_doc,
        c.ref_num,
        c.fecha DESC NULLS LAST
)
SELECT
    l.idsuc,
    l.prefijo,
    l.numero,
    l.cuenta,
    l.nit,
    l.sucursal,
    l.ref_doc,
    l.ref_num,
    suc.sk_sucursal,
    per.sk_persona,
    tm.sk_tiempo,
    COALESCE(suc.sk_perfil_cartera, 0) AS sk_perfil_cartera,
    l.plazo,
    l.fecha,
    l.fvence AS fecha_vencimiento,
    l.dias,
    l.saldo,
    l.debito,
    l.credito,
    l.rango1,
    l.rango2,
    l.rango3,
    l.rango4,
    l.rango5,
    l.rango6,
    l.interes,
    l.idformapago,
    l.transaccion,
    CURRENT_TIMESTAMP AS fecha_actualizacion
FROM latest_open l
INNER JOIN silver_guajiranet.tbl_dim_sucursal suc
        ON l.nit = suc.nit
       AND l.sucursal = suc.idsuc
INNER JOIN silver_guajiranet.tbl_dim_persona per
        ON l.nit = per.nit
INNER JOIN silver_guajiranet.tbl_dim_tiempo tm
        ON l.fecha = tm.fecha"""

SQL_PAGO_APL = """SELECT DISTINCT ON (
    v.idsuc,
    v.prefijo,
    v.numero,
    v.rc_idsuc,
    v.rc_prefijo,
    v.rc_numero
)
    v.idsuc,
    v.prefijo,
    v.numero,
    v.rc_idsuc,
    v.rc_prefijo,
    v.rc_numero,
    suc.sk_sucursal,
    per.sk_persona,
    doc.sk_documento,
    tf.sk_tiempo AS sk_tiempo_factura,
    tr.sk_tiempo AS sk_tiempo_recibo,
    v.carteraaplicado,
    v.pagorc,
    v.idformapago,
    v.ccosto,
    CURRENT_TIMESTAMP AS fecha_actualizacion
FROM bronze_guajiranet.vpagodiasfactura v
LEFT JOIN bronze_guajiranet.trfacturas f
       ON v.idsuc = f.idsuc
      AND v.prefijo = f.prefijo
      AND v.numero = f.numero
LEFT JOIN silver_guajiranet.tbl_dim_sucursal suc
       ON f.nit = suc.nit
      AND f.sucursal = suc.idsuc
LEFT JOIN silver_guajiranet.tbl_dim_persona per
       ON f.nit = per.nit
LEFT JOIN silver_guajiranet.tbl_dim_documento doc
       ON v.idsuc = doc.idsuc
      AND v.prefijo = doc.prefijo
LEFT JOIN silver_guajiranet.tbl_dim_tiempo tf
       ON v.fecha = tf.fecha
LEFT JOIN silver_guajiranet.tbl_dim_tiempo tr
       ON v.rc_fecha = tr.fecha
ORDER BY
    v.idsuc,
    v.prefijo,
    v.numero,
    v.rc_idsuc,
    v.rc_prefijo,
    v.rc_numero"""

SQL_PAGO_PAS = """SELECT
    p.id AS id_pago_digital,
    p.idsuc,
    p.prefijo,
    p.numero,
    p.rec_idsuc,
    p.rec_prefijo,
    p.rec_numero,
    suc.sk_sucursal,
    per.sk_persona,
    tm.sk_tiempo,
    p.foperacion,
    p.total,
    p.codigo_respuesta,
    p.numero_recibo,
    p.numero_autorizacion,
    p.referencia,
    p.numero_orden,
    CURRENT_TIMESTAMP AS fecha_actualizacion
FROM bronze_guajiranet.trpagodigital p
LEFT JOIN bronze_guajiranet.trfacturas f
       ON p.idsuc = f.idsuc
      AND p.prefijo = f.prefijo
      AND p.numero = f.numero
LEFT JOIN silver_guajiranet.tbl_dim_sucursal suc
       ON f.nit = suc.nit
      AND f.sucursal = suc.idsuc
LEFT JOIN silver_guajiranet.tbl_dim_persona per
       ON f.nit = per.nit
LEFT JOIN silver_guajiranet.tbl_dim_tiempo tm
       ON CAST(p.foperacion AS date) = tm.fecha"""


def cols(*names: str, dates: dict[str, str] | None = None) -> list[tuple[str, str]]:
    dates = dates or {}
    return [(n, dates.get(n, "")) for n in names]


files: dict[str, str] = {}

files["dim_persona.hpl"] = pipeline_string_ops(
    "dim_persona",
    SQL_PERSONA,
    "stg_dim_persona",
    cols(
        "nit", "dv", "razonsocial", "documento_identidad", "tipo_persona",
        "es_cliente", "es_proveedor", "tdoc", "idcliente", "fecha_creacion",
        "fecha_actualizacion",
        dates={"fecha_creacion": "DATE"},
    ),
    [
        ("razonsocial", "both", "none"),
        ("dv", "both", "none"),
        ("tipo_persona", "both", "upper"),
        ("es_cliente", "both", "upper"),
        ("es_proveedor", "both", "upper"),
        ("idcliente", "both", "none"),
    ],
)

files["dim_sucursal.hpl"] = pipeline_string_ops(
    "dim_sucursal",
    SQL_SUCURSAL,
    "stg_dim_sucursal",
    cols(
        "nit", "idsuc", "sk_persona", "sk_geografia", "sk_perfil_cartera",
        "razonsocial_suc", "direccion", "direccion2", "dpto", "mun", "ciudad",
        "email", "emailfe", "telefono1", "movil", "contacto1", "activo",
        "estrato", "coordenada", "finiciopermanencia", "fecharetiroisp",
        "idperfilcartera", "idperfilcartera_anterior", "fecha_actualizacion",
        dates={"finiciopermanencia": "DATE", "fecharetiroisp": "DATE"},
    ),
    [
        ("razonsocial_suc", "both", "none"),
        ("direccion", "both", "none"),
        ("direccion2", "both", "none"),
        ("ciudad", "both", "upper"),
        ("email", "both", "lower"),
        ("emailfe", "both", "lower"),
        ("contacto1", "both", "none"),
        ("activo", "both", "upper"),
        ("estrato", "both", "none"),
        ("coordenada", "both", "none"),
    ],
)

files["dim_contrato.hpl"] = pipeline_string_ops(
    "dim_contrato",
    SQL_CONTRATO,
    "stg_dim_contrato",
    cols(
        "idcontrato", "idcliente", "public_id", "state", "start_date",
        "created_at", "updated_at", "address_street", "address_city",
        "address_state", "address_country", "address_number", "latitude",
        "longitude", "ont_id", "ont_number", "ont_serial_number", "olt_id",
        "interface_gpon", "mac_address", "plan_id", "fecha_actualizacion",
        dates={
            "start_date": "TIMESTAMP",
            "created_at": "TIMESTAMP",
            "updated_at": "TIMESTAMP",
        },
    ),
    [
        ("idcontrato", "both", "none"),
        ("idcliente", "both", "none"),
        ("state", "both", "none"),
        ("address_street", "both", "none"),
        ("address_city", "both", "upper"),
        ("address_state", "both", "upper"),
        ("address_country", "both", "upper"),
        ("plan_id", "both", "none"),
        ("mac_address", "both", "upper"),
    ],
)

files["dim_plan.hpl"] = pipeline_string_ops(
    "dim_plan",
    SQL_PLAN,
    "stg_dim_plan",
    cols(
        "id_plan", "tipo", "nombre", "public_id", "ceil_down_kbps",
        "ceil_up_kbps", "cir", "precio", "frequency_in_months",
        "contracts_count", "created_at", "updated_at", "fecha_actualizacion",
        dates={"created_at": "TIMESTAMP", "updated_at": "TIMESTAMP"},
    ),
    [
        ("id_plan", "both", "none"),
        ("tipo", "both", "upper"),
        ("nombre", "both", "none"),
        ("cir", "both", "none"),
    ],
)

files["dim_producto_erp.hpl"] = pipeline_string_ops(
    "dim_producto_erp",
    SQL_PRODUCTO,
    "stg_dim_producto_erp",
    cols(
        "id_producto", "nombre_producto", "id_familia", "categoria",
        "tarifa_lista", "estado_activo", "fecha_actualizacion",
    ),
    [
        ("id_producto", "both", "none"),
        ("nombre_producto", "both", "none"),
        ("categoria", "both", "upper"),
        ("estado_activo", "both", "upper"),
    ],
)

files["dim_perfil_cartera.hpl"] = pipeline_string_ops(
    "dim_perfil_cartera",
    SQL_PERFIL,
    "stg_dim_perfil_cartera",
    cols(
        "id_perfil", "denominacion", "diasvence1", "diasvence2",
        "deshabilitar", "alertar", "diasvencefactura", "nofactura",
        "fecha_actualizacion",
    ),
    [
        ("denominacion", "both", "none"),
        ("deshabilitar", "both", "upper"),
        ("alertar", "both", "upper"),
    ],
)

files["brg_persona_uuid.hpl"] = pipeline_string_ops(
    "brg_persona_uuid",
    SQL_BRG_UUID,
    "stg_brg_persona_uuid",
    cols(
        "idcliente", "nit", "sk_persona", "en_materceros", "en_tmjsonclient",
        "fecha_actualizacion",
    ),
    [("idcliente", "both", "none")],
)

files["brg_sucursal_contrato.hpl"] = pipeline_string_ops(
    "brg_sucursal_contrato",
    SQL_BRG_SUC_CON,
    "stg_brg_sucursal_contrato",
    cols(
        "sk_sucursal", "sk_contrato", "nit", "idsuc", "idcontrato",
        "match_json", "fecha_actualizacion",
    ),
    [("idcontrato", "both", "none")],
)

files["brg_contrato_plan.hpl"] = pipeline_string_ops(
    "brg_contrato_plan",
    SQL_BRG_CON_PLAN,
    "stg_brg_contrato_plan",
    cols(
        "sk_contrato", "sk_plan", "idcontrato", "id_plan", "fecha_actualizacion",
    ),
    [
        ("idcontrato", "both", "none"),
        ("id_plan", "both", "none"),
    ],
)

fact_fact_cols = [
    "idsuc", "prefijo", "numero", "pos", "sk_sucursal", "sk_persona",
    "sk_producto", "sk_documento", "sk_geografia", "sk_tiempo", "sk_contrato",
    "sk_plan", "fecha_factura", "anulado", "cantidad", "precio", "subtotal",
    "iva", "neto", "fecha_actualizacion",
]
files["fact_facturacion_v2.hpl"] = pipeline_select(
    "fact_facturacion_v2",
    SQL_FACT_FACT,
    "stg_fact_facturacion",
    cols(*fact_fact_cols, dates={"fecha_factura": "DATE"}),
    fact_fact_cols,
)

fact_car_cols = [
    "idsuc", "prefijo", "numero", "cuenta", "nit", "sucursal", "ref_doc",
    "ref_num", "sk_sucursal", "sk_persona", "sk_tiempo", "sk_perfil_cartera",
    "plazo", "fecha", "fecha_vencimiento", "dias", "saldo", "debito", "credito",
    "rango1", "rango2", "rango3", "rango4", "rango5", "rango6", "interes",
    "idformapago", "transaccion", "fecha_actualizacion",
]
files["fact_cartera_v2.hpl"] = pipeline_select(
    "fact_cartera_v2",
    SQL_FACT_CARTERA,
    "stg_fact_cartera",
    cols(*fact_car_cols, dates={"fecha": "DATE", "fecha_vencimiento": "DATE"}),
    fact_car_cols,
)

pago_apl_cols = [
    "idsuc", "prefijo", "numero", "rc_idsuc", "rc_prefijo", "rc_numero",
    "sk_sucursal", "sk_persona", "sk_documento", "sk_tiempo_factura",
    "sk_tiempo_recibo", "carteraaplicado", "pagorc", "idformapago", "ccosto",
    "fecha_actualizacion",
]
files["fact_pago_aplicacion.hpl"] = pipeline_select(
    "fact_pago_aplicacion",
    SQL_PAGO_APL,
    "stg_fact_pago_aplicacion",
    cols(*pago_apl_cols),
    pago_apl_cols,
)

pago_pas_cols = [
    "id_pago_digital", "idsuc", "prefijo", "numero", "rec_idsuc", "rec_prefijo",
    "rec_numero", "sk_sucursal", "sk_persona", "sk_tiempo", "foperacion",
    "total", "codigo_respuesta", "numero_recibo", "numero_autorizacion",
    "referencia", "numero_orden", "fecha_actualizacion",
]
files["fact_pago_pasarela.hpl"] = pipeline_select(
    "fact_pago_pasarela",
    SQL_PAGO_PAS,
    "stg_fact_pago_pasarela",
    cols(*pago_pas_cols, dates={"foperacion": "TIMESTAMP"}),
    pago_pas_cols,
)

for fname, xml in files.items():
    path = OUT / fname
    path.write_text(xml, encoding="utf-8", newline="\n")
    print(f"wrote {path}")

print(f"total {len(files)}")

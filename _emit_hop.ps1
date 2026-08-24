# Regenerates Fase 2 HPL (except dim_geografia_v2) and Fase 3 HWF without Python.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$py2 = Get-Content -LiteralPath (Join-Path $root "_gen_phase2_hpl.py") -Raw -Encoding UTF8
$pipeDir = Join-Path $root "Pipelines"
$wfDir = Join-Path $root "Workflows"
New-Item -ItemType Directory -Force -Path $pipeDir, $wfDir | Out-Null

function Escape-Xml([string]$s) {
    if ($null -eq $s) { return "" }
    return ($s -replace "&", "&amp;" -replace "<", "&lt;" -replace ">", "&gt;")
}

function Get-PyTriple([string]$src, [string]$name) {
    $m = [regex]::Match($src, [regex]::Escape($name) + ' = """(.*?)"""', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $m.Success) { throw "SQL block $name not found" }
    return $m.Groups[1].Value.Trim("`r","`n")
}

function So-Field([string]$name, [string]$trim, [string]$case) {
    return @"
      <field>
        <in_stream_name>$(Escape-Xml $name)</in_stream_name>
        <out_stream_name/>
        <trim_type>$trim</trim_type>
        <lower_upper>$case</lower_upper>
        <padding_type>none</padding_type>
        <pad_char/>
        <pad_len/>
        <init_cap>no</init_cap>
        <mask_xml>none</mask_xml>
        <digits>none</digits>
        <remove_special_characters>none</remove_special_characters>
      </field>
"@
}

function Mapping-Field([string]$name, [string]$dateMask) {
    return @"
    <mapping>
      <date_mask>$dateMask</date_mask>
      <field_name>$(Escape-Xml $name)</field_name>
      <stream_name>$(Escape-Xml $name)</stream_name>
    </mapping>
"@
}

function Select-Field([string]$name) {
    return @"
      <field>
        <name>$(Escape-Xml $name)</name>
        <rename/>
        <length>-2</length>
        <precision>-2</precision>
      </field>
"@
}

function Wrap-Pipeline([string]$name, [string]$hops, [string]$transforms) {
    return @"
<?xml version="1.0" encoding="UTF-8"?>
<pipeline>
  <info>
    <name>$(Escape-Xml $name)</name>
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
$hops
  </order>
$transforms
  <transform_error_handling>
  </transform_error_handling>
  <attributes/>
</pipeline>
"@
}

function Table-Input([string]$sql, [int]$x = 336, [int]$y = 240) {
    return @"
  <transform>
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
    <sql>$(Escape-Xml $sql)</sql>
    <variables_active>N</variables_active>
    <attributes/>
    <GUI>
      <xloc>$x</xloc>
      <yloc>$y</yloc>
    </GUI>
  </transform>
"@
}

function String-Ops([string]$fields) {
    return @"
  <transform>
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
$fields
    </fields>
    <attributes/>
    <GUI>
      <xloc>544</xloc>
      <yloc>240</yloc>
    </GUI>
  </transform>
"@
}

function Select-Values([string]$fields) {
    return @"
  <transform>
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
$fields
      <select_unspecified>N</select_unspecified>
    </fields>
    <attributes/>
    <GUI>
      <xloc>432</xloc>
      <yloc>256</yloc>
    </GUI>
  </transform>
"@
}

function Bulk-Loader([string]$table, [string]$maps, [int]$x, [int]$y) {
    return @"
  <transform>
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
$maps
    <schema>silver_guajiranet</schema>
    <stop_on_error>N</stop_on_error>
    <table>$(Escape-Xml $table)</table>
    <attributes/>
    <GUI>
      <xloc>$x</xloc>
      <yloc>$y</yloc>
    </GUI>
  </transform>
"@
}

function Pipeline-StringOps($name, $sql, $table, $mappings, $stringOps) {
    $hops = @"
    <hop>
      <from>Table input</from>
      <to>String operations</to>
      <enabled>Y</enabled>
    </hop>
    <hop>
      <from>String operations</from>
      <to>PostgreSQL Bulk Loader</to>
      <enabled>Y</enabled>
    </hop>
"@
    $so = ($stringOps | ForEach-Object { So-Field $_.n $_.t $_.c }) -join "`n"
    $maps = ($mappings | ForEach-Object { Mapping-Field $_[0] $_[1] }) -join "`n"
    return (Wrap-Pipeline $name $hops ((Table-Input $sql) + (String-Ops $so) + (Bulk-Loader $table $maps 832 240)))
}

function Pipeline-Select($name, $sql, $table, $mappings, $selectNames) {
    $hops = @"
    <hop>
      <from>Table input</from>
      <to>Select values</to>
      <enabled>Y</enabled>
    </hop>
    <hop>
      <from>Select values</from>
      <to>PostgreSQL Bulk Loader</to>
      <enabled>Y</enabled>
    </hop>
"@
    $fields = ($selectNames | ForEach-Object { Select-Field $_ }) -join "`n"
    $maps = ($mappings | ForEach-Object { Mapping-Field $_[0] $_[1] }) -join "`n"
    return (Wrap-Pipeline $name $hops ((Table-Input $sql 224 256) + (Select-Values $fields) + (Bulk-Loader $table $maps 688 256)))
}

function Cols([string[]]$names, $dates) {
    if (-not $dates) { $dates = @{} }
    return @($names | ForEach-Object {
        $mask = ""
        if ($dates.ContainsKey($_)) { $mask = $dates[$_] }
        ,@($_, $mask)
    })
}

function Write-Utf8NoBom([string]$path, [string]$text) {
    $enc = New-Object System.Text.UTF8Encoding $false
    $norm = $text -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($path, $norm, $enc)
}

$SQL_PERSONA = Get-PyTriple $py2 "SQL_PERSONA"
$SQL_SUCURSAL = Get-PyTriple $py2 "SQL_SUCURSAL"
$SQL_CONTRATO = Get-PyTriple $py2 "SQL_CONTRATO"
$SQL_PLAN = Get-PyTriple $py2 "SQL_PLAN"
$SQL_PRODUCTO = Get-PyTriple $py2 "SQL_PRODUCTO"
$SQL_PERFIL = Get-PyTriple $py2 "SQL_PERFIL"
$SQL_BRG_UUID = Get-PyTriple $py2 "SQL_BRG_UUID"
$SQL_BRG_SUC_CON = Get-PyTriple $py2 "SQL_BRG_SUC_CON"
$SQL_BRG_CON_PLAN = Get-PyTriple $py2 "SQL_BRG_CON_PLAN"
$SQL_FACT_FACT = Get-PyTriple $py2 "SQL_FACT_FACT"
$SQL_FACT_CARTERA = Get-PyTriple $py2 "SQL_FACT_CARTERA"
$SQL_PAGO_APL = Get-PyTriple $py2 "SQL_PAGO_APL"
$SQL_PAGO_PAS = Get-PyTriple $py2 "SQL_PAGO_PAS"

function Op($n,$t,$c) { return @{ n = $n; t = $t; c = $c } }

$hpl = @{}
$hpl["dim_persona.hpl"] = Pipeline-StringOps "dim_persona" $SQL_PERSONA "stg_dim_persona" `
    (Cols @("nit","dv","razonsocial","documento_identidad","tipo_persona","es_cliente","es_proveedor","tdoc","idcliente","fecha_creacion","fecha_actualizacion") @{ fecha_creacion = "DATE" }) `
    @((Op "razonsocial" "both" "none"), (Op "dv" "both" "none"), (Op "tipo_persona" "both" "upper"), (Op "es_cliente" "both" "upper"), (Op "es_proveedor" "both" "upper"), (Op "idcliente" "both" "none"))

$hpl["dim_sucursal.hpl"] = Pipeline-StringOps "dim_sucursal" $SQL_SUCURSAL "stg_dim_sucursal" `
    (Cols @("nit","idsuc","sk_persona","sk_geografia","sk_perfil_cartera","razonsocial_suc","direccion","direccion2","dpto","mun","ciudad","email","emailfe","telefono1","movil","contacto1","activo","estrato","coordenada","finiciopermanencia","fecharetiroisp","idperfilcartera","idperfilcartera_anterior","fecha_actualizacion") @{ finiciopermanencia = "DATE"; fecharetiroisp = "DATE" }) `
    @((Op "razonsocial_suc" "both" "none"), (Op "direccion" "both" "none"), (Op "direccion2" "both" "none"), (Op "ciudad" "both" "upper"), (Op "email" "both" "lower"), (Op "emailfe" "both" "lower"), (Op "contacto1" "both" "none"), (Op "activo" "both" "upper"), (Op "estrato" "both" "none"), (Op "coordenada" "both" "none"))

$hpl["dim_contrato.hpl"] = Pipeline-StringOps "dim_contrato" $SQL_CONTRATO "stg_dim_contrato" `
    (Cols @("idcontrato","idcliente","public_id","state","start_date","created_at","updated_at","address_street","address_city","address_state","address_country","address_number","latitude","longitude","ont_id","ont_number","ont_serial_number","olt_id","interface_gpon","mac_address","plan_id","fecha_actualizacion") @{ start_date = "TIMESTAMP"; created_at = "TIMESTAMP"; updated_at = "TIMESTAMP" }) `
    @((Op "idcontrato" "both" "none"), (Op "idcliente" "both" "none"), (Op "state" "both" "none"), (Op "address_street" "both" "none"), (Op "address_city" "both" "upper"), (Op "address_state" "both" "upper"), (Op "address_country" "both" "upper"), (Op "plan_id" "both" "none"), (Op "mac_address" "both" "upper"))

$hpl["dim_plan.hpl"] = Pipeline-StringOps "dim_plan" $SQL_PLAN "stg_dim_plan" `
    (Cols @("id_plan","tipo","nombre","public_id","ceil_down_kbps","ceil_up_kbps","cir","precio","frequency_in_months","contracts_count","created_at","updated_at","fecha_actualizacion") @{ created_at = "TIMESTAMP"; updated_at = "TIMESTAMP" }) `
    @((Op "id_plan" "both" "none"), (Op "tipo" "both" "upper"), (Op "nombre" "both" "none"), (Op "cir" "both" "none"))

$hpl["dim_producto_erp.hpl"] = Pipeline-StringOps "dim_producto_erp" $SQL_PRODUCTO "stg_dim_producto_erp" `
    (Cols @("id_producto","nombre_producto","id_familia","categoria","tarifa_lista","estado_activo","fecha_actualizacion") @{}) `
    @((Op "id_producto" "both" "none"), (Op "nombre_producto" "both" "none"), (Op "categoria" "both" "upper"), (Op "estado_activo" "both" "upper"))

$hpl["dim_perfil_cartera.hpl"] = Pipeline-StringOps "dim_perfil_cartera" $SQL_PERFIL "stg_dim_perfil_cartera" `
    (Cols @("id_perfil","denominacion","diasvence1","diasvence2","deshabilitar","alertar","diasvencefactura","nofactura","fecha_actualizacion") @{}) `
    @((Op "denominacion" "both" "none"), (Op "deshabilitar" "both" "upper"), (Op "alertar" "both" "upper"))

$hpl["brg_persona_uuid.hpl"] = Pipeline-StringOps "brg_persona_uuid" $SQL_BRG_UUID "stg_brg_persona_uuid" `
    (Cols @("idcliente","nit","sk_persona","en_materceros","en_tmjsonclient","fecha_actualizacion") @{}) `
    @((Op "idcliente" "both" "none"))

$hpl["brg_sucursal_contrato.hpl"] = Pipeline-StringOps "brg_sucursal_contrato" $SQL_BRG_SUC_CON "stg_brg_sucursal_contrato" `
    (Cols @("sk_sucursal","sk_contrato","nit","idsuc","idcontrato","match_json","fecha_actualizacion") @{}) `
    @((Op "idcontrato" "both" "none"))

$hpl["brg_contrato_plan.hpl"] = Pipeline-StringOps "brg_contrato_plan" $SQL_BRG_CON_PLAN "stg_brg_contrato_plan" `
    (Cols @("sk_contrato","sk_plan","idcontrato","id_plan","fecha_actualizacion") @{}) `
    @((Op "idcontrato" "both" "none"), (Op "id_plan" "both" "none"))

$fact_fact_cols = @("idsuc","prefijo","numero","pos","sk_sucursal","sk_persona","sk_producto","sk_documento","sk_geografia","sk_tiempo","sk_contrato","sk_plan","fecha_factura","anulado","cantidad","precio","subtotal","iva","neto","fecha_actualizacion")
$hpl["fact_facturacion_v2.hpl"] = Pipeline-Select "fact_facturacion_v2" $SQL_FACT_FACT "stg_fact_facturacion" (Cols $fact_fact_cols @{ fecha_factura = "DATE" }) $fact_fact_cols

$fact_car_cols = @("idsuc","prefijo","numero","cuenta","nit","sucursal","ref_doc","ref_num","sk_sucursal","sk_persona","sk_tiempo","sk_perfil_cartera","plazo","fecha","fecha_vencimiento","dias","saldo","debito","credito","rango1","rango2","rango3","rango4","rango5","rango6","interes","idformapago","transaccion","fecha_actualizacion")
$hpl["fact_cartera_v2.hpl"] = Pipeline-Select "fact_cartera_v2" $SQL_FACT_CARTERA "stg_fact_cartera" (Cols $fact_car_cols @{ fecha = "DATE"; fecha_vencimiento = "DATE" }) $fact_car_cols

$pago_apl_cols = @("idsuc","prefijo","numero","rc_idsuc","rc_prefijo","rc_numero","sk_sucursal","sk_persona","sk_documento","sk_tiempo_factura","sk_tiempo_recibo","carteraaplicado","pagorc","idformapago","ccosto","fecha_actualizacion")
$hpl["fact_pago_aplicacion.hpl"] = Pipeline-Select "fact_pago_aplicacion" $SQL_PAGO_APL "stg_fact_pago_aplicacion" (Cols $pago_apl_cols @{}) $pago_apl_cols

$pago_pas_cols = @("id_pago_digital","idsuc","prefijo","numero","rec_idsuc","rec_prefijo","rec_numero","sk_sucursal","sk_persona","sk_tiempo","foperacion","total","codigo_respuesta","numero_recibo","numero_autorizacion","referencia","numero_orden","fecha_actualizacion")
$hpl["fact_pago_pasarela.hpl"] = Pipeline-Select "fact_pago_pasarela" $SQL_PAGO_PAS "stg_fact_pago_pasarela" (Cols $pago_pas_cols @{ foperacion = "TIMESTAMP" }) $pago_pas_cols

foreach ($k in $hpl.Keys) {
    Write-Utf8NoBom (Join-Path $pipeDir $k) $hpl[$k]
    Write-Output "wrote Pipelines\$k"
}

function Conflict-Cols([string]$conflict) {
    $names = New-Object System.Collections.Generic.HashSet[string]
    $depth = 0
    $cur = New-Object System.Text.StringBuilder
    foreach ($ch in $conflict.ToCharArray()) {
        if ($ch -eq [char]'(') { $depth++; [void]$cur.Append($ch) }
        elseif ($ch -eq [char]')') { $depth--; [void]$cur.Append($ch) }
        elseif ($ch -eq [char]',' -and $depth -eq 0) {
            $p = $cur.ToString().Trim()
            if ($p -match "nit") { [void]$names.Add("nit") }
            elseif ($p -notmatch "^\(" -and $p -notmatch "COALESCE") { [void]$names.Add($p) }
            $cur.Clear() | Out-Null
        }
        else { [void]$cur.Append($ch) }
    }
    $p = $cur.ToString().Trim()
    if ($p) {
        if ($p -match "COALESCE" -or $p.StartsWith("(")) {
            if ($p -match "nit") { [void]$names.Add("nit") }
        } else { [void]$names.Add($p) }
    }
    return $names
}

function Upsert-Sql([string]$table, [string[]]$cols, [string]$conflict, [string]$distinctOn, [string]$prefix = "") {
    $colList = $cols -join ",`n    "
    $stg = "stg_" + $table.Substring(4)
    $skip = Conflict-Cols $conflict
    $updates = @($cols | Where-Object { -not $skip.Contains($_) })
    $setList = ($updates | ForEach-Object {
        if ($_ -eq "fecha_actualizacion") { "fecha_actualizacion = CURRENT_TIMESTAMP" }
        else { "$_ = EXCLUDED.$_" }
    }) -join ",`n    "
    $distinct = ""
    $order = ""
    if ($distinctOn) {
        $distinct = " DISTINCT ON ($distinctOn)`n    "
        $order = "`nORDER BY $distinctOn"
    }
    return ($prefix + @"
INSERT INTO silver_guajiranet.$table
(
    $colList
)
SELECT$distinct
    $colList
FROM silver_guajiranet.$stg$order

ON CONFLICT ($conflict)
DO UPDATE SET
    $setList;
"@)
}

function Unit-Hwf([string]$wfName, [string]$pipeline, [string]$sql) {
    $sqlEsc = Escape-Xml $sql
    $wfEsc = Escape-Xml $wfName
    $pEsc = Escape-Xml $pipeline
    return @"
<?xml version="1.0" encoding="UTF-8"?>
<workflow>
  <name>$wfEsc</name>
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
      <name>$pEsc</name>
      <description/>
      <type>PIPELINE</type>
      <attributes/>
      <add_date>N</add_date>
      <add_time>N</add_time>
      <clear_files>N</clear_files>
      <clear_rows>N</clear_rows>
      <create_parent_folder>N</create_parent_folder>
      <exec_per_row>N</exec_per_row>
      <filename>`${PROJECT_HOME}/Pipelines/$pEsc</filename>
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
      <sql>$sqlEsc</sql>
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
      <message>Fallo ${wfEsc}: pipeline o UPSERT no termino correctamente</message>
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
      <to>$pEsc</to>
      <enabled>Y</enabled>
      <evaluation>Y</evaluation>
      <unconditional>Y</unconditional>
    </hop>
    <hop>
      <from>$pEsc</from>
      <to>SQL</to>
      <enabled>Y</enabled>
      <evaluation>Y</evaluation>
      <unconditional>N</unconditional>
    </hop>
    <hop>
      <from>$pEsc</from>
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
"@
}

function Wf-Action([string]$name, [int]$x, [int]$y) {
    $n = Escape-Xml $name
    return @"
    <action>
      <filename>`${PROJECT_HOME}/Workflows/$n</filename>
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
      <name>$n</name>
      <type>WORKFLOW</type>
      <attributes/>
      <xloc>$x</xloc>
      <yloc>$y</yloc>
      <parallel>N</parallel>
      <attributes_hac/>
    </action>
"@
}

function Wf-Hop([string]$from, [string]$to, [bool]$enabled, [bool]$uncond) {
    $en = $(if ($enabled) { "Y" } else { "N" })
    $un = $(if ($uncond) { "Y" } else { "N" })
    return @"
    <hop>
      <from>$(Escape-Xml $from)</from>
      <to>$(Escape-Xml $to)</to>
      <evaluation>Y</evaluation>
      <unconditional>$un</unconditional>
      <enabled>$en</enabled>
    </hop>
"@
}

$C_PERSONA = @("nit","dv","razonsocial","documento_identidad","tipo_persona","es_cliente","es_proveedor","tdoc","idcliente","fecha_creacion","fecha_actualizacion")
$C_SUCURSAL = @("nit","idsuc","sk_persona","sk_geografia","sk_perfil_cartera","razonsocial_suc","direccion","direccion2","dpto","mun","ciudad","email","emailfe","telefono1","movil","contacto1","activo","estrato","coordenada","finiciopermanencia","fecharetiroisp","idperfilcartera","idperfilcartera_anterior","fecha_actualizacion")
$C_CONTRATO = @("idcontrato","idcliente","public_id","state","start_date","created_at","updated_at","address_street","address_city","address_state","address_country","address_number","latitude","longitude","ont_id","ont_number","ont_serial_number","olt_id","interface_gpon","mac_address","plan_id","fecha_actualizacion")
$C_PLAN = @("id_plan","tipo","nombre","public_id","ceil_down_kbps","ceil_up_kbps","cir","precio","frequency_in_months","contracts_count","created_at","updated_at","fecha_actualizacion")
$C_PRODUCTO = @("id_producto","nombre_producto","id_familia","categoria","tarifa_lista","estado_activo","fecha_actualizacion")
$C_PERFIL = @("id_perfil","denominacion","diasvence1","diasvence2","deshabilitar","alertar","diasvencefactura","nofactura","fecha_actualizacion")
$C_GEO = @("id_barrio","barrio","dpto","mun","municipio","departamento","fecha_actualizacion")
$C_BRG_UUID = @("idcliente","nit","sk_persona","en_materceros","en_tmjsonclient","fecha_actualizacion")
$C_BRG_SC = @("sk_sucursal","sk_contrato","nit","idsuc","idcontrato","match_json","fecha_actualizacion")
$C_BRG_CP = @("sk_contrato","sk_plan","idcontrato","id_plan","fecha_actualizacion")
$C_FACT_F = $fact_fact_cols
$C_FACT_C = $fact_car_cols
$C_PAGO_A = $pago_apl_cols
$C_PAGO_P = $pago_pas_cols

$DELETE_CARTERA = @"
DELETE FROM silver_guajiranet.tbl_fact_cartera AS t
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

"@

$units = [ordered]@{
    "wf_dim_perfil_cartera.hwf" = @("wf_dim_perfil_cartera","dim_perfil_cartera.hpl", (Upsert-Sql "tbl_dim_perfil_cartera" $C_PERFIL "id_perfil" "id_perfil"))
    "wf_dim_persona.hwf" = @("wf_dim_persona","dim_persona.hpl", (Upsert-Sql "tbl_dim_persona" $C_PERSONA "nit" "nit"))
    "wf_brg_persona_uuid.hwf" = @("wf_brg_persona_uuid","brg_persona_uuid.hpl", (Upsert-Sql "tbl_brg_persona_uuid" $C_BRG_UUID "idcliente, (COALESCE(nit, -1))" "idcliente, COALESCE(nit, -1)"))
    "wf_dim_plan.hwf" = @("wf_dim_plan","dim_plan.hpl", (Upsert-Sql "tbl_dim_plan" $C_PLAN "id_plan" "id_plan"))
    "wf_dim_contrato.hwf" = @("wf_dim_contrato","dim_contrato.hpl", (Upsert-Sql "tbl_dim_contrato" $C_CONTRATO "idcontrato" "idcontrato"))
    "wf_dim_geografia_v2.hwf" = @("wf_dim_geografia_v2","dim_geografia_v2.hpl", (Upsert-Sql "tbl_dim_geografia" $C_GEO "id_barrio" "id_barrio"))
    "wf_dim_sucursal.hwf" = @("wf_dim_sucursal","dim_sucursal.hpl", (Upsert-Sql "tbl_dim_sucursal" $C_SUCURSAL "nit, idsuc" "nit, idsuc"))
    "wf_dim_producto_erp.hwf" = @("wf_dim_producto_erp","dim_producto_erp.hpl", (Upsert-Sql "tbl_dim_producto_erp" $C_PRODUCTO "id_producto" "id_producto"))
    "wf_brg_sucursal_contrato.hwf" = @("wf_brg_sucursal_contrato","brg_sucursal_contrato.hpl", (Upsert-Sql "tbl_brg_sucursal_contrato" $C_BRG_SC "nit, idsuc, idcontrato" "nit, idsuc, idcontrato"))
    "wf_brg_contrato_plan.hwf" = @("wf_brg_contrato_plan","brg_contrato_plan.hpl", (Upsert-Sql "tbl_brg_contrato_plan" $C_BRG_CP "idcontrato" "idcontrato"))
    "wf_fact_pago_aplicacion.hwf" = @("wf_fact_pago_aplicacion","fact_pago_aplicacion.hpl", (Upsert-Sql "tbl_fact_pago_aplicacion" $C_PAGO_A "idsuc, prefijo, numero, rc_idsuc, rc_prefijo, rc_numero" "idsuc, prefijo, numero, rc_idsuc, rc_prefijo, rc_numero"))
    "wf_fact_pago_pasarela.hwf" = @("wf_fact_pago_pasarela","fact_pago_pasarela.hpl", (Upsert-Sql "tbl_fact_pago_pasarela" $C_PAGO_P "id_pago_digital" "id_pago_digital"))
    "wf_fact_facturacion_v2.hwf" = @("wf_fact_facturacion_v2","fact_facturacion_v2.hpl", (Upsert-Sql "tbl_fact_facturacion" $C_FACT_F "idsuc, prefijo, numero, pos" "idsuc, prefijo, numero, pos"))
    "wf_fact_cartera_v2.hwf" = @("wf_fact_cartera_v2","fact_cartera_v2.hpl", (Upsert-Sql "tbl_fact_cartera" $C_FACT_C "idsuc, prefijo, numero, cuenta, nit, sucursal, ref_doc, ref_num" "idsuc, prefijo, numero, cuenta, nit, sucursal, ref_doc, ref_num" $DELETE_CARTERA))
}

foreach ($fname in $units.Keys) {
    $u = $units[$fname]
    Write-Utf8NoBom (Join-Path $wfDir $fname) (Unit-Hwf $u[0] $u[1] $u[2])
    Write-Output "wrote Workflows\$fname"
}

$chain_live = @(
    "wf_dim_tiempo.hwf","wf_dim_documento.hwf","wf_dim_perfil_cartera.hwf","wf_dim_persona.hwf",
    "wf_brg_persona_uuid.hwf","wf_dim_plan.hwf","wf_dim_contrato.hwf","wf_dim_sucursal.hwf",
    "wf_dim_producto_erp.hwf","wf_brg_sucursal_contrato.hwf","wf_brg_contrato_plan.hwf",
    "wf_fact_pago_aplicacion.hwf","wf_fact_pago_pasarela.hwf"
)
$geo_blocked = "wf_dim_geografia_v2.hwf"
$blocked = @("wf_fact_facturacion_v2.hwf","wf_fact_cartera_v2.hwf")

$actions = New-Object System.Collections.Generic.List[string]
[void]$actions.Add(@"
    <action>
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
"@)
$x = 200
$graph = $chain_live[0..6] + @($geo_blocked) + $chain_live[7..($chain_live.Length-1)] + $blocked
foreach ($name in $graph) {
    $y = 160
    if ($name -eq $geo_blocked) { $y = 48 }
    elseif ($blocked -contains $name) { $y = 320 }
    [void]$actions.Add((Wf-Action $name $x $y))
    if ($name -ne $geo_blocked) { $x += 180 }
}
[void]$actions.Add(@"
    <action>
      <name>Success</name>
      <description/>
      <type>SUCCESS</type>
      <attributes/>
      <xloc>2720</xloc>
      <yloc>160</yloc>
      <parallel>N</parallel>
      <attributes_hac/>
    </action>
"@)

$hops = New-Object System.Collections.Generic.List[string]
[void]$hops.Add((Wf-Hop "Start" $chain_live[0] $true $true))
for ($i = 0; $i -lt $chain_live.Length - 1; $i++) {
    [void]$hops.Add((Wf-Hop $chain_live[$i] $chain_live[$i+1] $true $false))
}
[void]$hops.Add((Wf-Hop $chain_live[-1] "Success" $true $false))
[void]$hops.Add((Wf-Hop "wf_dim_contrato.hwf" $geo_blocked $false $false))
[void]$hops.Add((Wf-Hop $geo_blocked "wf_dim_sucursal.hwf" $false $false))
[void]$hops.Add((Wf-Hop $chain_live[-1] $blocked[0] $false $false))
[void]$hops.Add((Wf-Hop $blocked[0] $blocked[1] $false $false))
[void]$hops.Add((Wf-Hop $blocked[1] "Success" $false $false))

$orch = @"
<?xml version="1.0" encoding="UTF-8"?>
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
$($actions -join "")  </actions>
  <hops>
$($hops -join "")  </hops>
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
"@
Write-Utf8NoBom (Join-Path $wfDir "wf_actualizacion_silver_v2.hwf") $orch
Write-Output "wrote Workflows\wf_actualizacion_silver_v2.hwf"
Write-Output "done"

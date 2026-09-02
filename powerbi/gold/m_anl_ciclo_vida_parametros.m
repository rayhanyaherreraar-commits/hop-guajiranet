let
    Origen = PostgreSQL.Database("cluster-guajiranet-instance-1.cur2img2cxzx.us-east-1.rds.amazonaws.com:5432", "db_bronze"),
    Navigation = Origen{[Schema="gold_guajiranet",Item="vw_anl_ciclo_vida_parametros"]}[Data],
    #"Columnas seleccionadas" = Table.SelectColumns(Navigation,{
        "umbral_dias_inactividad",
        "umbral_meses_inactividad",
        "ventana_facturacion_cercana_meses",
        "umbral_dias_interrupcion_pago",
        "umbral_meses_interrupcion_pago",
        "as_of_facturacion",
        "as_of_pago",
        "estado_parametro"
    }),
    #"Tipo cambiado" = Table.TransformColumnTypes(#"Columnas seleccionadas",{
        {"umbral_dias_inactividad", Int64.Type},
        {"umbral_meses_inactividad", Int64.Type},
        {"ventana_facturacion_cercana_meses", Int64.Type},
        {"umbral_dias_interrupcion_pago", Int64.Type},
        {"umbral_meses_interrupcion_pago", Int64.Type},
        {"as_of_facturacion", type date},
        {"as_of_pago", type date},
        {"estado_parametro", type text}
    })
in
    #"Tipo cambiado"

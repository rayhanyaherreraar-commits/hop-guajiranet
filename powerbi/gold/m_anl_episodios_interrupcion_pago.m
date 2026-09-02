let
    Origen = PostgreSQL.Database("cluster-guajiranet-instance-1.cur2img2cxzx.us-east-1.rds.amazonaws.com:5432", "db_bronze"),
    Navigation = Origen{[Schema="gold_guajiranet",Item="vw_anl_episodios_interrupcion_pago"]}[Data],
    #"Columnas seleccionadas" = Table.SelectColumns(Navigation,{
        "sk_cliente",
        "nit",
        "idsuc",
        "numero_episodio_pago",
        "tipo_episodio",
        "fecha_ultimo_pago_previo",
        "fecha_inicio_interrupcion_pago",
        "fecha_primer_pago_posterior",
        "fecha_fin_interrupcion_pago",
        "dias_sin_pago",
        "meses_sin_pago",
        "recupero_pago",
        "meses_hasta_recuperacion_pago",
        "ultima_fecha_factura",
        "pago_posterior_a_ultima_factura",
        "factura_cercana_al_pago_previo",
        "fecha_retiro_registrada",
        "estado_retiro_registrado",
        "motivo_inferido",
        "nivel_confianza"
    }),
    #"Tipo cambiado" = Table.TransformColumnTypes(#"Columnas seleccionadas",{
        {"sk_cliente", Int64.Type},
        {"nit", Int64.Type},
        {"idsuc", Int64.Type},
        {"numero_episodio_pago", Int64.Type},
        {"tipo_episodio", type text},
        {"fecha_ultimo_pago_previo", type date},
        {"fecha_inicio_interrupcion_pago", type date},
        {"fecha_primer_pago_posterior", type date},
        {"fecha_fin_interrupcion_pago", type date},
        {"dias_sin_pago", Int64.Type},
        {"meses_sin_pago", type number},
        {"recupero_pago", type logical},
        {"meses_hasta_recuperacion_pago", type number},
        {"ultima_fecha_factura", type date},
        {"pago_posterior_a_ultima_factura", type logical},
        {"factura_cercana_al_pago_previo", type logical},
        {"fecha_retiro_registrada", type date},
        {"estado_retiro_registrado", type text},
        {"motivo_inferido", type text},
        {"nivel_confianza", type text}
    }),
    #"sk_cliente texto" = Table.TransformColumns(#"Tipo cambiado",{
        {"sk_cliente", each if _ = null then null else Text.From(_), type text}
    })
in
    #"sk_cliente texto"

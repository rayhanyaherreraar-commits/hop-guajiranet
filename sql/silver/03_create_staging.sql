-- =============================================================================
-- 03_create_staging.sql
-- Staging espejo: columnas de negocio, SIN SK (excepto KEEP stg_dim_tiempo).
-- Todo NULLABLE. Sin PK / UNIQUE / índices. Hop hace TRUNCATE cada carga.
-- No DROP de stg_dim_cliente / stg_dim_servicio.
-- =============================================================================

SET search_path TO silver_guajiranet, public;

-- -----------------------------------------------------------------------------
-- KEEP — stg_dim_tiempo (incluye sk_tiempo: smart key generada en Hop)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF to_regclass('silver_guajiranet.stg_dim_tiempo') IS NULL THEN
        RAISE EXCEPTION
            'BLOQUEO: silver_guajiranet.stg_dim_tiempo no existe. Es KEEP.';
    END IF;
END
$$;

-- -----------------------------------------------------------------------------
-- KEEP — stg_dim_documento
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF to_regclass('silver_guajiranet.stg_dim_documento') IS NULL THEN
        RAISE EXCEPTION
            'BLOQUEO: silver_guajiranet.stg_dim_documento no existe. Es KEEP.';
    END IF;
END
$$;

-- -----------------------------------------------------------------------------
-- stg_dim_geografia — REPLACE mismo nombre (id_barrio integer)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF to_regclass('silver_guajiranet.stg_dim_geografia') IS NULL THEN
        EXECUTE $ct$
            CREATE TABLE silver_guajiranet.stg_dim_geografia (
                id_barrio           integer,
                barrio              character varying(40),
                dpto                character varying(3),
                mun                 character varying(5),
                municipio           character varying(40),
                departamento        character varying(60),
                fecha_actualizacion timestamp without time zone
            );
        $ct$;
        RAISE NOTICE 'Creada stg_dim_geografia (modelo nuevo).';
    ELSIF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'silver_guajiranet'
          AND table_name = 'stg_dim_geografia'
          AND column_name = 'id_barrio'
          AND data_type = 'integer'
    ) THEN
        RAISE NOTICE 'stg_dim_geografia ya está en el modelo nuevo.';
    ELSE
        RAISE NOTICE
            'BLOQUEO: stg_dim_geografia existe con modelo viejo (id_barrio varchar). No se DROP. Cutover: 07, luego re-ejecutar 03.';
    END IF;
END
$$;

-- -----------------------------------------------------------------------------
-- CREATE — dims nuevas
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver_guajiranet.stg_dim_persona (
    nit                 integer,
    dv                  character(1),
    razonsocial         character varying(128),
    documento_identidad bigint,
    tipo_persona        character(1),
    es_cliente          character(1),
    es_proveedor        character(1),
    tdoc                smallint,
    idcliente           character varying(64),
    fecha_creacion      date,
    fecha_actualizacion timestamp without time zone
);

CREATE TABLE IF NOT EXISTS silver_guajiranet.stg_dim_sucursal (
    nit                         integer,
    idsuc                       smallint,
    sk_persona                  integer,
    sk_geografia                integer,
    sk_perfil_cartera           integer,
    razonsocial_suc             character varying(128),
    direccion                   character varying(128),
    direccion2                  character varying(128),
    dpto                        character varying(3),
    mun                         character varying(5),
    ciudad                      character varying(40),
    email                       character varying(128),
    emailfe                     character varying(128),
    telefono1                   character varying(20),
    movil                       character varying(20),
    contacto1                   character varying(40),
    activo                      character(1),
    estrato                     character varying(8),
    coordenada                  character varying(64),
    finiciopermanencia          date,
    fecharetiroisp              date,
    idperfilcartera             integer,
    idperfilcartera_anterior    integer,
    fecha_actualizacion         timestamp without time zone
);

CREATE TABLE IF NOT EXISTS silver_guajiranet.stg_dim_contrato (
    idcontrato          character varying(64),
    idcliente           character varying(64),
    public_id           integer,
    state               character varying(32),
    start_date          timestamp with time zone,
    created_at          timestamp with time zone,
    updated_at          timestamp with time zone,
    address_street      character varying(256),
    address_city        character varying(80),
    address_state       character varying(80),
    address_country     character varying(80),
    address_number      character varying(64),
    latitude            numeric(12, 8),
    longitude           numeric(12, 8),
    ont_id              character varying(64),
    ont_number          character varying(64),
    ont_serial_number   character varying(64),
    olt_id              character varying(64),
    interface_gpon      character varying(64),
    mac_address         character varying(32),
    plan_id             character varying(64),
    fecha_actualizacion timestamp without time zone
);

CREATE TABLE IF NOT EXISTS silver_guajiranet.stg_dim_plan (
    id_plan             character varying(64),
    tipo                character(1),
    nombre              character varying(256),
    public_id           integer,
    ceil_down_kbps      integer,
    ceil_up_kbps        integer,
    cir                 character varying(32),
    precio              numeric(18, 2),
    frequency_in_months integer,
    contracts_count     integer,
    created_at          timestamp with time zone,
    updated_at          timestamp with time zone,
    fecha_actualizacion timestamp without time zone
);

CREATE TABLE IF NOT EXISTS silver_guajiranet.stg_dim_producto_erp (
    id_producto         character varying(25),
    nombre_producto     character varying(128),
    id_familia          character varying(10),
    categoria           character varying(40),
    tarifa_lista        numeric(18, 2),
    estado_activo       character(1),
    fecha_actualizacion timestamp without time zone
);

CREATE TABLE IF NOT EXISTS silver_guajiranet.stg_dim_perfil_cartera (
    id_perfil           integer,
    denominacion        character varying(32),
    diasvence1          integer,
    diasvence2          integer,
    deshabilitar        character(1),
    alertar             character(1),
    diasvencefactura    integer,
    nofactura           boolean,
    fecha_actualizacion timestamp without time zone
);

-- -----------------------------------------------------------------------------
-- CREATE — bridges
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS silver_guajiranet.stg_brg_persona_uuid (
    idcliente           character varying(64),
    nit                 integer,
    sk_persona          integer,
    en_materceros       boolean,
    en_tmjsonclient     boolean,
    fecha_actualizacion timestamp without time zone
);

CREATE TABLE IF NOT EXISTS silver_guajiranet.stg_brg_sucursal_contrato (
    sk_sucursal         integer,
    sk_contrato         integer,
    nit                 integer,
    idsuc               smallint,
    idcontrato          character varying(64),
    match_json          boolean,
    fecha_actualizacion timestamp without time zone
);

CREATE TABLE IF NOT EXISTS silver_guajiranet.stg_brg_contrato_plan (
    sk_contrato         integer,
    sk_plan             integer,
    idcontrato          character varying(64),
    id_plan             character varying(64),
    fecha_actualizacion timestamp without time zone
);

-- -----------------------------------------------------------------------------
-- stg_fact_facturacion — REBUILD mismo nombre
-- Detector: columna pos (viejo: posicion_factura).
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF to_regclass('silver_guajiranet.stg_fact_facturacion') IS NULL THEN
        EXECUTE $ct$
            CREATE TABLE silver_guajiranet.stg_fact_facturacion (
                idsuc               smallint,
                prefijo             character varying(3),
                numero              integer,
                pos                 smallint,
                sk_sucursal         integer,
                sk_persona          integer,
                sk_producto         integer,
                sk_documento        integer,
                sk_geografia        integer,
                sk_tiempo           integer,
                sk_contrato         integer,
                sk_plan             integer,
                fecha_factura       date,
                anulado             character(1),
                cantidad            numeric(18, 2),
                precio              numeric(18, 2),
                subtotal            numeric(18, 2),
                iva                 numeric(18, 2),
                neto                numeric(18, 2),
                fecha_actualizacion timestamp without time zone
            );
        $ct$;
        RAISE NOTICE 'Creada stg_fact_facturacion (modelo nuevo).';
    ELSIF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'silver_guajiranet'
          AND table_name = 'stg_fact_facturacion'
          AND column_name = 'pos'
    ) THEN
        RAISE NOTICE 'stg_fact_facturacion ya está en el modelo nuevo.';
    ELSE
        RAISE NOTICE
            'BLOQUEO: stg_fact_facturacion existe con modelo viejo. No se DROP. Cutover: 07, luego re-ejecutar 03.';
    END IF;
END
$$;

-- -----------------------------------------------------------------------------
-- stg_fact_cartera — REPLACE mismo nombre
-- Detector: columna idsuc.
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF to_regclass('silver_guajiranet.stg_fact_cartera') IS NULL THEN
        EXECUTE $ct$
            CREATE TABLE silver_guajiranet.stg_fact_cartera (
                idsuc               smallint,
                prefijo             character varying(3),
                numero              integer,
                cuenta              integer,
                nit                 integer,
                sucursal            smallint,
                ref_doc             character varying(3),
                ref_num             character varying(15),
                sk_sucursal         integer,
                sk_persona          integer,
                sk_tiempo           integer,
                sk_perfil_cartera   integer,
                plazo               smallint,
                fecha               date,
                fecha_vencimiento   date,
                dias                integer,
                saldo               numeric(18, 2),
                debito              numeric(18, 2),
                credito             numeric(18, 2),
                rango1              numeric(18, 2),
                rango2              numeric(18, 2),
                rango3              numeric(18, 2),
                rango4              numeric(18, 2),
                rango5              numeric(18, 2),
                rango6              numeric(18, 2),
                interes             numeric(18, 2),
                idformapago         smallint,
                transaccion         character varying(128),
                fecha_actualizacion timestamp without time zone
            );
        $ct$;
        RAISE NOTICE 'Creada stg_fact_cartera (modelo nuevo).';
    ELSIF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'silver_guajiranet'
          AND table_name = 'stg_fact_cartera'
          AND column_name = 'idsuc'
    ) THEN
        RAISE NOTICE 'stg_fact_cartera ya está en el modelo nuevo.';
    ELSE
        RAISE NOTICE
            'BLOQUEO: stg_fact_cartera existe con modelo viejo. No se DROP. Cutover: 07, luego re-ejecutar 03.';
    END IF;
END
$$;

CREATE TABLE IF NOT EXISTS silver_guajiranet.stg_fact_pago_aplicacion (
    idsuc               smallint,
    prefijo             character varying(3),
    numero              integer,
    rc_idsuc            smallint,
    rc_prefijo          character varying(3),
    rc_numero           integer,
    sk_sucursal         integer,
    sk_persona          integer,
    sk_documento        integer,
    sk_tiempo_factura   integer,
    sk_tiempo_recibo    integer,
    carteraaplicado     numeric(18, 2),
    pagorc              numeric(18, 2),
    idformapago         smallint,
    ccosto              integer,
    fecha_actualizacion timestamp without time zone
);

CREATE TABLE IF NOT EXISTS silver_guajiranet.stg_fact_pago_pasarela (
    id_pago_digital     integer,
    idsuc               smallint,
    prefijo             character varying(3),
    numero              integer,
    rec_idsuc           smallint,
    rec_prefijo         character varying(3),
    rec_numero          integer,
    sk_sucursal         integer,
    sk_persona          integer,
    sk_tiempo           integer,
    foperacion          timestamp without time zone,
    total               numeric(18, 2),
    codigo_respuesta    character varying(16),
    numero_recibo       character varying(64),
    numero_autorizacion character varying(64),
    referencia          character varying(64),
    numero_orden        character varying(64),
    fecha_actualizacion timestamp without time zone
);

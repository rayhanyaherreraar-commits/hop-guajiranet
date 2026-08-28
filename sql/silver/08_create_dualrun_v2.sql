-- =============================================================================
-- 08_create_dualrun_v2.sql
-- Dual-run físico de geo/facts homónimos SIN DROP del Silver viejo.
-- Mismo modelo/grano que 01–03; nombres *_v2 para poder cargar Hop ahora.
-- No toca tbl_dim_geografia / tbl_fact_* / stg_* actuales.
-- No ejecutar 06 ni 07 desde aquí.
-- =============================================================================

SET search_path TO silver_guajiranet, public;

-- -----------------------------------------------------------------------------
-- DIM GEOGRAFÍA v2
-- -----------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS silver_guajiranet.tbl_dim_geografia_v2_sk_geografia_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO CYCLE;

CREATE TABLE IF NOT EXISTS silver_guajiranet.tbl_dim_geografia_v2 (
    sk_geografia        integer NOT NULL
        DEFAULT nextval('silver_guajiranet.tbl_dim_geografia_v2_sk_geografia_seq'::regclass),
    id_barrio           integer NOT NULL,
    barrio              character varying(40),
    dpto                character varying(3),
    mun                 character varying(5),
    municipio           character varying(40),
    departamento        character varying(60),
    fecha_actualizacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT tbl_dim_geografia_v2_pkey PRIMARY KEY (sk_geografia),
    CONSTRAINT uq_dim_geografia_v2 UNIQUE (id_barrio)
);

ALTER SEQUENCE silver_guajiranet.tbl_dim_geografia_v2_sk_geografia_seq
    OWNED BY silver_guajiranet.tbl_dim_geografia_v2.sk_geografia;

CREATE INDEX IF NOT EXISTS idx_dim_geografia_v2_dpto_mun
    ON silver_guajiranet.tbl_dim_geografia_v2 USING btree (dpto, mun);

CREATE TABLE IF NOT EXISTS silver_guajiranet.stg_dim_geografia_v2 (
    id_barrio           integer,
    barrio              character varying(40),
    dpto                character varying(3),
    mun                 character varying(5),
    municipio           character varying(40),
    departamento        character varying(60),
    fecha_actualizacion timestamp without time zone
);

DO $$
DECLARE
    v_max integer;
BEGIN
    IF EXISTS (
        SELECT 1 FROM silver_guajiranet.tbl_dim_geografia_v2 WHERE sk_geografia = 0
    ) THEN
        UPDATE silver_guajiranet.tbl_dim_geografia_v2
        SET
            id_barrio    = 0,
            barrio       = 'SIN BARRIO',
            municipio    = 'SIN MUNICIPIO',
            departamento = 'SIN DEPARTAMENTO'
        WHERE sk_geografia = 0;
    ELSIF EXISTS (
        SELECT 1 FROM silver_guajiranet.tbl_dim_geografia_v2 WHERE id_barrio = 0
    ) THEN
        RAISE NOTICE
            'BLOQUEO seed geo v2: id_barrio=0 existe con sk_geografia <> 0. No se reasigna PK.';
    ELSE
        INSERT INTO silver_guajiranet.tbl_dim_geografia_v2 (
            sk_geografia, id_barrio, barrio, dpto, mun, municipio, departamento
        ) VALUES (
            0, 0, 'SIN BARRIO', NULL, NULL, 'SIN MUNICIPIO', 'SIN DEPARTAMENTO'
        );
    END IF;

    SELECT MAX(sk_geografia) INTO v_max
    FROM silver_guajiranet.tbl_dim_geografia_v2;

    IF v_max IS NULL OR v_max <= 0 THEN
        PERFORM setval('silver_guajiranet.tbl_dim_geografia_v2_sk_geografia_seq', 1, false);
    ELSE
        PERFORM setval('silver_guajiranet.tbl_dim_geografia_v2_sk_geografia_seq', v_max, true);
    END IF;
END
$$;

-- -----------------------------------------------------------------------------
-- FACT FACTURACIÓN v2
-- -----------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS silver_guajiranet.tbl_fact_facturacion_v2_sk_fact_facturacion_seq
    AS bigint
    START WITH 1
    INCREMENT BY 1
    NO CYCLE;

CREATE TABLE IF NOT EXISTS silver_guajiranet.tbl_fact_facturacion_v2 (
    sk_fact_facturacion bigint NOT NULL
        DEFAULT nextval('silver_guajiranet.tbl_fact_facturacion_v2_sk_fact_facturacion_seq'::regclass),
    idsuc               smallint NOT NULL,
    prefijo             character varying(3) NOT NULL,
    numero              integer NOT NULL,
    pos                 smallint NOT NULL,
    sk_sucursal         integer NOT NULL,
    sk_persona          integer NOT NULL,
    sk_producto         integer NOT NULL,
    sk_documento        integer NOT NULL,
    sk_geografia        integer,
    sk_tiempo           integer NOT NULL,
    sk_contrato         integer,
    sk_plan             integer,
    fecha_factura       date NOT NULL,
    anulado             character(1),
    cantidad            numeric(18, 2),
    precio              numeric(18, 2),
    subtotal            numeric(18, 2),
    iva                 numeric(18, 2),
    neto                numeric(18, 2),
    fecha_actualizacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT tbl_fact_facturacion_v2_pkey PRIMARY KEY (sk_fact_facturacion),
    CONSTRAINT uq_fact_facturacion_v2_nk UNIQUE (idsuc, prefijo, numero, pos)
);

ALTER SEQUENCE silver_guajiranet.tbl_fact_facturacion_v2_sk_fact_facturacion_seq
    OWNED BY silver_guajiranet.tbl_fact_facturacion_v2.sk_fact_facturacion;

CREATE INDEX IF NOT EXISTS idx_fact_facturacion_v2_sk_sucursal
    ON silver_guajiranet.tbl_fact_facturacion_v2 USING btree (sk_sucursal);
CREATE INDEX IF NOT EXISTS idx_fact_facturacion_v2_sk_persona
    ON silver_guajiranet.tbl_fact_facturacion_v2 USING btree (sk_persona);
CREATE INDEX IF NOT EXISTS idx_fact_facturacion_v2_sk_producto
    ON silver_guajiranet.tbl_fact_facturacion_v2 USING btree (sk_producto);
CREATE INDEX IF NOT EXISTS idx_fact_facturacion_v2_sk_documento
    ON silver_guajiranet.tbl_fact_facturacion_v2 USING btree (sk_documento);
CREATE INDEX IF NOT EXISTS idx_fact_facturacion_v2_sk_geografia
    ON silver_guajiranet.tbl_fact_facturacion_v2 USING btree (sk_geografia);
CREATE INDEX IF NOT EXISTS idx_fact_facturacion_v2_sk_tiempo
    ON silver_guajiranet.tbl_fact_facturacion_v2 USING btree (sk_tiempo);
CREATE INDEX IF NOT EXISTS idx_fact_facturacion_v2_fecha_factura
    ON silver_guajiranet.tbl_fact_facturacion_v2 USING btree (fecha_factura);

CREATE TABLE IF NOT EXISTS silver_guajiranet.stg_fact_facturacion_v2 (
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

-- -----------------------------------------------------------------------------
-- FACT CARTERA v2
-- -----------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS silver_guajiranet.tbl_fact_cartera_v2_sk_fact_cartera_seq
    AS bigint
    START WITH 1
    INCREMENT BY 1
    NO CYCLE;

CREATE TABLE IF NOT EXISTS silver_guajiranet.tbl_fact_cartera_v2 (
    sk_fact_cartera     bigint NOT NULL
        DEFAULT nextval('silver_guajiranet.tbl_fact_cartera_v2_sk_fact_cartera_seq'::regclass),
    idsuc               smallint NOT NULL,
    prefijo             character varying(3) NOT NULL,
    numero              integer NOT NULL,
    cuenta              integer NOT NULL,
    nit                 integer NOT NULL,
    sucursal            smallint NOT NULL,
    ref_doc             character varying(3) NOT NULL,
    ref_num             character varying(15) NOT NULL,
    sk_sucursal         integer NOT NULL,
    sk_persona          integer NOT NULL,
    sk_tiempo           integer NOT NULL,
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
    fecha_actualizacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT tbl_fact_cartera_v2_pkey PRIMARY KEY (sk_fact_cartera),
    CONSTRAINT uq_fact_cartera_v2_nk UNIQUE (idsuc, prefijo, numero, cuenta, nit, sucursal, ref_doc, ref_num)
);

ALTER SEQUENCE silver_guajiranet.tbl_fact_cartera_v2_sk_fact_cartera_seq
    OWNED BY silver_guajiranet.tbl_fact_cartera_v2.sk_fact_cartera;

CREATE INDEX IF NOT EXISTS idx_fact_cartera_v2_sk_sucursal
    ON silver_guajiranet.tbl_fact_cartera_v2 USING btree (sk_sucursal);
CREATE INDEX IF NOT EXISTS idx_fact_cartera_v2_sk_persona
    ON silver_guajiranet.tbl_fact_cartera_v2 USING btree (sk_persona);
CREATE INDEX IF NOT EXISTS idx_fact_cartera_v2_sk_tiempo
    ON silver_guajiranet.tbl_fact_cartera_v2 USING btree (sk_tiempo);
CREATE INDEX IF NOT EXISTS idx_fact_cartera_v2_sk_perfil_cartera
    ON silver_guajiranet.tbl_fact_cartera_v2 USING btree (sk_perfil_cartera);
CREATE INDEX IF NOT EXISTS idx_fact_cartera_v2_fecha
    ON silver_guajiranet.tbl_fact_cartera_v2 USING btree (fecha);
CREATE INDEX IF NOT EXISTS idx_fact_cartera_v2_fecha_vencimiento
    ON silver_guajiranet.tbl_fact_cartera_v2 USING btree (fecha_vencimiento);

CREATE TABLE IF NOT EXISTS silver_guajiranet.stg_fact_cartera_v2 (
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

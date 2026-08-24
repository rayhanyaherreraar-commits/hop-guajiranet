-- =============================================================================
-- 01_create_dims.sql
-- Silver definitivo GuajiraNet — dimensiones
-- Esquema: silver_guajiranet
-- Idempotente. No DROP de tbl_dim_cliente / tbl_dim_servicio.
-- No se ejecuta contra Aurora desde este repo (Fase 1 = solo archivos).
--
-- KEEP : tbl_dim_tiempo, tbl_dim_documento
-- CREATE: persona, sucursal, contrato, plan, producto_erp, perfil_cartera
-- REPLACE mismo nombre: tbl_dim_geografia
--   Si existe el modelo viejo (id_barrio varchar), NO se altera.
--   Ver 07_drop_obsolete.sql (cutover) y discovery/silver_ddl_implementation.md.
-- =============================================================================

SET search_path TO silver_guajiranet, public;

-- -----------------------------------------------------------------------------
-- KEEP — tbl_dim_tiempo
-- SK = YYYYMMDD (Hop). Sequence no aplica.
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF to_regclass('silver_guajiranet.tbl_dim_tiempo') IS NULL THEN
        RAISE EXCEPTION
            'BLOQUEO: silver_guajiranet.tbl_dim_tiempo no existe. Es KEEP: cargarla con el modelo actual antes de este script.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = 'silver_guajiranet'
          AND t.relname = 'tbl_dim_tiempo'
          AND c.conname = 'uq_dim_tiempo_fecha'
    ) THEN
        BEGIN
            ALTER TABLE silver_guajiranet.tbl_dim_tiempo
                ADD CONSTRAINT uq_dim_tiempo_fecha UNIQUE (fecha);
        EXCEPTION
            WHEN others THEN
                RAISE NOTICE
                    'BLOQUEO: no se añadió uq_dim_tiempo_fecha (%). Corregir duplicados y re-ejecutar 01.',
                    SQLERRM;
        END;
    END IF;

    -- Smart key: SK debe coincidir con la fecha.
    -- Si hay filas sucias, NO se aborta el resto del script (dual-run).
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = 'silver_guajiranet'
          AND t.relname = 'tbl_dim_tiempo'
          AND c.conname = 'chk_dim_tiempo_sk'
    ) THEN
        BEGIN
            ALTER TABLE silver_guajiranet.tbl_dim_tiempo
                ADD CONSTRAINT chk_dim_tiempo_sk
                CHECK (sk_tiempo = to_char(fecha, 'YYYYMMDD')::integer);
        EXCEPTION
            WHEN others THEN
                RAISE NOTICE
                    'BLOQUEO: no se añadió chk_dim_tiempo_sk (%). Corregir filas y re-ejecutar 01.',
                    SQLERRM;
        END;
    END IF;
END
$$;

-- -----------------------------------------------------------------------------
-- KEEP — tbl_dim_documento
-- Columnas y UNIQUE (idsuc, prefijo) ya coinciden con Bronze PK. Sin ALTER de tipos.
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF to_regclass('silver_guajiranet.tbl_dim_documento') IS NULL THEN
        RAISE EXCEPTION
            'BLOQUEO: silver_guajiranet.tbl_dim_documento no existe. Es KEEP.';
    END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_dim_documento_tipodoc
    ON silver_guajiranet.tbl_dim_documento USING btree (tipodoc);

-- -----------------------------------------------------------------------------
-- tbl_dim_geografia — REPLACE (grano mabarrio.idbarrio integer)
-- No DROP del modelo viejo (zona/estrato/coordenada, id_barrio varchar).
-- La sequence puede existir ya (modelo viejo). IF NOT EXISTS no la recrea.
-- -----------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS silver_guajiranet.tbl_dim_geografia_sk_geografia_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO CYCLE;

DO $$
BEGIN
    IF to_regclass('silver_guajiranet.tbl_dim_geografia') IS NULL THEN
        EXECUTE $ct$
            CREATE TABLE silver_guajiranet.tbl_dim_geografia (
                sk_geografia        integer NOT NULL
                    DEFAULT nextval('silver_guajiranet.tbl_dim_geografia_sk_geografia_seq'::regclass),
                id_barrio           integer NOT NULL,
                barrio              character varying(40),
                dpto                character varying(3),
                mun                 character varying(5),
                municipio           character varying(40),
                departamento        character varying(60),
                fecha_actualizacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
                CONSTRAINT tbl_dim_geografia_pkey PRIMARY KEY (sk_geografia),
                CONSTRAINT uq_dim_geografia UNIQUE (id_barrio)
            );
        $ct$;
        EXECUTE $ow$
            ALTER SEQUENCE silver_guajiranet.tbl_dim_geografia_sk_geografia_seq
                OWNED BY silver_guajiranet.tbl_dim_geografia.sk_geografia;
        $ow$;
        RAISE NOTICE 'Creada tbl_dim_geografia (modelo nuevo, id_barrio integer).';
    ELSIF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'silver_guajiranet'
          AND table_name = 'tbl_dim_geografia'
          AND column_name = 'id_barrio'
          AND data_type = 'integer'
    ) THEN
        RAISE NOTICE 'tbl_dim_geografia ya está en el modelo nuevo (id_barrio integer).';
    ELSE
        RAISE NOTICE
            'BLOQUEO: tbl_dim_geografia existe con modelo viejo (id_barrio varchar). No se DROP. Cutover: 07_drop_obsolete.sql sección geografia, luego re-ejecutar 01/03/04.';
    END IF;
END
$$;

-- dpto/mun no existen en el modelo viejo; no crear el índice hasta el REPLACE.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'silver_guajiranet'
          AND table_name = 'tbl_dim_geografia'
          AND column_name = 'dpto'
    ) THEN
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_dim_geografia_dpto_mun
                 ON silver_guajiranet.tbl_dim_geografia USING btree (dpto, mun)';
    END IF;
END
$$;

-- -----------------------------------------------------------------------------
-- DIM_PERFIL_CARTERA — CREATE
-- SK 0 = desconocido (nulos y código 0 de sucursal). Seed en 04.
-- -----------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS silver_guajiranet.tbl_dim_perfil_cartera_sk_perfil_cartera_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO CYCLE;

CREATE TABLE IF NOT EXISTS silver_guajiranet.tbl_dim_perfil_cartera (
    sk_perfil_cartera   integer NOT NULL
        DEFAULT nextval('silver_guajiranet.tbl_dim_perfil_cartera_sk_perfil_cartera_seq'::regclass),
    id_perfil           integer NOT NULL,
    denominacion        character varying(32),
    diasvence1          integer,
    diasvence2          integer,
    deshabilitar        character(1),
    alertar             character(1),
    diasvencefactura    integer,
    nofactura           boolean,
    fecha_actualizacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT tbl_dim_perfil_cartera_pkey PRIMARY KEY (sk_perfil_cartera),
    CONSTRAINT uq_dim_perfil_cartera_id UNIQUE (id_perfil)
);

ALTER SEQUENCE silver_guajiranet.tbl_dim_perfil_cartera_sk_perfil_cartera_seq
    OWNED BY silver_guajiranet.tbl_dim_perfil_cartera.sk_perfil_cartera;

-- -----------------------------------------------------------------------------
-- DIM_PERSONA — CREATE  (materceros; NK nit integer)
-- idcliente NO es UNIQUE: 5 UUID con 2 nit. El puente UUID es tbl_brg_persona_uuid.
-- -----------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS silver_guajiranet.tbl_dim_persona_sk_persona_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO CYCLE;

CREATE TABLE IF NOT EXISTS silver_guajiranet.tbl_dim_persona (
    sk_persona          integer NOT NULL
        DEFAULT nextval('silver_guajiranet.tbl_dim_persona_sk_persona_seq'::regclass),
    nit                 integer NOT NULL,
    dv                  character(1),
    razonsocial         character varying(128),
    documento_identidad bigint,
    tipo_persona        character(1),
    es_cliente          character(1),
    es_proveedor        character(1),
    tdoc                smallint,
    idcliente           character varying(64),
    fecha_creacion      date,
    fecha_actualizacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT tbl_dim_persona_pkey PRIMARY KEY (sk_persona),
    CONSTRAINT uq_dim_persona_nit UNIQUE (nit)
);

ALTER SEQUENCE silver_guajiranet.tbl_dim_persona_sk_persona_seq
    OWNED BY silver_guajiranet.tbl_dim_persona.sk_persona;

CREATE INDEX IF NOT EXISTS idx_dim_persona_idcliente
    ON silver_guajiranet.tbl_dim_persona USING btree (idcliente);

-- -----------------------------------------------------------------------------
-- DIM_SUCURSAL — CREATE  (matercerosuc; NK nit+idsuc)
-- idcontrato NO se guarda aquí → tbl_brg_sucursal_contrato.
-- idsuc=0 es NK válida (11 filas).
-- -----------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS silver_guajiranet.tbl_dim_sucursal_sk_sucursal_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO CYCLE;

CREATE TABLE IF NOT EXISTS silver_guajiranet.tbl_dim_sucursal (
    sk_sucursal                 integer NOT NULL
        DEFAULT nextval('silver_guajiranet.tbl_dim_sucursal_sk_sucursal_seq'::regclass),
    nit                         integer NOT NULL,
    idsuc                       smallint NOT NULL,
    sk_persona                  integer NOT NULL,
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
    fecha_actualizacion         timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT tbl_dim_sucursal_pkey PRIMARY KEY (sk_sucursal),
    CONSTRAINT uq_dim_sucursal_nk UNIQUE (nit, idsuc)
);

ALTER SEQUENCE silver_guajiranet.tbl_dim_sucursal_sk_sucursal_seq
    OWNED BY silver_guajiranet.tbl_dim_sucursal.sk_sucursal;

CREATE INDEX IF NOT EXISTS idx_dim_sucursal_sk_persona
    ON silver_guajiranet.tbl_dim_sucursal USING btree (sk_persona);

CREATE INDEX IF NOT EXISTS idx_dim_sucursal_sk_geografia
    ON silver_guajiranet.tbl_dim_sucursal USING btree (sk_geografia);

CREATE INDEX IF NOT EXISTS idx_dim_sucursal_sk_perfil_cartera
    ON silver_guajiranet.tbl_dim_sucursal USING btree (sk_perfil_cartera);

CREATE INDEX IF NOT EXISTS idx_dim_sucursal_fecharetiroisp
    ON silver_guajiranet.tbl_dim_sucursal USING btree (fecharetiroisp);

-- -----------------------------------------------------------------------------
-- DIM_PLAN — CREATE  (tmjsonplan_server tipo='P')
-- NK = datajson.id (UUID), NO el integer tmjsonplan_server.id.
-- No se copian passwords (esta tabla no los tiene).
-- -----------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS silver_guajiranet.tbl_dim_plan_sk_plan_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO CYCLE;

CREATE TABLE IF NOT EXISTS silver_guajiranet.tbl_dim_plan (
    sk_plan                 integer NOT NULL
        DEFAULT nextval('silver_guajiranet.tbl_dim_plan_sk_plan_seq'::regclass),
    id_plan                 character varying(64) NOT NULL,
    tipo                    character(1) NOT NULL DEFAULT 'P',
    nombre                  character varying(256),
    public_id               integer,
    ceil_down_kbps          integer,
    ceil_up_kbps            integer,
    cir                     character varying(32),
    precio                  numeric(18, 2),
    frequency_in_months     integer,
    contracts_count         integer,
    created_at              timestamp with time zone,
    updated_at              timestamp with time zone,
    fecha_actualizacion     timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT tbl_dim_plan_pkey PRIMARY KEY (sk_plan),
    CONSTRAINT uq_dim_plan_id UNIQUE (id_plan)
);

ALTER SEQUENCE silver_guajiranet.tbl_dim_plan_sk_plan_seq
    OWNED BY silver_guajiranet.tbl_dim_plan.sk_plan;

-- -----------------------------------------------------------------------------
-- DIM_CONTRATO — CREATE  (tmjsoncontract)
-- No se persisten pppoe_password ni wifi_password.
-- plan_id es degenerada; el vínculo canónico es tbl_brg_contrato_plan.
-- address_* son atributos, no FK a geografía.
-- -----------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS silver_guajiranet.tbl_dim_contrato_sk_contrato_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO CYCLE;

CREATE TABLE IF NOT EXISTS silver_guajiranet.tbl_dim_contrato (
    sk_contrato             integer NOT NULL
        DEFAULT nextval('silver_guajiranet.tbl_dim_contrato_sk_contrato_seq'::regclass),
    idcontrato              character varying(64) NOT NULL,
    idcliente               character varying(64),
    public_id               integer,
    state                   character varying(32),
    start_date              timestamp with time zone,
    created_at              timestamp with time zone,
    updated_at              timestamp with time zone,
    address_street          character varying(256),
    address_city            character varying(80),
    address_state           character varying(80),
    address_country         character varying(80),
    address_number          character varying(64),
    latitude                numeric(12, 8),
    longitude               numeric(12, 8),
    ont_id                  character varying(64),
    ont_number              character varying(64),
    ont_serial_number       character varying(64),
    olt_id                  character varying(64),
    interface_gpon          character varying(64),
    mac_address             character varying(32),
    plan_id                 character varying(64),
    fecha_actualizacion     timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT tbl_dim_contrato_pkey PRIMARY KEY (sk_contrato),
    CONSTRAINT uq_dim_contrato_idcontrato UNIQUE (idcontrato)
);

ALTER SEQUENCE silver_guajiranet.tbl_dim_contrato_sk_contrato_seq
    OWNED BY silver_guajiranet.tbl_dim_contrato.sk_contrato;

CREATE INDEX IF NOT EXISTS idx_dim_contrato_idcliente
    ON silver_guajiranet.tbl_dim_contrato USING btree (idcliente);

CREATE INDEX IF NOT EXISTS idx_dim_contrato_plan_id
    ON silver_guajiranet.tbl_dim_contrato USING btree (plan_id);

CREATE INDEX IF NOT EXISTS idx_dim_contrato_state
    ON silver_guajiranet.tbl_dim_contrato USING btree (state);

-- -----------------------------------------------------------------------------
-- DIM_PRODUCTO_ERP — CREATE  (maproductos + mafamiliasproductos)
-- Reemplaza semántica de tbl_dim_servicio. No se DROP servicio aquí.
-- -----------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS silver_guajiranet.tbl_dim_producto_erp_sk_producto_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO CYCLE;

CREATE TABLE IF NOT EXISTS silver_guajiranet.tbl_dim_producto_erp (
    sk_producto             integer NOT NULL
        DEFAULT nextval('silver_guajiranet.tbl_dim_producto_erp_sk_producto_seq'::regclass),
    id_producto             character varying(25) NOT NULL,
    nombre_producto         character varying(128),
    id_familia              character varying(10),
    categoria               character varying(40),
    tarifa_lista            numeric(18, 2),
    estado_activo           character(1),
    fecha_actualizacion     timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT tbl_dim_producto_erp_pkey PRIMARY KEY (sk_producto),
    CONSTRAINT uq_dim_producto_erp_id UNIQUE (id_producto)
);

ALTER SEQUENCE silver_guajiranet.tbl_dim_producto_erp_sk_producto_seq
    OWNED BY silver_guajiranet.tbl_dim_producto_erp.sk_producto;

CREATE INDEX IF NOT EXISTS idx_dim_producto_erp_id_familia
    ON silver_guajiranet.tbl_dim_producto_erp USING btree (id_familia);

-- =============================================================================
-- 02_create_bridges_facts.sql
-- Silver definitivo GuajiraNet — bridges y facts
-- Idempotente. No DROP de facts actuales si aún tienen el grano viejo.
--
-- CREATE: brg_persona_uuid, brg_sucursal_contrato, brg_contrato_plan,
--         fact_pago_aplicacion, fact_pago_pasarela
-- REPLACE mismo nombre: tbl_fact_facturacion, tbl_fact_cartera
--   Si el modelo viejo sigue en pie, NOTICE de BLOQUEO (cutover = 07).
--
-- FACT_FACTURACION: sk_contrato y sk_plan son NULLABLE y se cargan siempre NULL.
--   No hay CHECK que lo fuerce: Hop podrá llenarlos cuando exista un join fiable.
--   No usar SK 0 para contrato/plan.
-- =============================================================================

SET search_path TO silver_guajiranet, public;

-- -----------------------------------------------------------------------------
-- BRG_PERSONA_UUID
-- NK lógica (idcliente, nit). nit NULL = UUID solo en tmjsonclient.
-- UNIQUE de constraint no admite COALESCE → índice único expresional.
-- No UNIQUE(idcliente): 5 UUID tienen 2 nit.
-- -----------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS silver_guajiranet.tbl_brg_persona_uuid_sk_brg_persona_uuid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO CYCLE;

CREATE TABLE IF NOT EXISTS silver_guajiranet.tbl_brg_persona_uuid (
    sk_brg_persona_uuid integer NOT NULL
        DEFAULT nextval('silver_guajiranet.tbl_brg_persona_uuid_sk_brg_persona_uuid_seq'::regclass),
    idcliente           character varying(64) NOT NULL,
    nit                 integer,
    sk_persona          integer,
    en_materceros       boolean,
    en_tmjsonclient     boolean,
    fecha_actualizacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT tbl_brg_persona_uuid_pkey PRIMARY KEY (sk_brg_persona_uuid)
);

ALTER SEQUENCE silver_guajiranet.tbl_brg_persona_uuid_sk_brg_persona_uuid_seq
    OWNED BY silver_guajiranet.tbl_brg_persona_uuid.sk_brg_persona_uuid;

-- Sentinel -1 solo en el índice: nit NULL sigue siendo NULL en la columna.
CREATE UNIQUE INDEX IF NOT EXISTS uq_brg_persona_uuid_nk
    ON silver_guajiranet.tbl_brg_persona_uuid USING btree (idcliente, (COALESCE(nit, -1)));

CREATE INDEX IF NOT EXISTS idx_brg_persona_uuid_idcliente
    ON silver_guajiranet.tbl_brg_persona_uuid USING btree (idcliente);

CREATE INDEX IF NOT EXISTS idx_brg_persona_uuid_sk_persona
    ON silver_guajiranet.tbl_brg_persona_uuid USING btree (sk_persona);

-- -----------------------------------------------------------------------------
-- BRG_SUCURSAL_CONTRATO
-- Fuente: matercerosuc WHERE idcontrato IS NOT NULL.
-- Contratos solo JSON (sin sucursal) NO entran.
-- -----------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS silver_guajiranet.tbl_brg_sucursal_contrato_sk_brg_sucursal_contrato_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO CYCLE;

CREATE TABLE IF NOT EXISTS silver_guajiranet.tbl_brg_sucursal_contrato (
    sk_brg_sucursal_contrato integer NOT NULL
        DEFAULT nextval('silver_guajiranet.tbl_brg_sucursal_contrato_sk_brg_sucursal_contrato_seq'::regclass),
    sk_sucursal             integer NOT NULL,
    sk_contrato             integer,
    nit                     integer NOT NULL,
    idsuc                   smallint NOT NULL,
    idcontrato              character varying(64) NOT NULL,
    match_json              boolean,
    fecha_actualizacion     timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT tbl_brg_sucursal_contrato_pkey PRIMARY KEY (sk_brg_sucursal_contrato),
    CONSTRAINT uq_brg_sucursal_contrato_nk UNIQUE (nit, idsuc, idcontrato)
);

ALTER SEQUENCE silver_guajiranet.tbl_brg_sucursal_contrato_sk_brg_sucursal_contrato_seq
    OWNED BY silver_guajiranet.tbl_brg_sucursal_contrato.sk_brg_sucursal_contrato;

CREATE INDEX IF NOT EXISTS idx_brg_sucursal_contrato_sk_sucursal
    ON silver_guajiranet.tbl_brg_sucursal_contrato USING btree (sk_sucursal);

CREATE INDEX IF NOT EXISTS idx_brg_sucursal_contrato_sk_contrato
    ON silver_guajiranet.tbl_brg_sucursal_contrato USING btree (sk_contrato);

CREATE INDEX IF NOT EXISTS idx_brg_sucursal_contrato_idcontrato
    ON silver_guajiranet.tbl_brg_sucursal_contrato USING btree (idcontrato);

-- -----------------------------------------------------------------------------
-- BRG_CONTRATO_PLAN  (N:1 vigente; sin histórico)
-- UNIQUE idcontrato = NK. UNIQUE sk_contrato refuerza N:1.
-- -----------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS silver_guajiranet.tbl_brg_contrato_plan_sk_brg_contrato_plan_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO CYCLE;

CREATE TABLE IF NOT EXISTS silver_guajiranet.tbl_brg_contrato_plan (
    sk_brg_contrato_plan integer NOT NULL
        DEFAULT nextval('silver_guajiranet.tbl_brg_contrato_plan_sk_brg_contrato_plan_seq'::regclass),
    sk_contrato          integer NOT NULL,
    sk_plan              integer NOT NULL,
    idcontrato           character varying(64) NOT NULL,
    id_plan              character varying(64) NOT NULL,
    fecha_actualizacion  timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT tbl_brg_contrato_plan_pkey PRIMARY KEY (sk_brg_contrato_plan),
    CONSTRAINT uq_brg_contrato_plan_idcontrato UNIQUE (idcontrato),
    CONSTRAINT uq_brg_contrato_plan_sk_contrato UNIQUE (sk_contrato)
);

ALTER SEQUENCE silver_guajiranet.tbl_brg_contrato_plan_sk_brg_contrato_plan_seq
    OWNED BY silver_guajiranet.tbl_brg_contrato_plan.sk_brg_contrato_plan;

CREATE INDEX IF NOT EXISTS idx_brg_contrato_plan_sk_plan
    ON silver_guajiranet.tbl_brg_contrato_plan USING btree (sk_plan);

CREATE INDEX IF NOT EXISTS idx_brg_contrato_plan_id_plan
    ON silver_guajiranet.tbl_brg_contrato_plan USING btree (id_plan);

-- -----------------------------------------------------------------------------
-- FACT_FACTURACION — REBUILD mismo nombre
-- NK: (idsuc, prefijo, numero, pos)
-- Detector modelo nuevo: columna pos (el viejo usa posicion_factura).
-- -----------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS silver_guajiranet.tbl_fact_facturacion_sk_fact_facturacion_seq
    AS bigint
    START WITH 1
    INCREMENT BY 1
    NO CYCLE;

DO $$
BEGIN
    IF to_regclass('silver_guajiranet.tbl_fact_facturacion') IS NULL THEN
        EXECUTE $ct$
            CREATE TABLE silver_guajiranet.tbl_fact_facturacion (
                sk_fact_facturacion bigint NOT NULL
                    DEFAULT nextval('silver_guajiranet.tbl_fact_facturacion_sk_fact_facturacion_seq'::regclass),
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
                -- Siempre NULL en la carga actual: no hay join confiable a contrato/plan.
                -- No SK 0. No CHECK IS NULL (permite Hop futuro).
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
                CONSTRAINT tbl_fact_facturacion_pkey PRIMARY KEY (sk_fact_facturacion),
                CONSTRAINT uq_fact_facturacion_nk UNIQUE (idsuc, prefijo, numero, pos)
            );
        $ct$;
        EXECUTE $ow$
            ALTER SEQUENCE silver_guajiranet.tbl_fact_facturacion_sk_fact_facturacion_seq
                OWNED BY silver_guajiranet.tbl_fact_facturacion.sk_fact_facturacion;
        $ow$;
        RAISE NOTICE 'Creada tbl_fact_facturacion (modelo nuevo, NK idsuc+prefijo+numero+pos).';
    ELSIF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'silver_guajiranet'
          AND table_name = 'tbl_fact_facturacion'
          AND column_name = 'pos'
    ) THEN
        RAISE NOTICE 'tbl_fact_facturacion ya está en el modelo nuevo (columna pos).';
    ELSE
        RAISE NOTICE
            'BLOQUEO: tbl_fact_facturacion existe con modelo viejo (posicion_factura / sk_cliente). No se DROP. Cutover: 07_drop_obsolete.sql sección facts, luego re-ejecutar 02/03.';
    END IF;
END
$$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'silver_guajiranet'
          AND table_name = 'tbl_fact_facturacion'
          AND column_name = 'pos'
    ) THEN
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_fact_facturacion_sk_sucursal ON silver_guajiranet.tbl_fact_facturacion USING btree (sk_sucursal)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_fact_facturacion_sk_persona ON silver_guajiranet.tbl_fact_facturacion USING btree (sk_persona)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_fact_facturacion_sk_producto ON silver_guajiranet.tbl_fact_facturacion USING btree (sk_producto)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_fact_facturacion_sk_documento ON silver_guajiranet.tbl_fact_facturacion USING btree (sk_documento)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_fact_facturacion_sk_geografia ON silver_guajiranet.tbl_fact_facturacion USING btree (sk_geografia)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_fact_facturacion_sk_tiempo ON silver_guajiranet.tbl_fact_facturacion USING btree (sk_tiempo)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_fact_facturacion_sk_contrato ON silver_guajiranet.tbl_fact_facturacion USING btree (sk_contrato)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_fact_facturacion_sk_plan ON silver_guajiranet.tbl_fact_facturacion USING btree (sk_plan)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_fact_facturacion_fecha_factura ON silver_guajiranet.tbl_fact_facturacion USING btree (fecha_factura)';
    END IF;
END
$$;

-- -----------------------------------------------------------------------------
-- FACT_CARTERA — REPLACE mismo nombre
-- NK: (idsuc, prefijo, numero, cuenta, nit, sucursal, ref_doc, ref_num)
-- Detector modelo nuevo: columna idsuc (el viejo no la tiene).
-- -----------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS silver_guajiranet.tbl_fact_cartera_sk_fact_cartera_seq
    AS bigint
    START WITH 1
    INCREMENT BY 1
    NO CYCLE;

DO $$
BEGIN
    IF to_regclass('silver_guajiranet.tbl_fact_cartera') IS NULL THEN
        EXECUTE $ct$
            CREATE TABLE silver_guajiranet.tbl_fact_cartera (
                sk_fact_cartera     bigint NOT NULL
                    DEFAULT nextval('silver_guajiranet.tbl_fact_cartera_sk_fact_cartera_seq'::regclass),
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
                CONSTRAINT tbl_fact_cartera_pkey PRIMARY KEY (sk_fact_cartera),
                CONSTRAINT uq_fact_cartera_nk UNIQUE (idsuc, prefijo, numero, cuenta, nit, sucursal, ref_doc, ref_num)
            );
        $ct$;
        EXECUTE $ow$
            ALTER SEQUENCE silver_guajiranet.tbl_fact_cartera_sk_fact_cartera_seq
                OWNED BY silver_guajiranet.tbl_fact_cartera.sk_fact_cartera;
        $ow$;
        RAISE NOTICE 'Creada tbl_fact_cartera (modelo nuevo, NK latest-open tmcartera).';
    ELSIF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'silver_guajiranet'
          AND table_name = 'tbl_fact_cartera'
          AND column_name = 'idsuc'
    ) THEN
        RAISE NOTICE 'tbl_fact_cartera ya está en el modelo nuevo (columna idsuc).';
    ELSE
        RAISE NOTICE
            'BLOQUEO: tbl_fact_cartera existe con modelo viejo (sk_cliente / sin idsuc). No se DROP. Cutover: 07_drop_obsolete.sql sección facts, luego re-ejecutar 02/03.';
    END IF;
END
$$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'silver_guajiranet'
          AND table_name = 'tbl_fact_cartera'
          AND column_name = 'idsuc'
    ) THEN
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_fact_cartera_sk_sucursal ON silver_guajiranet.tbl_fact_cartera USING btree (sk_sucursal)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_fact_cartera_sk_persona ON silver_guajiranet.tbl_fact_cartera USING btree (sk_persona)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_fact_cartera_sk_tiempo ON silver_guajiranet.tbl_fact_cartera USING btree (sk_tiempo)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_fact_cartera_sk_perfil_cartera ON silver_guajiranet.tbl_fact_cartera USING btree (sk_perfil_cartera)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_fact_cartera_fecha ON silver_guajiranet.tbl_fact_cartera USING btree (fecha)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_fact_cartera_fecha_vencimiento ON silver_guajiranet.tbl_fact_cartera USING btree (fecha_vencimiento)';
    END IF;
END
$$;

-- -----------------------------------------------------------------------------
-- FACT_PAGO_APLICACION — CREATE
-- NK: (idsuc, prefijo, numero, rc_idsuc, rc_prefijo, rc_numero)
-- pagorc = total del recibo; no sumar por factura.
-- -----------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS silver_guajiranet.tbl_fact_pago_aplicacion_sk_fact_pago_aplicacion_seq
    AS bigint
    START WITH 1
    INCREMENT BY 1
    NO CYCLE;

CREATE TABLE IF NOT EXISTS silver_guajiranet.tbl_fact_pago_aplicacion (
    sk_fact_pago_aplicacion bigint NOT NULL
        DEFAULT nextval('silver_guajiranet.tbl_fact_pago_aplicacion_sk_fact_pago_aplicacion_seq'::regclass),
    idsuc                   smallint NOT NULL,
    prefijo                 character varying(3) NOT NULL,
    numero                  integer NOT NULL,
    rc_idsuc                smallint NOT NULL,
    rc_prefijo              character varying(3) NOT NULL,
    rc_numero               integer NOT NULL,
    sk_sucursal             integer,
    sk_persona              integer,
    sk_documento            integer,
    sk_tiempo_factura       integer,
    sk_tiempo_recibo        integer,
    carteraaplicado         numeric(18, 2),
    pagorc                  numeric(18, 2),
    idformapago             smallint,
    ccosto                  integer,
    fecha_actualizacion     timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT tbl_fact_pago_aplicacion_pkey PRIMARY KEY (sk_fact_pago_aplicacion),
    CONSTRAINT uq_fact_pago_aplicacion_nk UNIQUE (idsuc, prefijo, numero, rc_idsuc, rc_prefijo, rc_numero)
);

ALTER SEQUENCE silver_guajiranet.tbl_fact_pago_aplicacion_sk_fact_pago_aplicacion_seq
    OWNED BY silver_guajiranet.tbl_fact_pago_aplicacion.sk_fact_pago_aplicacion;

CREATE INDEX IF NOT EXISTS idx_fact_pago_aplicacion_sk_sucursal
    ON silver_guajiranet.tbl_fact_pago_aplicacion USING btree (sk_sucursal);

CREATE INDEX IF NOT EXISTS idx_fact_pago_aplicacion_sk_persona
    ON silver_guajiranet.tbl_fact_pago_aplicacion USING btree (sk_persona);

CREATE INDEX IF NOT EXISTS idx_fact_pago_aplicacion_sk_documento
    ON silver_guajiranet.tbl_fact_pago_aplicacion USING btree (sk_documento);

CREATE INDEX IF NOT EXISTS idx_fact_pago_aplicacion_sk_tiempo_factura
    ON silver_guajiranet.tbl_fact_pago_aplicacion USING btree (sk_tiempo_factura);

CREATE INDEX IF NOT EXISTS idx_fact_pago_aplicacion_sk_tiempo_recibo
    ON silver_guajiranet.tbl_fact_pago_aplicacion USING btree (sk_tiempo_recibo);

-- -----------------------------------------------------------------------------
-- FACT_PAGO_PASARELA — CREATE
-- NK: id_pago_digital (= trpagodigital.id). Paralelo a aplicacion, no subconjunto.
-- -----------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS silver_guajiranet.tbl_fact_pago_pasarela_sk_fact_pago_pasarela_seq
    AS bigint
    START WITH 1
    INCREMENT BY 1
    NO CYCLE;

CREATE TABLE IF NOT EXISTS silver_guajiranet.tbl_fact_pago_pasarela (
    sk_fact_pago_pasarela bigint NOT NULL
        DEFAULT nextval('silver_guajiranet.tbl_fact_pago_pasarela_sk_fact_pago_pasarela_seq'::regclass),
    id_pago_digital       integer NOT NULL,
    idsuc                 smallint,
    prefijo               character varying(3),
    numero                integer,
    rec_idsuc             smallint,
    rec_prefijo           character varying(3),
    rec_numero            integer,
    sk_sucursal           integer,
    sk_persona            integer,
    sk_tiempo             integer,
    foperacion            timestamp without time zone,
    total                 numeric(18, 2),
    codigo_respuesta      character varying(16),
    numero_recibo         character varying(64),
    numero_autorizacion   character varying(64),
    referencia            character varying(64),
    numero_orden          character varying(64),
    fecha_actualizacion   timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT tbl_fact_pago_pasarela_pkey PRIMARY KEY (sk_fact_pago_pasarela),
    CONSTRAINT uq_fact_pago_pasarela_id UNIQUE (id_pago_digital)
);

ALTER SEQUENCE silver_guajiranet.tbl_fact_pago_pasarela_sk_fact_pago_pasarela_seq
    OWNED BY silver_guajiranet.tbl_fact_pago_pasarela.sk_fact_pago_pasarela;

CREATE INDEX IF NOT EXISTS idx_fact_pago_pasarela_sk_sucursal
    ON silver_guajiranet.tbl_fact_pago_pasarela USING btree (sk_sucursal);

CREATE INDEX IF NOT EXISTS idx_fact_pago_pasarela_sk_persona
    ON silver_guajiranet.tbl_fact_pago_pasarela USING btree (sk_persona);

CREATE INDEX IF NOT EXISTS idx_fact_pago_pasarela_sk_tiempo
    ON silver_guajiranet.tbl_fact_pago_pasarela USING btree (sk_tiempo);

CREATE INDEX IF NOT EXISTS idx_fact_pago_pasarela_factura
    ON silver_guajiranet.tbl_fact_pago_pasarela USING btree (idsuc, prefijo, numero);

CREATE INDEX IF NOT EXISTS idx_fact_pago_pasarela_foperacion
    ON silver_guajiranet.tbl_fact_pago_pasarela USING btree (foperacion);

CREATE INDEX IF NOT EXISTS idx_fact_pago_pasarela_codigo_respuesta
    ON silver_guajiranet.tbl_fact_pago_pasarela USING btree (codigo_respuesta);

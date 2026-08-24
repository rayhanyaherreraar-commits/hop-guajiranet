-- =============================================================================
-- 07_drop_obsolete.sql
-- SOLO DESPUÉS del cutover Gold (vistas/jobs ya no leen el modelo viejo).
-- No ejecutar en Fase 1.
--
-- Sección A: DROP de objetos con nombre distinto (persona/sucursal ya viven
--            en paralelo). Seguro respecto a las tablas nuevas.
-- Sección B: DROP condicional de objetos CON EL MISMO NOMBRE (geo, facts, stg)
--            solo si todavía tienen el esquema viejo. Después hay que
--            re-ejecutar 01/02/03/04 para crear el modelo nuevo.
-- =============================================================================

SET search_path TO silver_guajiranet, public;

-- Prerrequisito: ejecutar 05_drop_fk.sql antes, para no chocar con FK NOT VALID.
-- CASCADE en A/B solo para vistas Gold residuales y defaults de sequence OWNED BY.

-- ---------------------------------------------------------------------------
-- A. Cutover: cliente y servicio (nombres que no colisionan con el modelo nuevo)
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS silver_guajiranet.stg_dim_cliente CASCADE;
DROP TABLE IF EXISTS silver_guajiranet.tbl_dim_cliente CASCADE;
DROP SEQUENCE IF EXISTS silver_guajiranet.tbl_dim_cliente_sk_cliente_seq;

DROP TABLE IF EXISTS silver_guajiranet.stg_dim_servicio CASCADE;
DROP TABLE IF EXISTS silver_guajiranet.tbl_dim_servicio CASCADE;
DROP SEQUENCE IF EXISTS silver_guajiranet.tbl_dim_servicio_sk_servicio_seq;

-- ---------------------------------------------------------------------------
-- B. Mismo nombre — DROP solo si el detector de modelo viejo es positivo.
--    Gold debe haber dejado de leer estas tablas antes de este bloque.
-- ---------------------------------------------------------------------------

-- Geografía vieja: id_barrio varchar (zona/estrato/coordenada).
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'silver_guajiranet'
          AND table_name = 'tbl_dim_geografia'
          AND column_name = 'id_barrio'
          AND data_type IN ('character varying', 'varchar', 'text')
    ) THEN
        DROP TABLE silver_guajiranet.tbl_dim_geografia CASCADE;
        RAISE NOTICE 'DROP tbl_dim_geografia (modelo viejo). Re-ejecutar 01 y 04.';
    ELSE
        RAISE NOTICE 'Skip DROP tbl_dim_geografia: no hay modelo viejo (o no existe).';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'silver_guajiranet'
          AND table_name = 'stg_dim_geografia'
          AND column_name = 'id_barrio'
          AND data_type IN ('character varying', 'varchar', 'text')
    ) THEN
        DROP TABLE silver_guajiranet.stg_dim_geografia CASCADE;
        RAISE NOTICE 'DROP stg_dim_geografia (modelo viejo). Re-ejecutar 03.';
    ELSE
        RAISE NOTICE 'Skip DROP stg_dim_geografia: no hay modelo viejo (o no existe).';
    END IF;
END
$$;

-- Facturación vieja: posicion_factura, sin columna pos.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'silver_guajiranet'
          AND table_name = 'tbl_fact_facturacion'
          AND column_name = 'posicion_factura'
    ) AND NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'silver_guajiranet'
          AND table_name = 'tbl_fact_facturacion'
          AND column_name = 'pos'
    ) THEN
        DROP TABLE silver_guajiranet.tbl_fact_facturacion CASCADE;
        RAISE NOTICE 'DROP tbl_fact_facturacion (modelo viejo). Re-ejecutar 02.';
    ELSE
        RAISE NOTICE 'Skip DROP tbl_fact_facturacion: no hay modelo viejo (o ya es nuevo).';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'silver_guajiranet'
          AND table_name = 'stg_fact_facturacion'
          AND column_name = 'posicion_factura'
    ) AND NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'silver_guajiranet'
          AND table_name = 'stg_fact_facturacion'
          AND column_name = 'pos'
    ) THEN
        DROP TABLE silver_guajiranet.stg_fact_facturacion CASCADE;
        RAISE NOTICE 'DROP stg_fact_facturacion (modelo viejo). Re-ejecutar 03.';
    ELSE
        RAISE NOTICE 'Skip DROP stg_fact_facturacion: no hay modelo viejo (o ya es nuevo).';
    END IF;
END
$$;

-- Cartera vieja: sk_cliente y sin idsuc.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'silver_guajiranet'
          AND table_name = 'tbl_fact_cartera'
          AND column_name = 'sk_cliente'
    ) AND NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'silver_guajiranet'
          AND table_name = 'tbl_fact_cartera'
          AND column_name = 'idsuc'
    ) THEN
        DROP TABLE silver_guajiranet.tbl_fact_cartera CASCADE;
        RAISE NOTICE 'DROP tbl_fact_cartera (modelo viejo). Re-ejecutar 02.';
    ELSE
        RAISE NOTICE 'Skip DROP tbl_fact_cartera: no hay modelo viejo (o ya es nuevo).';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'silver_guajiranet'
          AND table_name = 'stg_fact_cartera'
          AND column_name = 'sk_cliente'
    ) AND NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'silver_guajiranet'
          AND table_name = 'stg_fact_cartera'
          AND column_name = 'idsuc'
    ) THEN
        DROP TABLE silver_guajiranet.stg_fact_cartera CASCADE;
        RAISE NOTICE 'DROP stg_fact_cartera (modelo viejo). Re-ejecutar 03.';
    ELSE
        RAISE NOTICE 'Skip DROP stg_fact_cartera: no hay modelo viejo (o ya es nuevo).';
    END IF;
END
$$;

-- Sequences de geo/facts: OWNED BY la tabla. DROP TABLE las elimina.
-- NO dropear aquí por nombre: si el modelo nuevo ya existe, la sequence sigue en uso.

-- =============================================================================
-- 04_seed_unknown_members.sql
-- Miembros desconocidos SK = 0. Solo geografía y perfil cartera.
-- Insertar 0 ANTES de setval. No se usa SK 0 para contrato/plan/persona/etc.
-- Idempotente. No toca tablas con modelo viejo.
-- =============================================================================

SET search_path TO silver_guajiranet, public;

-- -----------------------------------------------------------------------------
-- Geografía SK=0 / id_barrio=0
-- Textos de seed no están en el plan; se eligen literales explícitos ISP.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_max integer;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'silver_guajiranet'
          AND table_name = 'tbl_dim_geografia'
          AND column_name = 'id_barrio'
          AND data_type = 'integer'
    ) THEN
        RAISE NOTICE
            'BLOQUEO seed geo: tbl_dim_geografia no está en el modelo nuevo. Skip.';
        RETURN;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM silver_guajiranet.tbl_dim_geografia
        WHERE sk_geografia = 0
    ) THEN
        UPDATE silver_guajiranet.tbl_dim_geografia
        SET
            id_barrio    = 0,
            barrio       = 'SIN BARRIO',
            municipio    = 'SIN MUNICIPIO',
            departamento = 'SIN DEPARTAMENTO'
        WHERE sk_geografia = 0;
    ELSIF EXISTS (
        SELECT 1
        FROM silver_guajiranet.tbl_dim_geografia
        WHERE id_barrio = 0
    ) THEN
        RAISE NOTICE
            'BLOQUEO seed geo: id_barrio=0 existe con sk_geografia <> 0. No se reasigna PK.';
    ELSE
        -- Sequence DEFAULT no aplica: SK 0 se inserta explícito (no es IDENTITY ALWAYS).
        INSERT INTO silver_guajiranet.tbl_dim_geografia (
            sk_geografia,
            id_barrio,
            barrio,
            dpto,
            mun,
            municipio,
            departamento
        ) VALUES (
            0,
            0,
            'SIN BARRIO',
            NULL,
            NULL,
            'SIN MUNICIPIO',
            'SIN DEPARTAMENTO'
        );
    END IF;

    SELECT MAX(sk_geografia) INTO v_max
    FROM silver_guajiranet.tbl_dim_geografia;

    IF v_max IS NULL OR v_max <= 0 THEN
        -- Próximo nextval = 1 (is_called = false).
        PERFORM setval(
            'silver_guajiranet.tbl_dim_geografia_sk_geografia_seq',
            1,
            false
        );
    ELSE
        PERFORM setval(
            'silver_guajiranet.tbl_dim_geografia_sk_geografia_seq',
            v_max,
            true
        );
    END IF;
END
$$;

-- -----------------------------------------------------------------------------
-- Perfil cartera SK=0 / id_perfil=0
-- denominacion 'DESCONOCIDO': el plan no fija el texto.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_max integer;
BEGIN
    IF to_regclass('silver_guajiranet.tbl_dim_perfil_cartera') IS NULL THEN
        RAISE NOTICE 'BLOQUEO seed perfil: tbl_dim_perfil_cartera no existe. Skip.';
        RETURN;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM silver_guajiranet.tbl_dim_perfil_cartera
        WHERE sk_perfil_cartera = 0
    ) THEN
        UPDATE silver_guajiranet.tbl_dim_perfil_cartera
        SET
            id_perfil    = 0,
            denominacion = 'DESCONOCIDO'
        WHERE sk_perfil_cartera = 0;
    ELSIF EXISTS (
        SELECT 1
        FROM silver_guajiranet.tbl_dim_perfil_cartera
        WHERE id_perfil = 0
    ) THEN
        RAISE NOTICE
            'BLOQUEO seed perfil: id_perfil=0 existe con sk_perfil_cartera <> 0. No se reasigna PK.';
    ELSE
        INSERT INTO silver_guajiranet.tbl_dim_perfil_cartera (
            sk_perfil_cartera,
            id_perfil,
            denominacion,
            diasvence1,
            diasvence2,
            deshabilitar,
            alertar,
            diasvencefactura,
            nofactura
        ) VALUES (
            0,
            0,
            'DESCONOCIDO',
            NULL,
            NULL,
            NULL,
            NULL,
            NULL,
            NULL
        );
    END IF;

    SELECT MAX(sk_perfil_cartera) INTO v_max
    FROM silver_guajiranet.tbl_dim_perfil_cartera;

    IF v_max IS NULL OR v_max <= 0 THEN
        PERFORM setval(
            'silver_guajiranet.tbl_dim_perfil_cartera_sk_perfil_cartera_seq',
            1,
            false
        );
    ELSE
        PERFORM setval(
            'silver_guajiranet.tbl_dim_perfil_cartera_sk_perfil_cartera_seq',
            v_max,
            true
        );
    END IF;
END
$$;

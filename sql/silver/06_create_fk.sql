-- =============================================================================
-- 06_create_fk.sql
-- FK Silver NOT VALID. Ejecutar DESPUÉS de la primera carga (plan §7–8).
-- Idempotente. Si el fact/geo aún es modelo viejo, se omite esa FK (NOTICE).
-- No VALIDATE aquí: evita ACCESS EXCLUSIVE largo en el cutover.
-- =============================================================================

SET search_path TO silver_guajiranet, public;

CREATE OR REPLACE FUNCTION silver_guajiranet._add_fk_not_valid(
    p_table     text,
    p_conname   text,
    p_column    text,
    p_reftable  text,
    p_refcolumn text
) RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF to_regclass(format('silver_guajiranet.%I', p_table)) IS NULL THEN
        RAISE NOTICE 'Skip FK %: falta tabla %.', p_conname, p_table;
        RETURN;
    END IF;

    IF to_regclass(format('silver_guajiranet.%I', p_reftable)) IS NULL THEN
        RAISE NOTICE 'Skip FK %: falta tabla ref %.', p_conname, p_reftable;
        RETURN;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'silver_guajiranet'
          AND table_name = p_table
          AND column_name = p_column
    ) THEN
        RAISE NOTICE
            'Skip FK %: falta columna %.% (¿modelo viejo todavía?).',
            p_conname, p_table, p_column;
        RETURN;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = 'silver_guajiranet'
          AND t.relname = p_table
          AND c.conname = p_conname
    ) THEN
        RETURN;
    END IF;

    EXECUTE format(
        'ALTER TABLE silver_guajiranet.%I
         ADD CONSTRAINT %I
         FOREIGN KEY (%I)
         REFERENCES silver_guajiranet.%I (%I)
         NOT VALID',
        p_table, p_conname, p_column, p_reftable, p_refcolumn
    );
END;
$$;

-- DIM_SUCURSAL
SELECT silver_guajiranet._add_fk_not_valid(
    'tbl_dim_sucursal', 'fk_dim_sucursal_sk_persona',
    'sk_persona', 'tbl_dim_persona', 'sk_persona');
SELECT silver_guajiranet._add_fk_not_valid(
    'tbl_dim_sucursal', 'fk_dim_sucursal_sk_geografia',
    'sk_geografia', 'tbl_dim_geografia', 'sk_geografia');
SELECT silver_guajiranet._add_fk_not_valid(
    'tbl_dim_sucursal', 'fk_dim_sucursal_sk_perfil_cartera',
    'sk_perfil_cartera', 'tbl_dim_perfil_cartera', 'sk_perfil_cartera');

-- BRIDGES
SELECT silver_guajiranet._add_fk_not_valid(
    'tbl_brg_persona_uuid', 'fk_brg_persona_uuid_sk_persona',
    'sk_persona', 'tbl_dim_persona', 'sk_persona');
SELECT silver_guajiranet._add_fk_not_valid(
    'tbl_brg_sucursal_contrato', 'fk_brg_sucursal_contrato_sk_sucursal',
    'sk_sucursal', 'tbl_dim_sucursal', 'sk_sucursal');
SELECT silver_guajiranet._add_fk_not_valid(
    'tbl_brg_sucursal_contrato', 'fk_brg_sucursal_contrato_sk_contrato',
    'sk_contrato', 'tbl_dim_contrato', 'sk_contrato');
SELECT silver_guajiranet._add_fk_not_valid(
    'tbl_brg_contrato_plan', 'fk_brg_contrato_plan_sk_contrato',
    'sk_contrato', 'tbl_dim_contrato', 'sk_contrato');
SELECT silver_guajiranet._add_fk_not_valid(
    'tbl_brg_contrato_plan', 'fk_brg_contrato_plan_sk_plan',
    'sk_plan', 'tbl_dim_plan', 'sk_plan');

-- FACT_FACTURACION (sk_contrato / sk_plan nullable; carga actual = NULL)
SELECT silver_guajiranet._add_fk_not_valid(
    'tbl_fact_facturacion', 'fk_fact_facturacion_sk_sucursal',
    'sk_sucursal', 'tbl_dim_sucursal', 'sk_sucursal');
SELECT silver_guajiranet._add_fk_not_valid(
    'tbl_fact_facturacion', 'fk_fact_facturacion_sk_persona',
    'sk_persona', 'tbl_dim_persona', 'sk_persona');
SELECT silver_guajiranet._add_fk_not_valid(
    'tbl_fact_facturacion', 'fk_fact_facturacion_sk_producto',
    'sk_producto', 'tbl_dim_producto_erp', 'sk_producto');
SELECT silver_guajiranet._add_fk_not_valid(
    'tbl_fact_facturacion', 'fk_fact_facturacion_sk_documento',
    'sk_documento', 'tbl_dim_documento', 'sk_documento');
SELECT silver_guajiranet._add_fk_not_valid(
    'tbl_fact_facturacion', 'fk_fact_facturacion_sk_geografia',
    'sk_geografia', 'tbl_dim_geografia', 'sk_geografia');
SELECT silver_guajiranet._add_fk_not_valid(
    'tbl_fact_facturacion', 'fk_fact_facturacion_sk_tiempo',
    'sk_tiempo', 'tbl_dim_tiempo', 'sk_tiempo');
SELECT silver_guajiranet._add_fk_not_valid(
    'tbl_fact_facturacion', 'fk_fact_facturacion_sk_contrato',
    'sk_contrato', 'tbl_dim_contrato', 'sk_contrato');
SELECT silver_guajiranet._add_fk_not_valid(
    'tbl_fact_facturacion', 'fk_fact_facturacion_sk_plan',
    'sk_plan', 'tbl_dim_plan', 'sk_plan');

-- FACT_CARTERA
SELECT silver_guajiranet._add_fk_not_valid(
    'tbl_fact_cartera', 'fk_fact_cartera_sk_sucursal',
    'sk_sucursal', 'tbl_dim_sucursal', 'sk_sucursal');
SELECT silver_guajiranet._add_fk_not_valid(
    'tbl_fact_cartera', 'fk_fact_cartera_sk_persona',
    'sk_persona', 'tbl_dim_persona', 'sk_persona');
SELECT silver_guajiranet._add_fk_not_valid(
    'tbl_fact_cartera', 'fk_fact_cartera_sk_tiempo',
    'sk_tiempo', 'tbl_dim_tiempo', 'sk_tiempo');
SELECT silver_guajiranet._add_fk_not_valid(
    'tbl_fact_cartera', 'fk_fact_cartera_sk_perfil_cartera',
    'sk_perfil_cartera', 'tbl_dim_perfil_cartera', 'sk_perfil_cartera');

-- FACT_PAGO_APLICACION
SELECT silver_guajiranet._add_fk_not_valid(
    'tbl_fact_pago_aplicacion', 'fk_fact_pago_aplicacion_sk_sucursal',
    'sk_sucursal', 'tbl_dim_sucursal', 'sk_sucursal');
SELECT silver_guajiranet._add_fk_not_valid(
    'tbl_fact_pago_aplicacion', 'fk_fact_pago_aplicacion_sk_persona',
    'sk_persona', 'tbl_dim_persona', 'sk_persona');
SELECT silver_guajiranet._add_fk_not_valid(
    'tbl_fact_pago_aplicacion', 'fk_fact_pago_aplicacion_sk_documento',
    'sk_documento', 'tbl_dim_documento', 'sk_documento');
SELECT silver_guajiranet._add_fk_not_valid(
    'tbl_fact_pago_aplicacion', 'fk_fact_pago_aplicacion_sk_tiempo_factura',
    'sk_tiempo_factura', 'tbl_dim_tiempo', 'sk_tiempo');
SELECT silver_guajiranet._add_fk_not_valid(
    'tbl_fact_pago_aplicacion', 'fk_fact_pago_aplicacion_sk_tiempo_recibo',
    'sk_tiempo_recibo', 'tbl_dim_tiempo', 'sk_tiempo');

-- FACT_PAGO_PASARELA
SELECT silver_guajiranet._add_fk_not_valid(
    'tbl_fact_pago_pasarela', 'fk_fact_pago_pasarela_sk_sucursal',
    'sk_sucursal', 'tbl_dim_sucursal', 'sk_sucursal');
SELECT silver_guajiranet._add_fk_not_valid(
    'tbl_fact_pago_pasarela', 'fk_fact_pago_pasarela_sk_persona',
    'sk_persona', 'tbl_dim_persona', 'sk_persona');
SELECT silver_guajiranet._add_fk_not_valid(
    'tbl_fact_pago_pasarela', 'fk_fact_pago_pasarela_sk_tiempo',
    'sk_tiempo', 'tbl_dim_tiempo', 'sk_tiempo');

DROP FUNCTION silver_guajiranet._add_fk_not_valid(text, text, text, text, text);

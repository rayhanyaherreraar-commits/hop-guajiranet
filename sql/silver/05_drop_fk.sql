-- =============================================================================
-- 05_drop_fk.sql
-- Quita las FK Silver definidas en 06_create_fk.sql.
-- Idempotente: DROP CONSTRAINT IF EXISTS.
-- Hoy Aurora no tiene FK Silver; este script queda listo para el ciclo
-- drop → carga → 06 (NOT VALID) sin copiar wf_delta Bronze.
-- =============================================================================

SET search_path TO silver_guajiranet, public;

ALTER TABLE IF EXISTS silver_guajiranet.tbl_dim_sucursal
    DROP CONSTRAINT IF EXISTS fk_dim_sucursal_sk_persona;

ALTER TABLE IF EXISTS silver_guajiranet.tbl_dim_sucursal
    DROP CONSTRAINT IF EXISTS fk_dim_sucursal_sk_geografia;

ALTER TABLE IF EXISTS silver_guajiranet.tbl_dim_sucursal
    DROP CONSTRAINT IF EXISTS fk_dim_sucursal_sk_perfil_cartera;

ALTER TABLE IF EXISTS silver_guajiranet.tbl_brg_persona_uuid
    DROP CONSTRAINT IF EXISTS fk_brg_persona_uuid_sk_persona;

ALTER TABLE IF EXISTS silver_guajiranet.tbl_brg_sucursal_contrato
    DROP CONSTRAINT IF EXISTS fk_brg_sucursal_contrato_sk_sucursal;

ALTER TABLE IF EXISTS silver_guajiranet.tbl_brg_sucursal_contrato
    DROP CONSTRAINT IF EXISTS fk_brg_sucursal_contrato_sk_contrato;

ALTER TABLE IF EXISTS silver_guajiranet.tbl_brg_contrato_plan
    DROP CONSTRAINT IF EXISTS fk_brg_contrato_plan_sk_contrato;

ALTER TABLE IF EXISTS silver_guajiranet.tbl_brg_contrato_plan
    DROP CONSTRAINT IF EXISTS fk_brg_contrato_plan_sk_plan;

ALTER TABLE IF EXISTS silver_guajiranet.tbl_fact_facturacion
    DROP CONSTRAINT IF EXISTS fk_fact_facturacion_sk_sucursal;

ALTER TABLE IF EXISTS silver_guajiranet.tbl_fact_facturacion
    DROP CONSTRAINT IF EXISTS fk_fact_facturacion_sk_persona;

ALTER TABLE IF EXISTS silver_guajiranet.tbl_fact_facturacion
    DROP CONSTRAINT IF EXISTS fk_fact_facturacion_sk_producto;

ALTER TABLE IF EXISTS silver_guajiranet.tbl_fact_facturacion
    DROP CONSTRAINT IF EXISTS fk_fact_facturacion_sk_documento;

ALTER TABLE IF EXISTS silver_guajiranet.tbl_fact_facturacion
    DROP CONSTRAINT IF EXISTS fk_fact_facturacion_sk_geografia;

ALTER TABLE IF EXISTS silver_guajiranet.tbl_fact_facturacion
    DROP CONSTRAINT IF EXISTS fk_fact_facturacion_sk_tiempo;

ALTER TABLE IF EXISTS silver_guajiranet.tbl_fact_facturacion
    DROP CONSTRAINT IF EXISTS fk_fact_facturacion_sk_contrato;

ALTER TABLE IF EXISTS silver_guajiranet.tbl_fact_facturacion
    DROP CONSTRAINT IF EXISTS fk_fact_facturacion_sk_plan;

ALTER TABLE IF EXISTS silver_guajiranet.tbl_fact_cartera
    DROP CONSTRAINT IF EXISTS fk_fact_cartera_sk_sucursal;

ALTER TABLE IF EXISTS silver_guajiranet.tbl_fact_cartera
    DROP CONSTRAINT IF EXISTS fk_fact_cartera_sk_persona;

ALTER TABLE IF EXISTS silver_guajiranet.tbl_fact_cartera
    DROP CONSTRAINT IF EXISTS fk_fact_cartera_sk_tiempo;

ALTER TABLE IF EXISTS silver_guajiranet.tbl_fact_cartera
    DROP CONSTRAINT IF EXISTS fk_fact_cartera_sk_perfil_cartera;

ALTER TABLE IF EXISTS silver_guajiranet.tbl_fact_pago_aplicacion
    DROP CONSTRAINT IF EXISTS fk_fact_pago_aplicacion_sk_sucursal;

ALTER TABLE IF EXISTS silver_guajiranet.tbl_fact_pago_aplicacion
    DROP CONSTRAINT IF EXISTS fk_fact_pago_aplicacion_sk_persona;

ALTER TABLE IF EXISTS silver_guajiranet.tbl_fact_pago_aplicacion
    DROP CONSTRAINT IF EXISTS fk_fact_pago_aplicacion_sk_documento;

ALTER TABLE IF EXISTS silver_guajiranet.tbl_fact_pago_aplicacion
    DROP CONSTRAINT IF EXISTS fk_fact_pago_aplicacion_sk_tiempo_factura;

ALTER TABLE IF EXISTS silver_guajiranet.tbl_fact_pago_aplicacion
    DROP CONSTRAINT IF EXISTS fk_fact_pago_aplicacion_sk_tiempo_recibo;

ALTER TABLE IF EXISTS silver_guajiranet.tbl_fact_pago_pasarela
    DROP CONSTRAINT IF EXISTS fk_fact_pago_pasarela_sk_sucursal;

ALTER TABLE IF EXISTS silver_guajiranet.tbl_fact_pago_pasarela
    DROP CONSTRAINT IF EXISTS fk_fact_pago_pasarela_sk_persona;

ALTER TABLE IF EXISTS silver_guajiranet.tbl_fact_pago_pasarela
    DROP CONSTRAINT IF EXISTS fk_fact_pago_pasarela_sk_tiempo;

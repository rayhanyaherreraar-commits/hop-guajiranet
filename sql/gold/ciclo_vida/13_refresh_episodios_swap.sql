-- =============================================================================
-- 13_refresh_episodios_swap.sql
-- Refresh operativo post Silver v2 de tbl_anl_episodios_ciclo_vida_cliente.
-- Mantiene vw_anl_episodios_ciclo_vida_cliente como fuente de verdad y publica
-- el nuevo snapshot mediante un swap atomico dentro de una transaccion.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

SET LOCAL statement_timeout = '40min';
SET LOCAL lock_timeout = '5min';

-- Evita dos refresh simultaneos incluso si se invocan desde hosts distintos.
SELECT pg_advisory_xact_lock(
    hashtextextended('gold_guajiranet.tbl_anl_episodios_ciclo_vida_cliente', 0)
);

DO $precheck$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'gold_guajiranet'
          AND c.relname = 'vw_anl_episodios_ciclo_vida_cliente'
          AND c.relkind = 'v'
    ) THEN
        RAISE EXCEPTION 'La fuente Gold esperada no existe o no es una VIEW';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'gold_guajiranet'
          AND c.relname = 'tbl_anl_episodios_ciclo_vida_cliente'
          AND c.relkind = 'r'
    ) THEN
        RAISE EXCEPTION 'El snapshot esperado no existe o no es una TABLE';
    END IF;
END
$precheck$;

DROP TABLE IF EXISTS gold_guajiranet.tbl_anl_episodios_ciclo_vida_cliente_new;
DROP TABLE IF EXISTS gold_guajiranet.tbl_anl_episodios_ciclo_vida_cliente_old;

CREATE TABLE gold_guajiranet.tbl_anl_episodios_ciclo_vida_cliente_new AS
SELECT *
FROM gold_guajiranet.vw_anl_episodios_ciclo_vida_cliente;

CREATE UNIQUE INDEX uq_tbl_anl_episodios_ciclo_vida_cliente_new
    ON gold_guajiranet.tbl_anl_episodios_ciclo_vida_cliente_new (sk_cliente, numero_episodio);

CREATE INDEX idx_tbl_anl_episodios_ciclo_vida_cliente_new_sk
    ON gold_guajiranet.tbl_anl_episodios_ciclo_vida_cliente_new (sk_cliente);

ANALYZE gold_guajiranet.tbl_anl_episodios_ciclo_vida_cliente_new;

DO $validate$
DECLARE
    new_rows bigint;
    column_differences bigint;
BEGIN
    SELECT count(*)
    INTO new_rows
    FROM gold_guajiranet.tbl_anl_episodios_ciclo_vida_cliente_new;

    IF new_rows = 0 THEN
        RAISE EXCEPTION 'El refresh produjo cero filas; se conserva el snapshot anterior';
    END IF;

    SELECT count(*)
    INTO column_differences
    FROM (
        WITH view_columns AS (
            SELECT ordinal_position, column_name, data_type, udt_name
            FROM information_schema.columns
            WHERE table_schema = 'gold_guajiranet'
              AND table_name = 'vw_anl_episodios_ciclo_vida_cliente'
        ), new_columns AS (
            SELECT ordinal_position, column_name, data_type, udt_name
            FROM information_schema.columns
            WHERE table_schema = 'gold_guajiranet'
              AND table_name = 'tbl_anl_episodios_ciclo_vida_cliente_new'
        )
        SELECT 1
        FROM view_columns v
        FULL JOIN new_columns n USING (ordinal_position)
        WHERE (v.column_name, v.data_type, v.udt_name)
              IS DISTINCT FROM
              (n.column_name, n.data_type, n.udt_name)
    ) differences;

    IF column_differences <> 0 THEN
        RAISE EXCEPTION 'Las columnas del snapshot no coinciden con la VIEW (% diferencias)', column_differences;
    END IF;

    RAISE NOTICE 'Snapshot validado: % filas, columnas identicas a la VIEW', new_rows;
END
$validate$;

ALTER TABLE gold_guajiranet.tbl_anl_episodios_ciclo_vida_cliente
    RENAME TO tbl_anl_episodios_ciclo_vida_cliente_old;

ALTER TABLE gold_guajiranet.tbl_anl_episodios_ciclo_vida_cliente_new
    RENAME TO tbl_anl_episodios_ciclo_vida_cliente;

DROP TABLE gold_guajiranet.tbl_anl_episodios_ciclo_vida_cliente_old;

ALTER INDEX gold_guajiranet.uq_tbl_anl_episodios_ciclo_vida_cliente_new
    RENAME TO uq_tbl_anl_episodios_ciclo_vida_cliente;

ALTER INDEX gold_guajiranet.idx_tbl_anl_episodios_ciclo_vida_cliente_new_sk
    RENAME TO idx_tbl_anl_episodios_ciclo_vida_cliente_sk;

DO $comment$
BEGIN
    EXECUTE format(
        'COMMENT ON TABLE gold_guajiranet.tbl_anl_episodios_ciclo_vida_cliente IS %L',
        'Snapshot Gold de vw_anl_episodios_ciclo_vida_cliente. Refresh post Silver v2. Ultimo refresh UTC: '
        || to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
    );
END
$comment$;

COMMIT;

SELECT
    count(*) AS snapshot_rows,
    obj_description(
        'gold_guajiranet.tbl_anl_episodios_ciclo_vida_cliente'::regclass,
        'pg_class'
    ) AS refresh_status
FROM gold_guajiranet.tbl_anl_episodios_ciclo_vida_cliente;

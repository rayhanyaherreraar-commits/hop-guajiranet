-- =============================================================================
-- silver_preflight.sql
-- SOLO LECTURA. No DDL. No DML. No setval. No Aurora desde esta Fase 4.
-- Esquemas: silver_guajiranet, gold_guajiranet.
-- information_schema / pg_catalog / SELECT COUNT sobre tablas KEEP/COLLIDE.
-- NO ejecutar en esta fase.
-- =============================================================================

SET search_path TO silver_guajiranet, public;

-- -----------------------------------------------------------------------------
-- 0. Inventario esperado vs catálogo
-- -----------------------------------------------------------------------------
SELECT
    e.clase,
    e.script,
    e.table_name,
    CASE WHEN n.oid IS NULL THEN 'AUSENTE' ELSE 'EXISTE' END AS en_catalogo,
    c.relkind,
    c.reltuples::bigint AS estimate_reltuples
FROM (VALUES
        ('KEEP',    '01', 'tbl_dim_tiempo'),
        ('KEEP',    '01', 'tbl_dim_documento'),
        ('KEEP',    '03', 'stg_dim_tiempo'),
        ('KEEP',    '03', 'stg_dim_documento'),
        ('NEW',     '01', 'tbl_dim_persona'),
        ('NEW',     '01', 'tbl_dim_sucursal'),
        ('NEW',     '01', 'tbl_dim_contrato'),
        ('NEW',     '01', 'tbl_dim_plan'),
        ('NEW',     '01', 'tbl_dim_producto_erp'),
        ('NEW',     '01', 'tbl_dim_perfil_cartera'),
        ('NEW',     '02', 'tbl_brg_persona_uuid'),
        ('NEW',     '02', 'tbl_brg_sucursal_contrato'),
        ('NEW',     '02', 'tbl_brg_contrato_plan'),
        ('NEW',     '02', 'tbl_fact_pago_aplicacion'),
        ('NEW',     '02', 'tbl_fact_pago_pasarela'),
        ('NEW',     '03', 'stg_dim_persona'),
        ('NEW',     '03', 'stg_dim_sucursal'),
        ('NEW',     '03', 'stg_dim_contrato'),
        ('NEW',     '03', 'stg_dim_plan'),
        ('NEW',     '03', 'stg_dim_producto_erp'),
        ('NEW',     '03', 'stg_dim_perfil_cartera'),
        ('NEW',     '03', 'stg_brg_persona_uuid'),
        ('NEW',     '03', 'stg_brg_sucursal_contrato'),
        ('NEW',     '03', 'stg_brg_contrato_plan'),
        ('NEW',     '03', 'stg_fact_pago_aplicacion'),
        ('NEW',     '03', 'stg_fact_pago_pasarela'),
        ('COLLIDE', '01', 'tbl_dim_geografia'),
        ('COLLIDE', '03', 'stg_dim_geografia'),
        ('COLLIDE', '02', 'tbl_fact_facturacion'),
        ('COLLIDE', '03', 'stg_fact_facturacion'),
        ('COLLIDE', '02', 'tbl_fact_cartera'),
        ('COLLIDE', '03', 'stg_fact_cartera'),
        ('UNTOUCH', '-',  'tbl_dim_cliente'),
        ('UNTOUCH', '-',  'tbl_dim_servicio'),
        ('UNTOUCH', '-',  'stg_dim_cliente'),
        ('UNTOUCH', '-',  'stg_dim_servicio')
) AS e(clase, script, table_name)
LEFT JOIN pg_class c
       ON c.relname = e.table_name
      AND c.relkind IN ('r', 'p')
LEFT JOIN pg_namespace n
       ON n.oid = c.relnamespace
      AND n.nspname = 'silver_guajiranet'
ORDER BY
    CASE e.clase
        WHEN 'KEEP' THEN 1
        WHEN 'NEW' THEN 2
        WHEN 'COLLIDE' THEN 3
        ELSE 4
    END,
    e.table_name;

-- -----------------------------------------------------------------------------
-- 1. Tablas nuevas (CREATE IF NOT EXISTS)
-- -----------------------------------------------------------------------------
SELECT
    t.table_name,
    CASE
        WHEN n.oid IS NULL THEN 'AUSENTE — 01/02/03 CREATE IF NOT EXISTS'
        ELSE 'EXISTE — IF NOT EXISTS no-op'
    END AS estado
FROM (VALUES
    ('tbl_dim_persona'),
    ('tbl_dim_sucursal'),
    ('tbl_dim_contrato'),
    ('tbl_dim_plan'),
    ('tbl_dim_producto_erp'),
    ('tbl_dim_perfil_cartera'),
    ('tbl_brg_persona_uuid'),
    ('tbl_brg_sucursal_contrato'),
    ('tbl_brg_contrato_plan'),
    ('tbl_fact_pago_aplicacion'),
    ('tbl_fact_pago_pasarela'),
    ('stg_dim_persona'),
    ('stg_dim_sucursal'),
    ('stg_dim_contrato'),
    ('stg_dim_plan'),
    ('stg_dim_producto_erp'),
    ('stg_dim_perfil_cartera'),
    ('stg_brg_persona_uuid'),
    ('stg_brg_sucursal_contrato'),
    ('stg_brg_contrato_plan'),
    ('stg_fact_pago_aplicacion'),
    ('stg_fact_pago_pasarela')
) AS t(table_name)
LEFT JOIN pg_class c
       ON c.relname = t.table_name
      AND c.relkind IN ('r', 'p')
LEFT JOIN pg_namespace n
       ON n.oid = c.relnamespace
      AND n.nspname = 'silver_guajiranet'
ORDER BY t.table_name;

-- -----------------------------------------------------------------------------
-- 2. Tablas viejas que bloquean (mismo nombre)
-- -----------------------------------------------------------------------------
SELECT
    t.table_name,
    CASE
        WHEN n.oid IS NULL THEN 'LIBRE — script CREARÁ el modelo nuevo'
        ELSE 'OCUPADA — RAISE NOTICE BLOQUEO; no CREATE; no DROP'
    END AS bloqueo,
    c.reltuples::bigint AS estimate_reltuples
FROM (VALUES
    ('tbl_dim_geografia'),
    ('stg_dim_geografia'),
    ('tbl_fact_facturacion'),
    ('stg_fact_facturacion'),
    ('tbl_fact_cartera'),
    ('stg_fact_cartera')
) AS t(table_name)
LEFT JOIN pg_class c
       ON c.relname = t.table_name
      AND c.relkind IN ('r', 'p')
LEFT JOIN pg_namespace n
       ON n.oid = c.relnamespace
      AND n.nspname = 'silver_guajiranet'
ORDER BY t.table_name;

-- -----------------------------------------------------------------------------
-- 3. Columnas y tipos
-- -----------------------------------------------------------------------------
SELECT
    c.table_name,
    c.ordinal_position,
    c.column_name,
    c.data_type,
    c.udt_name,
    c.character_maximum_length,
    c.numeric_precision,
    c.numeric_scale,
    c.is_nullable,
    c.column_default
FROM information_schema.columns c
WHERE c.table_schema = 'silver_guajiranet'
  AND c.table_name IN (
        'tbl_dim_tiempo', 'tbl_dim_documento',
        'tbl_dim_geografia', 'stg_dim_geografia',
        'tbl_fact_facturacion', 'stg_fact_facturacion',
        'tbl_fact_cartera', 'stg_fact_cartera',
        'tbl_dim_cliente', 'tbl_dim_servicio',
        'stg_dim_cliente', 'stg_dim_servicio',
        'stg_dim_tiempo', 'stg_dim_documento',
        'tbl_dim_persona', 'tbl_dim_sucursal',
        'tbl_dim_contrato', 'tbl_dim_plan',
        'tbl_dim_producto_erp', 'tbl_dim_perfil_cartera',
        'tbl_brg_persona_uuid', 'tbl_brg_sucursal_contrato',
        'tbl_brg_contrato_plan',
        'tbl_fact_pago_aplicacion', 'tbl_fact_pago_pasarela'
  )
ORDER BY c.table_name, c.ordinal_position;

-- Detectores modelo viejo vs nuevo (los que usan 01/02/03)
SELECT
    t.table_name,
    (SELECT c.data_type
       FROM information_schema.columns c
      WHERE c.table_schema = 'silver_guajiranet'
        AND c.table_name = t.table_name
        AND c.column_name = 'id_barrio') AS id_barrio_tipo,
    EXISTS (SELECT 1 FROM information_schema.columns c
            WHERE c.table_schema = 'silver_guajiranet'
              AND c.table_name = t.table_name AND c.column_name = 'zona') AS tiene_zona,
    EXISTS (SELECT 1 FROM information_schema.columns c
            WHERE c.table_schema = 'silver_guajiranet'
              AND c.table_name = t.table_name AND c.column_name = 'dpto') AS tiene_dpto,
    EXISTS (SELECT 1 FROM information_schema.columns c
            WHERE c.table_schema = 'silver_guajiranet'
              AND c.table_name = t.table_name AND c.column_name = 'posicion_factura') AS tiene_posicion_factura,
    EXISTS (SELECT 1 FROM information_schema.columns c
            WHERE c.table_schema = 'silver_guajiranet'
              AND c.table_name = t.table_name AND c.column_name = 'pos') AS tiene_pos,
    EXISTS (SELECT 1 FROM information_schema.columns c
            WHERE c.table_schema = 'silver_guajiranet'
              AND c.table_name = t.table_name AND c.column_name = 'sk_cliente') AS tiene_sk_cliente,
    EXISTS (SELECT 1 FROM information_schema.columns c
            WHERE c.table_schema = 'silver_guajiranet'
              AND c.table_name = t.table_name AND c.column_name = 'sk_sucursal') AS tiene_sk_sucursal,
    EXISTS (SELECT 1 FROM information_schema.columns c
            WHERE c.table_schema = 'silver_guajiranet'
              AND c.table_name = t.table_name AND c.column_name = 'idsuc') AS tiene_idsuc,
    EXISTS (SELECT 1 FROM information_schema.columns c
            WHERE c.table_schema = 'silver_guajiranet'
              AND c.table_name = t.table_name AND c.column_name = 'sk_contrato') AS tiene_sk_contrato
FROM (VALUES
    ('tbl_dim_geografia'),
    ('stg_dim_geografia'),
    ('tbl_fact_facturacion'),
    ('stg_fact_facturacion'),
    ('tbl_fact_cartera'),
    ('stg_fact_cartera')
) AS t(table_name);

-- KEEP tiempo: constraints actuales
SELECT
    n.nspname AS schema_name,
    t.relname AS table_name,
    c.conname,
    c.contype,
    pg_get_constraintdef(c.oid) AS definicion
FROM pg_constraint c
JOIN pg_class t ON t.oid = c.conrelid
JOIN pg_namespace n ON n.oid = t.relnamespace
WHERE n.nspname = 'silver_guajiranet'
  AND t.relname IN ('tbl_dim_tiempo', 'tbl_dim_documento')
ORDER BY t.relname, c.conname;

-- Riesgo ADD UNIQUE(fecha) / CHECK SK=YYYYMMDD en 01 (SELECT; no ALTER)
SELECT
    COUNT(*) AS filas_tiempo,
    COUNT(DISTINCT fecha) AS fechas_distintas,
    COUNT(*) - COUNT(DISTINCT fecha) AS duplicados_fecha,
    COUNT(*) FILTER (
        WHERE sk_tiempo IS DISTINCT FROM to_char(fecha, 'YYYYMMDD')::integer
    ) AS filas_fuera_de_check_sk
FROM silver_guajiranet.tbl_dim_tiempo;

-- -----------------------------------------------------------------------------
-- 4. PK / UNIQUE
-- -----------------------------------------------------------------------------
SELECT
    n.nspname AS schema_name,
    t.relname AS table_name,
    c.conname,
    CASE c.contype
        WHEN 'p' THEN 'PRIMARY KEY'
        WHEN 'u' THEN 'UNIQUE'
        ELSE c.contype::text
    END AS tipo,
    pg_get_constraintdef(c.oid) AS definicion
FROM pg_constraint c
JOIN pg_class t ON t.oid = c.conrelid
JOIN pg_namespace n ON n.oid = t.relnamespace
WHERE n.nspname = 'silver_guajiranet'
  AND c.contype IN ('p', 'u')
ORDER BY t.relname, c.contype, c.conname;

SELECT
    n.nspname,
    t.relname AS table_name,
    i.relname AS index_name,
    ix.indisunique,
    ix.indisprimary,
    pg_get_indexdef(ix.indexrelid) AS definicion
FROM pg_index ix
JOIN pg_class t ON t.oid = ix.indrelid
JOIN pg_class i ON i.oid = ix.indexrelid
JOIN pg_namespace n ON n.oid = t.relnamespace
WHERE n.nspname = 'silver_guajiranet'
  AND ix.indisunique
ORDER BY t.relname, i.relname;

-- -----------------------------------------------------------------------------
-- 5. Sequences (nombres reales de 01/02)
-- -----------------------------------------------------------------------------
SELECT
    n.nspname AS schema_name,
    c.relname AS sequence_name
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'silver_guajiranet'
  AND c.relkind = 'S'
ORDER BY c.relname;

SELECT
    s.sequence_schema,
    s.sequence_name,
    s.data_type,
    s.start_value,
    s.minimum_value,
    s.maximum_value,
    s.increment
FROM information_schema.sequences s
WHERE s.sequence_schema = 'silver_guajiranet'
ORDER BY s.sequence_name;

SELECT
    d.classid::regclass AS classid,
    n.nspname AS seq_schema,
    seq.relname AS sequence_name,
    nt.nspname AS table_schema,
    tbl.relname AS table_name,
    a.attname AS column_name
FROM pg_depend d
JOIN pg_class seq ON seq.oid = d.objid AND seq.relkind = 'S'
JOIN pg_namespace n ON n.oid = seq.relnamespace
JOIN pg_class tbl ON tbl.oid = d.refobjid
JOIN pg_namespace nt ON nt.oid = tbl.relnamespace
JOIN pg_attribute a
       ON a.attrelid = tbl.oid
      AND a.attnum = d.refobjsubid
WHERE n.nspname = 'silver_guajiranet'
  AND d.deptype IN ('a', 'i')
ORDER BY seq.relname;

SELECT
    seq.sequence_name,
    CASE
        WHEN n.oid IS NULL THEN 'AUSENTE — 01/02 CREATE SEQUENCE IF NOT EXISTS'
        ELSE 'EXISTE'
    END AS estado
FROM (VALUES
    ('tbl_dim_geografia_sk_geografia_seq'),
    ('tbl_dim_persona_sk_persona_seq'),
    ('tbl_dim_sucursal_sk_sucursal_seq'),
    ('tbl_dim_contrato_sk_contrato_seq'),
    ('tbl_dim_plan_sk_plan_seq'),
    ('tbl_dim_producto_erp_sk_producto_seq'),
    ('tbl_dim_perfil_cartera_sk_perfil_cartera_seq'),
    ('tbl_brg_persona_uuid_sk_brg_persona_uuid_seq'),
    ('tbl_brg_sucursal_contrato_sk_brg_sucursal_contrato_seq'),
    ('tbl_brg_contrato_plan_sk_brg_contrato_plan_seq'),
    ('tbl_fact_pago_aplicacion_sk_fact_pago_aplicacion_seq'),
    ('tbl_fact_pago_pasarela_sk_fact_pago_pasarela_seq'),
    ('tbl_fact_facturacion_sk_fact_facturacion_seq'),
    ('tbl_fact_cartera_sk_fact_cartera_seq')
) AS seq(sequence_name)
LEFT JOIN pg_class c
       ON c.relname = seq.sequence_name
      AND c.relkind = 'S'
LEFT JOIN pg_namespace n
       ON n.oid = c.relnamespace
      AND n.nspname = 'silver_guajiranet'
ORDER BY seq.sequence_name;

-- -----------------------------------------------------------------------------
-- 6. Índices
-- -----------------------------------------------------------------------------
SELECT
    n.nspname AS schema_name,
    t.relname AS table_name,
    i.relname AS index_name,
    ix.indisunique,
    ix.indisprimary,
    pg_get_indexdef(ix.indexrelid) AS definicion
FROM pg_index ix
JOIN pg_class t ON t.oid = ix.indrelid
JOIN pg_class i ON i.oid = ix.indexrelid
JOIN pg_namespace n ON n.oid = t.relnamespace
WHERE n.nspname = 'silver_guajiranet'
ORDER BY t.relname, i.relname;

SELECT
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM pg_class i
            JOIN pg_namespace n ON n.oid = i.relnamespace
            WHERE n.nspname = 'silver_guajiranet'
              AND i.relname = 'idx_dim_documento_tipodoc'
        ) THEN 'EXISTE idx_dim_documento_tipodoc'
        ELSE 'AUSENTE — 01 CREATE INDEX IF NOT EXISTS'
    END AS idx_documento_tipodoc,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM pg_constraint c
            JOIN pg_class t ON t.oid = c.conrelid
            JOIN pg_namespace n ON n.oid = t.relnamespace
            WHERE n.nspname = 'silver_guajiranet'
              AND t.relname = 'tbl_dim_tiempo'
              AND c.conname = 'uq_dim_tiempo_fecha'
        ) THEN 'EXISTE uq_dim_tiempo_fecha'
        ELSE 'AUSENTE — 01 ADD CONSTRAINT (EXCEPTION → NOTICE si falla)'
    END AS uq_tiempo_fecha,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM pg_constraint c
            JOIN pg_class t ON t.oid = c.conrelid
            JOIN pg_namespace n ON n.oid = t.relnamespace
            WHERE n.nspname = 'silver_guajiranet'
              AND t.relname = 'tbl_dim_tiempo'
              AND c.conname = 'chk_dim_tiempo_sk'
        ) THEN 'EXISTE chk_dim_tiempo_sk'
        ELSE 'AUSENTE — 01 ADD CHECK (EXCEPTION → NOTICE si falla)'
    END AS chk_tiempo_sk;

-- -----------------------------------------------------------------------------
-- 7. Dependencias de vistas Gold
-- -----------------------------------------------------------------------------
SELECT
    nv.nspname AS view_schema,
    v.relname AS view_name,
    ns.nspname AS table_schema,
    t.relname AS table_name,
    d.deptype
FROM pg_depend d
JOIN pg_rewrite r ON r.oid = d.objid
JOIN pg_class v ON v.oid = r.ev_class AND v.relkind IN ('v', 'm')
JOIN pg_namespace nv ON nv.oid = v.relnamespace
JOIN pg_class t ON t.oid = d.refobjid AND t.relkind IN ('r', 'v', 'm', 'p')
JOIN pg_namespace ns ON ns.oid = t.relnamespace
WHERE nv.nspname = 'gold_guajiranet'
  AND ns.nspname = 'silver_guajiranet'
  AND d.deptype = 'n'
ORDER BY v.relname, t.relname;

SELECT
    n.nspname AS view_schema,
    c.relname AS view_name,
    pg_get_viewdef(c.oid, true) AS definicion
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'gold_guajiranet'
  AND c.relkind IN ('v', 'm')
ORDER BY c.relname;

SELECT
    n.nspname AS view_schema,
    c.relname AS view_name,
    (pg_get_viewdef(c.oid, true) ILIKE '%tbl_fact_facturacion%') AS usa_fact_facturacion,
    (pg_get_viewdef(c.oid, true) ILIKE '%tbl_fact_cartera%') AS usa_fact_cartera,
    (pg_get_viewdef(c.oid, true) ILIKE '%tbl_dim_cliente%') AS usa_dim_cliente,
    (pg_get_viewdef(c.oid, true) ILIKE '%tbl_dim_servicio%') AS usa_dim_servicio,
    (pg_get_viewdef(c.oid, true) ILIKE '%tbl_dim_geografia%') AS usa_dim_geografia
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'gold_guajiranet'
  AND c.relkind IN ('v', 'm')
ORDER BY c.relname;

-- -----------------------------------------------------------------------------
-- 8. FKs existentes + las que 06 nombraría
-- -----------------------------------------------------------------------------
SELECT
    n.nspname AS schema_name,
    t.relname AS table_name,
    c.conname,
    pg_get_constraintdef(c.oid) AS definicion,
    c.convalidated
FROM pg_constraint c
JOIN pg_class t ON t.oid = c.conrelid
JOIN pg_namespace n ON n.oid = t.relnamespace
WHERE n.nspname = 'silver_guajiranet'
  AND c.contype = 'f'
ORDER BY t.relname, c.conname;

SELECT
    fk.conname,
    fk.src_table,
    fk.src_col,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM pg_constraint c
            JOIN pg_class t ON t.oid = c.conrelid
            JOIN pg_namespace n ON n.oid = t.relnamespace
            WHERE n.nspname = 'silver_guajiranet'
              AND c.conname = fk.conname
              AND c.contype = 'f'
        ) THEN 'YA EXISTE'
        ELSE 'AUSENTE'
    END AS estado_constraint,
    CASE
        WHEN to_regclass(format('silver_guajiranet.%I', fk.src_table)) IS NULL
            THEN 'Skip 06: falta tabla origen'
        WHEN NOT EXISTS (
            SELECT 1 FROM information_schema.columns c
            WHERE c.table_schema = 'silver_guajiranet'
              AND c.table_name = fk.src_table
              AND c.column_name = fk.src_col
        ) THEN 'Skip 06: falta columna (¿modelo viejo?)'
        WHEN to_regclass(format('silver_guajiranet.%I', fk.ref_table)) IS NULL
            THEN 'Skip 06: falta tabla ref'
        ELSE '06 podría ADD NOT VALID (no ejecutar en 01-04)'
    END AS efecto_si_se_corriera_06
FROM (VALUES
    ('fk_dim_sucursal_sk_persona',               'tbl_dim_sucursal',          'sk_persona',        'tbl_dim_persona'),
    ('fk_dim_sucursal_sk_geografia',             'tbl_dim_sucursal',          'sk_geografia',      'tbl_dim_geografia'),
    ('fk_dim_sucursal_sk_perfil_cartera',        'tbl_dim_sucursal',          'sk_perfil_cartera', 'tbl_dim_perfil_cartera'),
    ('fk_brg_persona_uuid_sk_persona',           'tbl_brg_persona_uuid',      'sk_persona',        'tbl_dim_persona'),
    ('fk_brg_sucursal_contrato_sk_sucursal',     'tbl_brg_sucursal_contrato', 'sk_sucursal',       'tbl_dim_sucursal'),
    ('fk_brg_sucursal_contrato_sk_contrato',     'tbl_brg_sucursal_contrato', 'sk_contrato',       'tbl_dim_contrato'),
    ('fk_brg_contrato_plan_sk_contrato',         'tbl_brg_contrato_plan',     'sk_contrato',       'tbl_dim_contrato'),
    ('fk_brg_contrato_plan_sk_plan',             'tbl_brg_contrato_plan',     'sk_plan',           'tbl_dim_plan'),
    ('fk_fact_facturacion_sk_sucursal',          'tbl_fact_facturacion',      'sk_sucursal',       'tbl_dim_sucursal'),
    ('fk_fact_facturacion_sk_persona',           'tbl_fact_facturacion',      'sk_persona',        'tbl_dim_persona'),
    ('fk_fact_facturacion_sk_producto',          'tbl_fact_facturacion',      'sk_producto',       'tbl_dim_producto_erp'),
    ('fk_fact_facturacion_sk_documento',         'tbl_fact_facturacion',      'sk_documento',      'tbl_dim_documento'),
    ('fk_fact_facturacion_sk_geografia',         'tbl_fact_facturacion',      'sk_geografia',      'tbl_dim_geografia'),
    ('fk_fact_facturacion_sk_tiempo',            'tbl_fact_facturacion',      'sk_tiempo',         'tbl_dim_tiempo'),
    ('fk_fact_facturacion_sk_contrato',          'tbl_fact_facturacion',      'sk_contrato',       'tbl_dim_contrato'),
    ('fk_fact_facturacion_sk_plan',              'tbl_fact_facturacion',      'sk_plan',           'tbl_dim_plan'),
    ('fk_fact_cartera_sk_sucursal',              'tbl_fact_cartera',          'sk_sucursal',       'tbl_dim_sucursal'),
    ('fk_fact_cartera_sk_persona',               'tbl_fact_cartera',          'sk_persona',        'tbl_dim_persona'),
    ('fk_fact_cartera_sk_tiempo',                'tbl_fact_cartera',          'sk_tiempo',         'tbl_dim_tiempo'),
    ('fk_fact_cartera_sk_perfil_cartera',        'tbl_fact_cartera',          'sk_perfil_cartera', 'tbl_dim_perfil_cartera'),
    ('fk_fact_pago_aplicacion_sk_sucursal',      'tbl_fact_pago_aplicacion',  'sk_sucursal',       'tbl_dim_sucursal'),
    ('fk_fact_pago_aplicacion_sk_persona',       'tbl_fact_pago_aplicacion',  'sk_persona',        'tbl_dim_persona'),
    ('fk_fact_pago_aplicacion_sk_documento',     'tbl_fact_pago_aplicacion',  'sk_documento',      'tbl_dim_documento'),
    ('fk_fact_pago_aplicacion_sk_tiempo_factura','tbl_fact_pago_aplicacion',  'sk_tiempo_factura', 'tbl_dim_tiempo'),
    ('fk_fact_pago_aplicacion_sk_tiempo_recibo', 'tbl_fact_pago_aplicacion',  'sk_tiempo_recibo',  'tbl_dim_tiempo'),
    ('fk_fact_pago_pasarela_sk_sucursal',        'tbl_fact_pago_pasarela',    'sk_sucursal',       'tbl_dim_sucursal'),
    ('fk_fact_pago_pasarela_sk_persona',         'tbl_fact_pago_pasarela',    'sk_persona',        'tbl_dim_persona'),
    ('fk_fact_pago_pasarela_sk_tiempo',          'tbl_fact_pago_pasarela',    'sk_tiempo',         'tbl_dim_tiempo')
) AS fk(conname, src_table, src_col, ref_table)
ORDER BY fk.conname;

-- -----------------------------------------------------------------------------
-- 9. Conteos (catalog + COUNT de objetos que el discovery afirma existentes)
-- -----------------------------------------------------------------------------
SELECT
    n.nspname AS schema_name,
    c.relname AS table_name,
    c.reltuples::bigint AS estimate_reltuples,
    s.n_live_tup,
    s.n_dead_tup,
    s.last_analyze,
    s.last_autoanalyze
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_stat_user_tables s ON s.relid = c.oid
WHERE n.nspname = 'silver_guajiranet'
  AND c.relkind = 'r'
ORDER BY c.relname;

SELECT 'tbl_dim_tiempo' AS table_name, COUNT(*) AS n FROM silver_guajiranet.tbl_dim_tiempo
UNION ALL SELECT 'tbl_dim_documento', COUNT(*) FROM silver_guajiranet.tbl_dim_documento
UNION ALL SELECT 'tbl_dim_geografia', COUNT(*) FROM silver_guajiranet.tbl_dim_geografia
UNION ALL SELECT 'tbl_dim_cliente', COUNT(*) FROM silver_guajiranet.tbl_dim_cliente
UNION ALL SELECT 'tbl_dim_servicio', COUNT(*) FROM silver_guajiranet.tbl_dim_servicio
UNION ALL SELECT 'tbl_fact_facturacion', COUNT(*) FROM silver_guajiranet.tbl_fact_facturacion
UNION ALL SELECT 'tbl_fact_cartera', COUNT(*) FROM silver_guajiranet.tbl_fact_cartera
UNION ALL SELECT 'stg_dim_tiempo', COUNT(*) FROM silver_guajiranet.stg_dim_tiempo
UNION ALL SELECT 'stg_dim_documento', COUNT(*) FROM silver_guajiranet.stg_dim_documento
UNION ALL SELECT 'stg_dim_geografia', COUNT(*) FROM silver_guajiranet.stg_dim_geografia
UNION ALL SELECT 'stg_fact_facturacion', COUNT(*) FROM silver_guajiranet.stg_fact_facturacion
UNION ALL SELECT 'stg_fact_cartera', COUNT(*) FROM silver_guajiranet.stg_fact_cartera
UNION ALL SELECT 'stg_dim_cliente', COUNT(*) FROM silver_guajiranet.stg_dim_cliente
UNION ALL SELECT 'stg_dim_servicio', COUNT(*) FROM silver_guajiranet.stg_dim_servicio
ORDER BY 1;

SELECT
    COUNT(*) FILTER (WHERE sk_geografia = 0) AS geo_filas_sk0,
    COUNT(*) FILTER (WHERE id_barrio::text = '0') AS geo_filas_id_barrio_0
FROM silver_guajiranet.tbl_dim_geografia;

SELECT
    CASE
        WHEN EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'silver_guajiranet'
              AND table_name = 'tbl_dim_geografia'
              AND column_name = 'id_barrio'
              AND data_type IN ('integer', 'bigint', 'smallint')
        ) THEN 'id_barrio integer — 04 puede seedear geo'
        ELSE 'id_barrio no integer — 04 SKIP geo (no UPDATE/INSERT en modelo viejo)'
    END AS seed_geo_04;

-- -----------------------------------------------------------------------------
-- 10. Clasificación 01→02→03→04 (sin ejecutar esos scripts)
-- -----------------------------------------------------------------------------
SELECT 'KEEP_tbl_dim_tiempo' AS chequeo,
       CASE WHEN to_regclass('silver_guajiranet.tbl_dim_tiempo') IS NOT NULL
            THEN 'OK existe — 01 no aborta'
            ELSE 'FALLO — 01 RAISE EXCEPTION'
       END AS resultado
UNION ALL
SELECT 'KEEP_tbl_dim_documento',
       CASE WHEN to_regclass('silver_guajiranet.tbl_dim_documento') IS NOT NULL
            THEN 'OK existe — 01 no aborta'
            ELSE 'FALLO — 01 RAISE EXCEPTION'
       END
UNION ALL
SELECT 'KEEP_stg_dim_tiempo',
       CASE WHEN to_regclass('silver_guajiranet.stg_dim_tiempo') IS NOT NULL
            THEN 'OK existe — 03 no aborta'
            ELSE 'FALLO — 03 RAISE EXCEPTION'
       END
UNION ALL
SELECT 'KEEP_stg_dim_documento',
       CASE WHEN to_regclass('silver_guajiranet.stg_dim_documento') IS NOT NULL
            THEN 'OK existe — 03 no aborta'
            ELSE 'FALLO — 03 RAISE EXCEPTION'
       END
UNION ALL
SELECT 'BLOQUEO_tbl_dim_geografia',
       CASE
           WHEN to_regclass('silver_guajiranet.tbl_dim_geografia') IS NULL
               THEN 'LIBRE — 01 CREATE modelo nuevo'
           WHEN EXISTS (
               SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'silver_guajiranet'
                 AND table_name = 'tbl_dim_geografia'
                 AND column_name = 'id_barrio'
                 AND data_type = 'integer'
           ) THEN 'YA modelo nuevo'
           ELSE 'OCUPADA modelo viejo — 01 NOTICE BLOQUEO; no DROP'
       END
UNION ALL
SELECT 'BLOQUEO_stg_dim_geografia',
       CASE
           WHEN to_regclass('silver_guajiranet.stg_dim_geografia') IS NULL
               THEN 'LIBRE — 03 CREATE'
           WHEN EXISTS (
               SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'silver_guajiranet'
                 AND table_name = 'stg_dim_geografia'
                 AND column_name = 'id_barrio'
                 AND data_type = 'integer'
           ) THEN 'YA modelo nuevo'
           ELSE 'OCUPADA modelo viejo — 03 NOTICE BLOQUEO; no DROP'
       END
UNION ALL
SELECT 'BLOQUEO_tbl_fact_facturacion',
       CASE
           WHEN to_regclass('silver_guajiranet.tbl_fact_facturacion') IS NULL
               THEN 'LIBRE — 02 CREATE modelo nuevo'
           WHEN EXISTS (
               SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'silver_guajiranet'
                 AND table_name = 'tbl_fact_facturacion'
                 AND column_name = 'pos'
           ) THEN 'YA modelo nuevo'
           ELSE 'OCUPADA modelo viejo — 02 NOTICE BLOQUEO; no DROP (Gold depende)'
       END
UNION ALL
SELECT 'BLOQUEO_stg_fact_facturacion',
       CASE
           WHEN to_regclass('silver_guajiranet.stg_fact_facturacion') IS NULL
               THEN 'LIBRE — 03 CREATE'
           WHEN EXISTS (
               SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'silver_guajiranet'
                 AND table_name = 'stg_fact_facturacion'
                 AND column_name = 'pos'
           ) THEN 'YA modelo nuevo'
           ELSE 'OCUPADA modelo viejo — 03 NOTICE BLOQUEO; no DROP'
       END
UNION ALL
SELECT 'BLOQUEO_tbl_fact_cartera',
       CASE
           WHEN to_regclass('silver_guajiranet.tbl_fact_cartera') IS NULL
               THEN 'LIBRE — 02 CREATE modelo nuevo'
           WHEN EXISTS (
               SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'silver_guajiranet'
                 AND table_name = 'tbl_fact_cartera'
                 AND column_name = 'idsuc'
           ) THEN 'YA modelo nuevo'
           ELSE 'OCUPADA modelo viejo — 02 NOTICE BLOQUEO; no DROP'
       END
UNION ALL
SELECT 'BLOQUEO_stg_fact_cartera',
       CASE
           WHEN to_regclass('silver_guajiranet.stg_fact_cartera') IS NULL
               THEN 'LIBRE — 03 CREATE'
           WHEN EXISTS (
               SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'silver_guajiranet'
                 AND table_name = 'stg_fact_cartera'
                 AND column_name = 'idsuc'
           ) THEN 'YA modelo nuevo'
           ELSE 'OCUPADA modelo viejo — 03 NOTICE BLOQUEO; no DROP'
       END
UNION ALL
SELECT 'UNTOUCH_tbl_dim_cliente',
       CASE WHEN to_regclass('silver_guajiranet.tbl_dim_cliente') IS NOT NULL
            THEN 'EXISTE — 01–04 no la nombran (no DROP)'
            ELSE 'AUSENTE'
       END
UNION ALL
SELECT 'UNTOUCH_tbl_dim_servicio',
       CASE WHEN to_regclass('silver_guajiranet.tbl_dim_servicio') IS NOT NULL
            THEN 'EXISTE — 01–04 no la nombran (no DROP)'
            ELSE 'AUSENTE'
       END
UNION ALL
SELECT 'DROP_TABLE_en_01_04',
       'NO — los scripts 01–04 no contienen DROP TABLE / TRUNCATE'
UNION ALL
SELECT '06_en_esta_tanda',
       'NO — 06 es post-carga; no forma parte de 01→04';

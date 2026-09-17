#!/usr/bin/env python3
"""Refresca y valida el snapshot Gold de episodios de ciclo de vida."""

from __future__ import annotations

import argparse
import os
from pathlib import Path

import psycopg2
from dotenv import load_dotenv


VIEW = "gold_guajiranet.vw_anl_episodios_ciclo_vida_cliente"
TABLE = "gold_guajiranet.tbl_anl_episodios_ciclo_vida_cliente"


def env_value(*names: str, default: str | None = None) -> str | None:
    for name in names:
        value = os.environ.get(name)
        if value:
            return value
    return default


def connect():
    settings = {
        "host": env_value("PGHOST", "DB_HOST", "AURORA_HOST"),
        "port": env_value("PGPORT", "DB_PORT", "AURORA_PORT", default="5432"),
        "dbname": env_value("PGDATABASE", "DB_NAME", "AURORA_DATABASE"),
        "user": env_value("PGUSER", "DB_USER", "AURORA_USER"),
        "password": env_value("PGPASSWORD", "DB_PASSWORD", "AURORA_PASSWORD"),
    }
    missing = [name for name in ("host", "dbname", "user", "password") if not settings[name]]
    if missing:
        raise RuntimeError("Configuracion PostgreSQL incompleta: " + ", ".join(missing))
    return psycopg2.connect(
        **settings,
        application_name="guajiranet_gold_refresh_episodios",
        connect_timeout=30,
    )


def validate(connection) -> tuple[int, int, int, int]:
    with connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT
                (SELECT c.relkind
                 FROM pg_class c
                 JOIN pg_namespace n ON n.oid = c.relnamespace
                 WHERE n.nspname = 'gold_guajiranet'
                   AND c.relname = 'vw_anl_episodios_ciclo_vida_cliente') AS view_kind,
                (SELECT c.relkind
                 FROM pg_class c
                 JOIN pg_namespace n ON n.oid = c.relnamespace
                 WHERE n.nspname = 'gold_guajiranet'
                   AND c.relname = 'tbl_anl_episodios_ciclo_vida_cliente') AS table_kind
            """
        )
        view_kind, table_kind = cursor.fetchone()
        if view_kind != "v" or table_kind != "r":
            raise RuntimeError(
                f"Tipos de objeto inesperados: view={view_kind!r}, table={table_kind!r}"
            )

        cursor.execute(
            """
            WITH view_columns AS (
                SELECT ordinal_position, column_name, data_type, udt_name
                FROM information_schema.columns
                WHERE table_schema = 'gold_guajiranet'
                  AND table_name = 'vw_anl_episodios_ciclo_vida_cliente'
            ), table_columns AS (
                SELECT ordinal_position, column_name, data_type, udt_name
                FROM information_schema.columns
                WHERE table_schema = 'gold_guajiranet'
                  AND table_name = 'tbl_anl_episodios_ciclo_vida_cliente'
            )
            SELECT
                (SELECT count(*) FROM view_columns) AS view_columns,
                (SELECT count(*) FROM table_columns) AS table_columns,
                (SELECT count(*)
                 FROM view_columns v
                 FULL JOIN table_columns t USING (ordinal_position)
                 WHERE (v.column_name, v.data_type, v.udt_name)
                       IS DISTINCT FROM
                       (t.column_name, t.data_type, t.udt_name)) AS column_differences
            """
        )
        view_columns, table_columns, column_differences = cursor.fetchone()
        if view_columns != 26 or table_columns != 26 or column_differences != 0:
            raise RuntimeError(
                "Esquema inesperado: "
                f"view_columns={view_columns}, table_columns={table_columns}, "
                f"differences={column_differences}"
            )

        cursor.execute(
            f"""
            SELECT
                (SELECT count(*) FROM {VIEW}) AS view_rows,
                (SELECT count(*) FROM {TABLE}) AS table_rows,
                (SELECT count(*) - count(DISTINCT (sk_cliente, numero_episodio))
                 FROM {TABLE}) AS duplicate_keys
            """
        )
        view_rows, table_rows, duplicate_keys = cursor.fetchone()
        if view_rows != table_rows or duplicate_keys != 0:
            raise RuntimeError(
                f"Datos no validos: view_rows={view_rows}, table_rows={table_rows}, "
                f"duplicate_keys={duplicate_keys}"
            )
    return view_rows, table_rows, duplicate_keys, column_differences


def execute_refresh(connection, sql_path: Path) -> None:
    sql = "\n".join(
        line for line in sql_path.read_text(encoding="utf-8").splitlines()
        if not line.lstrip().startswith("\\")
    )
    connection.autocommit = True
    with connection.cursor() as cursor:
        cursor.execute(sql)
        if cursor.description:
            snapshot_rows, refresh_status = cursor.fetchone()
            print(f"snapshot_rows={snapshot_rows}")
            print(f"refresh_status={refresh_status}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sql", type=Path, required=True)
    parser.add_argument("--env", type=Path, required=True)
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()

    if args.env.is_file():
        load_dotenv(args.env, override=False)

    with connect() as connection:
        if not args.validate_only:
            execute_refresh(connection, args.sql)
        view_rows, table_rows, duplicate_keys, column_differences = validate(connection)

    print(
        "validation_ok "
        f"view_rows={view_rows} table_rows={table_rows} "
        f"duplicate_keys={duplicate_keys} column_differences={column_differences}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

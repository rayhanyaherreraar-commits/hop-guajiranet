#!/usr/bin/env bash
# Ejecutar al final de run_silver_v2.sh, unicamente despues de que Hop termine
# con exit 0. El runner carga las credenciales AURORA_*/DB_*/PG* del ETL.
#
# No toca Delta, Silver v1 ni vw_anl_episodios_ciclo_vida_cliente.

set -euo pipefail

LOG="${GOLD_EPISODIOS_LOG:-/opt/guajiranet-etl/logs/cron_gold_episodios.log}"
SQL_SWAP="${GOLD_EPISODIOS_SQL:-/opt/guajiranet-etl/sql/13_refresh_episodios_swap.sql}"
LOCK="${GOLD_EPISODIOS_LOCK:-/opt/guajiranet-etl/logs/gold_episodios.lock}"
PYTHON="${GOLD_EPISODIOS_PYTHON:-/opt/guajiranet-etl/venv/bin/python}"
RUNNER="${GOLD_EPISODIOS_RUNNER:-/opt/guajiranet-etl/bin/run_refresh_episodios_gold.py}"
ENV_FILE="${GOLD_EPISODIOS_ENV:-/opt/guajiranet-etl/.env}"

log() { echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') $*" | tee -a "$LOG"; }

exec 9>"$LOCK"
if ! flock -n 9; then
  log "GOLD EPISODIOS: otro refresh en curso; abort"
  exit 1
fi

if [[ ! -r "$SQL_SWAP" ]]; then
  log "GOLD EPISODIOS: SQL no legible: $SQL_SWAP"
  exit 1
fi

if [[ ! -x "$PYTHON" || ! -r "$RUNNER" || ! -r "$ENV_FILE" ]]; then
  log "GOLD EPISODIOS: runtime incompleto (python/runner/env)"
  exit 1
fi

log "GOLD EPISODIOS: inicio swap tbl_anl_episodios_ciclo_vida_cliente"
T0=$(date +%s)

ARGS=(--sql "$SQL_SWAP" --env "$ENV_FILE")
if [[ "${GOLD_EPISODIOS_VALIDATE_ONLY:-0}" == "1" ]]; then
  ARGS+=(--validate-only)
fi

if "$PYTHON" "$RUNNER" "${ARGS[@]}" >>"$LOG" 2>&1; then
  RC=0
else
  RC=$?
fi

T1=$(date +%s)
log "GOLD EPISODIOS: fin rc=${RC} duracion_s=$((T1 - T0))"
exit "$RC"

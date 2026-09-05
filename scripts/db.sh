#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
data="$PWD/.local/postgres"
socket="$PWD/.local/socket"
mkdir -p "$socket"
case "${1:-start}" in
  start)
    if [ ! -f "$data/PG_VERSION" ]; then
      initdb -D "$data" --encoding=UTF8 --locale=C --auth=trust > .local/initdb.log
    fi
    if ! pg_ctl -D "$data" status > /dev/null 2>&1; then
      pg_ctl -D "$data" -l "$PWD/.local/postgres.log" -o "-h 127.0.0.1 -p 55432 -k '$socket'" start
    fi
    if ! psql -h 127.0.0.1 -p 55432 -d postgres -Atc "SELECT 1 FROM pg_database WHERE datname='drone_match'" | grep -q 1; then
      createdb -h 127.0.0.1 -p 55432 drone_match
    fi
    ;;
  stop) pg_ctl -D "$data" stop -m fast ;;
  *) echo 'Usage: bash scripts/db.sh start|stop' >&2; exit 1 ;;
esac

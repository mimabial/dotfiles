#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-$HOME/.local/lib/hypr}/core/common.bash" || exit 1

hypr_help_guard "Usage: hyprshell install/docker-dbs [database...]
Run selected database containers via docker (prompts when none given)." "$@"

DATABASES=(
  "MySQL 3306 mysql8 mysql:8.4 -e MYSQL_ROOT_PASSWORD= -e MYSQL_ALLOW_EMPTY_PASSWORD=true"
  "PostgreSQL 5432 postgres17 postgres:17 -e POSTGRES_HOST_AUTH_METHOD=trust"
  "Redis 6379 redis redis:7"
  "MongoDB 27017 mongodb mongo:noble -e MONGO_INITDB_ROOT_USERNAME=admin -e MONGO_INITDB_ROOT_PASSWORD=admin123"
  "MariaDB 3306 mariadb11 mariadb:11.8 -e MARIADB_ROOT_PASSWORD= -e MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=true"
  "MSSQL 1433 mssql mcr.microsoft.com/mssql/server:2022-CU12-ubuntu-22.04 -e MSSQL_PID=Developer -e ACCEPT_EULA=Y -e MSSQL_SA_PASSWORD=@dmin123"
)

run_database_container() {
  local label="$1" entry="" port="" container="" image=""
  local -a options=()

  for entry in "${DATABASES[@]}"; do
    [[ "${entry%% *}" == "${label}" ]] || continue
    read -r _ port container image options <<<"${entry}"
    read -r -a options <<<"${options}"
    sudo docker run -d --restart unless-stopped -p "127.0.0.1:${port}:${port}" --name="${container}" "${options[@]}" "${image}"
    return
  done
  printf 'Unknown database: %s\n' "${label}" >&2
  exit 2
}

if [[ "$#" -eq 0 ]]; then
  mapfile -t choices < <(printf "%s\n" "${DATABASES[@]%% *}" | fzf --prompt="Select database > " --header="Select database (ESC to cancel)" --reverse)
  [[ "${#choices[@]}" -gt 0 ]] || exit 0
else
  choices=("$@")
fi

for database in "${choices[@]}"; do
  run_database_container "${database}"
done

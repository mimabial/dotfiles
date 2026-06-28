#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=/dev/null
source "${HYPR_LIB_DIR:-${LIB_DIR:-$HOME/.local/lib}/hypr}/core/common.sh" || exit 1

hypr_help_guard "Usage: hyprshell install/docker-dbs [database...]
Run selected database containers via docker (prompts when none given)." "$@"

options=("MySQL" "PostgreSQL" "Redis" "MongoDB" "MariaDB" "MSSQL")

if [[ "$#" -eq 0 ]]; then
  mapfile -t choices < <(printf "%s\n" "${options[@]}" | fzf --prompt="Select database > " --header="Select database (ESC to cancel)" --reverse)
  [[ "${#choices[@]}" -gt 0 ]] || exit 0
else
  choices=("$@")
fi

if [[ "${#choices[@]}" -gt 0 ]]; then
  for db in "${choices[@]}"; do
    case $db in
    MySQL) sudo docker run -d --restart unless-stopped -p "127.0.0.1:3306:3306" --name=mysql8 -e MYSQL_ROOT_PASSWORD= -e MYSQL_ALLOW_EMPTY_PASSWORD=true mysql:8.4 ;;
    PostgreSQL) sudo docker run -d --restart unless-stopped -p "127.0.0.1:5432:5432" --name=postgres17 -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17 ;;
    MariaDB) sudo docker run -d --restart unless-stopped -p "127.0.0.1:3306:3306" --name=mariadb11 -e MARIADB_ROOT_PASSWORD= -e MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=true mariadb:11.8 ;;
    Redis) sudo docker run -d --restart unless-stopped -p "127.0.0.1:6379:6379" --name=redis redis:7 ;;
    MongoDB) sudo docker run -d --restart unless-stopped -p "127.0.0.1:27017:27017" --name mongodb -e MONGO_INITDB_ROOT_USERNAME=admin -e MONGO_INITDB_ROOT_PASSWORD=admin123 mongo:noble ;;
    MSSQL) sudo docker run -d --restart unless-stopped -p "127.0.0.1:1433:1433" --name mssql -e MSSQL_PID=Developer -e ACCEPT_EULA=Y -e "MSSQL_SA_PASSWORD=@dmin123" mcr.microsoft.com/mssql/server:2022-CU12-ubuntu-22.04 ;;
    esac
  done
else
  echo "No databases selected for installation."
fi

#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

DB_USER="app"
DB_NAME="hotel"

# Wait until the database is ready
until docker compose exec -T db pg_isready -h 127.0.0.1 -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; do
  echo "Waiting for database..."
  sleep 2
done

mkdir -p backups
FILE="backups/${DB_NAME}_$(date +%Y%m%d_%H%M%S).sql"

docker compose exec -T db pg_dump -U "$DB_USER" -d "$DB_NAME" > "$FILE"

echo "Backup created: $FILE"

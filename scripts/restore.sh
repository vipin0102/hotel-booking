#!/usr/bin/env bash

set -euo pipefail
cd "$(dirname "$0")/.."

DB_USER="app"
SOURCE_DB="hotel"
NEW_DB="hotel_restore"

FILE="${1:-$(ls -t backups/*.sql 2>/dev/null | head -n 1)}"
if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "No backup file found. Run ./scripts/backup.sh first."
  exit 1
fi

echo "Creating fresh database: $NEW_DB"
docker compose exec -T db psql -q -U "$DB_USER" -d postgres \
  -c "SET client_min_messages TO warning;" \
  -c "DROP DATABASE IF EXISTS $NEW_DB WITH (FORCE);" \
  -c "CREATE DATABASE $NEW_DB;"

echo "Restoring $FILE into $NEW_DB"
docker compose exec -T db psql -q -U "$DB_USER" -d "$NEW_DB" -v ON_ERROR_STOP=1 < "$FILE" > /dev/null

# Verification: compare row counts of source and restored database
COUNT_SQL="SELECT (SELECT COUNT(*) FROM hotel_bookings) || ' bookings, ' || (SELECT COUNT(*) FROM booking_events) || ' events';"
echo "Source   ($SOURCE_DB):     $(docker compose exec -T db psql -U "$DB_USER" -d "$SOURCE_DB" -tAc "$COUNT_SQL")"
echo "Restored ($NEW_DB): $(docker compose exec -T db psql -U "$DB_USER" -d "$NEW_DB" -tAc "$COUNT_SQL")"
echo "Restore completed."

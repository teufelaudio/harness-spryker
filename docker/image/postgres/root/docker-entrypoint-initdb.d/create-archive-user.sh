#!/bin/bash

set -e

echo "Creating archive user"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    BEGIN;
    CREATE USER ${ARCHIVE_USER} WITH PASSWORD '${ARCHIVE_PASS}';
    ALTER ROLE archive WITH LOGIN;
    CREATE SCHEMA IF NOT EXISTS archive;
    GRANT USAGE ON SCHEMA archive TO archive;
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO archive;
    GRANT SELECT ON ALL TABLES IN SCHEMA archive TO archive;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON SEQUENCES TO archive;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO archive;
    ALTER ROLE archive SET search_path = archive,public;
    COMMIT;
EOSQL

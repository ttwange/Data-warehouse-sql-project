#!/bin/bash

# =============================================================
# Script  : docker_setup.sh
# Project : Data Warehouse (Medallion Architecture)
# Author  : twange
# =============================================================
# Purpose:
#   Spins up a PostgreSQL 16 container with two volume mounts:
#     1. pgdata  — named volume for database persistence.
#                  Data survives container stop/rm/recreate.
#     2. datasets — binds your local datasets folder into the
#                  container at /datasets so PostgreSQL can read
#                  CSV files directly via COPY commands.
#
# Usage:
#   1. Edit the variables in the CONFIG section below
#   2. Run:  bash infrastructure/docker_setup.sh
#
# Requirements:
#   - Docker installed and running
#   - Datasets folder exists at the path you provide
# =============================================================


# -------------------------------------------------------------
# CONFIG — edit these values before running
# -------------------------------------------------------------
CONTAINER_NAME="pg_warehouse"
POSTGRES_USER="your_username"
POSTGRES_PASSWORD="your_password"
POSTGRES_DB="data_warehouse"
DATASETS_PATH="/Users/your_name/Data-warehouse-sql-project/datasets"
HOST_PORT=5432


# -------------------------------------------------------------
# RUN — do not edit below this line
# -------------------------------------------------------------
docker run -d \
  --name "$CONTAINER_NAME" \
  -e POSTGRES_USER="$POSTGRES_USER" \
  -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  -e POSTGRES_DB="$POSTGRES_DB" \
  -p "$HOST_PORT":5432 \
  -v pgdata:/var/lib/postgresql/data \
  -v "$DATASETS_PATH":/datasets \
  postgres:16

# -------------------------------------------------------------
# VERIFY — confirm the container started successfully
# -------------------------------------------------------------
echo ""
echo "Container status:"
docker ps --filter "name=$CONTAINER_NAME" \
  --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "Datasets mount check:"
docker exec "$CONTAINER_NAME" ls /datasets
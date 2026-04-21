#!/bin/bash
# SPDX-License-Identifier: MIT-0
#
# restore-db.sh — Restore a PostgreSQL database backup into the ADempiere database.
#
# Usage:
#   ./restore-db.sh
#
# BEFORE RUNNING:
#   1. Download the backup file to a directory on this control node.
#   2. Set restore_backup_filename and restore_local_dir in group_vars/all/vars.yml.
#   3. Ensure ~/.vault_pass.txt exists (configured via vault_password_file in ansible.cfg).
#   4. Ensure the ADempiere container stack is running on the BackEnd server.
#
# WARNING:
#   This operation OVERWRITES the adempiere database. It cannot be undone.
#   The decompressed dump file is always removed after the restore.
#   The backup archive is kept if keep_restore_file is true (the default).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARS_FILE="$SCRIPT_DIR/group_vars/all/vars.yml"

# --- Read backend IP from inventory ---

BACKEND_IP=$(ansible-inventory --host backend 2>/dev/null \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('ansible_host','(unknown)'))" 2>/dev/null || echo "(unknown)")

# --- Read variables from vars.yml ---

read_var() {
  grep -E "^$1:" "$VARS_FILE" | head -1 | sed "s/^$1:[[:space:]]*//" | tr -d '"'"'"
}

RESTORE_FILENAME=$(read_var restore_backup_filename)
RESTORE_LOCAL_DIR=$(read_var restore_local_dir)
RESTORE_REMOTE_DIR=$(read_var restore_remote_backup_dir)
KEEP_RESTORE_FILE=$(read_var keep_restore_file)
PG_HOST=$(read_var pg_host)
PG_PORT=$(read_var pg_port)
PG_SUPERUSER=$(read_var pg_superuser)
ADEMPIERE_DB=$(read_var adempiere_db)
ADEMPIERE_OWNER=$(read_var adempiere_owner)

# Derive remote dir: resolve {{ install_path }} if present
if echo "$RESTORE_REMOTE_DIR" | grep -q "install_path"; then
  INSTALL_PATH=$(read_var install_path)
  RESTORE_REMOTE_DIR="${INSTALL_PATH}/adempiere-ui-gateway/docker-compose/postgresql/postgres_backups"
fi

# Detect format from filename
if [[ "$RESTORE_FILENAME" == *.tar.gz ]]; then
  FORMAT="tar.gz"
  DUMP_FILENAME="${RESTORE_FILENAME%.tar.gz}.sql"
else
  FORMAT="gz"
  DUMP_FILENAME="${RESTORE_FILENAME%.gz}"
fi

# ---  Pre-flight checks ---

if [[ ! -f "$HOME/.vault_pass.txt" ]]; then
  echo "ERROR: ~/.vault_pass.txt not found."
  echo "       Create it with your vault password before running this script."
  exit 1
fi

if [[ -z "$RESTORE_FILENAME" || -z "$RESTORE_LOCAL_DIR" ]]; then
  echo "ERROR: restore_backup_filename or restore_local_dir is not set in $VARS_FILE"
  exit 1
fi

if [[ ! -f "$RESTORE_LOCAL_DIR/$RESTORE_FILENAME" ]]; then
  echo "ERROR: Backup file not found on this control node:"
  echo "       $RESTORE_LOCAL_DIR/$RESTORE_FILENAME"
  exit 1
fi

# --- Confirmation prompt ---

echo ""
echo "================================================================"
echo "  ADempiere — Database Restore"
echo "================================================================"
echo ""
echo "  Source file  : $RESTORE_LOCAL_DIR/$RESTORE_FILENAME"
echo "  Format       : $FORMAT  →  dump file: $DUMP_FILENAME"
echo "  Destination  : $RESTORE_REMOTE_DIR/"
echo "  Keep archive : $KEEP_RESTORE_FILE"
echo ""
echo "  Backend host : $BACKEND_IP  (from inventory)"
echo "  Database     : $ADEMPIERE_DB"
echo "  Owner        : $ADEMPIERE_OWNER"
echo "  PG connect   : $PG_HOST:$PG_PORT  (on the backend server)"
echo "  Superuser    : $PG_SUPERUSER"
echo ""
echo "  Passwords    : postgres_password      — group_vars/all/vault.yml"
echo "               : adempiere_db_password  — group_vars/all/vault.yml"
echo ""
echo "  !! WARNING: This will OVERWRITE the '$ADEMPIERE_DB' database. !!"
echo "  !! This operation cannot be undone.                           !!"
echo ""
read -rp "  Type YES to proceed with the restore: " confirm
if [[ "$confirm" != "YES" ]]; then
  echo "  Aborted."
  exit 1
fi
echo "================================================================"
echo ""

# --- Log setup ---

LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
LOGFILE="$LOG_DIR/restore-db-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "Output is logged to: $LOGFILE"
echo ""

# --- Run restore ---

echo ">>> adempiere-restoredb.yml — Restore database"
ansible-playbook adempiere-restoredb.yml
echo ""

echo "================================================================"
echo "  Database restore complete."
echo "================================================================"
echo ""

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

# --- Read backend hosts from inventory ---

BACKEND_HOSTS=$(ansible-inventory --list 2>/dev/null | python3 -c "
import sys, json
try:
    inv = json.load(sys.stdin)
    hosts = inv.get('BackEnd', {}).get('hosts', [])
    for h in hosts:
        ip = inv.get('_meta', {}).get('hostvars', {}).get(h, {}).get('ansible_host', '(no IP)')
        print(f'    {h}  →  {ip}')
except Exception:
    pass
" 2>/dev/null || true)

BACKEND_COUNT=$(echo "$BACKEND_HOSTS" | grep -c "→" 2>/dev/null || echo "0")

# --- Read variables from vars.yml ---

# Read a plain-text variable from vars.yml using grep+sed rather than ansible-vault
# or ansible-inventory, because vars.yml is not encrypted and this avoids the overhead
# of spawning a full Ansible process just to display the confirmation prompt.
read_var() {
  grep -E "^$1:" "$VARS_FILE" | head -1 | sed "s/^$1:[[:space:]]*//" | tr -d '"'"'"
}

RESTORE_FILENAME=$(read_var restore_backup_filename)
RESTORE_LOCAL_DIR=$(read_var restore_local_dir)
RESTORE_REMOTE_DIR=$(read_var restore_remote_backup_dir)
KEEP_RESTORE_FILE=$(read_var keep_restore_file)
PG_SUPERUSER=$(read_var pg_superuser)
PG_CONTAINER=$(read_var pg_container)
ADEMPIERE_DB=$(read_var adempiere_db)
ADEMPIERE_OWNER=$(read_var adempiere_owner)
CONTAINER_BACKUP_DIR=$(read_var restore_container_backup_dir)
POST_SQL_ENABLED=$(read_var post_restore_sql_enabled)
POST_SQL_FILENAME=$(read_var post_restore_sql_filename)
POST_SQL_LOCAL_DIR=$(read_var post_restore_sql_local_dir)
POST_SQL_REMOTE_DIR=$(read_var post_restore_sql_remote_dir)

# Resolve {{ install_path }} Jinja2 references in the remote dir paths.
# vars.yml may contain "{{ install_path }}/..." as a literal string; the shell
# cannot evaluate Jinja2 syntax, so we expand it manually here.
if echo "$RESTORE_REMOTE_DIR" | grep -q "install_path"; then
  INSTALL_PATH=$(read_var install_path)
  RESTORE_REMOTE_DIR="${INSTALL_PATH}/adempiere-ui-gateway/docker-compose/postgresql/postgres_backups"
fi

if echo "$POST_SQL_REMOTE_DIR" | grep -q "install_path"; then
  INSTALL_PATH="${INSTALL_PATH:-$(read_var install_path)}"
  POST_SQL_REMOTE_DIR="${INSTALL_PATH}/adempiere-ui-gateway/docker-compose/postgresql/postgres_backups/03-Misc-SQLs"
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

if [[ "$POST_SQL_ENABLED" == "true" ]]; then
  if [[ -z "$POST_SQL_FILENAME" || -z "$POST_SQL_LOCAL_DIR" ]]; then
    echo "ERROR: post_restore_sql_enabled is true but post_restore_sql_filename or post_restore_sql_local_dir is not set."
    exit 1
  fi
  if [[ ! -f "$POST_SQL_LOCAL_DIR/$POST_SQL_FILENAME" ]]; then
    echo "ERROR: Post-restore SQL script not found on this control node:"
    echo "       $POST_SQL_LOCAL_DIR/$POST_SQL_FILENAME"
    exit 1
  fi
fi

# --- Multi-backend safety check ---

if [[ "$BACKEND_COUNT" -gt 1 ]]; then
  echo ""
  echo "================================================================"
  echo "  MULTI-BACKEND WARNING"
  echo "================================================================"
  echo ""
  echo "  More than one BackEnd server is defined in the inventory:"
  echo ""
  echo "$BACKEND_HOSTS"
  echo ""
  echo "  The restore will run on ALL servers listed above."
  echo "  This operation CANNOT be undone on any of them."
  echo ""
  read -rp "  Type YES to restore to ALL servers, or anything else to abort: " multi_confirm
  if [[ "$multi_confirm" != "YES" ]]; then
    echo ""
    echo "  Aborted. To restore a single server only, remove the others"
    echo "  from the BackEnd group in inventories/hosts.yml and re-run."
    exit 1
  fi
  echo "================================================================"
  echo ""
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
echo "  Backend host(s) (from inventory):"
echo "$BACKEND_HOSTS"
echo "  Container    : $PG_CONTAINER"
echo "  Database     : $ADEMPIERE_DB  (owner: $ADEMPIERE_OWNER)"
echo "  Superuser    : $PG_SUPERUSER  (via docker exec — no TCP auth)"
echo "  adempiere_db_password  — group_vars/all/vault.yml"
echo ""
if [[ "$POST_SQL_ENABLED" == "true" ]]; then
  echo "  Post-restore SQL:"
  echo "    Source     : $POST_SQL_LOCAL_DIR/$POST_SQL_FILENAME"
  echo "    Dest       : $POST_SQL_REMOTE_DIR/$POST_SQL_FILENAME"
  echo "    Execute as : $PG_SUPERUSER on db $ADEMPIERE_DB  (via docker exec)"
else
  echo "  Post-restore SQL: disabled"
fi
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

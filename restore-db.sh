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
format_duration() { local s=$1; printf '%dm %ds' $((s / 60)) $((s % 60)); }

# --- Argument parsing (before any ansible call so --help is instant) ---

case "${1:-}" in
  --help|-h)
    cat <<'EOF'

Usage:
  ./restore-db.sh         Restore a PostgreSQL backup into the running ADempiere stack.
  ./restore-db.sh --help  This help.

There is no dry-run mode — the restore always overwrites the database.

WHAT IT DOES:
  1  Pre-flight      — verify ~/.vault_pass.txt, backup file, and (if enabled)
                       post-restore SQL file exist on the control node.
  2  Multi-backend   — if more than one BackEnd host is in the inventory, shows
                       an extra warning and asks for explicit YES before continuing.
  3  Confirmation    — displays a full summary (file, format, destination, container,
                       database, post-restore SQL status) and asks for YES.
  4  Upload          — copies the backup archive to the BackEnd server.
  5  Decompress      — auto-detects format from the filename:
                         *.backup.gz  →  gzip -dk  →  *.backup  (plain SQL)
                         *.sql.gz     →  gzip -dk  →  *.sql     (plain SQL)
                         *.tar.gz     →  tar -xzf  →  *.sql     (plain SQL)
  6  Drop & recreate — drops the adempiere database and recreates it with the
                       correct owner.
  7  Restore         — runs psql inside the PostgreSQL container via docker exec
                       (no TCP port needs to be open).
  8  Post-restore SQL — if post_restore_sql_enabled: true, uploads and executes
                        the specified SQL script.
  9  Cleanup         — removes the decompressed dump file; keeps or removes the
                       archive based on keep_restore_file in vars.yml.

PREREQUISITES:
  ~/.vault_pass.txt                      vault password file (mode 0600)
  group_vars/all/vars.yml                restore variables set (see below)
  group_vars/all/vault.yml               adempiere_db_password set
  inventories/hosts.yml                  at least one BackEnd host defined
  Backup file on this machine at         restore_local_dir/restore_backup_filename
  ADempiere stack running on BackEnd     (deploy-adempiere.yml completed)

VARIABLES TO SET IN group_vars/all/vars.yml:
  restore_backup_filename    filename of the backup archive (e.g. adempiere-2026-07-27.backup.gz)
  restore_local_dir          directory on this control node that holds the backup file
  (all other restore_* and post_restore_* variables have defaults)

ONE-TIME LOCAL SIDE EFFECT:
  Before connecting to the server, the script runs ssh-keygen -R <BackEnd IP>
  to remove the server's old SSH host fingerprint from ~/.ssh/known_hosts.
  A backup is saved as ~/.ssh/known_hosts.old. This is harmless and ensures
  Ansible can connect after a server reinstall.

INTERACTION POINTS:
  The script pauses at up to two points and waits for operator input.

  #  When                              Prompt
  -  --------------------------------  -----------------------------------------
  1  More than one BackEnd host found  "Type YES to restore to ALL servers"
  2  Before restore starts             "Type YES to proceed with the restore"

  Point 1 only appears when the BackEnd inventory group has more than one host.

Run ./check-config.sh restore-db first to validate all variables and files.
EOF
    exit 0
    ;;
  "")
    ;;
  *)
    echo "ERROR: unknown argument '${1}'."
    echo "Usage: ./restore-db.sh [--help]"
    exit 1
    ;;
esac

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

CUSTOM_SSHPORT=$(read_var custom_sshport)
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

# Pre-flight: refresh host keys for all BackEnd servers in known_hosts.
# Remove the stale entry (left over from a previous server install) and add
# the current fingerprint on the custom SSH port so Ansible can connect.
echo ">>> Task 1 of 2: Pre-flight — refresh known_hosts"
_t_preflight=$SECONDS
FOUND_IP=false
while IFS= read -r line; do
  IP=$(echo "$line" | awk '{print $NF}')
  if [[ "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo ">>> Pre-flight: refreshing known_hosts entry for $IP (port $CUSTOM_SSHPORT)"
    ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$IP" 2>/dev/null || true
    ssh-keyscan -H -p "$CUSTOM_SSHPORT" "$IP" >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
    FOUND_IP=true
  fi
done <<< "$BACKEND_HOSTS"
if [[ "$FOUND_IP" == "false" ]]; then
  echo "WARNING: could not determine backend IP(s) from inventory — skipping known_hosts refresh."
fi
echo ""
dur_preflight=$((SECONDS - _t_preflight))

# --- Run restore ---

echo ">>> Task 2 of 2: adempiere-restoredb.yml — Restore database"
_t_restore=$SECONDS
ansible-playbook adempiere-restoredb.yml
dur_restore=$((SECONDS - _t_restore))
echo ""

echo "================================================================"
echo "  Database restore complete."
echo "================================================================"
echo ""

CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}${BOLD}  ⏱  Restore Timing${NC}"
echo -e "${CYAN}  Task 1  Pre-flight:  $(format_duration $dur_preflight)${NC}"
echo -e "${CYAN}  Task 2  Restore:     $(format_duration $dur_restore)${NC}"
echo -e "${CYAN}  ─────────────────────${NC}"
echo -e "${CYAN}${BOLD}  Total:               $(format_duration $((dur_preflight + dur_restore)))${NC}"
echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo ""

#!/bin/bash
# SPDX-License-Identifier: MIT-0
#
# check-config.sh — Display and validate configuration variables for deploy-backend.sh
#                   or restore-db.sh without executing any changes.
#
# Usage:
#   ./check-config.sh deploy-backend   # check variables for deploy-backend.sh
#   ./check-config.sh restore-db       # check variables for restore-db.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARS_FILE="$SCRIPT_DIR/group_vars/all/vars.yml"
VAULT_FILE="$SCRIPT_DIR/group_vars/all/vault.yml"
BACKEND_YML="$SCRIPT_DIR/group_vars/BackEnd.yml"

TARGET="${1:-}"

if [[ "$TARGET" != "deploy-backend" && "$TARGET" != "restore-db" ]]; then
    echo ""
    echo "Usage: $0 deploy-backend | restore-db"
    echo ""
    echo "  deploy-backend"
    echo "      Scans and validates all variables required by deploy-backend.sh:"
    echo "      BackEnd inventory, SSH keypair, server configuration (vars.yml,"
    echo "      BackEnd.yml), and vault secrets. Shows each variable with its"
    echo "      current value and source file. Vault secret values are never"
    echo "      displayed — only whether they are set or missing. Reports at the"
    echo "      end whether deploy-backend.sh is ready to run."
    echo ""
    echo "  restore-db"
    echo "      Scans and validates all variables required by restore-db.sh:"
    echo "      BackEnd inventory, backup file presence, database connection"
    echo "      settings (vars.yml), vault secrets, and optional post-restore SQL"
    echo "      configuration. Shows each variable with its current value and"
    echo "      source file. Reports at the end whether restore-db.sh is ready"
    echo "      to run."
    echo ""
    exit 1
fi

# --- Helpers ---

read_var() {
    grep -E "^$1:" "$VARS_FILE" 2>/dev/null | head -1 | sed "s/^$1:[[:space:]]*//" | tr -d '"'"'" || true
}

read_backend_var() {
    grep -E "^$1:" "$BACKEND_YML" 2>/dev/null | head -1 | sed "s/^$1:[[:space:]]*//" | tr -d '"'"'" || true
}

print_row() {
    local tag="$1" label="$2" value="$3" source="$4"
    printf "  %-6s %-36s %-30s %s\n" "$tag" "$label" "$value" "$source"
}

ALL_OK=true
FAIL_REASONS=()

_fail() {
    ALL_OK=false
    FAIL_REASONS+=("$1")
}

print_preflight() {
    # args: ok(true|false)  label  value  source  fail-reason
    if [[ "$1" == true ]]; then
        print_row "[OK]" "$2" "$3" "$4"
    else
        _fail "$5"
        print_row "[FAIL]" "$2" "$3" "$4"
    fi
}

print_mandatory() {
    local name="$1" value="$2" source="$3"
    if [[ -n "$value" ]]; then
        print_row "[OK]" "$name" "$value" "$source"
    else
        _fail "\"$name\" not set  ($source)"
        print_row "[FAIL]" "$name" "(NOT SET)" "$source"
    fi
}

print_vault_secret() {
    local name="$1" status="$2"
    if [[ "$status" == "set" ]]; then
        print_row "[OK]" "$name" "set" "group_vars/all/vault.yml"
    else
        _fail "vault secret \"$name\": $status"
        print_row "[FAIL]" "$name" "$status" "group_vars/all/vault.yml"
    fi
}

print_optional() {
    print_row "[OPT]" "$1" "${2:-(not set)}" "$3"
}

# --- Common: vault and inventory ---

VAULT_CONTENT=""
if [[ -f "$HOME/.vault_pass.txt" ]]; then
    VAULT_CONTENT=$(ansible-vault view --vault-password-file "$HOME/.vault_pass.txt" "$VAULT_FILE" 2>/dev/null || true)
fi

vault_status() {
    if [[ -z "$VAULT_CONTENT" ]]; then
        echo "*** vault not readable ***"
    elif echo "$VAULT_CONTENT" | grep -q "^$1:"; then
        echo "set"
    else
        echo "*** MISSING ***"
    fi
}

BACKEND_LIST=$(ansible-inventory --list 2>/dev/null | python3 -c "
import sys, json
try:
    inv = json.load(sys.stdin)
    hosts = inv.get('BackEnd', {}).get('hosts', [])
    for h in hosts:
        ip = inv.get('_meta', {}).get('hostvars', {}).get(h, {}).get('ansible_host', '(no IP)')
        print(f'{h}  →  {ip}')
except Exception:
    pass
" 2>/dev/null || true)

BACKEND_COUNT=$(echo "$BACKEND_LIST" | grep -c "→" || true)


# ===================================================================
# deploy-backend
# ===================================================================

if [[ "$TARGET" == "deploy-backend" ]]; then

    ADEMPIERE_USERNAME=$(read_var adempiere_username)
    CUSTOM_SSHPORT=$(read_var custom_sshport)
    TIMEZONE=$(read_var timezone)
    SERVER_LOCALE=$(read_var server_locale)
    REPO_URL=$(read_var repo_url)
    REPO_VERSION=$(read_var repo_version)
    INSTALL_PATH=$(read_var install_path)
    SWAP_SIZE=$(read_backend_var swap_size_mb)
    CRONTAB_ENABLED=$(read_backend_var crontab_enabled)

    CRONTAB_DEFAULTS_FILE="$SCRIPT_DIR/roles/deploy-crontab/defaults/main.yml"
    CRONTAB_JOBS=$(python3 -c "
import yaml, sys
try:
    with open('$CRONTAB_DEFAULTS_FILE') as f:
        data = yaml.safe_load(f)
    jobs = data.get('crontab_jobs', [])
    n = len(jobs)
    print(str(n) + ' entr' + ('y' if n == 1 else 'ies'))
except Exception:
    print('(could not parse)')
" 2>/dev/null || echo "(could not read)")

    echo ""
    echo "================================================================"
    echo "  Configuration check — deploy-backend.sh"
    echo "================================================================"
    echo ""
    echo "  Pre-flight requirements:"
    echo ""

    if [[ -f "$HOME/.vault_pass.txt" ]]; then
        print_preflight true  "~/.vault_pass.txt" "exists"   "~/"  ""
    else
        print_preflight false "~/.vault_pass.txt" "NOT FOUND" "~/" "~/.vault_pass.txt is missing"
    fi

    if [[ "$BACKEND_COUNT" -gt 0 ]]; then
        print_preflight true  "BackEnd inventory" "$BACKEND_COUNT host(s)" "inventories/hosts.yml" ""
        while IFS= read -r line; do
            [[ -n "$line" ]] && printf "         %s\n" "$line"
        done <<< "$BACKEND_LIST"
    else
        print_preflight false "BackEnd inventory" "NO HOSTS" "inventories/hosts.yml" \
            "no BackEnd hosts defined in inventory"
    fi

    echo ""
    echo "  SSH keypair  (deploy-backend.sh will ask whether to keep or regenerate if found):"
    echo ""

    KEY_DIR="$SCRIPT_DIR/ssh_keys"
    KEY_PRIV="adempiere_installation_key"
    KEY_PUB="adempiere_installation_key.pub"

    if [[ -f "$KEY_DIR/$KEY_PRIV" ]]; then
        print_row "[INFO]" "Private key found" "$KEY_PRIV" "$KEY_DIR/"
        if [[ -f "$KEY_DIR/$KEY_PUB" ]]; then
            print_row "[INFO]" "Public key found"  "$KEY_PUB"  "$KEY_DIR/"
        else
            print_row "[WARN]" "Public key missing" "$KEY_PUB" "$KEY_DIR/"
        fi
    else
        print_row "[INFO]" "No keypair found" "(will be generated by deploy-backend.sh)" "$KEY_DIR/"
    fi

    echo ""
    echo "  Mandatory variables:"
    echo ""

    print_mandatory "adempiere_username"   "$ADEMPIERE_USERNAME" "group_vars/all/vars.yml"
    print_mandatory "custom_sshport"       "$CUSTOM_SSHPORT"     "group_vars/all/vars.yml"
    print_mandatory "timezone"             "$TIMEZONE"           "group_vars/all/vars.yml"
    print_mandatory "server_locale"        "$SERVER_LOCALE"      "group_vars/all/vars.yml"
    print_mandatory "repo_url"             "$REPO_URL"           "group_vars/all/vars.yml"
    print_mandatory "repo_version"         "$REPO_VERSION"       "group_vars/all/vars.yml"
    print_mandatory "install_path"         "$INSTALL_PATH"       "group_vars/all/vars.yml"
    print_mandatory "swap_size_mb"         "$SWAP_SIZE"          "group_vars/BackEnd.yml"
    print_mandatory "crontab_enabled"      "$CRONTAB_ENABLED"    "group_vars/BackEnd.yml"

    echo ""
    echo "  Vault secrets  (values not shown):"
    echo ""

    print_vault_secret "root_user_password"         "$(vault_status root_user_password)"
    print_vault_secret "adempiere_user_password"    "$(vault_status adempiere_user_password)"
    print_vault_secret "adempiere_user_become_pass" "$(vault_status adempiere_user_become_pass)"
    print_vault_secret "postgres_password"          "$(vault_status postgres_password)"

    echo ""
    echo "  Optional variables:"
    echo ""

    print_optional "crontab_jobs" "$CRONTAB_JOBS" "roles/deploy-crontab/defaults/main.yml"

    echo ""
    echo "================================================================"
    if [[ "$ALL_OK" == true ]]; then
        echo "  RESULT: deploy-backend.sh CAN run."
    else
        echo "  RESULT: deploy-backend.sh CANNOT run."
        echo ""
        for r in "${FAIL_REASONS[@]}"; do
            echo "    - $r"
        done
    fi
    echo "================================================================"
    echo ""

fi


# ===================================================================
# restore-db
# ===================================================================

if [[ "$TARGET" == "restore-db" ]]; then

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
    INSTALL_PATH=$(read_var install_path)

    # Resolve {{ install_path }} Jinja2 references (mirrors restore-db.sh logic)
    if echo "$RESTORE_REMOTE_DIR" | grep -q "install_path"; then
        RESTORE_REMOTE_DIR="${INSTALL_PATH}/adempiere-ui-gateway/docker-compose/postgresql/postgres_backups"
    fi
    if echo "$POST_SQL_REMOTE_DIR" | grep -q "install_path"; then
        POST_SQL_REMOTE_DIR="${INSTALL_PATH}/adempiere-ui-gateway/docker-compose/postgresql/postgres_backups/03-Misc-SQLs"
    fi

    # Detect format
    if [[ "$RESTORE_FILENAME" == *.tar.gz ]]; then
        FORMAT="tar.gz"
        DUMP_FILENAME="${RESTORE_FILENAME%.tar.gz}.sql"
    elif [[ -n "$RESTORE_FILENAME" ]]; then
        FORMAT="gz"
        DUMP_FILENAME="${RESTORE_FILENAME%.gz}"
    else
        FORMAT="(unknown)"
        DUMP_FILENAME="(unknown)"
    fi

    echo ""
    echo "================================================================"
    echo "  Configuration check — restore-db.sh"
    echo "================================================================"
    echo ""
    echo "  Pre-flight requirements:"
    echo ""

    if [[ -f "$HOME/.vault_pass.txt" ]]; then
        print_preflight true  "~/.vault_pass.txt" "exists"    "~/"  ""
    else
        print_preflight false "~/.vault_pass.txt" "NOT FOUND" "~/"  "~/.vault_pass.txt is missing"
    fi

    if [[ "$BACKEND_COUNT" -gt 0 ]]; then
        print_preflight true  "BackEnd inventory" "$BACKEND_COUNT host(s)" "inventories/hosts.yml" ""
        while IFS= read -r line; do
            [[ -n "$line" ]] && printf "         %s\n" "$line"
        done <<< "$BACKEND_LIST"
    else
        print_preflight false "BackEnd inventory" "NO HOSTS" "inventories/hosts.yml" \
            "no BackEnd hosts defined in inventory"
    fi

    if [[ -n "$RESTORE_FILENAME" && -n "$RESTORE_LOCAL_DIR" && -f "$RESTORE_LOCAL_DIR/$RESTORE_FILENAME" ]]; then
        print_preflight true "Backup file" "exists" \
            "${RESTORE_LOCAL_DIR}/${RESTORE_FILENAME}" ""
    else
        _bk_path="${RESTORE_LOCAL_DIR:-(not set)}/${RESTORE_FILENAME:-(not set)}"
        print_preflight false "Backup file" "NOT FOUND" "$_bk_path" \
            "backup file not found: $_bk_path"
    fi

    echo ""
    echo "  Mandatory variables:"
    echo ""

    print_mandatory "restore_backup_filename"  "$RESTORE_FILENAME"   "group_vars/all/vars.yml"
    print_mandatory "restore_local_dir"        "$RESTORE_LOCAL_DIR"  "group_vars/all/vars.yml"
    print_mandatory "pg_superuser"             "$PG_SUPERUSER"       "group_vars/all/vars.yml"
    print_mandatory "pg_container"             "$PG_CONTAINER"       "group_vars/all/vars.yml"
    print_mandatory "adempiere_db"             "$ADEMPIERE_DB"       "group_vars/all/vars.yml"
    print_mandatory "adempiere_owner"          "$ADEMPIERE_OWNER"    "group_vars/all/vars.yml"
    print_mandatory "install_path"             "$INSTALL_PATH"       "group_vars/all/vars.yml"

    echo ""
    echo "  Vault secrets  (values not shown):"
    echo ""

    print_vault_secret "adempiere_db_password" "$(vault_status adempiere_db_password)"

    echo ""
    echo "  Optional variables:"
    echo ""

    print_optional "restore_remote_backup_dir"    "$RESTORE_REMOTE_DIR"    "group_vars/all/vars.yml"
    print_optional "keep_restore_file"            "$KEEP_RESTORE_FILE"     "group_vars/all/vars.yml"
    print_optional "restore_container_backup_dir" "$CONTAINER_BACKUP_DIR"  "group_vars/all/vars.yml"
    print_optional "post_restore_sql_enabled"     "$POST_SQL_ENABLED"      "group_vars/all/vars.yml"

    echo ""
    echo "  Post-restore SQL  (mandatory only when post_restore_sql_enabled = true):"
    echo ""

    if [[ "$POST_SQL_ENABLED" == "true" ]]; then
        print_mandatory "post_restore_sql_filename"  "$POST_SQL_FILENAME"  "group_vars/all/vars.yml"
        print_mandatory "post_restore_sql_local_dir" "$POST_SQL_LOCAL_DIR" "group_vars/all/vars.yml"

        if [[ -n "$POST_SQL_FILENAME" && -n "$POST_SQL_LOCAL_DIR" && -f "$POST_SQL_LOCAL_DIR/$POST_SQL_FILENAME" ]]; then
            print_preflight true "SQL file" "exists" \
                "${POST_SQL_LOCAL_DIR}/${POST_SQL_FILENAME}" ""
        else
            _sql_path="${POST_SQL_LOCAL_DIR:-(not set)}/${POST_SQL_FILENAME:-(not set)}"
            print_preflight false "SQL file" "NOT FOUND" "$_sql_path" \
                "post-restore SQL file not found: $_sql_path"
        fi

        print_optional "post_restore_sql_remote_dir" "$POST_SQL_REMOTE_DIR" "group_vars/all/vars.yml"
    else
        echo "  (disabled — post_restore_sql_enabled is not \"true\")"
    fi

    echo ""
    echo "  Detected format: $FORMAT  →  dump file: $DUMP_FILENAME"
    echo ""

    echo "================================================================"
    if [[ "$ALL_OK" == true ]]; then
        echo "  RESULT: restore-db.sh CAN run."
    else
        echo "  RESULT: restore-db.sh CANNOT run."
        echo ""
        for r in "${FAIL_REASONS[@]}"; do
            echo "    - $r"
        done
    fi
    echo "================================================================"
    echo ""

fi

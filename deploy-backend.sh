#!/bin/bash
# SPDX-License-Identifier: MIT-0
#
# deploy-backend.sh — Full BackEnd provisioning from a clean server reset,
#                     or selective re-run on an already-provisioned server.
#
# Usage:
#   ./deploy-backend.sh           # real run — makes changes on the server
#   ./deploy-backend.sh --check   # dry run — shows what would change, no writes
#
# IDEMPOTENCY:
#   The script probes port 22 and the custom SSH port before starting and
#   auto-detects whether the server is fresh or already hardened:
#     Port 22 open, custom port closed  ->  FRESH mode   — all 10 tasks run.
#     Port 22 closed, custom port open  ->  HARDENED mode — Tasks 1-5 skipped,
#                                            deployment resumes from Task 6.
#   Use this to apply new roles (WireGuard, Docker, crontab ...) to servers
#   that were provisioned before those roles were added.
#
# BEFORE RUNNING:
#   1. Ensure ~/.vault_pass.txt exists (configured via vault_password_file in
#      ansible.cfg).
#   2. Fresh server: confirm port 22 is open as root with password auth.
#      Already-provisioned server: confirm the custom SSH port is open.
#   The script auto-detects which situation applies by probing both ports.

set -euo pipefail
export ANSIBLE_FORCE_COLOR=1   # colorize PLAY RECAP even when piped through tee

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
format_duration() { local s=$1; printf '%dm %ds' $((s / 60)) $((s % 60)); }
format_bool()     { if [[ "$1" == "true" ]]; then echo "yes"; else echo "no"; fi; }
_box()            { printf "  │  %-63s│\n" "$1"; }

# --- Argument parsing (before log setup so --help never creates a log file) ---

case "${1:-}" in
  --help|-h)
    cat <<'EOF'

Usage:
  ./deploy-backend.sh           Real run  — provision the BackEnd server end-to-end.
  ./deploy-backend.sh --check   Dry run   — show what Ansible would change; no writes.
  ./deploy-backend.sh --help    This help.

WHAT IT DOES (10 steps):
  1  Keypair check        — keep or regenerate ssh_keys/adempiere_installation_key.
  2  genkey.yml           — generate RSA keypair (skipped when keypair is kept).
  3  serversprep.yml      — copy public key to BackEnd as root on port 22.
  4  os-updates.yml       — OS update + reboot; waits for the server to return.
  5  serversconf.yml      — harden SSH, create admin user, move SSH to custom port.
  6  deploy-wireguard.yml — install WireGuard VPN server (skipped if wireguard_enabled: false).
  7  serverswap.yml       — configure swap (size from group_vars/BackEnd.yml).
  8  install-docker.yml   — install Docker CE.
  9  deploy-adempiere.yml — deploy the ADempiere container stack.
  10 deploy-crontab.yml   — configure crontab (start/stop/restart schedule).

IDEMPOTENCY (auto-detection):
  Before starting, the script probes port 22 and the custom SSH port on the
  BackEnd server to determine whether it is fresh or already hardened.

  Port 22 open, custom port closed  ->  FRESH mode    — all 10 tasks run.
  Port 22 closed, custom port open  ->  HARDENED mode — Tasks 1-5 are skipped;
                                         deployment resumes from Task 6.

  Use this to apply roles that were added after initial provisioning (WireGuard,
  Docker updates, new crontab entries, etc.) without repeating the destructive
  steps (password reset, key distribution, SSH hardening).

  Because Ansible roles are idempotent, tasks that were already applied will
  report "ok" (no change); only missing or modified configuration is applied.

  If both ports respond or neither responds, the script warns and runs in
  FRESH mode (all 10 tasks). Check your cloud firewall if the state is unexpected.

REAL RUN (no argument):
  Displays a full configuration summary and asks for explicit YES before
  making any changes. All output is also written to a timestamped file in logs/.

DRY RUN (--check):
  Passes --check to every Ansible playbook — no changes are made on the server.
  Ansible still connects to the server, so the relevant SSH port(s) must respond:
    FRESH mode:    port 22          (Steps 3-5) and custom SSH port (Steps 6-10).
    HARDENED mode: custom SSH port  (Steps 6-10 only; Steps 3-5 are skipped).
  In HARDENED mode the dry-run output for Steps 6-10 is accurate: the admin user
  and custom SSH port already exist, so Ansible reports the real diff.
  One local side effect always runs even in --check mode:
    ~/.ssh/known_hosts is updated — the old host fingerprint for the BackEnd IP
    is removed so Ansible can connect without a key-mismatch error. A backup is
    saved as ~/.ssh/known_hosts.old. This is harmless: if the server was
    reinstalled the removal is required; if not, the key is re-added on the
    next successful connection.
  Limitations:
    Step 1 (keypair handling) is skipped — no local files are touched.
    Step 4 (os-updates): the reboot task is skipped in check mode; the dry-run
    output does not reflect the post-reboot state.

INTERACTION POINTS:
  The script pauses at up to five points and waits for input.

  #  When                                   Fresh  Hardened  Mode
  -  --------------------------------------  -----  --------  ----------
  1  Before deployment starts               yes    yes       real only
  2  Existing SSH keypair found             maybe  no        real only
  3  Before Step 3 (needs port 22)          yes    no        always
  4  After Step 5 (SSH port changed)        yes    no        always
  5  After Step 6 (WireGuard enabled)       yes    yes       always

  In HARDENED mode, points 2, 3, and 4 are skipped automatically.
  Point 5 appears only when wireguard_enabled: true.

ANSIBLE TASK PREFIXES:
  Every task in the Ansible roles carries one of two prefixes so you can tell
  at a glance what kind of task it is and what the status means:

  INFO:   Diagnostic print only (ansible.builtin.debug). Always reports "ok".
          The status tells you nothing about server state — the message was
          simply printed.
          Example:
            TASK [serversconf : INFO: Install basic packages]
            ok: [backend1] => { "msg": "target=backend1 | installing 35 utility packages" }

  APPLY:  Real state-enforcement task (package, file, template, service, ...).
          The status reflects the actual server state:
            ok      -- state was already correct; nothing changed on the server.
            changed -- configuration applied (was missing or differed from desired state).
            skipped -- condition was false (when: ...) or a feature is disabled.
            failed  -- task encountered an error; playbook was aborted.

  When an already-provisioned server shows "ok" on APPLY: tasks, it is in
  the desired state. "changed" on an APPLY: task means that configuration
  was genuinely applied during this run.

ANSIBLE TASK COUNTERS:
  The summary at the end of each run shows two layers of counters.

  Total line (from PLAY RECAP — authoritative):
    ok=N            All ok tasks combined (APPLY: already correct + INFO: prints).
    changed=N       Configurations applied this run (APPLY: tasks only).
    skipped=N       Tasks skipped by a condition (when:) or disabled feature.
    failed=N        Tasks that failed (playbook aborted).
    ignored=N       Failed tasks with ignore_errors: true.
    rescued=N       Failed tasks recovered by a rescue: block.
    unreachable=N   Hosts that could not be reached.

  Breakdown by task prefix (parsed from task output lines):
    INFO:   ok=N  skipped=N   -- diagnostic prints only; ok here is uninformative.
    APPLY:  ok=N  changed=N  skipped=N  failed=N
                              -- ok means state already correct; changed means
                                 configuration was applied during this run.

PREREQUISITES:
  ~/.vault_pass.txt            vault password file (mode 0600)
  group_vars/all/vars.yml      deployment configuration
  group_vars/all/vault.yml     encrypted secrets
  inventories/hosts.yml        BackEnd host IP
  nc (netcat)                  used for server state auto-detection

  Fresh server:     port 22 must respond as root with password auth.
  Already-hardened: custom SSH port (configured in vars.yml) must respond.
  The script probes both ports automatically — no flag needed.

Run ./check-config.sh deploy-backend first to validate all variables.
EOF
    exit 0
    ;;
  --check)
    CHECK="--check"
    ;;
  "")
    CHECK=""
    ;;
  *)
    echo "ERROR: unknown argument '${1}'."
    echo "Usage: ./deploy-backend.sh [--check | --help]"
    exit 1
    ;;
esac

LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
LOGFILE="$LOG_DIR/deploy-backend-$(date +%Y%m%d-%H%M%S).log"
# Redirect all stdout and stderr to both the terminal and the log file simultaneously.
exec > >(tee -a "$LOGFILE") 2>&1
echo "Output is logged to: $LOGFILE"
echo ""

# Pre-flight: vault password file must exist (ansible.cfg references ~/.vault_pass.txt)
if [[ ! -f "$HOME/.vault_pass.txt" ]]; then
  echo "ERROR: ~/.vault_pass.txt not found."
  echo "       Create it with your vault password before running this script."
  exit 1
fi

# Clear any stale SSH ControlMaster sockets left by a previously interrupted run.
# Stale sockets cause Ansible to hang at Gathering Facts on the next run.
rm -f "$HOME/.ansible/cp/"*

# --- Read configuration values for the summary display ---

VARS_FILE="$SCRIPT_DIR/group_vars/all/vars.yml"
VAULT_FILE="$SCRIPT_DIR/group_vars/all/vault.yml"
BACKEND_YML="$SCRIPT_DIR/group_vars/BackEnd.yml"

read_var() {
  grep -E "^$1:" "$VARS_FILE" | head -1 | sed "s/^$1:[[:space:]]*//" | tr -d '"'"'"
}
read_backend_var() {
  grep -E "^$1:" "$BACKEND_YML" | head -1 | sed "s/^$1:[[:space:]]*//" | tr -d '"'"'"
}

PROJECT_NAME=$(read_var project_name)
ADEMPIERE_USERNAME=$(read_var adempiere_username)
CUSTOM_SSHPORT=$(read_var custom_sshport)
TIMEZONE=$(read_var timezone)
SERVER_LOCALE=$(read_var server_locale)
SERVER_HOSTNAME=$(read_var server_hostname)
REPO_URL=$(read_var repo_url)
REPO_VERSION=$(read_var repo_version)
INSTALL_PATH=$(read_var install_path)
SWAP_SIZE=$(read_backend_var swap_size_mb)
CRONTAB_ENABLED=$(read_backend_var crontab_enabled)
WIREGUARD_ENABLED=$(read_backend_var wireguard_enabled)
WIREGUARD_PORT=$(read_var wireguard_port)
WIREGUARD_ADDR=$(read_var wireguard_server_address)

CRONTAB_DEFAULTS_FILE="$SCRIPT_DIR/roles/deploy-crontab/defaults/main.yml"
CRONTAB_JOBS=$(python3 -c "
import yaml, sys
try:
    with open('$CRONTAB_DEFAULTS_FILE') as f:
        data = yaml.safe_load(f)
    for job in data.get('crontab_jobs', []):
        t = job.get('special_time') or '{}:{}'.format(job.get('hour','?'), job.get('minute','?'))
        print('      {:<14} -> {}'.format(t, job.get('script','?')))
except Exception as e:
    print('      (could not parse crontab_jobs: {})'.format(e))
" 2>/dev/null || echo "      (could not read crontab defaults)")

VAULT_CONTENT=$(ansible-vault view --vault-password-file "$HOME/.vault_pass.txt" "$VAULT_FILE" 2>/dev/null || echo "")
vault_status() {
  if [[ -z "$VAULT_CONTENT" ]]; then
    echo "*** vault not readable ***"
  elif echo "$VAULT_CONTENT" | grep -q "^$1:"; then
    echo "set"
  else
    echo "*** MISSING ***"
  fi
}

# Build a display list of BackEnd hosts and their IPs.
# We parse ansible-inventory --list JSON rather than --graph because --graph
# does not include the ansible_host value needed for the confirmation prompt.
BACKEND_LIST=$(ansible-inventory --list 2>/dev/null | python3 -c "
import sys, json
try:
    inv = json.load(sys.stdin)
    hosts = inv.get('BackEnd', {}).get('hosts', [])
    for h in hosts:
        ip = inv.get('_meta', {}).get('hostvars', {}).get(h, {}).get('ansible_host', '(no IP)')
        print(f'      {h}  →  {ip}')
except Exception:
    print('      (could not read inventory)')
" 2>/dev/null || echo "      (could not read inventory)")

# --- Auto-detect server state by probing SSH ports ---
#
# Probes port 22 and the custom SSH port to decide whether the server has
# already been provisioned (hardened) by a previous run of this script.
#
#   FRESH    — port 22 open, custom port closed: run all 10 tasks.
#   HARDENED — port 22 closed, custom port open: skip Tasks 1-5, resume from 6.
#   UNREACHABLE — neither port responds: warn, fall through to FRESH mode.
#   AMBIGUOUS   — both ports respond: warn, fall through to FRESH mode.
#   UNKNOWN     — inventory yielded no IP: cannot probe, fall through to FRESH.
#
BACKEND_IP=$(echo "$BACKEND_LIST" | awk '{print $NF}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
SERVER_MODE="unknown"
PORT22_OPEN=false
CUSTOM_OPEN=false

if [[ -n "$BACKEND_IP" ]]; then
  nc -z -w 5 "$BACKEND_IP" 22               2>/dev/null && PORT22_OPEN=true || true
  nc -z -w 5 "$BACKEND_IP" "$CUSTOM_SSHPORT" 2>/dev/null && CUSTOM_OPEN=true  || true
  if   [[ "$PORT22_OPEN" == "true"  && "$CUSTOM_OPEN" == "false" ]]; then SERVER_MODE="fresh"
  elif [[ "$PORT22_OPEN" == "false" && "$CUSTOM_OPEN" == "true"  ]]; then SERVER_MODE="hardened"
  elif [[ "$PORT22_OPEN" == "false" && "$CUSTOM_OPEN" == "false" ]]; then SERVER_MODE="unreachable"
  else                                                                     SERVER_MODE="ambiguous"
  fi
fi

# --- Configuration summary (shown in both dry-run and real-run mode) ---

echo ""
echo "================================================================"
if [[ -n "$CHECK" ]]; then
  echo "  BackEnd Deployment — DRY RUN (--check) — no changes will be made"
else
  echo "  BackEnd Deployment — LIVE RUN — changes will be made on the server"
fi
echo "================================================================"
echo ""
echo "  Target BackEnd server(s):"
echo "$BACKEND_LIST"
echo ""
echo "  Server configuration  (group_vars/all/vars.yml + group_vars/BackEnd.yml):"
printf "    %-30s %s\n" "Project name:"               "$PROJECT_NAME"
printf "    %-30s %s\n" "Hostname:"                   "$SERVER_HOSTNAME"
printf "    %-30s %s\n" "Admin username:"             "$ADEMPIERE_USERNAME"
printf "    %-30s %s\n" "SSH port (after hardening):" "$CUSTOM_SSHPORT"
printf "    %-30s %s\n" "Timezone:"                   "$TIMEZONE"
printf "    %-30s %s\n" "Locale:"                     "$SERVER_LOCALE"
printf "    %-30s %s\n" "Swap:"                       "${SWAP_SIZE} MB"
echo ""
echo "  Application  (group_vars/all/vars.yml):"
printf "    %-30s %s\n" "Repository URL:"             "$REPO_URL"
printf "    %-30s %s\n" "Branch:"                     "$REPO_VERSION"
printf "    %-30s %s\n" "Install path:"               "$INSTALL_PATH"
echo ""
echo "  Crontab  (group_vars/BackEnd.yml + role defaults):"
printf "    %-30s %s\n" "Enabled:"                    "$CRONTAB_ENABLED"
if [[ "$CRONTAB_ENABLED" == "true" ]]; then
  echo "    Schedule:"
  echo "$CRONTAB_JOBS"
fi
echo ""
echo "  WireGuard  (group_vars/BackEnd.yml + group_vars/all/vars.yml):"
printf "    %-30s %s\n" "Enabled:"                    "$WIREGUARD_ENABLED"
if [[ "$WIREGUARD_ENABLED" == "true" ]]; then
  printf "    %-30s %s\n" "Listen port (UDP):"        "$WIREGUARD_PORT"
  printf "    %-30s %s\n" "Server VPN address:"       "$WIREGUARD_ADDR"
fi
echo ""
echo "  Auto-detected server state:"
printf "    %-30s %s\n" "Port 22 open:"                  "$(format_bool "$PORT22_OPEN")"
printf "    %-30s %s\n" "Port $CUSTOM_SSHPORT (SSH) open:" "$(format_bool "$CUSTOM_OPEN")"
case "$SERVER_MODE" in
  fresh)       printf "    %-30s %s\n" "Mode:" "FRESH -- all 10 tasks will run" ;;
  hardened)    printf "    %-30s %s\n" "Mode:" "HARDENED -- Tasks 1-5 skipped, resuming from Task 6" ;;
  unreachable) printf "    %-30s %s\n" "Mode:" "UNREACHABLE -- neither port responds (check firewall)" ;;
  ambiguous)   printf "    %-30s %s\n" "Mode:" "AMBIGUOUS -- both ports open (running all 10 tasks)" ;;
  unknown)     printf "    %-30s %s\n" "Mode:" "UNKNOWN -- no server IP in inventory (running all 10 tasks)" ;;
esac
echo ""
echo "  Secrets  (group_vars/all/vault.yml — values not shown):"
printf "    %-30s %s\n" "root_user_password:"         "$(vault_status root_user_password)"
printf "    %-30s %s\n" "adempiere_user_password:"    "$(vault_status adempiere_user_password)"
printf "    %-30s %s\n" "adempiere_user_become_pass:" "$(vault_status adempiere_user_become_pass)"
printf "    %-30s %s\n" "postgres_password:"          "$(vault_status postgres_password)"
echo ""

# --- Mode banners: shown before confirmation so the operator sees them clearly ---

if [[ "$SERVER_MODE" == "hardened" ]]; then
  echo "  ┌─────────────────────────────────────────────────────────────────┐"
  _box "RESUME MODE: Tasks 1-5 will be skipped"
  _box "Port 22 closed, port $CUSTOM_SSHPORT open -- server already hardened."
  _box "Deployment resumes from Task 6. Only missing or changed"
  _box "configuration will be applied (Ansible roles are idempotent)."
  echo "  └─────────────────────────────────────────────────────────────────┘"
  echo ""
elif [[ "$SERVER_MODE" == "unreachable" ]]; then
  echo "  ┌─────────────────────────────────────────────────────────────────┐"
  _box "WARNING: SERVER NOT REACHABLE"
  _box "Neither port 22 nor port $CUSTOM_SSHPORT responds on $BACKEND_IP."
  _box "Ensure the server is running and at least one port is open."
  _box "Ansible will fail to connect if the server stays unreachable."
  echo "  └─────────────────────────────────────────────────────────────────┘"
  echo ""
elif [[ "$SERVER_MODE" == "ambiguous" ]]; then
  echo "  ┌─────────────────────────────────────────────────────────────────┐"
  _box "WARNING: BOTH PORT 22 AND PORT $CUSTOM_SSHPORT RESPOND"
  _box "Possible cause: server is hardened but cloud firewall still"
  _box "allows port 22. Running in FRESH mode (all 10 tasks)."
  echo "  └─────────────────────────────────────────────────────────────────┘"
  echo ""
  SERVER_MODE="fresh"
elif [[ "$SERVER_MODE" == "unknown" ]]; then
  echo "  WARNING: Could not determine server IP from inventory."
  echo "  Server state auto-detection skipped. Running in FRESH mode (all 10 tasks)."
  echo ""
  SERVER_MODE="fresh"
fi

if [[ -z "$CHECK" ]]; then
  read -rp "  Type YES to proceed with the deployment: " confirm
  if [[ "$confirm" != "YES" ]]; then
    echo "  Aborted."
    exit 1
  fi
fi
echo "================================================================"
echo ""

dur_preflight=0; dur_genkey=0
dur_step3=0; dur_step4=0; dur_step5=0
dur_wireguard=0; dur_step7=0; dur_step8=0; dur_step9=0; dur_step10=0
GENKEY_STATUS="skipped"; WIREGUARD_STATUS="skipped"
STEP3_STATUS="skipped"; STEP4_STATUS="skipped"; STEP5_STATUS="skipped"
STEP7_STATUS="skipped"; STEP8_STATUS="skipped"
STEP9_STATUS="skipped"; STEP10_STATUS="skipped"

# Pre-flight: remove stale host keys for all BackEnd servers from known_hosts.
# Required after a server reset — the host presents a new key and SSH would refuse to connect.
_t=$SECONDS
FOUND_IP=false
while IFS= read -r line; do
  IP=$(echo "$line" | awk '{print $NF}')
  if [[ "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo ">>> Pre-flight: removing stale known_hosts entries for $IP (port 22 and $CUSTOM_SSHPORT)"
    ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$IP"                    2>/dev/null || true
    ssh-keygen -f "$HOME/.ssh/known_hosts" -R "[$IP]:$CUSTOM_SSHPORT" 2>/dev/null || true
    FOUND_IP=true
  fi
done <<< "$BACKEND_LIST"
if [[ "$FOUND_IP" == "false" ]]; then
  echo "WARNING: could not determine backend IP(s) from inventory — skipping known_hosts cleanup."
fi
echo ""
dur_preflight=$((SECONDS - _t))

KEY_PATH="$SCRIPT_DIR/ssh_keys/adempiere_installation_key"
REGEN_KEY=false

if [[ "$SERVER_MODE" == "hardened" ]]; then
  # Server is already hardened: skip all pre-hardening steps.
  # To redo hardening, reinstall the OS and rerun this script on the fresh server.
  echo ">>> Tasks 1-5: Skipped — server is already hardened"
  echo "    (port $CUSTOM_SSHPORT is open, port 22 is closed)"
  echo ""
else
  # Task 1 — Keypair handling
  if [[ -n "$CHECK" ]]; then
    echo ">>> Task 1 of 10: Keypair check — skipped in dry-run mode"
    echo ""
  elif [[ -f "$KEY_PATH" ]]; then
    echo ">>> Task 1 of 10: SSH keypair already exists at ssh_keys/adempiere_installation_key"
    echo ""
    echo "  ┌─────────────────────────────────────────────────────────────────┐"
    echo "  │  WARNING                                                        │"
    echo "  │  Deleting this keypair will lock you out of ANY server that     │"
    echo "  │  already has the current public key deployed.                   │"
    echo "  │  Only answer YES if this is a full server reset and no other    │"
    echo "  │  servers are using this keypair.                                │"
    echo "  └─────────────────────────────────────────────────────────────────┘"
    echo ""
    read -rp "  Delete and regenerate the keypair? [yes/NO]: " key_confirm
    if [[ "$key_confirm" == "YES" ]]; then
      echo "  Deleting old keypair..."
      rm -f "$KEY_PATH" "$KEY_PATH.pub"
      REGEN_KEY=true
      echo "  Done."
    else
      echo "  Keeping existing keypair."
      REGEN_KEY=false
    fi
    echo ""
  else
    echo ">>> Task 1 of 10: No keypair found — a new one will be generated."
    REGEN_KEY=true
    echo ""
  fi

  # Task 2 — Generate keypair
  if [[ "$REGEN_KEY" == "true" ]]; then
    echo ">>> Task 2 of 10: genkey.yml — Generate SSH keypair"
    _t=$SECONDS; ansible-playbook genkey.yml $CHECK
    dur_genkey=$((SECONDS - _t)); GENKEY_STATUS="$(format_duration $dur_genkey)"
  else
    echo ">>> Task 2 of 10: genkey.yml — Skipped (existing keypair kept)"
  fi
  echo ""

  echo "  ┌─────────────────────────────────────────────────────────────────┐"
  _box "TASKS 3-5 CONNECT AS ROOT ON PORT 22"
  _box "Ensure port 22 is open on the server before continuing."
  _box ""
  _box "Cloud firewall users (Contabo, Hetzner, AWS ...): verify now."
  _box "Port 22 will be closed after Task 5 (serversconf.yml)."
  echo "  └─────────────────────────────────────────────────────────────────┘"
  echo ""
  read -rp "  Confirm port 22 is open, then press ENTER to continue: " _
  echo ""

  # Task 3 — Distribute public key to backend (root, port 22)
  echo ">>> Task 3 of 10: serversprep.yml — Distribute SSH key to BackEnd"
  _t=$SECONDS; ansible-playbook serversprep.yml --limit BackEnd $CHECK
  dur_step3=$((SECONDS - _t)); STEP3_STATUS="$(format_duration $dur_step3)"
  echo ""

  # Task 4 — OS updates + reboot
  echo ">>> Task 4 of 10: os-updates.yml — OS update + reboot"
  _t=$SECONDS; ansible-playbook os-updates.yml --limit BackEnd $CHECK
  dur_step4=$((SECONDS - _t)); STEP4_STATUS="$(format_duration $dur_step4)"
  echo ""

  # Task 5 — Full server hardening
  echo ">>> Task 5 of 10: serversconf.yml — Server hardening"
  _t=$SECONDS; ansible-playbook serversconf.yml --limit BackEnd $CHECK
  dur_step5=$((SECONDS - _t)); STEP5_STATUS="$(format_duration $dur_step5)"
  echo ""

  if [[ -z "$CHECK" ]]; then
    echo "  ┌─────────────────────────────────────────────────────────────────┐"
    _box "SSH PORT HAS CHANGED"
    _box "serversconf.yml has moved SSH from port 22 to port $CUSTOM_SSHPORT."
    _box "Tasks 6-10 will connect on the new port."
    _box ""
    _box "Cloud firewall users (Contabo, Hetzner, AWS ...): act now."
    _box "  1. Open port $CUSTOM_SSHPORT."
    _box "  2. Close port 22."
    _box "Tasks 6-10 will fail to connect if port $CUSTOM_SSHPORT is blocked."
    echo "  └─────────────────────────────────────────────────────────────────┘"
    echo ""
    read -rp "  Firewall updated for SSH? Press ENTER to continue with Tasks 6-10: " _
  else
    echo "  NOTE (dry run): in a real run SSH moves to port $CUSTOM_SSHPORT after this step."
    echo "  Ensure port $CUSTOM_SSHPORT is open in your cloud firewall before running live."
    echo ""
    read -rp "  Press ENTER to continue with Tasks 6-10: " _
  fi
  echo ""
fi

# Task 6 — WireGuard VPN server
if [[ "$WIREGUARD_ENABLED" == "true" ]]; then
  echo ">>> Task 6 of 10: deploy-wireguard.yml — Install WireGuard VPN server"
  _t=$SECONDS; ansible-playbook deploy-wireguard.yml $CHECK
  dur_wireguard=$((SECONDS - _t)); WIREGUARD_STATUS="$(format_duration $dur_wireguard)"
  echo ""
  echo "  ┌─────────────────────────────────────────────────────────────────┐"
  _box "WIREGUARD UDP PORT $WIREGUARD_PORT"
  if [[ -z "$CHECK" ]]; then
    _box "WireGuard is now running. Open UDP port $WIREGUARD_PORT in your"
    _box "cloud firewall so POS clients can reach the VPN server."
  else
    _box "NOTE (dry run): in a real run WireGuard would now be running."
    _box "Open UDP port $WIREGUARD_PORT in your cloud firewall so POS"
    _box "clients can reach the VPN server."
  fi
  _box ""
  _box "Cloud firewall users (Contabo, Hetzner, AWS ...): act now."
  _box "Protocol: UDP -- not TCP."
  echo "  └─────────────────────────────────────────────────────────────────┘"
  echo ""
  read -rp "  Firewall updated for WireGuard UDP? Press ENTER to continue: " _
else
  echo ">>> Task 6 of 10: deploy-wireguard.yml — Skipped (wireguard_enabled: false)"
fi
echo ""

# Task 7 — Swap
echo ">>> Task 7 of 10: serverswap.yml — Configure swap"
_t=$SECONDS; ansible-playbook serverswap.yml --limit BackEnd $CHECK
dur_step7=$((SECONDS - _t)); STEP7_STATUS="$(format_duration $dur_step7)"
echo ""

# Task 8 — Docker CE
echo ">>> Task 8 of 10: install-docker.yml — Install Docker"
_t=$SECONDS; ansible-playbook install-docker.yml --limit BackEnd $CHECK
dur_step8=$((SECONDS - _t)); STEP8_STATUS="$(format_duration $dur_step8)"
echo ""

# Task 9 — ADempiere stack
echo ">>> Task 9 of 10: deploy-adempiere.yml — Deploy ADempiere"
_t=$SECONDS; ansible-playbook deploy-adempiere.yml $CHECK
dur_step9=$((SECONDS - _t)); STEP9_STATUS="$(format_duration $dur_step9)"
echo ""

# Task 10 — Crontab
echo ">>> Task 10 of 10: deploy-crontab.yml — Configure crontab"
_t=$SECONDS; ansible-playbook deploy-crontab.yml $CHECK
dur_step10=$((SECONDS - _t)); STEP10_STATUS="$(format_duration $dur_step10)"
echo ""

CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}${BOLD}  ⏱  Deployment Timing${NC}"
echo -e "${CYAN}  Pre-flight:           $(format_duration $dur_preflight)${NC}"
echo -e "${CYAN}  Task 2  genkey:       $GENKEY_STATUS${NC}"
echo -e "${CYAN}  Task 3  serversprep:  $STEP3_STATUS${NC}"
echo -e "${CYAN}  Task 4  os-updates:   $STEP4_STATUS${NC}"
echo -e "${CYAN}  Task 5  serversconf:  $STEP5_STATUS${NC}"
echo -e "${CYAN}  Task 6  WireGuard:    $WIREGUARD_STATUS${NC}"
echo -e "${CYAN}  Task 7  swap:         $STEP7_STATUS${NC}"
echo -e "${CYAN}  Task 8  Docker:       $STEP8_STATUS${NC}"
echo -e "${CYAN}  Task 9  ADempiere:    $STEP9_STATUS${NC}"
echo -e "${CYAN}  Task 10 crontab:      $STEP10_STATUS${NC}"
echo -e "${CYAN}  ─────────────────────${NC}"
echo -e "${CYAN}${BOLD}  Total:                $(format_duration $((dur_preflight + dur_genkey + dur_step3 + dur_step4 + dur_step5 + dur_wireguard + dur_step7 + dur_step8 + dur_step9 + dur_step10)))${NC}"
echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo ""

# --- Aggregated Ansible task counters from all PLAY RECAP lines in the log ---
# Strip ANSI codes first (ANSIBLE_FORCE_COLOR=1 embeds them), then sum each
# counter field across every per-host PLAY RECAP line in this run's log file.
read -r T_OK T_CHANGED T_UNREACHABLE T_FAILED T_SKIPPED T_RESCUED T_IGNORED < <(
  sed 's/\x1b\[[0-9;]*m//g' "$LOGFILE" \
  | awk '/ : ok=/ {
      for (i=1; i<=NF; i++) { n=split($i,a,"="); if (n==2) c[a[1]] += a[2]+0 }
    }
    END { print c["ok"]+0, c["changed"]+0, c["unreachable"]+0,
                c["failed"]+0, c["skipped"]+0, c["rescued"]+0, c["ignored"]+0 }'
)
# Parse individual TASK [...] + status lines to split counters by prefix (INFO: vs APPLY:).
# Counts one status per task (highest priority wins) to match PLAY RECAP task-level counting.
# Priority: failed(4) > changed(3) > skipped(2) > ok/included(1).
# This avoids overcounting looped tasks where each item emits its own status line.
read -r I_OK I_SKP AP_OK AP_CHG AP_SKP AP_FAIL < <(
  sed 's/\x1b\[[0-9;]*m//g' "$LOGFILE" \
  | awk '
    BEGIN { cur = ""; cs = ""; cp = 0 }
    function commit() { if (cur != "" && cs != "") cnt[cur,cs]++ }
    function see(s, p) { if (p > cp) { cs = s; cp = p } }
    /^TASK \[/ {
      commit()
      if      ($0 ~ /: INFO:/)  cur = "info"
      else if ($0 ~ /: APPLY:/) cur = "apply"
      else                      cur = "other"
      cs = ""; cp = 0
      next
    }
    /^ok: /       || /^included: / { see("ok",      1); next }
    /^changed: /                   { see("changed",  3); next }
    /^skipping: / || /^skipped: /  { see("skipped",  2); next }
    /^failed: /                    { see("failed",   4); next }
    END {
      commit()
      print cnt["info","ok"]+0,  cnt["info","skipped"]+0,
            cnt["apply","ok"]+0, cnt["apply","changed"]+0,
            cnt["apply","skipped"]+0, cnt["apply","failed"]+0
    }
  '
)
# _c: print one colored "key=val" counter followed by two spaces
_c() {
  local col
  case "$1" in
    ok|rescued)          col='\033[0;32m' ;;   # green
    changed|ignored)     col='\033[1;33m' ;;   # yellow
    unreachable|failed)  col='\033[1;31m' ;;   # bright red
    skipped)             col='\033[0;36m' ;;   # cyan
  esac
  printf "${col}${1}=${2:-0}\033[0m  "
}
echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}${BOLD}  Ansible Task Counters (all playbooks combined)${NC}"
printf "  "
_c ok          "${T_OK:-0}"
_c changed     "${T_CHANGED:-0}"
_c unreachable "${T_UNREACHABLE:-0}"
_c failed      "${T_FAILED:-0}"
_c skipped     "${T_SKIPPED:-0}"
_c rescued     "${T_RESCUED:-0}"
_c ignored     "${T_IGNORED:-0}"
echo ""
echo ""
echo -e "  ${BOLD}By task prefix:${NC}"
printf "  %-8s" "INFO:"
_c ok      "${I_OK:-0}"
_c skipped "${I_SKP:-0}"
echo -e "  ${CYAN}(diagnostic prints only)${NC}"
printf "  %-8s" "APPLY:"
_c ok      "${AP_OK:-0}"
_c changed "${AP_CHG:-0}"
_c skipped "${AP_SKP:-0}"
_c failed  "${AP_FAIL:-0}"
echo ""
echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo ""

echo "================================================================"
if [[ -z "$CHECK" ]]; then
  echo "  BackEnd provisioning complete."
else
  echo "  Dry run complete. Review output above before running live."
fi
echo "================================================================"
echo ""

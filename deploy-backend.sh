#!/bin/bash
# SPDX-License-Identifier: MIT-0
#
# deploy-backend.sh — Full BackEnd provisioning from a clean server reset.
#
# Usage:
#   ./deploy-backend.sh           # real run — makes changes on the server
#   ./deploy-backend.sh --check   # dry run — shows what would change, no writes
#
# BEFORE RUNNING:
#   1. Confirm the server is reachable on port 22 as root with password auth.
#   2. Ensure ~/.vault_pass.txt exists (configured via vault_password_file in ansible.cfg).
#
# WHAT THIS SCRIPT DOES:
#   Step 0  Keypair check — if an existing keypair is found, asks whether to delete it.
#           Default is NO. Only deletes on explicit YES. If no keypair exists, generates
#           one silently. WARNING: deleting regenerates the key and locks you out of any
#           server that still has the old public key deployed.
#   Step 1  genkey.yml         — Generate RSA keypair (skipped if existing key was kept).
#   Step 2  serversprep.yml    — Distribute the public key to the backend (root, port 22).
#   Step 3  so-updates.yml     — OS update + reboot.
#   Step 4  serversconf.yml    — Full server hardening: user, SSH, packages.
#   Step 5  serverswap.yml     — Configure swap file (8 GB, from group_vars/BackEnd.yml).
#   Step 6  install-docker.yml — Install Docker CE (pinned to 28.x).
#   Step 7  deploy-adempiere.yml — Deploy the ADempiere container stack.
#   Step 8  deploy-crontab.yml  — Configure crontab: @reboot start, 23:50 stop, 23:55 restart.
#
# NOTE ON --check:
#   Step 0 (keypair handling) is skipped in check mode — no local files are touched.
#   so-updates.yml: the reboot task uses shell/command and is skipped by Ansible
#   in check mode, so the dry run will not reflect the post-reboot state.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
LOGFILE="$LOG_DIR/deploy-backend-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "Output is logged to: $LOGFILE"
echo ""

# Build a display list of BackEnd hosts and their IPs from the inventory.
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

CHECK=""
if [[ "${1:-}" == "--check" ]]; then
  CHECK="--check"
  echo ""
  echo "================================================================"
  echo "  DRY RUN mode (--check) — no changes will be made"
  echo "================================================================"
  echo ""
else
  echo ""
  echo "================================================================"
  echo "  LIVE RUN — changes will be made on the backend server"
  echo ""
  echo "  Target BackEnd server(s):"
  echo "$BACKEND_LIST"
  echo "  Prerequisites:"
  echo "    - All servers above are reachable on port 22 as root with password auth"
  echo "    - ~/.vault_pass.txt exists (used automatically via ansible.cfg)"
  echo ""
  read -rp "  Type YES to continue: " confirm
  if [[ "$confirm" != "YES" ]]; then
    echo "  Aborted."
    exit 1
  fi
  echo "================================================================"
  echo ""
fi

# Pre-flight: vault password file must exist (ansible.cfg references ~/.vault_pass.txt)
if [[ ! -f "$HOME/.vault_pass.txt" ]]; then
  echo "ERROR: ~/.vault_pass.txt not found."
  echo "       Create it with your vault password before running this script."
  exit 1
fi

# Pre-flight: remove stale host key for the backend server from known_hosts.
# Required after a server reset — the host presents a new key and SSH would refuse to connect.
BACKEND_IP=$(ansible-inventory --host backend1 2>/dev/null \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('ansible_host',''))" 2>/dev/null)
if [[ -n "$BACKEND_IP" ]]; then
  echo ">>> Pre-flight: removing stale known_hosts entry for $BACKEND_IP"
  ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$BACKEND_IP" 2>/dev/null || true
  echo ""
else
  echo "WARNING: could not determine backend IP from inventory — skipping known_hosts cleanup."
  echo ""
fi

KEY_PATH="$SCRIPT_DIR/ssh_keys/adempiere_installation_key"
REGEN_KEY=false

# Step 0 — Keypair handling
if [[ -n "$CHECK" ]]; then
  echo ">>> Step 0: Keypair check — skipped in dry-run mode"
  echo ""
elif [[ -f "$KEY_PATH" ]]; then
  echo ">>> Step 0: SSH keypair already exists at ssh_keys/adempiere_installation_key"
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
  echo ">>> Step 0: No keypair found — a new one will be generated."
  REGEN_KEY=true
  echo ""
fi

# Step 1 — Generate keypair
if [[ "$REGEN_KEY" == "true" ]]; then
  echo ">>> Step 1: genkey.yml — Generate SSH keypair"
  ansible-playbook genkey.yml $CHECK
else
  echo ">>> Step 1: genkey.yml — Skipped (existing keypair kept)"
fi
echo ""

# Step 2 — Distribute public key to backend (root, port 22)
echo ">>> Step 2: serversprep.yml — Distribute SSH key to BackEnd"
ansible-playbook serversprep.yml --limit BackEnd $CHECK
echo ""

# Step 3 — OS updates + reboot
echo ">>> Step 3: so-updates.yml — OS update + reboot"
ansible-playbook so-updates.yml --limit BackEnd $CHECK
echo ""

# Step 4 — Full server hardening
echo ">>> Step 4: serversconf.yml — Server hardening"
ansible-playbook serversconf.yml --limit BackEnd $CHECK
echo ""

# Step 5 — Swap
echo ">>> Step 5: serverswap.yml — Configure swap"
ansible-playbook serverswap.yml --limit BackEnd $CHECK
echo ""

# Step 6 — Docker CE
echo ">>> Step 6: install-docker.yml — Install Docker"
ansible-playbook install-docker.yml --limit BackEnd $CHECK
echo ""

# Step 7 — ADempiere stack
echo ">>> Step 7: deploy-adempiere.yml — Deploy ADempiere"
ansible-playbook deploy-adempiere.yml $CHECK
echo ""

# Step 8 — Crontab
echo ">>> Step 8: deploy-crontab.yml — Configure crontab"
ansible-playbook deploy-crontab.yml $CHECK
echo ""

echo "================================================================"
if [[ -z "$CHECK" ]]; then
  echo "  BackEnd provisioning complete."
else
  echo "  Dry run complete. Review output above before running live."
fi
echo "================================================================"
echo ""

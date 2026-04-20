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
#   1. Reset the backend server (all data will be lost).
#   2. Confirm the server is reachable on port 22 as root with password auth.
#   3. Ensure vault password file / ANSIBLE_VAULT_PASSWORD_FILE is configured.
#
# WHAT THIS SCRIPT DOES:
#   Step 0  Delete the existing SSH keypair from ssh_keys/ on this control node.
#           Required because genkey.yml uses state=present and will not regenerate
#           an existing keypair. A server reset means the old public key is gone
#           from the server anyway — a fresh keypair keeps everything consistent.
#   Step 1  genkey.yml       — Generate a new RSA keypair on this control node.
#   Step 2  serversprep.yml  — Distribute the public key to the backend (root, port 22).
#   Step 3  so-updates.yml   — OS update + reboot.
#   Step 4  serversconf.yml  — Full server hardening: user, SSH, packages.
#   Step 5  install-docker.yml — Install Docker CE (pinned to 28.x).
#   Step 6  deploy-adempiere.yml — Deploy the ADempiere container stack.
#
# NOTE ON --check:
#   Step 0 (keypair deletion) is skipped in check mode — no local files are touched.
#   so-updates.yml: the reboot task uses shell/command and is skipped by Ansible
#   in check mode, so the dry run will not reflect the post-reboot state.

set -euo pipefail

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
  echo "  Prerequisites:"
  echo "    - Backend server has been RESET (fresh, port 22, root+password)"
  echo "    - Vault password is available (ANSIBLE_VAULT_PASSWORD_FILE set)"
  echo ""
  echo "  The existing SSH keypair in ssh_keys/ will be DELETED and"
  echo "  regenerated. This is intentional after a server reset."
  echo ""
  read -rp "  Type YES to continue: " confirm
  if [[ "$confirm" != "YES" ]]; then
    echo "  Aborted."
    exit 1
  fi
  echo "================================================================"
  echo ""
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEY_PATH="$SCRIPT_DIR/ssh_keys/adempiere_installation_key"

# Step 0 — Delete old keypair (skipped in check mode)
if [[ -z "$CHECK" ]]; then
  echo ">>> Step 0: Deleting old SSH keypair..."
  rm -f "$KEY_PATH" "$KEY_PATH.pub"
  echo "    Done."
  echo ""
fi

# Step 1 — Generate new keypair
echo ">>> Step 1: genkey.yml — Generate SSH keypair"
ansible-playbook genkey.yml $CHECK
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

# Step 5 — Docker CE
echo ">>> Step 5: install-docker.yml — Install Docker"
ansible-playbook install-docker.yml --limit BackEnd $CHECK
echo ""

# Step 6 — ADempiere stack
echo ">>> Step 6: deploy-adempiere.yml — Deploy ADempiere"
ansible-playbook deploy-adempiere.yml $CHECK
echo ""

echo "================================================================"
if [[ -z "$CHECK" ]]; then
  echo "  BackEnd provisioning complete."
else
  echo "  Dry run complete. Review output above before running live."
fi
echo "================================================================"
echo ""

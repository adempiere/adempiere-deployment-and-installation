# Getting Started — First Deployment

This page gives you the complete command sequence for a first deployment. Each step is covered in detail in [installation.md](installation.md).

Before running anything, work through:
1. [requirements.md](requirements.md) — verify your control node and servers meet all requirements
2. [vault.md](vault.md) — set up your vault password file and populate all variables

---

## Two Phases: Infrastructure vs. Application

The deployment is split into two distinct phases with different lifecycles:

| Phase | Playbooks | When to run |
|---|---|---|
| **Infrastructure** | `genkey`, `serversprep`, `so-updates`, `serversconf`, `install-docker`, `deploy-traefik` | **Once**, when setting up a new server. Re-run only if the server is rebuilt or configuration changes. |
| **Application** | `deploy-adempiere`, `adempiere-restoredb` | On every deployment, update, or database restore. Independent of the infrastructure phase. |

Traefik in particular is infrastructure: once it is running on the FrontEnd server it stays there, routing traffic, renewing certificates automatically. You do not reinstall it when you update ADempiere.

---

## Phase 1 — Infrastructure Setup (run once)

```bash
# --- One-time setup on your control node ---

# Install required Ansible collections
ansible-galaxy collection install community.docker community.postgresql community.crypto

# Create the vault password file
echo "YourVaultPassword" > ~/.vault_pass.txt && chmod 600 ~/.vault_pass.txt

# Populate all variables: secrets, IPs, domain, SSH port, Cloudflare token, etc.
# See vault.md for the full list of required variables
ansible-vault edit group_vars/all.yml


# --- Infrastructure playbooks (run from the project root, in this order) ---

ansible-playbook genkey.yml          # Generate SSH keypair on this machine
ansible-playbook serversprep.yml     # Distribute SSH key to servers
ansible-playbook so-updates.yml      # Update OS, reboot if needed
ansible-playbook serversconf.yml     # Harden SSH, create user, install packages
ansible-playbook install-docker.yml  # Install Docker CE
ansible-playbook deploy-traefik.yml  # Deploy Traefik proxy (FrontEnd — once)
```

---

## Phase 2 — Application Deployment (run as needed)

```bash
ansible-playbook deploy-adempiere.yml   # Deploy or update ADempiere (BackEnd)
# ansible-playbook adempiere-restoredb.yml  # Only when restoring from a backup
```

---

## What to Expect

**Infrastructure phase (Phase 1):**

| Step | Target | Duration | Notes |
|---|---|---|---|
| `genkey.yml` | localhost | seconds | Skipped if `~/.ssh/id_rsa` already exists |
| `serversprep.yml` | both servers | seconds | Needs root password in vault and port 22 open |
| `so-updates.yml` | both servers | 5–15 min | May reboot; waits automatically for server to return |
| `serversconf.yml` | both servers | 2–5 min | After this, root login is disabled and SSH port changes |
| `install-docker.yml` | both servers | 2–5 min | Docker is needed on both: BackEnd for ADempiere/PostgreSQL containers, FrontEnd for Traefik/socket-proxy |
| `deploy-traefik.yml` | FrontEnd only | 1–2 min | TLS certificate is issued on first HTTPS request; **run once** |

**Application phase (Phase 2):**

| Step | Target | Duration | Notes |
|---|---|---|---|
| `deploy-adempiere.yml` | BackEnd only | 5–10 min | Starts ADempiere + PostgreSQL containers; includes waiting for containers to become healthy |
| `adempiere-restoredb.yml` | BackEnd only | varies | Only when restoring from a backup |

---

## After Deployment

- ADempiere: `https://adempiere.<dns_domain>`
- Traefik dashboard: `http://traefik.<dns_domain>:28080`

If anything fails, see [troubleshooting.md](troubleshooting.md).

---

[← Configuration](configuration.md) | [Next: Installation →](installation.md)

# Getting Started — First Deployment

This page gives you the complete command sequence for a first deployment.   
Each step is covered in detail in [installation.md](installation.md).

Before running anything, work through:  
1. [requirements.md](requirements.md) — verify your control node and servers meet all requirements  
2. [vault.md](vault.md) — set up your vault password file and populate all variables

---

## Deployment Phases

The deployment is split into four phases.  
Phases 1 and 2 cover the BackEnd; phases 3 and 4 cover the FrontEnd.   
Within each server, a dry run (`--check`) comes first so you can verify configuration before making any real changes.

| Phase | Target | Mode | Purpose |
|---|---|---|---|
| **1** | BackEnd | `--check` | Dry run — validate configuration, catch errors early |
| **2** | BackEnd | real | Bring up ADempiere + PostgreSQL; verify directly on BackEnd IP |
| **3** | FrontEnd | `--check` | Dry run — validate Traefik configuration |
| **4** | FrontEnd | real | Bring up Traefik; full system reachable via domain + HTTPS |

Traefik is infrastructure: once running on the FrontEnd it stays there, routing traffic and renewing certificates automatically.   
You do not reinstall it when you update ADempiere.

> **Note on `--check` reliability:**   
> For OS-level playbooks (`serversprep`, `so-updates`, `serversconf`) dry-run output is accurate.  
> For Docker playbooks (`install-docker`, `deploy-adempiere`, `deploy-traefik`) it is approximate — images are not pulled and containers are not started, so some tasks may report `changed` or `skipped` inconsistently.   
> The main value is validating your variable configuration and Jinja2 templates.

---

## One-time control-node setup

Run these once on your **local machine** before any playbook. Nothing is sent to the servers yet.

> **If you have PostgreSQL or Docker installed locally:**  
> they are not affected. `ansible-galaxy collection install` only places Python module code in `~/.ansible/collections/` — it installs no services and does not interact with any local database or Docker daemon.  
> All playbook tasks run on the remote servers.   
> The one exception is `genkey.yml`, which runs locally but only generates an SSH keypair in `~/.ssh/`.

```bash
# Install required Ansible collections (Python module code only — no services installed locally).
# community.postgresql is used by adempiere-restoredb to connect to the PostgreSQL container
# on the BackEnd server. community.docker manages containers on the remote servers.
ansible-galaxy collection install community.docker community.postgresql community.crypto

# Create the vault password file
echo "MyVaultPassword" > ~/.vault_pass.txt && chmod 600 ~/.vault_pass.txt

# Populate all variables (IPs, domain, SSH port, passwords, Cloudflare token…)
ansible-vault edit group_vars/all.yml
```

See [vault.md](vault.md) for the full list of required variables.

---

## Phase 1 — BackEnd dry run

```bash
ansible-playbook genkey.yml                              --check
ansible-playbook serversprep.yml    --limit BackEnd      --check
ansible-playbook so-updates.yml     --limit BackEnd      --check
ansible-playbook serversconf.yml    --limit BackEnd      --check
ansible-playbook install-docker.yml --limit BackEnd      --check  # approximate
ansible-playbook deploy-adempiere.yml                    --check  # approximate
```

Review the output. Anything unexpected? Adjust `group_vars/all.yml` and re-run `--check` before proceeding.

---

## Phase 2 — BackEnd real run

```bash
ansible-playbook genkey.yml                         # Generate SSH keypair (skipped if already exists)
ansible-playbook serversprep.yml    --limit BackEnd  # Distribute SSH key; needs root + port 22
ansible-playbook so-updates.yml     --limit BackEnd  # OS update; may reboot, waits automatically
ansible-playbook serversconf.yml    --limit BackEnd  # Harden SSH, create user — root login disabled after this
ansible-playbook install-docker.yml --limit BackEnd  # Install Docker CE
ansible-playbook deploy-adempiere.yml                # Deploy ADempiere + PostgreSQL containers
```

After this phase ADempiere is reachable directly at `http://<backend_ip>:<adempiere_port>` — no domain, no TLS. Use this to verify the application is running before touching the FrontEnd.

---

## Phase 3 — FrontEnd dry run

> **Constraint:** The Docker playbooks (`install-docker`, `deploy-traefik`) connect as `westfalia` on the custom SSH port. For `--check` to work on those, the `westfalia` user must already exist on the FrontEnd. The OS playbooks are dry-run first (root, port 22); then `serversconf.yml` is run for real to create the user; then the Docker playbooks are dry-run.

```bash
# OS playbooks — accurate --check, connects as root on port 22
ansible-playbook serversprep.yml    --limit FrontEnd --check
ansible-playbook so-updates.yml     --limit FrontEnd --check
ansible-playbook serversconf.yml    --limit FrontEnd --check

# Run serversconf for real to create the westfalia user and change the SSH port
ansible-playbook serversprep.yml    --limit FrontEnd
ansible-playbook so-updates.yml     --limit FrontEnd
ansible-playbook serversconf.yml    --limit FrontEnd

# Now --check the Docker playbooks
ansible-playbook install-docker.yml --limit FrontEnd --check  # approximate
ansible-playbook deploy-traefik.yml                  --check  # approximate
```

---

## Phase 4 — FrontEnd real run

```bash
ansible-playbook install-docker.yml --limit FrontEnd  # Install Docker CE
ansible-playbook deploy-traefik.yml                   # Deploy Traefik + socket-proxy (run once)
```

After this phase the full system is reachable:

- ADempiere: `https://adempiere.<dns_domain>`
- Traefik dashboard: `http://traefik.<dns_domain>:28080`

TLS certificate is issued automatically on the first HTTPS request via Let's Encrypt + Cloudflare DNS.

---

## Duration reference

| Playbook | Target | Duration | Notes |
|---|---|---|---|
| `genkey.yml` | localhost | seconds | Skipped if `~/.ssh/id_rsa` already exists |
| `serversprep.yml` | per server | seconds | Needs root password in vault and port 22 open |
| `so-updates.yml` | per server | 5–15 min | May reboot; waits automatically for server to return |
| `serversconf.yml` | per server | 2–5 min | After this, root login is disabled and SSH port changes |
| `install-docker.yml` | per server | 2–5 min | Docker needed on both: BackEnd for ADempiere/PostgreSQL, FrontEnd for Traefik/socket-proxy |
| `deploy-adempiere.yml` | BackEnd | 5–10 min | Starts containers; waits for health checks |
| `deploy-traefik.yml` | FrontEnd | 1–2 min | Run once; TLS issued on first HTTPS request |
| `adempiere-restoredb.yml` | BackEnd | varies | Only when restoring from a backup |

---

If anything fails, see [troubleshooting.md](troubleshooting.md).

---

[← Configuration](configuration.md) | [Next: Installation →](installation.md)

# Getting Started — First Deployment

This page gives you the complete command sequence for a first deployment.   
Each step is covered in detail in [installation.md](installation.md).

Before running anything, work through:  
1. [requirements.md](requirements.md) — verify your control node and servers meet all requirements  
2. [vault.md](vault.md) — set up your vault password file and populate all variables

---

## Deployment Phases

| Phase | Target | Mode | Purpose |
|---|---|---|---|
| **0** | local | — | One-time control-node setup + pre-flight checks |
| **1** | BackEnd | `--check` | Dry run — validate OS configuration (`serversprep`, `so-updates`, `serversconf`) |
| **2** | BackEnd | real | Bring up ADempiere + PostgreSQL; verify directly on BackEnd IP |
| **3** | FrontEnd | `--check` | Dry run — validate Traefik configuration |
| **4** | FrontEnd | real | Bring up Traefik; full system reachable via domain + HTTPS |

Phases 1 and 2 cover the BackEnd; phases 3 and 4 cover the FrontEnd.  
Within each server, a dry run (`--check`) comes first so you can verify configuration before making any real changes.

Traefik is infrastructure: once running on the FrontEnd it stays there, routing traffic and renewing certificates automatically.   
You do not reinstall it when you update ADempiere.

> **Note on `--check` reliability:**   
> For OS-level playbooks (`serversprep`, `so-updates`, `serversconf`) dry-run output is accurate.  
> For Docker playbooks (`install-docker`, `deploy-adempiere`, `deploy-traefik`) `--check` is only run in Phase 3 (FrontEnd), after `serversconf.yml` has run for real and the user + custom SSH port exist. Output is approximate — images are not pulled and containers are not started, so some tasks may report `changed` or `skipped` inconsistently. The main value is validating your variable configuration and Jinja2 templates.
>
> **Expected `--check` warning in `serversconf.yml`:** The "Add ADMIN ssh-keys" task will report a failure for `adempiere_username` followed by `...ignoring`. This is expected: in check mode the user creation task does not actually run, so the user does not exist yet when the key task runs. The error is suppressed with `ignore_errors: "{{ ansible_check_mode }}"` and does not affect real runs.

---

## Phase 0 — One-time setup & pre-flight

Run these once on your **local machine** before any playbook. Nothing is sent to the servers yet.

> **If you have PostgreSQL or Docker installed locally:**  
> they are not affected. `ansible-galaxy collection install` only places Python module code in `~/.ansible/collections/` — it installs no services and does not interact with any local database or Docker daemon.  
> All playbook tasks run on the remote servers.  
> The one exception is `genkey.yml`, which runs locally and generates an SSH keypair inside the project under `ssh_keys/`.

```bash
# Install required Ansible collections (Python module code only — no services installed locally).
# community.postgresql is used by adempiere-restoredb to connect to the PostgreSQL container
# on the BackEnd server. community.docker manages containers on the remote servers.
ansible-galaxy collection install community.docker community.postgresql community.crypto

# Create the vault password file
echo "MyVaultPassword" > ~/.vault_pass.txt && chmod 600 ~/.vault_pass.txt

# Populate all variables (IPs, domain, SSH port, passwords, Cloudflare token…)
cp group_vars/vars_template.yml group_vars/all/vars.yml   # then fill in your values
cp group_vars/vault_template.yml group_vars/all/vault.yml  # then fill in secrets
ansible-vault encrypt group_vars/all/vault.yml
```

See [vault.md](vault.md) for the full list of required variables.

```bash
# Generate SSH keypair — required before any other playbook.
# The repository does not include SSH keys; each operator generates their own after cloning.
# Idempotent — safe to re-run; skips generation if the keypair already exists.
ansible-playbook genkey.yml
```

> **Strongly recommended:** keep the default key name `adempiere_installation_key`.  
> Changing it requires updating `key_name` and `ansible_ssh_private_key_file` in `group_vars/all/vars.yml`.

This creates:
- `ssh_keys/adempiere_installation_key` — private key (gitignored, never commit)
- `ssh_keys/adempiere_installation_key.pub` — public key (gitignored)
- `roles/serversconf/files/public_keys/present/admin/adempiere_installation_key.pub` — copy deployed to servers by `serversconf` (gitignored)

Then verify everything is in place before proceeding:

```bash
# Ansible version — expect core 2.14+
ansible --version

# Required collections — expect 3 lines
ansible-galaxy collection list | grep -E 'community\.(docker|postgresql|crypto)'

# Vault password file — expect mode 0600
ls -la ~/.vault_pass.txt

# Vault decrypts and contains all required variables
ansible-vault view group_vars/all/vault.yml | grep -E 'root_user_password|adempiere_username|adempiere_user_password|adempiere_user_become_pass|custom_sshport'

# Inventory has real IPs — no placeholders
cat inventories/hosts.yml

# SSH keypair exists
ls ssh_keys/adempiere_installation_key ssh_keys/adempiere_installation_key.pub

# Syntax check — no errors, no warnings
ansible-playbook main.yml --syntax-check
ansible-playbook main-w-traefik.yml --syntax-check
```

For a detailed explanation of each check, see [testing.md](testing.md).

Then verify that the BackEnd is reachable before any playbook touches it:

```bash
ROOT_PASS=$(ansible-vault view group_vars/all/vault.yml | grep root_user_password | awk '{print $2}') && ansible BackEnd -m ping -e "ansible_user=root ansible_password=$ROOT_PASS"
```

This single command replaces the need to manually run `ping`, `nc`, or `ssh` against the server IP.  
If it returns `pong`, you have confirmed:
- The server is reachable over the network
- Port 22 is open (SSH is listening)
- Root login with the vault password works
- Python is available on the server (required by Ansible)

The IP is never typed directly — Ansible reads it from `inventories/hosts.yml`. This also means the command stays correct if the IP changes; only the inventory needs updating.

**Expected:** `pong` from `backend`.  
If it fails, do not proceed — fix connectivity first. See the SSH / Network section in [testing.md](testing.md) for diagnostics.

---

## Phase 1 — BackEnd dry run

> **If you have previously SSH'd to the BackEnd manually**, its fingerprint is already in `~/.ssh/known_hosts`. Remove it first so `serversprep.yml` can add it correctly:
> ```bash
> ssh-keygen -R <backend_ip>
> ```
> The IP is in `inventories/hosts.yml`. `serversprep.yml` will re-add the fingerprint automatically.

```bash
# genkey.yml was already run in the one-time setup above — skip if keypair exists
ansible-playbook serversprep.yml    --limit BackEnd      --check
ansible-playbook so-updates.yml     --limit BackEnd      --check
ansible-playbook serversconf.yml    --limit BackEnd      --check
```

> **Why `install-docker.yml` and `deploy-adempiere.yml` are not dry-run here:**  
> Both connect as `adempiere_username` on the custom SSH port. Neither the user nor the port exist until `serversconf.yml` has run for real (Phase 2). Running `--check` at this stage will always fail with "Connection refused" — it provides no useful information.

Review the output. Anything unexpected? Adjust `group_vars/all/vars.yml` or `group_vars/all/vault.yml` and re-run `--check` before proceeding.

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

### Verify — BackEnd

```bash
# SSH port reachable (from your local machine)
nc -zv <backend_ip> <custom_sshport>

# SSH to BackEnd
ssh <admin_user>@<backend_ip> -p <custom_sshport>
```

On the BackEnd server:

```bash
docker ps                          # ADempiere containers in Up state
systemctl is-active docker         # expect: active
id <admin_user>                    # user exists, sudo group present
```

Open `http://<backend_ip>:<adempiere_port>` in a browser and confirm ADempiere loads before proceeding.  
If anything is wrong, see [testing.md](testing.md) for diagnostics.

---

## Phase 3 — FrontEnd dry run

Before proceeding, verify the FrontEnd is reachable:

```bash
ROOT_PASS=$(ansible-vault view group_vars/all/vault.yml | grep root_user_password | awk '{print $2}') && ansible FrontEnd -m ping -e "ansible_user=root ansible_password=$ROOT_PASS"
```

**Expected:** `pong` from `frontend`.  
If it fails, fix connectivity first. See the SSH / Network section in [testing.md](testing.md) for diagnostics.

> **Constraint:** The Docker playbooks (`install-docker`, `deploy-traefik`) connect as `<admin_user>` on the custom SSH port. For `--check` to work on those, the `adempiere_username` user must already exist on the FrontEnd. The OS playbooks are dry-run first (root, port 22); then `serversconf.yml` is run for real to create the user; then the Docker playbooks are dry-run.

```bash
# OS playbooks — accurate --check, connects as root on port 22
ansible-playbook serversprep.yml    --limit FrontEnd --check
ansible-playbook so-updates.yml     --limit FrontEnd --check
ansible-playbook serversconf.yml    --limit FrontEnd --check

# Run serversconf for real to create the adempiere_username user and change the SSH port
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

### Verify — Full system

```bash
# DNS resolves to FrontEnd IP
dig adempiere.<dns_domain> +short

# TLS certificate is valid and from Let's Encrypt
curl -sv https://adempiere.<dns_domain> 2>&1 | grep "issuer:"

# Application responds
curl -s -o /dev/null -w "%{http_code}" https://adempiere.<dns_domain>
```

Expected: DNS returns `<frontend_ip>`, certificate issued by Let's Encrypt, HTTP status `200` or `302`.  
Open `https://adempiere.<dns_domain>` in a browser and confirm the login page loads.  
If anything is wrong, see [testing.md](testing.md) for diagnostics.

---

## Duration reference

| Playbook | Target | Duration | Notes |
|---|---|---|---|
| `genkey.yml` | localhost | seconds | Skipped if `ssh_keys/adempiere_installation_key` already exists |
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

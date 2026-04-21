# Installation — Step by Step

## Overview

```
Step 1  genkey.yml              Generate RSA keypair on the control node
Step 2  serversprep.yml         Distribute SSH key to servers (root, password auth)
Step 3  so-updates.yml          Full OS update + reboot if a new kernel was installed
Step 4  serversconf.yml         Harden SSH, create user (adempiere_username), install packages
Step 5  install-docker.yml      Install Docker CE from official repo
Step 6  deploy-vim.yml          Install Vim + plugins  [optional]
Step 7  deploy-adempiere.yml    Deploy ADempiere container stack  [BackEnd only]
Step 8  deploy-traefik.yml      Deploy Traefik reverse proxy  [FrontEnd only]
Step 9  adempiere-restoredb.yml Restore a database backup  [only when needed]
```

Complete the [Pre-Flight Checklist](installation.md#pre-flight-checklist) before starting.

---

## Pre-Flight Checklist

**Control node:**
- [ ] Ansible 2.14+: `ansible --version`
- [ ] Collections installed: `ansible-galaxy collection list | grep -E 'community\.(docker|postgresql|crypto)'`
- [ ] Vault password file: `ls -la ~/.vault_pass.txt` (must be mode `0600`)
- [ ] Vault decrypts: `ansible-vault view group_vars/all/vault.yml`
- [ ] All vault variables populated — see [vault.md](vault.md)

**Target servers:**
- [ ] Accessible via root SSH on port 22
- [ ] OS is Ubuntu 22.04 or Debian 12
- [ ] Internet access: `ping 8.8.8.8` from the server

**DNS & Cloudflare:**
- [ ] `adempiere.<dns_domain>` → FrontEnd IP (`<frontend_ip>`)
- [ ] `traefik.<dns_domain>` → FrontEnd IP (`<frontend_ip>`)
- [ ] Cloudflare API token has `Zone:DNS:Edit` permission

**SSH keys:**
- [ ] Your `.pub` files are in `roles/serversconf/files/public_keys/present/admin/`
  (Step 1 `genkey.yml` adds your key there automatically)

---

## Step 1 — Generate SSH Keypair

Runs on **localhost only**. Creates the keypair at `ssh_keys/adempiere_installation_key` (private, gitignored) and `ssh_keys/adempiere_installation_key.pub` (public, gitignored) inside the project, then copies the public key into the `serversconf` role.

```bash
ansible-playbook genkey.yml
```

Idempotent — skips key generation if `ssh_keys/adempiere_installation_key` already exists.

> **Known issue:** `genkey.yml` has a typo `connection: loca1` (digit `1`). Ansible warns but falls back correctly to local execution. See [known-issues.md](known-issues.md).

---

## Step 2 — Distribute SSH Key

Adds the server host fingerprints to your `~/.ssh/known_hosts` and installs your public key as an authorized key for root on all `servers` servers.

```bash
ansible-playbook serversprep.yml
```

**Requires:** Root password in vault (`root_user_password`). Servers must be on port 22.

After this step you can SSH as root with your key, but Ansible still uses the vault password for the connection credential.

---

## Step 3 — Update the OS

Full `apt dist-upgrade` on all `servers` servers. Reboots automatically if a new kernel was installed and waits up to 5 minutes for the server to come back.

```bash
ansible-playbook so-updates.yml
```

Can take 5–15 minutes depending on pending updates.

---

## Step 4 — Harden and Configure Servers

The most comprehensive step. **Runs as root.**

```bash
ansible-playbook serversconf.yml
```

What it does in order:
1. Refreshes apt cache
2. Installs ~30 system packages (curl, git, htop, ncdu, rsync, tree, unattended-upgrades, vim, etc.)
3. Sets locale to `en_US.UTF-8`
4. Creates user `<admin_user>` with the hashed password from the vault
5. Adds `<admin_user>` to sudoers with `NOPASSWD:ALL`
6. Deploys `.bashrc` template for both root and `<admin_user>`
7. Installs all `.pub` keys from `roles/serversconf/files/public_keys/present/admin/` as authorized keys for both root and `<admin_user>`
8. Configures unattended security upgrades
9. Changes SSH port to `custom_sshport` (via systemd socket override)
10. Hardens `sshd_config`: no password auth, no root login, max 3 auth tries, modern ciphers only

**After this step:** root SSH login is disabled. All further connections use the `<admin_user>` user on the custom port.

---

## Step 5 — Install Docker

Installs Docker CE from the official Docker repository.

```bash
ansible-playbook install-docker.yml
```

What it does:
- Validates OS is Debian/Ubuntu (fails with a clear message otherwise)
- Downloads Docker GPG key to `/etc/apt/keyrings/docker.asc`
- Adds Docker apt repository (`deb822` format)
- Installs: `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`
- Enables and starts the Docker service
- Creates the `/docker` directory (base for all container config files)
- Adds the Ansible user to the `docker` group

---

## Step 6 — Deploy Vim (optional)

Installs a preconfigured Vim setup for the `<admin_user>` user.

```bash
ansible-playbook deploy-vim.yml
```

Plugins installed: `vim-airline`, `nerdtree`, `fzf-vim`, `vim-gitgutter`, `vim-fugitive`, `vim-floaterm`.

---

## Step 7 — Deploy ADempiere

Deploys the ADempiere container stack on the **BackEnd** server (`<backend_ip>`).

```bash
ansible-playbook deploy-adempiere.yml
```

What it does:
1. Creates `<install_path>` owned by `<admin_user>`
2. Clones `adempiere-ui-gateway` (branch `adempiere-trunk`) into `<install_path>/adempiere-ui-gateway`
3. Generates `<install_path>/adempiere-ui-gateway/docker-compose/override.env` with the server IP and PostgreSQL credentials from the vault
4. Checks whether the ADempiere containers are already running — if so, skips to validation
5. If not running, performs a two-phase start:
   - **First `start-all.sh`** — pulls all images and initializes the PostgreSQL database (~4 minutes on a fresh server). Waits for PostgreSQL to be running and ZK to be stable for ≥60 seconds.
   - **`stop-all.sh`** — stops all containers cleanly now that the DB is initialized.
   - **Second `start-all.sh`** — clean start with the pre-initialized DB. All containers come up stably. Waits again for PostgreSQL and ZK stability.
   - Checks the nginx exit code and restarts it if it exited on first run (nginx resolves upstream hostnames at startup; if ZK is not yet registered in Docker DNS, nginx exits with code 1 and needs one restart).
6. Validates that PostgreSQL and ZK are running
7. Prints the container status table

The two-phase start is necessary because of what happens inside the PostgreSQL container on first run: the image includes a custom `initdb.sh` script (in `/docker-entrypoint-initdb.d/`) that PostgreSQL runs automatically when the data directory is empty. It creates the `adempiere` user and database, then runs a full `pg_restore` from the seed backup included in the repository (`postgresql/postgres_backups/seed.backup`). This restore takes 3–5 minutes, during which ZK cannot connect to the DB and is restarted by Docker. The stop/start cycle clears this state and gives every container a clean first start against the fully restored database. On all subsequent starts the data directory already exists and `initdb.sh` is skipped entirely.

---

## Step 8 — Deploy Traefik

Deploys Traefik and the Docker socket proxy on the **FrontEnd** server (`<frontend_ip>`).

```bash
ansible-playbook deploy-traefik.yml
```

What it does:
1. Creates the `gateway` Docker network
2. Creates directory tree under `/docker/traefik/` and `/docker/socket-proxy/`
3. Renders and deploys all configuration from Jinja2 templates:
   - `traefik.yaml` — main Traefik config (entry points, ACME, log level)
   - `tls-opts.yml` — TLS cipher/protocol settings
   - `middlewares-secure-headers.yaml` — security response headers
   - `app-adempiere.yaml` — routing rules (hostname → BackEnd IP)
   - `.env` — Cloudflare API token (consumed by the Traefik container)
4. Starts `traefik` and `socket-proxy` containers via `docker compose`

---

## Step 9 — Restore a Database Backup (when needed)

Only needed when initializing from a backup — not part of a normal deployment.

```bash
ansible-playbook adempiere-restoredb.yml
```

Set `restore_backup_filename` and `restore_local_dir` in `group_vars/all/vars.yml` to point to your backup file on the control node, then run:

```bash
./restore-db.sh
```

The script shows a configuration summary and asks for confirmation before executing. See [operations.md](operations.md) for details.

---

[← Getting Started](getting-started.md) | [Next: Running the System →](running.md)

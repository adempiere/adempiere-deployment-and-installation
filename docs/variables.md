# Complete Variable Reference

## Table of Contents

- [How to use this reference](#how-to-use-this-reference)
- [1. Inventory — server IPs](#1-inventory--server-ips)
- [2. SSH and server access](#2-ssh-and-server-access)
- [3. Server configuration](#3-server-configuration)
- [4. Docker and application stack](#4-docker-and-application-stack)
- [5. TLS and routing — Traefik FrontEnd](#5-tls-and-routing--traefik-frontend)
- [6. Database](#6-database)
- [7. Database restore](#7-database-restore)
- [8. Role defaults — deploy-crontab](#8-role-defaults--deploy-crontab)
- [9. Role defaults — serverswap](#9-role-defaults--serverswap)
- [10. Role defaults — genkey](#10-role-defaults--genkey)

---

## How to use this reference

**M** = Mandatory — the deployment will fail without this value; there is no usable default.  
**O** = Optional — a sensible default exists; only set it to override the default.  
**M\*** = Conditionally mandatory — required only when a specific feature is enabled (noted in the Description column).

Files you must create before running any playbook (copy from the committed templates):

| File to create | Template to copy | Purpose |
|---|---|---|
| `inventories/hosts.yml` | `inventories/hosts_template.yml` | Server IP addresses and group assignments |
| `group_vars/all/vars.yml` | `group_vars/vars_template.yml` | Plain-text deployment configuration |
| `group_vars/all/vault.yml` | `group_vars/vault_template.yml` | Encrypted secrets — encrypt with `ansible-vault encrypt` after filling in |
| `roles/serversconf/vars/main.yml` | `roles/serversconf/vars_template.yml` | Admin user credentials — encrypt with `ansible-vault encrypt` after filling in |

The `all/` subdirectory is Ansible's auto-load path: every `.yml` file found there is loaded automatically on every run. The templates live one level up (`group_vars/`) so their placeholder values are never loaded alongside your real credentials.

See [vault.md](vault.md) for step-by-step instructions on creating and encrypting the vault files.

---

## 1. Inventory — server IPs

**File:** `inventories/hosts.yml` (copy from `inventories/hosts_template.yml`)

| Variable | M/O | Description | Example |
|---|---|---|---|
| `ansible_host` (BackEnd group) | **M** | IP address of the BackEnd VPS. | `203.0.113.10` |
| `ansible_host` (FrontEnd group) | **M\*** | IP address of the FrontEnd VPS. Required when `deploy_traefik: true`. | `203.0.113.20` |

**Adding a second BackEnd server:** uncomment the `backend2` block in `hosts_template.yml` and set its IP. All playbooks pick it up automatically by targeting the `BackEnd` group — no other change needed.

---

## 2. SSH and server access

**Files:** `group_vars/all/vars.yml`, `group_vars/all/vault.yml`, `roles/serversconf/vars/main.yml`

| Variable | Source file | M/O | Default | Description | Example |
|---|---|---|---|---|---|
| `key_name` | vars.yml | **O** | `adempiere_installation_key` | SSH keypair filename under `ssh_keys/`. Keep the default unless you need to manage multiple keypairs — changing it requires updating `ansible_ssh_private_key_file` below and `roles/genkey/defaults/main.yml`. | `adempiere_installation_key` |
| `ansible_ssh_private_key_file` | vars.yml | **O** | `{{ playbook_dir }}/ssh_keys/adempiere_installation_key` | Full path to the private SSH key used by all playbooks. Derived automatically from `key_name`. Only change if you keep the key outside the project directory. | *(use default)* |
| `adempiere_username` | vars.yml | **M** | — | Non-root system user created on every server by `serversconf.yml`. All post-hardening playbooks connect as this user on the custom SSH port. The same name is used on both BackEnd and FrontEnd servers. | `deploy-admin` |
| `adempiere_username` | serversconf/vars/main.yml | **M** | — | Same value as in vars.yml — must match exactly. The role stores it in its own higher-priority vars file so the value cannot be accidentally overridden by group_vars at play runtime. | `deploy-admin` |
| `user_path` | serversconf/vars/main.yml | **M** | — | Home directory path for `adempiere_username`. | `/home/deploy-admin` |
| `custom_sshport` | vars.yml | **M** | — | Custom SSH port. `serversconf.yml` moves SSH from port 22 to this port permanently. Must already match the port on the servers if they have been hardened previously. | `10099` |
| `root_user_password` | vault.yml | **M** | — | Root password for initial server access. Used only by `serversprep.yml`, `os-updates.yml`, and `serversconf.yml` (the first three playbooks). Not used again after those playbooks run. | *(vault secret)* |
| `adempiere_user_password` | vault.yml | **M** | — | SSH login password for the `adempiere_username` account. Used by all post-hardening playbooks. | *(vault secret)* |
| `adempiere_user_become_pass` | vault.yml | **M** | — | `sudo` password for the `adempiere_username` account. Must match `adempiere_user_password` unless passwordless sudo is configured separately. | *(vault secret)* |
| `your_password` | serversconf/vars/main.yml | **M** | — | SHA-512 hashed password for the `adempiere_username` Linux account (written to `/etc/shadow`). Generate with `mkpasswd --method=sha-512`. The hash starts with `$6$`. | `$6$salt$hash…` |

---

## 3. Server configuration

**Files:** `group_vars/all/vars.yml`, `group_vars/BackEnd.yml`, `group_vars/FrontEnd.yml`

| Variable | Source file | M/O | Default | Description | Example |
|---|---|---|---|---|---|
| `timezone` | vars.yml | **M** | — | System timezone for all servers and all Docker containers. Must be a valid [tz database name](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones). | `Europe/Berlin`, `America/New_York` |
| `server_locale` | vars.yml | **O** | `en_US.UTF-8` | System locale configured on all servers during initial setup by the `serversconf` role. The locale must be available in the OS image. | `en_US.UTF-8`, `de_DE.UTF-8` |
| `swap_size_mb` | group_vars/BackEnd.yml | **O** | `8192` | Swap file size in MB for the BackEnd server. Sized for PostgreSQL memory spikes. | `8192` (8 GB) |
| `swap_size_mb` | group_vars/FrontEnd.yml | **O** | `4096` | Swap file size in MB for the FrontEnd server. Traefik is lightweight; 4 GB provides a safe margin. | `4096` (4 GB) |

---

## 4. Docker and application stack

**Files:** `group_vars/all/vars.yml`, role defaults (`roles/deploy-adempiere/defaults/main.yml`)

| Variable | Source file | M/O | Default | Description | Example |
|---|---|---|---|---|---|
| `install_path` | vars.yml | **O** | `/opt/development` | Base directory on the BackEnd server where the ADempiere stack is cloned and run. The repository is cloned to `{{ install_path }}/adempiere-ui-gateway/`. | `/opt/development` |
| `repo_url` | vars.yml | **M** | — | Git repository URL for the ADempiere application stack. | `https://github.com/adempiere/adempiere-ui-gateway.git` |
| `repo_version` | vars.yml | **O** | `adempiere-trunk` | Branch or tag to deploy. Override on the command line to deploy a specific version without editing the file: `-e "repo_version=main"`. | `adempiere-trunk`, `main`, `v1.0.0` |
| `adempiere_profile` | vars.yml | **O** | `all` | Profile passed to [`start-all.sh`](https://github.com/adempiere/adempiere-ui-gateway/blob/main/docker-compose/start-all.sh) and [`health-check.sh`](https://github.com/adempiere/adempiere-ui-gateway/blob/main/docker-compose/health-check.sh). Controls which subset of services is started. `all` starts every service defined in the stack. Available profiles: `vue`, `zk`, `auth`, `cache`, `report`, `scheduler`, `storage`, `all`. See [adempiere-ui-gateway profiles](https://github.com/adempiere/adempiere-ui-gateway/blob/main/docs/profiles.md) for the full profile list and definitions. | `all`, `zk`, `vue` |
| `adempiere_container_filter` | deploy-adempiere defaults | **O** | `adempiere-ui-gateway` | String used to filter `docker ps` output when checking whether the stack is running. | `adempiere-ui-gateway` |
| `adempiere_container_name` | deploy-adempiere defaults | **O** | `adempiere-ui-gateway` | Container name prefix used for health checks. | `adempiere-ui-gateway` |
| `be_user` | deploy-adempiere defaults | **O** | `{{ adempiere_username }}` | File owner on the BackEnd server for the ADempiere stack directory. Inherits from `adempiere_username` by default. | *(inherits)* |
| `postgres_external_port` | deploy-adempiere defaults | **O** | `5432` | PostgreSQL port exposed on the host. Change only if you need multiple PostgreSQL instances on the same server. | `5432` |

---

## 5. TLS and routing — Traefik FrontEnd

**Files:** `group_vars/all/vars.yml`, `group_vars/all/vault.yml`, role defaults (`roles/deploy-traefik/defaults/main.yml`), role vars (`roles/deploy-traefik/vars/main.yml`)

> These variables are only relevant when `deploy_traefik: true`.  
> The BackEnd can run standalone — ADempiere is then reachable directly by IP without TLS.  
> ⚠ See [docs/traefik-status.md](traefik-status.md) before enabling Traefik — the workflow has known gaps.

### Main switches

| Variable | Source file | M/O | Default | Description | Example |
|---|---|---|---|---|---|
| `deploy_traefik` | vars.yml | **O** | `false` | Set to `true` to enable the Traefik FrontEnd deployment. Default is `false` (BackEnd-only). | `false` |
| `dns_domain` | vars.yml | **M\*** | — | Base domain for Traefik routing rules and the Let's Encrypt certificate. DNS must point to the FrontEnd IP **before** running `deploy-traefik.yml` — Let's Encrypt validates the domain immediately on first startup. | `example.com` |
| `traefik_dns_provider` | vars.yml | **O** | `cloudflare` | DNS provider for the ACME DNS-01 challenge. Only `cloudflare` is tested. Other providers supported by Traefik may work. | `cloudflare` |

### Cloudflare credentials (vault-encrypted)

`roles/deploy-traefik/vars/main.yml` contains placeholder values only. The real values must be set in `group_vars/all/vault.yml`. See [security.md](security.md) and [vault.md](vault.md).

| Variable | Source file | M/O | Default | Description | Example |
|---|---|---|---|---|---|
| `cloudflare_token` | vault.yml | **M\*** | — | Cloudflare API token with `Zone:DNS:Edit` permission. Required when `deploy_traefik: true`. | *(vault secret)* |
| `cloudflare_email` | vault.yml | **M\*** | — | Email address of the Cloudflare account. Required when `deploy_traefik: true`. | *(vault secret)* |

### Role defaults — `deploy-traefik`

All variables below are defined in `roles/deploy-traefik/defaults/main.yml`. Override in `group_vars/all/vars.yml` or on the command line.

| Variable | M/O | Default | Description | Example |
|---|---|---|---|---|
| `docker_base_path` | **O** | `/docker` | Base directory for Traefik config and certificate files on the FrontEnd server. | `/docker` |
| `traefik_container_name` | **O** | `traefik` | Traefik container name. | `traefik` |
| `traefik_image` | **O** | `docker.io/library/traefik:v3.6.7` | Traefik Docker image — pinned to a specific version for reproducibility. | `docker.io/library/traefik:v3.6.7` |
| `traefik_http_port` | **O** | `80` | HTTP entry point port. | `80` |
| `traefik_https_port` | **O** | `443` | HTTPS entry point port. | `443` |
| `traefik_dashboard_enabled` | **O** | `true` | Enable or disable the Traefik dashboard. ⚠ The dashboard has no authentication in the current implementation — see [known-issues.md](known-issues.md#4-traefik-dashboard-has-no-authentication). | `true` |
| `traefik_dashboard_host` | **O** | `traefik.<dns_domain>` | Domain for the Traefik dashboard. Assembled from `dns_domain` at runtime. | `traefik.example.com` |
| `traefik_dashboard_port` | **O** | `28080` | Port the dashboard listens on. | `28080` |
| `traefik_network_name` | **O** | `gateway` | Docker bridge network name on the FrontEnd. Both `traefik` and `socket-proxy` attach to this network. | `gateway` |
| `traefik_network_external` | **O** | `true` | Whether the Docker network is created externally before the containers start. The role creates it — set to `false` only if you manage it separately. | `true` |
| `traefik_log_level` | **O** | `DEBUG` | Traefik log verbosity. Reduce to `INFO` or `WARN` in production to reduce log noise. | `DEBUG`, `INFO`, `WARN` |
| `traefik_socket_uri` | **O** | `socket-proxy` | Hostname of the Docker socket proxy container — used by Traefik to discover containers without direct socket access. | `socket-proxy` |
| `socket_container_name` | **O** | `socket-proxy` | Docker socket proxy container name. | `socket-proxy` |
| `socket_image` | **O** | `lscr.io/linuxserver/socket-proxy:latest` | Socket proxy Docker image. The socket proxy limits Traefik's read-only access to the Docker API, reducing the attack surface. | `lscr.io/linuxserver/socket-proxy:latest` |
| `host` | **O** | `adempiere` | Subdomain prefix for the ADempiere routing rule. The full hostname is `{{ host }}.{{ dns_domain }}`. Override to use a different subdomain. | `adempiere`, `erp` |
| `adempiere_host` | **O** | `{{ host }}.{{ dns_domain }}` | Full FQDN for ADempiere routing — assembled from `host` and `dns_domain` at runtime. Override only if you need a completely custom hostname that does not follow the `<host>.<dns_domain>` pattern. | `adempiere.example.com` |
| `servers` | **O** | built from `groups['BackEnd']` | List of BackEnd server URLs used by the Traefik load balancer. Derived automatically from the inventory at runtime — adding a host to the `BackEnd` group in `hosts.yml` is all that is needed to scale out. | *(auto-derived)* |
| `timezone` | **O** | *(set in vars.yml)* | Timezone for the Traefik container — inherits from `group_vars/all/vars.yml`. | `Europe/Berlin` |

---

## 6. Database

**Files:** `group_vars/all/vault.yml`, role defaults (`roles/adempiere-restoredb/defaults/main.yml`)

| Variable | Source file | M/O | Default | Description | Example |
|---|---|---|---|---|---|
| `postgres_password` | vault.yml | **M** | — | PostgreSQL superuser (`postgres`) password. Used by `deploy-adempiere` when configuring the container stack and by `adempiere-restoredb` when connecting for restore operations. | *(vault secret)* |
| `adempiere_password` | vault.yml | **O** | Falls back to `postgres_password` | Password for the `adempiere` PostgreSQL application user. Set this to use a separate less-privileged password for the application. If not set, `postgres_password` is used for both roles. | *(vault secret)* |
| `pg_host` | restoredb defaults | **O** | `127.0.0.1` | PostgreSQL host for restore operations — the loopback address of the BackEnd server, where the PostgreSQL container exposes its port. | `127.0.0.1` |
| `pg_port` | restoredb defaults | **O** | `5432` | PostgreSQL port for restore operations. | `5432` |
| `pg_superuser` | restoredb defaults | **O** | `postgres` | PostgreSQL superuser used for the restore (via `docker exec` — no TCP authentication required). | `postgres` |
| `adempiere_db` | restoredb defaults | **O** | `adempiere` | Database name to drop, recreate, and restore into. | `adempiere` |
| `adempiere_owner` | restoredb defaults | **O** | `adempiere` | Owner of the `adempiere` database after restore. | `adempiere` |

---

## 7. Database restore

**File:** `group_vars/all/vars.yml` (uncomment the restore block when needed)

These variables are only needed when running `./restore-db.sh` or `adempiere-restoredb.yml`.

| Variable | Source file | M/O | Default | Description | Example |
|---|---|---|---|---|---|
| `restore_backup_filename` | vars.yml | **M\*** | — | Filename of the backup archive on the control node. Supports `.sql.gz` and `.tar.gz` formats. Must be inside `restore_local_dir`. | `my-backup-20260101.sql.gz` |
| `restore_local_dir` | vars.yml | **M\*** | — | Directory on the **control node** where the backup file is located. | `/home/user/backups` |
| `restore_remote_backup_dir` | vars.yml | **O** | `{{ install_path }}/adempiere-ui-gateway/docker-compose/postgresql/postgres_backups` | Destination directory on the BackEnd server for the uploaded backup. Uses the standard PostgreSQL backup location by default. | *(use default)* |
| `keep_restore_file` | vars.yml | **O** | `true` | Keep the compressed backup archive on the BackEnd server after a successful restore. Set to `false` to remove it and free disk space. | `true` |
| `post_restore_sql_enabled` | vars.yml | **O** | `false` | Run an additional SQL script immediately after the restore. Used to apply incremental migrations or patches on top of the restored database. | `false` |
| `post_restore_sql_filename` | vars.yml | **M\*** | — | Filename of the SQL script to execute after restore. Required when `post_restore_sql_enabled: true`. | `patch-20260101.sql` |
| `post_restore_sql_local_dir` | vars.yml | **M\*** | — | Directory on the control node containing the SQL script. Required when `post_restore_sql_enabled: true`. | `/home/user/sql-patches` |
| `post_restore_sql_remote_dir` | vars.yml | **O** | `{{ install_path }}/…/postgres_backups/03-Misc-SQLs` | Destination directory on the BackEnd for the SQL script. | *(use default)* |

---

## 8. Role defaults — `deploy-crontab`

**File:** `roles/deploy-crontab/defaults/main.yml` — override in `group_vars/BackEnd.yml` or `group_vars/all/vars.yml`.

| Variable | Default | Description |
|---|---|---|
| `crontab_enabled` | `true` | Install (`true`) or remove (`false`) all cron entries. Set to `false` and re-run `deploy-crontab.yml` to remove all entries cleanly. |
| `crontab_scripts_dir` | `{{ install_path }}/…/01-Backupscripts` | Directory where cron scripts are deployed on the BackEnd server. |
| `crontab_logs_dir` | `{{ install_path }}/…/02-Logs` | Directory for cron stdout/stderr logs on the BackEnd server. |
| `crontab_jobs` | (see below) | List of cron entries. Add a list item to schedule additional jobs. |

**`crontab_jobs` field reference:**

| Field | Required | Description |
|---|---|---|
| `name` | yes | Unique identifier for the entry (Ansible uses this to add, update, or remove it) |
| `script` | yes | Script filename inside `crontab_scripts_dir` |
| `special_time` | one of these | `reboot`, `hourly`, `daily`, etc. |
| `hour` | one of these | Hour field (0–23) |
| `minute` | one of these | Minute field (0–59) |

**Default cron jobs:**

| Name | When | Script |
|---|---|---|
| `adempiere start on reboot` | `@reboot` | `cron-job-start-all-services.sh` |
| `adempiere daily stop` | `23:50` | `cron-job-stop-all-services.sh` |
| `adempiere daily restart` | `23:55` | `cron-job-start-all-services.sh` |

---

## 9. Role defaults — `serverswap`

**File:** `roles/serverswap/defaults/main.yml` — overridden by `group_vars/BackEnd.yml` and `group_vars/FrontEnd.yml`.

| Variable | Default | Description |
|---|---|---|
| `swap_size_mb` | `4096` | Fallback swap size in MB. In practice always overridden by the group-specific values: BackEnd.yml sets 8192, FrontEnd.yml sets 4096. |

---

## 10. Role defaults — `genkey`

**File:** `roles/genkey/defaults/main.yml`

| Variable | Default | Description |
|---|---|---|
| `key_size` | `4096` | RSA key size in bits. 4096-bit is recommended; 2048 works but is not recommended for new deployments. |
| `key_name` | *(set in vars.yml)* | Keypair filename under `ssh_keys/`. Inherits from `group_vars/all/vars.yml`. Set it there — not here — so all playbooks use the same value. |

---

[← Security](security.md) | [← Back to README](../README.md)

# Complete Variable Reference

## Secrets & Credentials (`group_vars/all/vault.yml`)

These must be set manually via `ansible-vault edit group_vars/all/vault.yml`.

| Variable | Used in | Description |
|---|---|---|
| `root_user_password` | `serversprep.yml`, `serversconf.yml`, `so-updates.yml` | Root password for initial server access (before SSH key-based auth is configured) |
| `adempiere_username` | all post-hardening playbooks, `serversconf` role | Name of the non-root system user created on every server. Used as SSH login user and file owner. Personalise to any username you prefer — must match on both BackEnd and FrontEnd. |
| `your_password` | `serversconf` role | SHA-512 hashed password for `adempiere_username` (`mkpasswd --method=sha-512`) |
| `adempiere_user_password` | `install-docker.yml`, `deploy-adempiere.yml`, `deploy-traefik.yml`, `deploy-vim.yml`, `adempiere-restoredb.yml` | SSH login password for the `adempiere_username` account |
| `adempiere_user_become_pass` | same playbooks as above | Sudo password for the `adempiere_username` account |
| `postgres_password` | `deploy-adempiere` role, `adempiere-restoredb` role | PostgreSQL superuser (`postgres`) password |
| `adempiere_password` | `adempiere-restoredb` role | Password for the `adempiere` PostgreSQL user (falls back to `postgres_password` if not set) |

## Per-group Variables

These variables are set per inventory group and **committed to git** (not secrets, not operator-specific).

| Variable | File | Value | Description |
|---|---|---|---|
| `swap_size_mb` | `group_vars/BackEnd.yml` | `8192` | Swap file size in MB for the BackEnd server (8 GB) |
| `swap_size_mb` | `group_vars/FrontEnd.yml` | `4096` | Swap file size in MB for the FrontEnd server (4 GB) |

---

## Deployment Variables (`group_vars/all/vars.yml`)

| Variable | Used in | Description |
|---|---|---|
| `adempiere_username` | All post-hardening playbooks, `serversconf` role | Admin username created on every server — also defined here as a non-secret config value |
| `custom_sshport` | All post-hardening playbooks, `serversconf` role | Custom SSH port — serversconf moves SSH from 22 to this port |
| `dns_domain` | `deploy-traefik` role | Base domain for routing and TLS certificates (e.g. `example.com`) |
| `timezone` | `deploy-traefik` role | Timezone for containers (e.g. `America/El_Salvador`, `Europe/Berlin`) |
| `repo_url` | `deploy-adempiere` role | Git repository URL for the ADempiere stack |
| `repo_version` | `deploy-adempiere` role | Branch or tag to deploy (e.g. `adempiere-trunk`, `main`) |
| `key_name` | `genkey` role, `serversprep` role | SSH keypair filename under `ssh_keys/` |
| `ansible_ssh_private_key_file` | All playbooks connecting to remote servers | Path to the project SSH private key (`ssh_keys/adempiere_installation_key`) |

---

## Role: `deploy-crontab` — Defaults

| Variable | Default | Description |
|---|---|---|
| `crontab_enabled` | `true` | Install (`true`) or remove (`false`) all entries — overridden by `group_vars/BackEnd.yml` |
| `crontab_scripts_dir` | `{{ install_path }}/…/01-Backupscripts` | Directory where cron scripts are deployed |
| `crontab_logs_dir` | `{{ install_path }}/…/02-Logs` | Directory for cron stdout/stderr logs |
| `crontab_jobs` | see below | List of cron entries; add items here to schedule additional jobs |

**`crontab_jobs` list structure** — each item supports:

| Field | Required | Description |
|---|---|---|
| `name` | yes | Unique cron entry name (used by Ansible to identify/update the entry) |
| `script` | yes | Script filename inside `crontab_scripts_dir` |
| `special_time` | one of these | `reboot`, `hourly`, `daily`, etc. (omit if using `hour`/`minute`) |
| `hour` | one of these | Hour field (0–23) |
| `minute` | one of these | Minute field (0–59) |

**Default jobs:**

| name | when | script |
|---|---|---|
| `adempiere start on reboot` | `@reboot` | `cron-job-start-all-services.sh` |
| `adempiere daily stop` | `23:50` | `cron-job-stop-all-services.sh` |
| `adempiere daily restart` | `23:55` | `cron-job-start-all-services.sh` |

---

## Role: `serverswap` — Defaults

| Variable | Default | Description |
|---|---|---|
| `swap_size_mb` | `4096` | Fallback swap size in MB — overridden by `group_vars/BackEnd.yml` (8192) and `group_vars/FrontEnd.yml` (4096) |

---

## Role: `genkey` — Defaults

| Variable | Default | Description |
|---|---|---|
| `key_size` | `4096` | RSA key size in bits |
| `key_name` | *(set in `group_vars/all/vars.yml`)* | Filename for the keypair under `ssh_keys/` |

---

## Role: `deploy-adempiere` — Defaults

| Variable | Default | Description |
|---|---|---|
| `adempiere_container_filter` | `adempiere-ui-gateway` | String used to filter `docker ps` output |
| `adempiere_container_name` | `adempiere-ui-gateway` | Exact container name for `docker inspect` |
| `install_path` | `/opt/development` | Base directory on the BackEnd server |
| `repo_url` | `https://github.com/Systemhaus-Westfalia/adempiere-ui-gateway.git` | Git repository URL |
| `repo_version` | `adempiere-trunk` | Branch or tag to deploy |
| `be_user` | `{{ adempiere_username }}` | File owner on the BackEnd server — inherits from `adempiere_username` |
| `postgres_external_port` | `5432` | PostgreSQL port exposed to the host |

---

## Role: `deploy-traefik` — Defaults

| Variable | Default | Description |
|---|---|---|
| `docker_base_path` | `/docker` | Base directory for container config files on FrontEnd |
| `traefik_container_name` | `traefik` | Traefik container name |
| `traefik_image` | `docker.io/library/traefik:v3.6.7` | Traefik Docker image |
| `traefik_http_port` | `80` | HTTP entry point port |
| `traefik_https_port` | `443` | HTTPS entry point port |
| `traefik_dashboard_enabled` | `true` | Enable/disable the Traefik dashboard |
| `traefik_dashboard_host` | `traefik.<dns_domain>` | Domain for the dashboard |
| `traefik_dashboard_port` | `28080` | Port the dashboard listens on |
| `traefik_network_name` | `gateway` | Docker network name |
| `traefik_network_external` | `true` | Whether the network is pre-created externally |
| `traefik_log_level` | `DEBUG` | Traefik log level (`TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`) |
| `traefik_dns_provider` | `cloudflare` | ACME DNS challenge provider |
| `traefik_socket_uri` | `socket-proxy` | Hostname of the Docker socket proxy container |
| `socket_container_name` | `socket-proxy` | Socket proxy container name |
| `socket_image` | `lscr.io/linuxserver/socket-proxy:latest` | Socket proxy Docker image |
| `dns_domain` | *(set in `group_vars/all/vars.yml`)* | Base domain for routing |
| `host` | `adempiere` | Subdomain prefix |
| `adempiere_host` | `{{ host }}.{{ dns_domain }}` | Full FQDN for ADempiere routing, assembled at runtime |
| `servers` | `["http://<backend_ip>"]` | List of BackEnd URLs for the ADempiere load balancer |
| `timezone` | *(set in `group_vars/all/vars.yml`)* | Timezone for the Traefik container |

## Role: `deploy-traefik` — Vars *(⚠ move to vault — see [security.md](security.md))*

| Variable | Description |
|---|---|
| `cloudflare_tocken` | Cloudflare API token *(misspelled — should be `cloudflare_token`)* |
| `cloudflare_email` | Email for Let's Encrypt registration |

---

## Role: `adempiere-restoredb` — Defaults

| Variable | Default | Description |
|---|---|---|
| `backup_name` | `Mini-PC-20260228-2345.sql.gz` | Backup filename in `roles/adempiere-restoredb/files/` |
| `remote_gz_path` | `/tmp/<backup_name>` | Temporary path on the server during transfer |
| `extract_destination` | `/opt/development/adempiere-ui-gateway/docker-compose/postgresql/postgres_backups` | Final destination for the SQL file |
| `pg_host` | `127.0.0.1` | PostgreSQL host |
| `pg_port` | `5432` | PostgreSQL port |
| `pg_superuser` | `postgres` | PostgreSQL superuser for the restore |
| `adempiere_db` | `adempiere` | Database name to create and restore into |
| `adempiere_owner` | `adempiere` | Database owner user |

---

## Role: `deploy-vim` — Vars

| Variable | Value | Description |
|---|---|---|
| `vim_dir` | `/home/<ansible_user>/.vim` | Vim config directory |
| `vimrc` | `/home/<ansible_user>/.vimrc` | Vim config file path |

---

[← Security](security.md) | [← Back to README](../README.md)

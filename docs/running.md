# Running the System

## Table of Contents

- [deploy-backend.sh — full BackEnd provisioning](#deploy-backendsh--full-backend-provisioning)
- [restore-db.sh — database restore](#restore-dbsh--database-restore)
- [Playbook reference](#playbook-reference)
- [Running a single playbook](#running-a-single-playbook)
- [Useful flags](#useful-flags)
- [Checking connectivity](#checking-connectivity)
- [Inspecting variables and host configuration](#inspecting-variables-and-host-configuration)
- [Syntax check (no execution)](#syntax-check-no-execution)
- [List tasks without running](#list-tasks-without-running)
- [Common scenarios](#common-scenarios)

---

## `deploy-backend.sh` — full BackEnd provisioning

`deploy-backend.sh` is the primary entry point for provisioning a BackEnd server from scratch. It handles everything a manual operator would need to remember: keypair setup, pre-flight checks, stale host key cleanup, interactive confirmation, and all eight playbooks in the correct order.

```bash
./deploy-backend.sh           # live run — makes changes on the server
./deploy-backend.sh --check   # dry run — shows what would change, no writes
```

### Prerequisites

Before running:
1. The BackEnd server must be reachable on port 22 with root password authentication.
2. `~/.vault_pass.txt` must exist with your vault password.
3. `group_vars/all/vars.yml`, `group_vars/all/vault.yml`, and `inventories/hosts.yml` must be populated.

### What it does — step by step

| Step | Playbook | Description |
|---|---|---|
| 1 | *(local)* | Keypair check: if `ssh_keys/adempiere_installation_key` exists, asks whether to delete and regenerate. Default is NO — only regenerate on a full server reset. |
| 2 | `genkey.yml` | Generate RSA keypair (skipped if Step 1 kept the existing key). |
| Pre-flight | *(script)* | Check `~/.vault_pass.txt` exists; remove stale known_hosts entries for all BackEnd IPs. |
| 3 | `serversprep.yml` | Distribute the public key to the BackEnd server (root, port 22). |
| 4 | `os-updates.yml` | OS dist-upgrade + reboot. Waits up to 5 minutes for server to return. |
| 5 | `serversconf.yml` | Full server hardening: create admin user, deploy SSH keys, install packages, harden SSH, configure unattended upgrades. After this step, root login is disabled and SSH moves to the custom port. |
| 6 | `serverswap.yml` | Configure swap file (8 GB from `group_vars/BackEnd.yml`). |
| 7 | `install-docker.yml` | Install Docker CE 28.x (pinned). |
| 8 | `deploy-adempiere.yml` | Deploy the [adempiere-ui-gateway](https://github.com/adempiere/adempiere-ui-gateway) container stack (clone repo, generate env file, two-run start via [`start-all.sh`](https://github.com/adempiere/adempiere-ui-gateway/blob/main/docker-compose/start-all.sh) with [profile](https://github.com/adempiere/adempiere-ui-gateway/blob/main/docs/profiles.md) `adempiere_profile`, [`health-check.sh`](https://github.com/adempiere/adempiere-ui-gateway/blob/main/docker-compose/health-check.sh) at the end). |
| 9 | `deploy-crontab.yml` | Install crontab entries: `@reboot` start, `23:50` stop, `23:55` restart. |

### Logs

Every run writes to `logs/deploy-backend-<YYYYMMDD-HHMMSS>.log` on the control node. Both stdout and stderr are captured. The `logs/` directory is gitignored — log files are never committed.

### Dry run notes

`--check` mode skips Step 1 entirely (no local file changes). The `os-updates.yml` reboot task uses `shell`/`command` and is skipped in check mode, so the dry-run output will not reflect the post-reboot state. For Docker playbooks, `--check` output is approximate.

**Why some steps use `--limit BackEnd` and others do not:**  
`serversprep.yml`, `os-updates.yml`, `serversconf.yml`, `serverswap.yml`, and `install-docker.yml` all have `hosts: servers` — they target both BackEnd and FrontEnd. The script passes `--limit BackEnd` to restrict them to the BackEnd only.  
`deploy-adempiere.yml` and `deploy-crontab.yml` already have `hosts: BackEnd` in their playbook definition — they never touch the FrontEnd regardless, so `--limit BackEnd` is not needed and is not passed.

### Re-running after a partial failure

All playbooks in this script are idempotent — safe to re-run. If the script fails partway through (e.g. at Step 5), fix the underlying issue and run `deploy-backend.sh` again. Steps that already completed will report `ok` (no change needed); only pending steps will make changes.

**Exception:** if the server has already been hardened (Step 5 completed), it is no longer reachable on port 22 as root. Re-running `deploy-backend.sh` from Step 2 will fail. In that case, run the remaining playbooks individually:

```bash
ansible-playbook serverswap.yml     --limit BackEnd
ansible-playbook install-docker.yml --limit BackEnd
ansible-playbook deploy-adempiere.yml
ansible-playbook deploy-crontab.yml
```

### Common failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| `Permission denied (publickey)` at Step 3 | Server not reachable as root, or root password is wrong | Verify `root_user_password` in vault; check server is on port 22 |
| Step 4 (`os-updates`) hangs after reboot | Server takes longer than 5 min to restart | Wait; if server is up, re-run from Step 5 manually |
| `Connection refused` at Step 5+ | `serversconf` already ran; server is now on custom port | Run remaining playbooks individually (see above) |
| `FAILED - RETRYING: Wait until ZK ...` | ZK is slow to start (normal on first run) | Wait; it will retry up to 20 times with 10-second delays |
| Docker playbook fails on `--check` | User/port not set up yet | This is expected in dry-run — run `serversconf.yml` for real first |

For a sample of real successful output, see [docs/demo.md](demo.md).

---

## `restore-db.sh` — database restore

`restore-db.sh` uploads a PostgreSQL backup from the control node and restores it into the running ADempiere stack on the BackEnd. It reads restore parameters from `group_vars/all/vars.yml`. See also: [adempiere-ui-gateway backup & restore documentation](https://github.com/adempiere/adempiere-ui-gateway/blob/main/docs/backup-restore.md).

```bash
./restore-db.sh
```

There is no `--check` mode for the restore (the operation is destructive by design).

### Prerequisites

Before running:
1. The ADempiere container stack must be running on the BackEnd (`deploy-adempiere.yml` completed successfully).
2. The backup file must exist on the control node at `restore_local_dir/restore_backup_filename`.
3. `restore_backup_filename` and `restore_local_dir` must be set in `group_vars/all/vars.yml` (uncomment the restore block).
4. `~/.vault_pass.txt` must exist.

**Where backup files come from:**

The standard source is the adempiere-ui-gateway automated backup script ([`04-backup-database.sh`](https://github.com/adempiere/adempiere-ui-gateway/blob/main/docs/scripts/04-backup-database.sh)). That script runs `pg_dump --no-owner`, writes the result as a plain SQL file, then compresses it with `gzip`:

```
adempiere-<YYYY-MM-DD-HHMMSS>.backup.gz
```

Despite the `.backup` base name (a naming convention from adempiere-ui-gateway), the content is a plain SQL dump — not the PostgreSQL custom binary format. Typical size: ~245 MB uncompressed → ~45 MB compressed (~80% reduction).

**Supported formats:**

| Filename ends with | Decompression | Resulting dump file |
|---|---|---|
| `.backup.gz` | `gzip -dk` | `.backup` (plain SQL) |
| `.sql.gz` | `gzip -dk` | `.sql` (plain SQL) |
| `.tar.gz` | `tar -xzf` | `.sql` (plain SQL inside the archive) |

The format is auto-detected from the filename — no configuration needed.

### What it does — step by step

| Step | Description |
|---|---|
| Pre-flight | Reads restore variables from `vars.yml`; checks the backup file exists locally; checks `~/.vault_pass.txt`; shows a confirmation summary. |
| Multi-backend check | If more than one BackEnd host is in the inventory, shows an additional warning — the restore will run on ALL of them. |
| Upload | Uploads the backup archive from the control node to `restore_remote_backup_dir` on the BackEnd. |
| Decompress | Auto-detects format from filename: `gzip -dk` for `.backup.gz` and `.sql.gz`; `tar -xzf` for `.tar.gz`. Produces a plain SQL dump file. |
| Drop & recreate | Drops the `adempiere` database and recreates it with the correct owner. |
| Restore | Runs `psql` inside the PostgreSQL container via `docker exec` — no TCP port needs to be open. |
| Post-restore SQL | If `post_restore_sql_enabled: true`, uploads and executes the specified SQL script. |
| Cleanup | Removes the decompressed dump file. Keeps or removes the archive based on `keep_restore_file`. |

### Logs

Every run writes to `logs/restore-db-<YYYYMMDD-HHMMSS>.log` on the control node. The `logs/` directory is gitignored — log files are never committed.

### Re-running after a failure

If the restore fails after the Drop step, the database is empty. Re-run `restore-db.sh` — it will drop (already empty), recreate, and restore again.

If the failure was a network error during upload, re-run — the upload is idempotent (skips if the archive already exists on the server).

---

## Playbook Reference

| Playbook | Target | Description |
|---|---|---|
| `genkey.yml` | localhost | Generate RSA keypair |
| `serversprep.yml` | servers | Distribute SSH key |
| `os-updates.yml` | servers | OS update + reboot |
| `serversconf.yml` | servers | Server hardening |
| `serverswap.yml` | servers | Swap file + kernel tuning (`vm.swappiness=10`); size from per-group vars |
| `install-docker.yml` | servers | Install Docker CE |
| `deploy-vim.yml` | servers | Vim + plugins |
| `deploy-adempiere.yml` | BackEnd | ADempiere container stack |
| `deploy-traefik.yml` | FrontEnd | Traefik reverse proxy |
| `deploy-crontab.yml` | BackEnd | Crontab: @reboot start, 23:50 stop, 23:55 restart |
| `adempiere-restoredb.yml` | BackEnd | PostgreSQL backup restore |
| `main.yml` | various | Orchestrates: genkey → serversprep → os-updates → serversconf → serverswap → deploy-vim → install-docker |
| `main-w-traefik.yml` | various | Orchestrates full setup: genkey → serversprep → os-updates → serversconf → install-docker → deploy-traefik → deploy-adempiere |

---

## Running a Single Playbook

```bash
ansible-playbook <playbook-name>.yml
```

---

## Useful Flags

### Dry run (check mode)

Shows what Ansible *would* do without making any changes. Note: `command` and `shell` tasks are skipped in check mode.

```bash
ansible-playbook serversconf.yml --check
ansible-playbook serversconf.yml --check --diff   # also shows file diffs
```

### Limit to a specific host or group

Several playbooks target the `servers` group, which includes both BackEnd and FrontEnd. `--limit` restricts execution to a subset — the playbook logic runs only on the matching hosts; all others are skipped.

You can limit by inventory group name, by hostname, or by IP:

```bash
ansible-playbook os-updates.yml --limit BackEnd        # BackEnd only (both servers → one)
ansible-playbook os-updates.yml --limit FrontEnd       # FrontEnd only
ansible-playbook os-updates.yml --limit <backend_ip>   # single host by IP
ansible-playbook os-updates.yml --limit backend1       # single host by name (from hosts.yml)
ansible-playbook serverswap.yml --limit BackEnd        # swap BackEnd only (8 GB)
ansible-playbook serverswap.yml --limit FrontEnd       # swap FrontEnd only (4 GB)
ansible-playbook deploy-adempiere.yml --limit ansible_test  # test VM only, never touches production
```

`--limit` is essential when you have multiple servers and want to apply a change to only one — for example, running `serversconf.yml` on a newly reset BackEnd without touching a FrontEnd that is already in production.

### Start from a specific task

```bash
ansible-playbook serversconf.yml --start-at-task "SSH hardening"
```

### Verbosity

```bash
ansible-playbook deploy-adempiere.yml -v      # basic
ansible-playbook deploy-adempiere.yml -vv     # more detail
ansible-playbook deploy-adempiere.yml -vvv    # connection debugging
ansible-playbook deploy-adempiere.yml -vvvv   # full network traffic
```

### Override a variable at the command line

```bash
ansible-playbook deploy-adempiere.yml -e "repo_version=main"
ansible-playbook deploy-traefik.yml -e "traefik_log_level=INFO"
```

---

## Checking Connectivity

```bash
# Ping all hosts
ansible all -m ping

# Ping only BackEnd (after serversconf — adempiere_username user, custom port)
ansible BackEnd -m ping \
  -e "ansible_user=westfalia" -e "ansible_port=10099"
```

---

## Inspecting Variables and Host Configuration

Three commands, each showing a different scope. The first two read **local files only** — no SSH needed. The third connects to the remote host via SSH.

**1. Inventory variables for a host** — what `group_vars`, `host_vars`, and the inventory file contribute. Fast, always works, no SSH:
```bash
ansible-inventory --host backend1
```

**2. All Ansible variables the host will use during a play** — inventory variables plus any cached facts. Useful to verify a variable like `{{ install_path }}` or `{{ be_user }}` resolves correctly before running. No SSH:
```bash
ansible backend1 -m debug -a "var=hostvars[inventory_hostname]"
```

**3. Complete remote host configuration** — OS, kernel, CPU, memory, network interfaces, disk, and all system facts gathered live from the server. Requires SSH (pass port and user after serversconf has run):
```bash
ansible backend1 -m setup -e "ansible_port={{ custom_sshport }}" -e "ansible_user={{ adempiere_username }}"
```

---

## Syntax Check (no execution)

```bash
ansible-playbook main.yml --syntax-check
ansible-playbook deploy-traefik.yml --syntax-check
```

---

## List Tasks Without Running

```bash
ansible-playbook serversconf.yml --list-tasks
ansible-playbook deploy-adempiere.yml --list-tasks
```

---

## Common Scenarios

### Scenario 1 — Full first-time setup (both servers)

Run this sequence once when provisioning both servers from scratch:

```bash
# 1. Generate SSH keypair on the control node
ansible-playbook genkey.yml

# 2. Distribute the public key to both servers (uses root password from vault)
ansible-playbook serversprep.yml

# 3. Run the full base setup: OS updates, hardening, vim, Docker
ansible-playbook main.yml

# 4. Deploy ADempiere on BackEnd
ansible-playbook deploy-adempiere.yml

# 5. Deploy Traefik on FrontEnd
ansible-playbook deploy-traefik.yml
```

Or use the orchestration playbooks (TO-DO — not yet created):

```bash
ansible-playbook main-backend.yml   # base setup + BackEnd app
ansible-playbook main-frontend.yml  # base setup + FrontEnd proxy
```

---

### Scenario 2 — BackEnd only (no FrontEnd / no Traefik)

Use this when you want ADempiere running without a reverse proxy, e.g. for internal use or testing.

```bash
# Base setup (if not already done)
ansible-playbook main.yml

# Deploy ADempiere on BackEnd
ansible-playbook deploy-adempiere.yml
```

ADempiere will be reachable directly at the BackEnd IP on its application port.  
Make sure the hosting provider's firewall allows that port from your IP.

---

### Scenario 3 — FrontEnd only (add Traefik to an existing BackEnd)

Use this when the BackEnd is already running and you only need to add or re-configure the reverse proxy.

```bash
ansible-playbook deploy-traefik.yml
```

---

### Scenario 4 — Re-deploy ADempiere after a code update

```bash
# Pull new repo version and restart containers
ansible-playbook deploy-adempiere.yml -e "repo_version=main"
```

---

### Scenario 5 — Restore PostgreSQL from backup

Place the `.sql.gz` backup file in `roles/adempiere-restoredb/files/`, then:

```bash
ansible-playbook adempiere-restoredb.yml
```

---

### Scenario 6 — Add a second BackEnd server

`deploy-backend.sh` deletes and regenerates the SSH keypair — **do not use it** when other servers already use the current keypair, or you will lose access to them.

Run the playbooks manually with `--limit` instead. The existing keypair is distributed to the new server:

```bash
ansible-playbook serversprep.yml    --limit backend2
ansible-playbook os-updates.yml     --limit backend2
ansible-playbook serversconf.yml    --limit backend2
ansible-playbook serverswap.yml     --limit backend2
ansible-playbook install-docker.yml --limit backend2
ansible-playbook deploy-adempiere.yml --limit backend2
```

---

### Scenario 7 — Apply OS security updates

```bash
ansible-playbook os-updates.yml
```

Servers reboot automatically if the kernel was updated.

---

### Scenario 8 — Test against a local VM (without touching production)

```bash
# Limit to the ansible_test group (see inventories/hosts.yml)
ansible-playbook serversconf.yml --limit ansible_test
ansible-playbook deploy-adempiere.yml --limit ansible_test
```

---

[← Installation](installation.md) | [Next: Operations →](operations.md)

# Operations & Day-2 Tasks

## Infrastructure vs. Application

Traefik and the server configuration are **infrastructure** — set up once, left running. You only touch them again if a server is rebuilt or you change the proxy configuration.

ADempiere is the **application** — deployed and updated independently, without affecting Traefik or server configuration.

| Need | Playbook | Touches infrastructure? |
|---|---|---|
| Update ADempiere | `deploy-adempiere.yml` | No |
| Restore database | `adempiere-restoredb.yml` | No |
| OS security update | `so-updates.yml` | Yes — schedule carefully |
| Add SSH key | `serversconf.yml` (single task) | Yes |
| Change Traefik config | `deploy-traefik.yml` | Yes |
| Add a customer | manual or `deploy-traefik.yml` | Yes |

---

## Adding a Customer

The FrontEnd Traefik server routes traffic to the correct BackEnd by hostname — one routing config file per customer. For the concept, see [architecture.md](architecture.md#multi-customer-routing-on-the-frontend).

**Prerequisites before either approach:**
- DNS record for the customer's domain pointing to the FrontEnd IP
- BackEnd server for that customer already running ADempiere

---

**Option A — Quick manual approach** (directly on the server, no Ansible)

SSH to the FrontEnd server and create the routing file in the Traefik config directory:

```bash
ssh <admin_user>@<frontend_ip> -p <custom_sshport>
nano /docker/traefik/config/app-customer-b.yaml
```

Paste and adjust:

```yaml
http:
  routers:
    customer-b-rtr:
      rule: "Host(`customer-b.example.com`)"
      entryPoints:
        - websecure
      service: customer-b-svc
      tls:
        certResolver: cloudflare

  services:
    customer-b-svc:
      loadBalancer:
        servers:
          - url: "http://<backend-ip-b>"
```

Traefik picks up the new file immediately — no restart needed. The TLS certificate is issued automatically on the first HTTPS request.

---

**Option B — Ansible approach** (version-controlled, repeatable)

1. Create a new template in the repository:
   ```
   roles/deploy-traefik/templates/app-customer-b.yaml.j2
   ```
   with the same content as above, using `{{ variables }}` for the hostname and IP.

2. Add it to the deploy list in `roles/deploy-traefik/tasks/main.yml`:
   ```yaml
   - src: 'app-customer-b.yaml.j2'
     dest: 'app-customer-b.yaml'
   ```

3. Add the customer's variables to `group_vars/all/vars.yml`.

4. Re-run:
   ```bash
   ansible-playbook deploy-traefik.yml
   ```

Option B is safer for production: the configuration is version-controlled and reproducible if the server is rebuilt. Option A is faster for testing or a one-off setup.

---

## Adding a New Admin SSH Key

1. Place the new `.pub` file in:
   ```
   roles/serversconf/files/public_keys/present/admin/newperson.pub
   ```

2. Re-run the key deployment task (idempotent — adds new key, does not remove existing ones):
   ```bash
   ansible-playbook serversconf.yml --start-at-task "Add ADMIN ssh-keys"
   ```

---

## Updating ADempiere to a New Version

The role always pulls the latest commits from the configured branch (`repo_version`) on every run. If containers are already running, `start-all.sh` is skipped — only the git pull and `override.env` regeneration happen.

To force a full restart (e.g. after a branch change or to pick up a new image):

```bash
# Stop containers on the BackEnd server first
ssh <admin_user>@<backend_ip> -p <custom_sshport>
cd /opt/development/adempiere-ui-gateway/docker-compose
sudo env PWD=$PWD bash stop-all.sh

# Re-run — containers are stopped so the full start sequence runs
ansible-playbook deploy-adempiere.yml
```

To deploy a specific branch:
```bash
ansible-playbook deploy-adempiere.yml -e "repo_version=my-branch"
```

---

## Performing an OS Update on Running Servers

Safe to run on live servers. If a kernel update requires a reboot, Ansible handles it automatically and waits for the server to come back.

```bash
ansible-playbook so-updates.yml
```

---

## Restoring a PostgreSQL Database from Backup

1. Download the backup file to any directory on the control node.

2. Set the two operator-facing variables in `group_vars/all/vars.yml`:
   ```yaml
   restore_backup_filename: "your-backup-file.sql.gz"
   restore_local_dir: "/path/to/directory/on/control/node"
   ```
   Supported formats: `.sql.gz` and `.tar.gz` — the role detects the format automatically.

3. Run the restore:
   ```bash
   ./restore-db.sh
   ```
   The script reads the variables from `group_vars/all/vars.yml`, shows a summary of all restore parameters, and asks for confirmation before proceeding. Type `YES` to execute.

What it does:
- Copies the backup file from the control node to the canonical PostgreSQL backups directory on the backend server
- Decompresses the archive (auto-detected: `gzip -dk` for `.gz`, `tar -xzf` for `.tar.gz`)
- Creates the `adempiere` database and user if they do not exist
- Restores the dump using the `postgres` superuser (destructive — overwrites existing data)
- Removes the decompressed dump file; keeps the archive if `keep_restore_file: true` (default)

The restore runs against the live stack — no need to stop containers beforehand.

---

## Checking Container Status

**BackEnd (ADempiere):**
```bash
ssh <admin_user>@<backend_ip> -p <custom_sshport>
docker ps
docker logs adempiere-ui-gateway
cd <install_path>/adempiere-ui-gateway/docker-compose && docker compose ps
```

**FrontEnd (Traefik):**
```bash
ssh <admin_user>@<frontend_ip> -p <custom_sshport>
docker ps
docker logs traefik
tail -f /docker/traefik/logs/traefik.log
tail -f /docker/traefik/logs/access.log
```

---

## Traefik Dashboard

Accessible at:
```
http://traefik.<dns_domain>:28080
```

Shows all routers, services, and middleware in real time. Useful for verifying that routing rules are active.

> ⚠ The dashboard has no authentication in the current configuration. See [security.md](security.md).

---

## Redeploying Traefik Configuration

Traefik is infrastructure — once running, it does not need to be redeployed when ADempiere is updated. Only re-run `deploy-traefik.yml` when you intentionally change the proxy configuration (new domain, TLS settings, log level, routing rules, etc.):

```bash
ansible-playbook deploy-traefik.yml
```

The `community.docker.docker_compose_v2` module is idempotent — it restarts containers only if their configuration has actually changed.

---

[← Running the System](running.md) | [Next: Troubleshooting →](troubleshooting.md)

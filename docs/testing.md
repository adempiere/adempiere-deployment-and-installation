# Testing & Debugging Guide

## Table of Contents

- [Quick diagnostic index](#quick-diagnostic-index)
- [SSH / Network](#ssh--network)
- [OS Configuration](#os-configuration)
- [Docker](#docker)
- [ADempiere — BackEnd](#adempiere--backend)
- [Traefik — FrontEnd](#traefik--frontend)
- [Integration](#integration)
- [End-to-End](#end-to-end)

---

Diagnostic reference — use this when something is not working as expected.  
Jump to the section that matches your failure.

For a step-by-step deployment with built-in verification, see [getting-started.md](getting-started.md).  
For pre-flight checks before first deployment, see the **Pre-flight check** section in [getting-started.md](getting-started.md).

---

## Quick diagnostic index

| Symptom | Section |
|---|---|
| Can't reach server (ping fails) | [SSH / Network](#ssh--network) |
| SSH connection refused | [SSH / Network](#ssh--network) |
| Ansible ping fails | [SSH / Network](#ssh--network) |
| SSH still on port 22 after serversconf | [OS Configuration](#os-configuration) |
| Root login still enabled | [OS Configuration](#os-configuration) |
| Admin user missing or no sudo | [OS Configuration](#os-configuration) |
| unattended-upgrades not running | [OS Configuration](#os-configuration) |
| Docker not installed or not running | [Docker](#docker) |
| ADempiere containers not running | [ADempiere — BackEnd](#adempiere--backend) |
| ADempiere application errors | [ADempiere — BackEnd](#adempiere--backend) |
| PostgreSQL not accepting connections | [ADempiere — BackEnd](#adempiere--backend) |
| Traefik or socket-proxy not running | [Traefik — FrontEnd](#traefik--frontend) |
| Certificate errors in Traefik logs | [Traefik — FrontEnd](#traefik--frontend) |
| Traefik not listening on 80/443 | [Traefik — FrontEnd](#traefik--frontend) |
| FrontEnd can't reach BackEnd | [Integration](#integration) |
| Traefik dashboard shows service unhealthy | [Integration](#integration) |
| DNS not resolving to FrontEnd IP | [Integration](#integration) |
| TLS certificate missing or invalid | [End-to-End](#end-to-end) |
| Login page not loading | [End-to-End](#end-to-end) |
| Login fails | [End-to-End](#end-to-end) |

> Variables used throughout this guide:
> - `<backend_ip>` — BackEnd server IP (from `inventories/hosts.yml`)
> - `<frontend_ip>` — FrontEnd server IP (from `inventories/hosts.yml`)
> - `<custom_sshport>` — custom SSH port (from `group_vars/all/vars.yml`, default `10099`)
> - `<admin_user>` — admin username set in `adempiere_username` (from `group_vars/all/vars.yml`)
> - `<dns_domain>` — your domain (from `group_vars/all/vars.yml`)

---

## SSH / Network

### Server is not pingable

```bash
ping -c 3 <backend_ip>
ping -c 3 <frontend_ip>
```

**Failure:** Routing or firewall problem at the hosting provider. Check the security group rules.

---

### SSH not reachable on port 22 (before serversconf.yml)

```bash
nc -zv <backend_ip> 22
nc -zv <frontend_ip> 22
```

**Failure:** Server not yet provisioned, or hosting provider firewall blocks port 22.

---

### SSH not reachable on custom port (after serversconf.yml)

```bash
nc -zv <backend_ip> <custom_sshport>
nc -zv <frontend_ip> <custom_sshport>
```

**Failure:** `serversconf.yml` has not run yet, or the hosting provider's firewall does not allow `<custom_sshport>`. Check the security group settings.

---

### Ansible ping fails

```bash
# Before serversconf (root, port 22)
ansible servers -m ping -e "ansible_user=root ansible_password=$(ansible-vault view group_vars/all/vault.yml | grep root_user_password | awk '{print $2}')"

# After serversconf (admin user, custom port)
ansible servers -m ping -e "ansible_user=<admin_user> ansible_port=<custom_sshport>"
```

**Failure:** Check connectivity above, vault credentials, and known_hosts (run `serversprep.yml` if host fingerprints are missing).

---

## OS Configuration

SSH to the server first:

```bash
ssh <admin_user>@<backend_ip> -p <custom_sshport>
ssh <admin_user>@<frontend_ip> -p <custom_sshport>
```

Run the checks below on **both** servers unless noted.

---

### SSH still on port 22 / hardening did not apply

```bash
ss -tlnp | grep sshd
```

**Expected:** `*:<custom_sshport>`. Port 22 should not appear.  
**Failure:** `serversconf.yml` did not complete — re-run it.

---

### Root login still enabled / password authentication still enabled

Always use `sshd -T` to check the **effective** SSH config — it merges `sshd_config` and all drop-in files in `sshd_config.d/`. Grepping individual files can be misleading when hosting providers (e.g. Contabo's `50-cloud-init.conf`) override settings in a drop-in file.

```bash
sudo sshd -T | grep -E "permitrootlogin|passwordauthentication"
```

**Expected:**
```
permitrootlogin no
passwordauthentication no
```

**Failure:** Re-run `serversconf.yml` (see known-issues.md item 2 for the correct command on an already-hardened server).

---

### Admin user missing or no sudo

```bash
id <admin_user>
sudo -l -U <admin_user>
```

**Expected:** User exists with `sudo` in groups; `sudo -l` shows `(ALL) NOPASSWD: ALL`.  
**Failure:** Check `adempiere_username` and `adempiere_user_password` in the vault, then re-run `serversconf.yml`.

---

### unattended-upgrades not running

```bash
systemctl is-active unattended-upgrades
cat /etc/apt/apt.conf.d/02periodic
```

**Expected:** `active` and the periodic config showing update intervals.  
**Failure:** Re-run `serversconf.yml`.

---

## Docker

### Docker not installed or not running

```bash
docker --version
systemctl is-active docker
```

**Expected:** Docker version `24+` and `active`.  
**Failure:** Run `install-docker.yml`.

---

## ADempiere — BackEnd

SSH to the BackEnd: `ssh <admin_user>@<backend_ip> -p <custom_sshport>`

---

### Containers not running

```bash
docker ps
```

**Expected:** At least the `adempiere-ui-gateway` container in `Up` state.  
**Failure:** Run `deploy-adempiere.yml`. If it was already run, check logs below.

---

### Application errors in container logs

```bash
cd /opt/development/adempiere-ui-gateway/docker-compose
sudo env PWD=$PWD docker compose logs adempiere-zk --tail 50
sudo env PWD=$PWD docker compose logs postgresql-service --tail 30
```

**Expected:** No `ERROR` or `Exception` entries. Application startup messages ending with the server being ready.  
**Failure:** See [troubleshooting.md](troubleshooting.md) for common ADempiere startup errors.

---

### PostgreSQL not accepting connections

```bash
docker ps --format '{{.Names}}' | grep -i postgres | xargs -I{} docker exec {} pg_isready -h localhost
```

**Expected:** `localhost:5432 - accepting connections`  
**Failure:** PostgreSQL container is not running or crashed. Check its logs:
```bash
docker ps -a | grep postgres
docker logs <postgres-container-name> --tail 30
```

---

## Traefik — FrontEnd

SSH to the FrontEnd: `ssh <admin_user>@<frontend_ip> -p <custom_sshport>`

---

### Traefik or socket-proxy not running

```bash
docker ps
```

**Expected:** Both `traefik` and `socket-proxy` in `Up` state.  
**Failure:** Run `deploy-traefik.yml`.

---

### Certificate errors in Traefik logs

```bash
docker logs traefik --tail 50
tail -20 /docker/traefik/logs/traefik.log
```

**Expected:** No `error` entries. Certificate messages should show `certificate obtained` or `using cached certificate`.  
**Failure:**
- Certificate errors → DNS record not pointing to FrontEnd IP, or Cloudflare API token invalid. Check `cloudflare_token` in `group_vars/all/vault.yml`.
- Routing errors → check `app-adempiere.yaml` in `/docker/traefik/config/`.

---

### Traefik not listening on ports 80 and 443

```bash
ss -tlnp | grep -E ':80|:443'
```

**Expected:** Traefik listed on both ports.  
**Failure:** Traefik container not running — see above.

---

## Integration

### FrontEnd can't reach BackEnd

SSH to FrontEnd, then:

```bash
curl -s -o /dev/null -w "%{http_code}" http://<backend_ip>:<adempiere_port>/
```

**Expected:** Any HTTP response code (`200`, `302`, `401`) — any response means connectivity works.  
**Failure:** No route to host or connection refused → hosting provider firewall between the two servers, or ADempiere is not running on BackEnd.

---

### Traefik dashboard shows service as unhealthy

```bash
# Open in browser
http://<frontend_ip>:28080
```

**Expected:** Dashboard loads; `adempiere-ui-gateway` shows as green/healthy.  
**Failure:**
- Dashboard does not load → Traefik not running, or port 28080 blocked by firewall.
- Service unhealthy → BackEnd unreachable from FrontEnd (see above).

---

### DNS not resolving to FrontEnd IP

```bash
dig adempiere.<dns_domain> +short
```

**Expected:** `<frontend_ip>`  
**Failure:** DNS record missing or not yet propagated (can take up to 5 minutes after creation).

---

## End-to-End

### TLS certificate missing or invalid

```bash
curl -sv https://adempiere.<dns_domain> 2>&1 | grep -E "subject:|issuer:|expire"
```

**Expected:** Certificate issued by `Let's Encrypt`, not expired.  
**Failure:**
- Self-signed or missing → Traefik has not yet obtained the certificate. Check Traefik logs above.
- DNS challenge failed → verify Cloudflare API token in `roles/deploy-traefik/vars/main.yml`.

---

### Login page not loading

```bash
curl -s -o /dev/null -w "%{http_code}" https://adempiere.<dns_domain>
```

**Expected:** `200` or `302`.  
**Failure:** See TLS certificate section above, or integration section for routing issues.

---

### Login fails

Open `https://adempiere.<dns_domain>` in a browser and attempt login.

**Expected:** Dashboard loads after login.  
**Failure:** Application error, database not ready, or wrong credentials. Check ADempiere container logs above.

---

[← Running the System](running.md) | [Next: Operations →](operations.md)

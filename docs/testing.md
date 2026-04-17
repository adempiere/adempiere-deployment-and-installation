# Testing & Debugging Guide

This guide lets you verify a deployment from scratch, or isolate exactly where a failure occurred.
Tests are ordered **bottom-up**: start at Layer 0 (your local machine) and work upward to Layer 5
(the running application). Each layer depends on the one below it — there is no point testing Layer 3
if Layer 2 is broken.

For each test: the exact command to run, the expected output, and what failure means.

> Variables used throughout this guide:
> - `<backend_ip>` — BackEnd server IP (from `inventories/hosts`)
> - `<frontend_ip>` — FrontEnd server IP (from `inventories/hosts`)
> - `<custom_sshport>` — custom SSH port (from `group_vars/all.yml`, default `10099`)
> - `<admin_user>` — admin username created by `serversconf.yml` (default `westfalia`)
> - `<dns_domain>` — your domain (from `group_vars/all.yml`)

---

## Layer 0 — Control Node / Local Prerequisites

These tests run entirely on your local machine before touching any server.

---

### 0.1 Ansible is installed and meets the minimum version

```bash
ansible --version
```

**Expected:** `ansible [core 2.14]` or higher.  
**Failure:** Install or upgrade Ansible — see [requirements.md](requirements.md).

---

### 0.2 Required Ansible collections are installed

```bash
ansible-galaxy collection list | grep -E 'community\.(docker|postgresql|crypto)'
```

**Expected:** Three lines, one for each collection.  
**Failure:** Install missing collections:
```bash
ansible-galaxy collection install community.docker community.postgresql community.crypto
```

---

### 0.3 Vault password file exists and has correct permissions

```bash
ls -la ~/.vault_pass.txt
```

**Expected:** File exists, permissions are `-rw-------` (mode `0600`).  
**Failure:** Create the file and restrict permissions:
```bash
echo "YourVaultPassword" > ~/.vault_pass.txt
chmod 600 ~/.vault_pass.txt
```

---

### 0.4 Vault file decrypts correctly

```bash
ansible-vault view group_vars/all.yml
```

**Expected:** Plaintext YAML showing variable names and values.  
**Failure:** Wrong vault password, or `group_vars/all.yml` does not exist.
- If the file is missing: copy and fill in `group_vars/all_template.yml`, then encrypt it.
- If the password is wrong: check `~/.vault_pass.txt` contents.

---

### 0.5 All required vault variables are present

After running 0.4, verify these keys appear in the output:

| Variable | Used by |
|---|---|
| `root_ansible_password` | `serversprep.yml`, `serversconf.yml`, `so-updates.yml` |
| `westfaila_ansible_password` | `deploy-adempiere.yml`, `deploy-traefik.yml` |
| `westfalia_ansible_become_pass` | `deploy-adempiere.yml`, `deploy-traefik.yml` |
| `custom_sshport` | All post-hardening playbooks |

**Failure:** Variable is missing — edit the vault and add it:
```bash
ansible-vault edit group_vars/all.yml
```

---

### 0.6 Inventory IPs are set

```bash
cat inventories/hosts
```

**Expected:** Real IP addresses under `[BackEnd]`, `[FrontEnd]`, and `[contabo]` — not placeholders.  
**Failure:** Edit `inventories/hosts` and fill in the actual server IPs.

---

### 0.7 SSH keypair exists inside the project

```bash
ls -la ssh_keys/adempiere_installation_key ssh_keys/adempiere_installation_key.pub
```

**Expected:** Both files exist; the private key has mode `0600` or `0640`.  
**Failure:** Generate the keypair:
```bash
ansible-playbook genkey.yml
```

---

### 0.8 Syntax check passes for all playbooks

```bash
ansible-playbook main.yml --syntax-check
ansible-playbook main-w-traefik.yml --syntax-check
ansible-playbook deploy-adempiere.yml --syntax-check
ansible-playbook deploy-traefik.yml --syntax-check
```

**Expected:** `playbook: <name>` with no errors.  
**Failure:** Syntax error — read the error message, it points to the exact file and line number.

---

## Layer 1 — Network / SSH Connectivity

These tests verify that the servers are reachable from your control node.

---

### 1.1 Control node can ping BackEnd

```bash
ping -c 3 <backend_ip>
```

**Expected:** 3 replies with low latency.  
**Failure:** Routing or firewall problem at the hosting provider level.

---

### 1.2 Control node can ping FrontEnd

```bash
ping -c 3 <frontend_ip>
```

**Expected:** 3 replies with low latency.  
**Failure:** Same as 1.1.

---

### 1.3 SSH on port 22 is reachable (before serversconf.yml)

Only relevant before `serversconf.yml` has run — i.e. on a freshly provisioned server.

```bash
nc -zv <backend_ip> 22
nc -zv <frontend_ip> 22
```

**Expected:** `Connection to <ip> 22 port [tcp/ssh] succeeded!`  
**Failure:** Server not yet provisioned, or hosting provider firewall blocks port 22.

---

### 1.4 SSH on custom port is reachable (after serversconf.yml)

```bash
nc -zv <backend_ip> <custom_sshport>
nc -zv <frontend_ip> <custom_sshport>
```

**Expected:** `Connection to <ip> <port> port [tcp/*] succeeded!`  
**Failure:** `serversconf.yml` has not run yet, or the hosting provider's firewall does not allow
`<custom_sshport>`. Check the hosting provider's security group settings.

---

### 1.5 Ansible ping succeeds for all groups

```bash
# Before serversconf (root, port 22)
ansible contabo -m ping -e "ansible_user=root ansible_password=$(ansible-vault view group_vars/all.yml | grep root_ansible_password | awk '{print $2}')"

# After serversconf (admin user, custom port)
ansible contabo -m ping \
  -e "ansible_user=<admin_user> ansible_port=<custom_sshport>"
```

**Expected:** `pong` for every host.  
**Failure:** Check SSH connectivity (1.3/1.4), vault credentials (0.4/0.5), and known_hosts
(run `serversprep.yml` if host fingerprints are missing).

---

## Layer 2 — OS Configuration

SSH to each server and verify that `serversconf.yml` applied correctly.

```bash
ssh <admin_user>@<backend_ip> -p <custom_sshport>
ssh <admin_user>@<frontend_ip> -p <custom_sshport>
```

Run the following checks on **both** servers unless noted.

---

### 2.1 SSH is listening on the custom port (not 22)

```bash
ss -tlnp | grep sshd
```

**Expected:** `*:<custom_sshport>` in the output. Port 22 should not appear.  
**Failure:** `serversconf.yml` did not complete — re-run it.

---

### 2.2 Root login is disabled

```bash
grep PermitRootLogin /etc/ssh/sshd_config
```

**Expected:** `PermitRootLogin no`  
**Failure:** SSH hardening task did not apply. Re-run `serversconf.yml`.

---

### 2.3 Password authentication is disabled

```bash
grep PasswordAuthentication /etc/ssh/sshd_config
```

**Expected:** `PasswordAuthentication no`  
**Failure:** Same as 2.2.

---

### 2.4 Admin user exists and has sudo

```bash
id <admin_user>
sudo -l -U <admin_user>
```

**Expected:**
- `id` shows the user with `sudo` in the groups list.
- `sudo -l` shows `(ALL) NOPASSWD: ALL`.

**Failure:** User was not created — check `username` and `your_password` in the vault, then
re-run `serversconf.yml`.

---

### 2.5 unattended-upgrades is active

```bash
systemctl is-active unattended-upgrades
cat /etc/apt/apt.conf.d/02periodic
```

**Expected:** `active` and the periodic config showing update intervals.  
**Failure:** Re-run `serversconf.yml`.

---

### 2.6 Docker is installed and running

```bash
docker --version
systemctl is-active docker
```

**Expected:** Docker version `24+` and `active`.  
**Failure:** Run `install-docker.yml`.

---

## Layer 3 — Services (per server)

### BackEnd server

SSH to the BackEnd: `ssh <admin_user>@<backend_ip> -p <custom_sshport>`

---

#### 3.1 ADempiere containers are running

```bash
docker ps
```

**Expected:** At least the `adempiere-ui-gateway` container in `Up` state. Typically several
containers from the Compose stack (ADempiere, PostgreSQL, etc.).  
**Failure:** Run `deploy-adempiere.yml`. If it was already run, check logs (3.3).

---

#### 3.2 Status files confirm successful deployment

```bash
cat /opt/development/git_status.txt
cat /opt/development/script_status.txt
```

**Expected:** `cloned` and `runned` respectively.  
**Failure:**
- Missing `git_status.txt` → git clone did not complete. Re-run `deploy-adempiere.yml`.
- Missing `script_status.txt` → Compose stack did not start. Check logs in 3.3.

---

#### 3.3 ADempiere container logs are clean

```bash
docker logs adempiere-ui-gateway --tail 50
```

**Expected:** No `ERROR` or `Exception` entries. Application startup messages ending with the
server being ready.  
**Failure:** See [troubleshooting.md](troubleshooting.md) for common ADempiere startup errors.

---

#### 3.4 PostgreSQL is accepting connections

```bash
docker exec -it adempiere-ui-gateway bash -c "pg_isready -h localhost -p 5432" 2>/dev/null || \
  docker ps --format '{{.Names}}' | grep -i postgres | xargs -I{} docker exec {} pg_isready -h localhost
```

**Expected:** `localhost:5432 - accepting connections`  
**Failure:** PostgreSQL container is not running or crashed. Check its logs:
```bash
docker ps -a | grep postgres
docker logs <postgres-container-name> --tail 30
```

---

### FrontEnd server

SSH to the FrontEnd: `ssh <admin_user>@<frontend_ip> -p <custom_sshport>`

---

#### 3.5 Traefik and socket-proxy containers are running

```bash
docker ps
```

**Expected:** Both `traefik` and `socket-proxy` in `Up` state.  
**Failure:** Run `deploy-traefik.yml`.

---

#### 3.6 Traefik logs are clean

```bash
docker logs traefik --tail 50
tail -20 /docker/traefik/logs/traefik.log
```

**Expected:** No `error` entries. Certificate-related messages should show `certificate obtained`
or `using cached certificate`.  
**Failure:**
- Certificate errors → DNS record not pointing to FrontEnd IP, or Cloudflare API token invalid.
- Routing errors → check `app-adempiere.yaml` in `/docker/traefik/config/`.

---

#### 3.7 Traefik is listening on ports 80 and 443

```bash
ss -tlnp | grep -E ':80|:443'
```

**Expected:** Traefik listed on both ports.  
**Failure:** Traefik container not running (see 3.5).

---

## Layer 4 — Integration (inter-server)

These tests verify that the FrontEnd can reach the BackEnd, and that Traefik routing is working.

---

### 4.1 FrontEnd can reach BackEnd on the ADempiere port

SSH to FrontEnd, then:

```bash
curl -s -o /dev/null -w "%{http_code}" http://<backend_ip>:<adempiere_port>/
```

Where `<adempiere_port>` is the ADempiere application port (check
`roles/deploy-adempiere/defaults/main.yml` or the Compose file for the exposed port).

**Expected:** HTTP response code (e.g. `200`, `302`, `401`) — any response means connectivity works.  
**Failure:** No route to host or connection refused → hosting provider firewall between the two
servers, or ADempiere is not running on BackEnd.

---

### 4.2 Traefik dashboard shows BackEnd as healthy

Open in a browser (or use curl from your local machine):

```
http://<frontend_ip>:28080
```

or if DNS is set up:

```
http://traefik.<dns_domain>:28080
```

**Expected:** Traefik dashboard loads. Under **Services**, `adempiere-ui-gateway` shows as green/healthy.  
**Failure:**
- Dashboard does not load → Traefik not running (3.5), or port 28080 blocked by firewall.
- Service shows as unhealthy → BackEnd is unreachable from FrontEnd (see 4.1).

---

### 4.3 DNS resolves to the FrontEnd IP

From your local machine:

```bash
dig adempiere.<dns_domain> +short
```

**Expected:** `<frontend_ip>`  
**Failure:** DNS record missing or not yet propagated (can take up to 5 minutes after creation).

---

## Layer 5 — End-to-End (Application)

---

### 5.1 TLS certificate is valid

```bash
curl -sv https://adempiere.<dns_domain> 2>&1 | grep -E "subject:|issuer:|expire"
```

**Expected:** Certificate issued by `Let's Encrypt`, not expired.  
**Failure:**
- Self-signed or missing → Traefik has not yet obtained the certificate. Check Traefik logs (3.6).
- Cloudflare DNS challenge failed → verify API token in `roles/deploy-traefik/vars/main.yml`.

---

### 5.2 ADempiere login page loads over HTTPS

```bash
curl -s -o /dev/null -w "%{http_code}" https://adempiere.<dns_domain>
```

**Expected:** `200` or `302`.  
In a browser: the ADempiere login page loads without certificate warnings.  
**Failure:** See 5.1 for certificate issues, or 4.1/4.2 for routing issues.

---

### 5.3 ADempiere login succeeds

Open `https://adempiere.<dns_domain>` in a browser and log in with the ADempiere admin credentials.

**Expected:** Dashboard loads after login.  
**Failure:** Application error, database not ready, or wrong credentials. Check ADempiere logs (3.3).

---

## Quick Reference — Full Test Sequence

Run this sequence in order when testing a fresh deployment:

```
0.1 → 0.2 → 0.3 → 0.4 → 0.5 → 0.6 → 0.7 → 0.8   (control node)
1.1 → 1.2 → 1.4 → 1.5                              (connectivity)
2.1 → 2.2 → 2.3 → 2.4 → 2.5 → 2.6                 (OS config — both servers)
3.1 → 3.2 → 3.3 → 3.4                              (BackEnd services)
3.5 → 3.6 → 3.7                                    (FrontEnd services)
4.1 → 4.2 → 4.3                                    (integration)
5.1 → 5.2 → 5.3                                    (end-to-end)
```

If any test fails, fix it before continuing to the next layer. For remediation steps, see
[troubleshooting.md](troubleshooting.md).

---

[← Running the System](running.md) | [Next: Operations →](operations.md)

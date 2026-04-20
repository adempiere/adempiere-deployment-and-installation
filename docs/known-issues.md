# Known Issues & Technical Debt

## ⚠ Action Required Before Running

These two items will cause immediate failure or lock you out if not addressed first:

**1. Verify `custom_sshport` appears in `vars.yml` only.**
`custom_sshport` is a plain-text config value and lives in `group_vars/all/vars.yml`. If it was accidentally also added to `group_vars/all/vault.yml`, Ansible will behave unpredictably. Open both files and ensure it appears only once total:
```bash
ansible-vault view group_vars/all/vault.yml | grep custom_sshport   # should return nothing
```

**2. Re-running `serversconf.yml` on an already-hardened server requires passing the port and user explicitly.**
`serversconf.yml` connects as `root` on port 22 — the default for a fresh server. Once the role has hardened a server (port changed to `custom_sshport`, root login disabled, port 22 closed), Ansible can no longer reach it as root on port 22. Pass the current port and the admin user explicitly:
```bash
ansible-playbook serversconf.yml --limit BackEnd -e "ansible_port=10099" -e "ansible_user=westfalia"
ansible-playbook serversconf.yml --limit FrontEnd -e "ansible_port=10099" -e "ansible_user=westfalia"
```
Other playbooks (`deploy-adempiere.yml`, `install-docker.yml`) set `ansible_port` automatically via a pre-task and are not affected by this.

---

## 1. Typo in `genkey.yml` — `connection: loca1`

**File:** `genkey.yml`, line 3
**Problem:** `connection: loca1` uses the digit `1` instead of the letter `l`. Should be `connection: local`.
**Current behavior:** Ansible warns about an unknown connection plugin and falls back to its default, which happens to work correctly for localhost. The play succeeds.
**Fix:** Change `loca1` → `local` in `genkey.yml`.

---


## 4. `serverswap` role is empty

**File:** `roles/serverswap/tasks/main.yml`
**Problem:** The role exists and has the directory structure but contains no tasks. It is not referenced by any playbook.
**Status:** Placeholder — swap space configuration is not yet implemented.

---

## 5. MOTD deployment is commented out

**File:** `roles/serversconf/tasks/main.yml`, lines 172–179
**Problem:** The task that deploys the `/etc/motd` banner from `motd.j2` is commented out. The template exists but is never deployed.
**Fix:** Uncomment the task block if the MOTD is desired.

---

## 6. Traefik dashboard has no authentication

**File:** `roles/deploy-traefik/templates/traefik.yaml.j2`
**Problem:** `api.insecure: true` exposes the dashboard on port `28080` without any authentication.
**Risk:** Anyone who can reach `<FrontEnd-IP>:28080` can see full routing configuration.
**Fix:** Either remove the dashboard in production (`traefik_dashboard_enabled: false`) or protect it with a middleware.

---

## 7. Plaintext Cloudflare credentials in `deploy-traefik/vars/main.yml`

See [security.md](security.md) — this is the most urgent item before pushing to GitHub.

---

## 8. `cloudflare_tocken` variable name is misspelled

**File:** `roles/deploy-traefik/vars/main.yml` and `roles/deploy-traefik/templates/.env.j2`
**Problem:** `cloudflare_tocken` (typo) instead of `cloudflare_token`.
**Fix:** Rename consistently in both files when moving the value to the vault.

---

---

## 9. Admin user password needs to be changed before production use

**File:** `roles/serversconf/vars/main.yml` — variable `your_password`  
**Problem:** The current SHA-512 hash is a placeholder/test password. It must be replaced with a
strong password before deploying to any production server.  
**Fix:** Generate a new hash and update the vault:
```bash
# Generate a new SHA-512 hash (you will be prompted for the password)
mkpasswd --method=sha-512

# Edit the vault file and replace your_password with the new hash
ansible-vault edit roles/serversconf/vars/main.yml
```

---

[← Troubleshooting](troubleshooting.md) | [Next: Security →](security.md)

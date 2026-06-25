# Known Issues & Technical Debt

## Table of Contents

- [1. Re-running `serversconf.yml` on an already-hardened server](#1-re-running-serversconfyml-on-an-already-hardened-server)
- [~~2. Typo in `genkey.yml`~~ ✓ Fixed](#2-typo-in-genkeyyml--connection-loca1--fixed)
- [3. MOTD deployment is commented out](#3-motd-deployment-is-commented-out)
- [4. Traefik dashboard has no authentication](#4-traefik-dashboard-has-no-authentication)
- [~~5. Plaintext Cloudflare credentials~~ ✓ Fixed](#5-plaintext-cloudflare-credentials-in-deploy-traefikvarsmainyml--fixed)
- [~~6. `cloudflare_tocken` typo~~ ✓ Fixed](#6-cloudflare_tocken-variable-name-is-misspelled--fixed)
- [7. Admin user password needs to be changed](#7-admin-user-password-needs-to-be-changed-before-production-use)
- [8. Traefik workflow is partially implemented](#8-traefik-workflow-is-partially-implemented--do-not-enable-without-completing-the-setup)

---

## 1. Re-running `serversconf.yml` on an already-hardened server

`serversconf.yml` connects as `root` on port 22 — the default for a fresh server. Once the role has hardened a server (port changed to `custom_sshport`, root login disabled, port 22 closed), Ansible can no longer reach it as root on port 22. Pass the current port and the admin user explicitly:
```bash
ansible-playbook serversconf.yml --limit BackEnd -e "ansible_port=10099" -e "ansible_user=westfalia"
ansible-playbook serversconf.yml --limit FrontEnd -e "ansible_port=10099" -e "ansible_user=westfalia"
```
Other playbooks (`deploy-adempiere.yml`, `install-docker.yml`) set `ansible_port` automatically via a pre-task and are not affected by this.

---

## ~~2. Typo in `genkey.yml` — `connection: loca1`~~ ✓ Fixed

`genkey.yml` already has `connection: local` — no change was needed.

---

## 3. MOTD deployment is commented out

**File:** `roles/serversconf/tasks/main.yml`
**Problem:** The task that deploys the `/etc/motd` banner from `motd.j2` is commented out. The template exists but is never deployed.
**Fix:** Uncomment the task block if the MOTD is desired.

---

## 4. Traefik dashboard has no authentication

**File:** `roles/deploy-traefik/templates/traefik.yaml.j2`
**Problem:** `api.insecure: true` exposes the dashboard on port `28080` without any authentication.
**Risk:** Anyone who can reach `<FrontEnd-IP>:28080` can see full routing configuration.
**Fix:** Either remove the dashboard in production (`traefik_dashboard_enabled: false`) or protect it with a middleware.

---

## ~~5. Plaintext Cloudflare credentials in `deploy-traefik/vars/main.yml`~~ ✓ Fixed

Credentials replaced with placeholders in `roles/deploy-traefik/vars/main.yml`.
Vault variables `cloudflare_token` and `cloudflare_email` added to `group_vars/vault_template.yml`.

---

## ~~6. `cloudflare_tocken` variable name is misspelled~~ ✓ Fixed

Renamed to `cloudflare_token` in `roles/deploy-traefik/vars/main.yml` and `roles/deploy-traefik/templates/.env.j2`.

---

## 8. Traefik workflow is partially implemented — do not enable without completing the setup

**Variable:** `deploy_traefik` in `group_vars/all/vars.yml`  
**Problem:** Setting `deploy_traefik: true` runs `deploy-traefik.yml`, but the FrontEnd workflow has known gaps:
- No `deploy-frontend.sh` orchestration script (the BackEnd has `deploy-backend.sh`; the FrontEnd has no equivalent entry point)
- Traefik dashboard exposed without authentication (`api.insecure: true` — see item 4 above)
- DNS for your domain must point to the FrontEnd IP **before** running `deploy-traefik.yml` — Let's Encrypt validates the domain immediately on first startup; if DNS is not live the certificate request fails and the deployment stops  

Enabling Traefik without addressing these gaps WILL cause deployment errors or expose the dashboard publicly.  
**See:** `docs/traefik-status.md` for the full status and a community contribution invitation.

---

## 7. Admin user password needs to be changed before production use

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

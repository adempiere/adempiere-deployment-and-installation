# Debugging & Troubleshooting

## Cannot connect after serversconf

**Symptom:** `Connection refused` or `Permission denied` after running `serversconf.yml`

**Why:** SSH port has changed to `custom_sshport` and root login is now disabled.

**Fix:** All post-hardening playbooks use `adempiere_username` + `custom_sshport` automatically (set via `set_fact` in `pre_tasks`). For manual SSH access:
```bash
ssh <admin_user>@<server-ip> -p <custom_sshport>
```

---

## Vault decryption error

**Symptom:**
```
ERROR! Decryption failed (no vault secrets would unlock...) on group_vars/all/vault.yml
```

**Checks:**
```bash
cat ~/.vault_pass.txt           # verify content
ls -la ~/.vault_pass.txt        # must show -rw------- (0600)
ansible-vault view group_vars/all/vault.yml   # test decryption directly
```

---

## SSH host key verification fails

**Symptom:**
```
UNREACHABLE! ... Host key verification failed
```

**Fix:**
```bash
# Remove the stale entry
ssh-keygen -R <server-ip>

# Serversprep re-adds the correct fingerprint
ansible-playbook serversprep.yml
```

---

## Docker installation fails

**Symptom:** GPG key download fails or the apt repository cannot be added.

**Check connectivity from the server:**
```bash
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | head -1
```

**Also check:** The `install-docker` role explicitly validates the OS is Debian or Ubuntu. Running on a different distribution produces a clear error message.

---

## ADempiere does not start (wait tasks time out)

**Symptom:** Play fails in `Wait until postgresql is running` or `Wait until ZK has been running stably for at least 60 seconds` after exhausting retries.

**Investigate on the BackEnd server:**
```bash
cd /opt/development/adempiere-ui-gateway/docker-compose
sudo env PWD=$PWD docker compose ps
sudo env PWD=$PWD docker compose logs postgresql-service
sudo env PWD=$PWD docker compose logs adempiere-zk
```

> **Note:** Always use `sudo env PWD=$PWD docker compose …` when running Docker Compose commands manually. `sudo` resets environment variables including `PWD`; without it Docker Compose warns and may resolve paths incorrectly.

> **Note:** Avoid `sudo docker ps -a` via Ansible SSH — it can hang when containers are in `Created` state. Use `sudo docker inspect <container-name>` for specific containers instead.

**Common causes:**
- `override.env` was not generated (missing PostgreSQL credentials in vault)
- `start-all.sh` failed silently — run it manually to see its full output:
  ```bash
  cd /opt/development/adempiere-ui-gateway/docker-compose
  sudo env PWD=$PWD bash start-all.sh
  ```
- Not enough memory (ADempiere requires at least 4 GB RAM)

---

## Traefik cannot obtain a TLS certificate

**Symptom:** Browser shows certificate error; Traefik logs show ACME errors.

**Check Traefik logs on FrontEnd:**
```bash
docker logs traefik
tail -f /docker/traefik/logs/traefik.log
```

**Common causes:**
- Cloudflare API token is wrong or has insufficient permissions (`Zone:DNS:Edit` required)
- DNS record does not yet point to the correct IP
- Token in `roles/deploy-traefik/vars/main.yml` was not updated before deployment

---

## SSH config is broken / locked out

The `serversconf` role validates the SSH config before writing it:
```bash
/usr/sbin/sshd -t -f /etc/ssh/sshd_config
```

If validation fails, Ansible reports the error and does **not** write the broken config — so you cannot lock yourself out through this role. To check the config manually on a running server:
```bash
sshd -t
```

---

## Force re-run of ADempiere deployment

The role skips `start-all.sh` if the ADempiere containers are already running. To force a full restart:

```bash
# Stop containers on the BackEnd server
ssh <admin_user>@<backend_ip> -p <custom_sshport>
cd /opt/development/adempiere-ui-gateway/docker-compose
sudo env PWD=$PWD bash stop-all.sh

# Re-run the playbook — containers are stopped so start-all.sh will run
ansible-playbook deploy-adempiere.yml
```

---

## Validate playbook syntax without running

```bash
ansible-playbook main.yml --syntax-check
ansible-playbook deploy-traefik.yml --syntax-check
```

---

## Increase output verbosity

```bash
ansible-playbook deploy-adempiere.yml -vvv
```

Use `-vvvv` for full SSH-level debug output.

---

[← Operations](operations.md) | [Next: Known Issues →](known-issues.md)

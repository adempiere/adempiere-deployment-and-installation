# Debugging & Troubleshooting

## Cannot connect after serversconf

**Symptom:** `Connection refused` or `Permission denied` after running `serversconf.yml`

**Why:** SSH port has changed to `custom_sshport` and root login is now disabled.

**Fix:** All post-hardening playbooks use `westfalia` + `custom_sshport` automatically (set via `set_fact` in `pre_tasks`). For manual SSH access:
```bash
ssh <admin_user>@<server-ip> -p <custom_sshport>
```

---

## Vault decryption error

**Symptom:**
```
ERROR! Decryption failed (no vault secrets would unlock...) on group_vars/all.yml
```

**Checks:**
```bash
cat ~/.vault_pass.txt           # verify content
ls -la ~/.vault_pass.txt        # must show -rw------- (0600)
ansible-vault view group_vars/all.yml   # test decryption directly
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

## ADempiere container does not start (wait.yml times out)

**Symptom:** Play fails in the `Wait until container is running` task after 30 retries (5 minutes).

**Investigate on the BackEnd server:**
```bash
docker ps -a | grep adempiere
docker logs adempiere-ui-gateway
cd /opt/development/adempiere-ui-gateway/docker-compose
docker compose ps
docker compose logs
```

**Common causes:**
- `override.env` was not generated (missing PostgreSQL credentials in vault)
- `start-all.sh` failed silently — check its exit code
- Not enough memory (ADempiere requires at least 4 GB RAM)
- The git clone did not succeed — check `/opt/development/git_status.txt`

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

If idempotency status files prevent the role from re-running:
```bash
# On BackEnd server
rm /opt/development/git_status.txt
rm /opt/development/script_status.txt

# Re-run
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

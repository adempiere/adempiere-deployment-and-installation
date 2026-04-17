# Security Notes

## ⚠ Plaintext Cloudflare Credentials — Fix Before Pushing to GitHub

`roles/deploy-traefik/vars/main.yml` currently contains real credentials in plaintext:

```yaml
cloudflare_tocken: <actual-api-token>
cloudflare_email: <actual-email>
```

**This file will be committed to git as-is.** Rotate the token and move it to the vault before the first push.

**Recommended fix:**

1. Rotate the Cloudflare API token (generate a new one in the Cloudflare dashboard, revoke the old one).

2. Add the new values to the vault:
   ```bash
   ansible-vault edit group_vars/all.yml
   ```
   Add (with corrected spelling):
   ```yaml
   cloudflare_token: "your-new-token"
   cloudflare_email: "your-email"
   ```

3. Clear `roles/deploy-traefik/vars/main.yml` to a comment only:
   ```yaml
   # Cloudflare credentials are stored in the vault (group_vars/all.yml)
   # Variables: cloudflare_token, cloudflare_email
   ```

4. Update the template `roles/deploy-traefik/templates/.env.j2` and `roles/deploy-traefik/templates/traefik.yaml.j2` to use `cloudflare_token` (correct spelling).

---

## SSH Hardening Summary

After `serversconf.yml` runs, the SSH configuration enforces:

| Setting | Value | Reason |
|---|---|---|
| `PasswordAuthentication` | `no` | Key-only login — prevents brute force |
| `PermitRootLogin` | `no` | Forces use of the named user account |
| `Port` | `<custom_sshport>` | Avoids automated port-22 scanners |
| `MaxAuthTries` | `3` | Limits authentication attempts |
| `X11Forwarding` | `no` | No GUI, reduces attack surface |
| `UseDNS` | `no` | Prevents slow logins from reverse DNS lookups |
| `KexAlgorithms` | Curve25519, DH-group16/18 | Drops legacy Diffie-Hellman groups |
| `Ciphers` | ChaCha20-Poly1305, AES-GCM | Drops legacy CBC ciphers |
| `MACs` | SHA2-512-etm, SHA2-256-etm | Encrypt-then-MAC only |

The SSH config is **validated** before being written (`sshd -t`), so a misconfiguration cannot lock you out through this role.

---

## Docker Socket Proxy

Traefik does not mount the Docker socket directly. Instead, the `socket-proxy` container exposes a restricted, read-only view of the Docker API. This means a compromised Traefik container cannot issue `docker run` or other management commands.

---

## Automatic Security Updates

`unattended-upgrades` is configured by the `serversconf` role:

- `/etc/apt/apt.conf.d/50unattended-upgrades` — defines which repositories auto-update
- `/etc/apt/apt.conf.d/02periodic` — defines the update frequency

Security patches are applied automatically without manual intervention.

---

## Vault Hygiene

- Never commit `~/.vault_pass.txt` to git
- Never commit `group_vars/all.yml` in decrypted form
- Never commit `ssh_keys/adempiere_installation_key` (the private key) — it is gitignored; only the `.pub` is tracked
- A `.gitignore` is in place covering all of the above
- If a secret is ever exposed: rotate it immediately, then update the vault

---

[← Known Issues](known-issues.md) | [Next: Variable Reference →](variables.md)

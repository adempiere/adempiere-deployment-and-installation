# Security Notes

## Table of Contents

- [Cloudflare Credentials](#cloudflare-credentials)
- [SSH Hardening Summary](#ssh-hardening-summary)
- [Docker Socket Proxy](#docker-socket-proxy)
- [Automatic Security Updates](#automatic-security-updates)
- [Vault Hygiene](#vault-hygiene)

---

## Cloudflare Credentials

Cloudflare API credentials (`cloudflare_token` and `cloudflare_email`) must never be stored in plain text in committed files.

**Current state (correctly configured):**

- `roles/deploy-traefik/vars/main.yml` contains only placeholder values and a comment pointing to the vault.
- The real credentials must be placed in `group_vars/all/vault.yml` (encrypted, gitignored).
- Use `group_vars/vault_template.yml` as a starting point — it already contains the two variables with placeholder values and instructions.

```bash
ansible-vault edit group_vars/all/vault.yml
```

Add:
```yaml
cloudflare_token: "your-cloudflare-api-token"   # Zone:DNS:Edit permission required
cloudflare_email: "your-cloudflare-account-email"
```

If a secret is ever accidentally committed, rotate it immediately at the Cloudflare dashboard and update the vault.

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
- Never commit `group_vars/all/vault.yml` in decrypted form
- Never commit `ssh_keys/adempiere_installation_key` or its `.pub` — both are gitignored; each operator generates their own keypair after cloning
- A `.gitignore` is in place covering all of the above
- If a secret is ever exposed: rotate it immediately, then update the vault

---

[← Known Issues](known-issues.md) | [Next: Variable Reference →](variables.md)

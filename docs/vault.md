# Secrets & Vault Management

## What is the Vault?

When you push a project to GitHub, everything in the repository becomes visible — including configuration files. Passwords, API tokens, and other sensitive values must never be stored in plain text in the repository.

**Ansible Vault** solves this by encrypting sensitive values using AES-256 (a military-grade symmetric encryption algorithm). The encrypted file looks like random gibberish to anyone who doesn't have the password. Ansible decrypts it automatically at runtime when it needs the values — you just need to provide the password once, via a local file on your machine that is never committed to git.

In short: the vault is an encrypted YAML file that lives in your repository but can only be read by someone who knows the vault password.

---

## Configuration File Structure

All variables — secrets and deployment-specific values alike — are stored in a single AES-256
encrypted vault file:

```
group_vars/all.yml       ← AES-256 encrypted — secrets + deployment values (IPs, domain, SSH port)
```

The vault password lives only on your local machine and is never committed to git:
```
~/.vault_pass.txt    ← referenced in ansible.cfg; read automatically on every run
```

### What is stored here

| Value | Reason |
|---|---|
| Server passwords | Must be encrypted |
| API tokens (Cloudflare) | Must be encrypted |
| Server IPs | Deployment-specific values |
| SSH port | Deployment-specific values |
| Domain name | Deployment-specific values |
| Admin username | Deployment-specific values |
| Timezone, paths | Deployment-specific values |

> **Future improvement:** splitting into a `vault.yml` (secrets only) and a plain-text `override.yml`
> (deployment values, gitignored) would make it easier to inspect non-secret values without
> decrypting. See [known-issues.md](known-issues.md) item 9 for details.

---

## Initial Setup

**1. Create the vault password file:**
```bash
echo "YourStrongVaultPassword" > ~/.vault_pass.txt
chmod 600 ~/.vault_pass.txt
```

**2. Edit the vault file with your secrets:**
```bash
ansible-vault edit group_vars/all.yml
```

---

## Vault File Contents

The vault file must contain the following variables. See [variables.md](variables.md) for the full reference.

```yaml
# Initial root access (used only during the first two playbooks)
root_ansible_password: "the-root-password-on-the-vps"

# System user to create on the servers
username: "westfalia"
your_password: "$6$..."          # SHA-512 hash — see below

# Post-hardening login credentials
westfaila_ansible_password: "westfalia-user-password"    # note: variable name has a typo — keep as-is
westfalia_ansible_become_pass: "westfalia-sudo-password"

# Database
postgres_password: "strong-postgres-password"
adempiere_password: "strong-adempiere-db-password"
```

> **⚠ IMPORTANT — `custom_sshport` must appear only once.**
> If it was accidentally added twice to `group_vars/all.yml`, Ansible will use an unpredictable value. Verify it appears only once:
> ```bash
> ansible-vault edit group_vars/all.yml
> # Ensure custom_sshport appears only once, then save and close
> ```

---

## Generating a SHA-512 Password Hash

The `your_password` variable must be a hashed password, not plaintext:

```bash
# Install mkpasswd (part of the 'whois' package)
apt-get install whois

# Generate hash — you will be prompted for the password
mkpasswd --method=sha-512
```

Copy the output (it starts with `$6$`) into the vault.

---

## Common Vault Commands

| Command | Purpose |
|---|---|
| `ansible-vault edit group_vars/all.yml` | Open encrypted file in your editor |
| `ansible-vault view group_vars/all.yml` | Print decrypted contents (read-only) |
| `ansible-vault create group_vars/all.yml` | Create a new encrypted file from scratch |
| `ansible-vault encrypt group_vars/all.yml` | Encrypt a plaintext file |
| `ansible-vault decrypt group_vars/all.yml` | Decrypt to plaintext (use with care — never commit the result) |
| `ansible-vault rekey group_vars/all.yml` | Change the vault password |

---

## How ansible.cfg connects the vault

```ini
[defaults]
vault_password_file = ~/.vault_pass.txt
```

Because of this setting, you never need to pass `--vault-password-file` on the command line. All `ansible-playbook` and `ansible-vault` commands pick it up automatically.

---

[← Project Structure](project-structure.md) | [Next: Configuration →](configuration.md)

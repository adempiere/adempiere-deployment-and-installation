# Vault Management

## Table of Contents

- [What is the vault?](#what-is-the-vault)
- [Configuration file structure](#configuration-file-structure)
- [Initial setup](#initial-setup)
- [Vault file contents](#vault-file-contents-group_varsallvaultyml)
- [Plain-text variables](#plain-text-variables-group_varsallvarsyml)
- [Generating a SHA-512 password hash](#generating-a-sha-512-password-hash)
- [Common vault commands](#common-vault-commands)
- [How vault variables are used in playbooks](#how-vault-variables-are-used-in-playbooks)
- [Role vars files](#role-vars-files)
- [How ansible.cfg connects the vault](#how-ansiblecfg-connects-the-vault)
- [Changing the vault password](#changing-the-vault-password)

---

## What is the Vault?

When you push a project to GitHub, everything in the repository becomes visible — including configuration files. Passwords, API tokens, and other sensitive values must never be stored in plain text in the repository.

**Ansible Vault** solves this by encrypting sensitive values using AES-256 (a military-grade symmetric encryption algorithm). The encrypted file looks like random gibberish to anyone who doesn't have the password. Ansible decrypts it automatically at runtime when it needs the values — you just need to provide the password once, via a local file on your machine that is never committed to git.

In short: the vault is an encrypted YAML file that lives in your repository but can only be read by someone who knows the vault password.

---

## Configuration File Structure

```
group_vars/
├── vars_template.yml      ← committed — reference; copy to all/vars.yml and fill in your values
├── vault_template.yml     ← committed — reference; copy to all/vault.yml, fill in secrets, then encrypt
└── all/                   ← Ansible auto-loads every .yml file found here
    ├── vars.yml           ← gitignored — plain-text config values (username, SSH port, key path)
    └── vault.yml          ← gitignored — AES-256 encrypted secrets (passwords, API tokens)
```

**Why the templates cannot live in `group_vars/all/`:**  
Ansible automatically loads every `.yml` file it finds in `group_vars/all/`. If the templates were placed there, their placeholder values (`your-root-password`, `your-admin-username`, etc.) would be loaded alongside the real files — and because files are loaded alphabetically, `vault_template.yml` would come after `vault.yml` and silently override all your real credentials. Keeping the templates one level up in `group_vars/` puts them completely outside Ansible's auto-load path.

The vault password lives only on your local machine and is never committed to git:
```
~/.vault_pass.txt    ← referenced in ansible.cfg; read automatically on every run
```

### What goes where

| Value | File | Reason |
|---|---|---|
| Server passwords | `vault.yml` | Must be encrypted |
| API tokens (Cloudflare) | `vault.yml` | Must be encrypted |
| Admin username | `vars.yml` | Non-secret config |
| SSH port | `vars.yml` | Non-secret config |
| Domain name | `vars.yml` | Non-secret config |
| SSH key name and path | `vars.yml` | Non-secret config |

---

## Initial Setup

**1. Create the vault password file:**
```bash
echo "YourStrongVaultPassword" > ~/.vault_pass.txt
chmod 600 ~/.vault_pass.txt
```

**2. Copy the templates and fill in your values:**
```bash
cp group_vars/vars_template.yml group_vars/all/vars.yml
# Edit vars.yml — username, SSH port, key path
```

**3. Create and encrypt the vault file:**
```bash
cp group_vars/vault_template.yml group_vars/all/vault.yml
# Edit vault.yml — passwords and API tokens
ansible-vault encrypt group_vars/all/vault.yml
```

After this, `vault.yml` is encrypted on disk. Use `ansible-vault edit` to modify it later.

---

## Vault File Contents (`group_vars/all/vault.yml`)

The vault file contains only secrets. See [variables.md](variables.md) for the full reference.

```yaml
# Initial root access (used only during the first two playbooks)
root_user_password: "the-root-password-on-the-vps"

# SHA-512 hash of the admin user's password — see below
your_password: "$6$..."

# Post-hardening SSH credentials for adempiere_username
adempiere_user_password: "your-admin-user-password"
adempiere_user_become_pass: "your-admin-sudo-password"

# Database
postgres_password: "strong-postgres-password"
adempiere_password: "strong-adempiere-db-password"
```

## Plain-Text Variables (`group_vars/all/vars.yml`)

```yaml
key_name: adempiere_installation_key
ansible_ssh_private_key_file: "{{ playbook_dir }}/ssh_keys/adempiere_installation_key"
adempiere_username: "your-admin-username"
custom_sshport: 10099
dns_domain: "your-domain.example.com"
timezone: "America/El_Salvador"
```

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
| `ansible-vault edit group_vars/all/vault.yml` | Open encrypted file in your editor |
| `ansible-vault view group_vars/all/vault.yml` | Print decrypted contents (read-only) |
| `ansible-vault create group_vars/all/vault.yml` | Create a new encrypted file from scratch |
| `ansible-vault encrypt group_vars/all/vault.yml` | Encrypt a plaintext file |
| `ansible-vault decrypt group_vars/all/vault.yml` | Decrypt to plaintext (use with care — never commit the result) |
| `ansible-vault rekey group_vars/all/vault.yml` | Change the vault password |

---

## Role Vars Files

Two role vars files are also vault-encrypted and use the **same password** as `group_vars/all/vault.yml`
(`MyVaultPassword` by default — change before going live):

| File | Contains |
|---|---|
| `roles/serversconf/vars/main.yml` | `adempiere_username`, `your_password` (SHA-512 hash), `user_path` |
| `roles/deploy-adempiere/vars/main.yml` | `postgres_password` |

To view or edit them:
```bash
ansible-vault view roles/serversconf/vars/main.yml
ansible-vault edit roles/deploy-adempiere/vars/main.yml
```

No `--ask-vault-pass` needed — `ansible.cfg` reads `~/.vault_pass.txt` automatically.

To change the vault password (applies to all three files at once):
```bash
printf "NewPassword" > /tmp/new_pass.txt
ansible-vault rekey --vault-password-file ~/.vault_pass.txt --new-vault-password-file /tmp/new_pass.txt \
  group_vars/all/vault.yml roles/serversconf/vars/main.yml roles/deploy-adempiere/vars/main.yml
cp /tmp/new_pass.txt ~/.vault_pass.txt && rm /tmp/new_pass.txt
```

---

## How vault variables are used in playbooks

Vault variables are referenced in playbooks and templates exactly like any other Ansible variable — using the `{{ variable_name }}` syntax. Ansible decrypts the vault file at runtime and injects the values transparently. You never reference "the vault" explicitly in a playbook.

**In a playbook `pre_tasks` block:**

```yaml
pre_tasks:
  - name: Assign connection credentials
    ansible.builtin.set_fact:
      ansible_user:           "{{ adempiere_username }}"
      ansible_password:       "{{ adempiere_user_password }}"     # from vault
      ansible_become_password: "{{ adempiere_user_become_pass }}" # from vault
      ansible_port:           "{{ custom_sshport }}"
```

**In a Jinja2 template (`override.env.j2`):**

```jinja2
POSTGRES_PASSWORD={{ postgres_password }}   {# value from vault, never written in plaintext #}
```

**In a role task:**

```yaml
- name: Create PostgreSQL user
  community.postgresql.postgresql_user:
    name: adempiere
    password: "{{ adempiere_password | default(postgres_password) }}"  # vault variable
```

The vault is transparent: from the role's perspective, vault variables and plain-text variables are identical. The only difference is where they are stored on disk.

---

## How ansible.cfg connects the vault

```ini
[defaults]
vault_password_file = ~/.vault_pass.txt
```

Because of this setting, you never need to pass `--vault-password-file` on the command line. All `ansible-playbook` and `ansible-vault` commands pick it up automatically.

---

## Changing the vault password

All three vault-encrypted files must be rekeyed together — they share the same password.

```bash
# Write the new password to a temporary file
printf "NewPassword" > /tmp/new_pass.txt

# Rekey all three encrypted files at once
ansible-vault rekey \
  --vault-password-file ~/.vault_pass.txt \
  --new-vault-password-file /tmp/new_pass.txt \
  group_vars/all/vault.yml \
  roles/serversconf/vars/main.yml \
  roles/deploy-adempiere/vars/main.yml

# Update the local vault password file
cp /tmp/new_pass.txt ~/.vault_pass.txt
rm /tmp/new_pass.txt
```

Verify the rekey worked:

```bash
ansible-vault view group_vars/all/vault.yml   # should print plaintext without error
```

---

[← Project Structure](project-structure.md) | [Next: Configuration →](configuration.md)

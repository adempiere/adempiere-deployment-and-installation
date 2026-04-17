# Configuration Reference

## ansible.cfg

```ini
[defaults]
inventory = ./inventories/hosts
vault_password_file = ~/.vault_pass.txt
```

- `inventory` — relative path to the inventory file, resolved from the project root
- `vault_password_file` — absolute path to the vault password; Ansible reads it automatically on every run

---

## Inventory (`inventories/hosts.yml`)

```yaml
all:
  children:
    servers:
      hosts:
        backend:
          ansible_host: <backend_ip>
        frontend:
          ansible_host: <frontend_ip>
    BackEnd:
      hosts:
        backend:
    FrontEnd:
      hosts:
        frontend:
    ansible_test:
      hosts:
        test:
          ansible_host: <test_ip>
```

> IPs live in `inventories/hosts.yml` — gitignored. Copy `inventories/hosts_template.yml` and fill in your values.

**Which playbooks target which groups:**

| Group | Used by |
|---|---|
| `servers` | `serversprep.yml`, `so-updates.yml`, `serversconf.yml`, `install-docker.yml`, `deploy-vim.yml` |
| `BackEnd` | `deploy-adempiere.yml`, `adempiere-restoredb.yml` |
| `FrontEnd` | `deploy-traefik.yml` |
| `localhost` | `genkey.yml` |

---

## Connection User per Playbook

Each playbook sets the connection user in a `pre_tasks` block using `set_fact`. This is why you do not set `ansible_user` in the inventory.

| Playbook | User | Auth |
|---|---|---|
| `genkey.yml` | *(local)* | local connection — no SSH |
| `serversprep.yml` | `root` | vault: `root_user_password` |
| `so-updates.yml` | `root` | vault: `root_user_password` |
| `serversconf.yml` | `root` | vault: `root_user_password` |
| `install-docker.yml` | `adempiere_username` | vault: `adempiere_user_password` + `adempiere_user_become_pass`, custom port |
| `deploy-vim.yml` | `adempiere_username` | vault: `adempiere_user_password` + `adempiere_user_become_pass`, custom port |
| `deploy-adempiere.yml` | `adempiere_username` | vault: `adempiere_user_password` + `adempiere_user_become_pass`, custom port |
| `deploy-traefik.yml` | `adempiere_username` | vault: `adempiere_user_password` + `adempiere_user_become_pass`, custom port |
| `adempiere-restoredb.yml` | `adempiere_username` | vault: `adempiere_user_password` + `adempiere_user_become_pass`, custom port |

The transition from `root` to `<admin_user>` happens after `serversconf.yml` creates the user and disables root login.

---

## Customizing Role Behavior

Role defaults are defined in `roles/<role>/defaults/main.yml`. Override any of them by setting the variable in:

- `group_vars/all.yml` (applies to all hosts)
- A host-specific block in `inventories/hosts.yml` under the relevant host
- On the command line: `ansible-playbook deploy-adempiere.yml -e "repo_version=main"`

See [variables.md](variables.md) for the full list of defaults per role.

---

## Changing the Domain

The domain is set in `group_vars/all.yml`:

```yaml
dns_domain: "yourdomain.example.com"
```

The subdomain prefix defaults to `adempiere` (defined in `roles/deploy-traefik/defaults/main.yml`). Override it in `override.yml` to change the full hostname:

```yaml
host: "erp"   # results in erp.yourdomain.example.com
```

Changes take effect when `deploy-traefik.yml` is re-run.

---

## Changing the ADempiere Branch

The Git branch is set in `roles/deploy-adempiere/defaults/main.yml`:

```yaml
repo_version: adempiere-trunk
```

Override it to deploy a different branch:
```bash
ansible-playbook deploy-adempiere.yml -e "repo_version=main"
```

Note: changing the branch does **not** automatically trigger a re-deploy if the idempotency status files already exist. Delete them first — see [operations.md](operations.md).

---

[← Vault Management](vault.md) | [Next: Getting Started →](getting-started.md)

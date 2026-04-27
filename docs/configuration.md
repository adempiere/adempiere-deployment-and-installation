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
    servers:           # parent group — automatically includes BackEnd and FrontEnd
      children:
        BackEnd:
          hosts:
            backend1:
              ansible_host: <backend_ip>
            # backend2:             # uncomment to add a second BackEnd server
            #   ansible_host: <ip>
        FrontEnd:
          hosts:
            frontend:
              ansible_host: <frontend_ip>
    ansible_test:
      hosts:
        test:
          ansible_host: <test_ip>
```

> IPs live in `inventories/hosts.yml` — gitignored. Copy `inventories/hosts_template.yml` and fill in your values.  
> Each host is defined exactly once. Adding `backend2` under `BackEnd` is all that is needed to scale out — all playbooks pick it up automatically.

**Which playbooks target which groups:**

| Group | Used by |
|---|---|
| `servers` | `serversprep.yml`, `so-updates.yml`, `serversconf.yml`, `serverswap.yml`, `install-docker.yml`, `deploy-vim.yml` |
| `BackEnd` | `deploy-adempiere.yml`, `deploy-crontab.yml`, `adempiere-restoredb.yml` |
| `FrontEnd` | `deploy-traefik.yml` |
| `localhost` | `genkey.yml` |

---

## Connection User per Playbook

`ansible_user` is never set in the inventory — each playbook sets its own connection user. There are two patterns depending on whether the playbook needs `gather_facts`:

- **`gather_facts: false` + `pre_tasks: set_fact`** — used when the role does not need OS facts. `pre_tasks` run before any SSH connection, so `set_fact` can safely set `ansible_user` first. (`serversprep.yml`, `so-updates.yml`)
- **`gather_facts: true` + play-level `vars:`** — used when the role needs OS facts (e.g. to detect the distribution). Ansible connects to gather facts before `pre_tasks` run, so `set_fact` in `pre_tasks` would be too late. Play-level `vars:` are evaluated before gather_facts, so the correct user is in place for the initial connection. (`serversconf.yml`, `install-docker.yml`)

| Playbook | User | Auth | gather_facts |
|---|---|---|---|
| `genkey.yml` | *(local)* | local connection — no SSH | `true` |
| `serversprep.yml` | `root` | vault: `root_user_password` | `false` |
| `so-updates.yml` | `root` | vault: `root_user_password` | `false` |
| `serversconf.yml` | `root` | vault: `root_user_password` | `true` |
| `install-docker.yml` | `adempiere_username` | vault: `adempiere_user_password` + `adempiere_user_become_pass`, custom port | `true` |
| `deploy-vim.yml` | `adempiere_username` | vault: `adempiere_user_password` + `adempiere_user_become_pass`, custom port | `false` |
| `deploy-adempiere.yml` | `adempiere_username` | vault: `adempiere_user_password` + `adempiere_user_become_pass`, custom port | `false` |
| `deploy-traefik.yml` | `adempiere_username` | vault: `adempiere_user_password` + `adempiere_user_become_pass`, custom port | `false` |
| `adempiere-restoredb.yml` | `adempiere_username` | vault: `adempiere_user_password` + `adempiere_user_become_pass`, custom port | `false` |

The transition from `root` to `<admin_user>` happens after `serversconf.yml` creates the user and disables root login.

---

## Customizing Role Behavior

Role defaults are defined in `roles/<role>/defaults/main.yml`. Override any of them by setting the variable in:

- `group_vars/all/vars.yml` (applies to all hosts)
- A host-specific block in `inventories/hosts.yml` under the relevant host
- On the command line: `ansible-playbook deploy-adempiere.yml -e "repo_version=main"`

See [variables.md](variables.md) for the full list of defaults per role.

---

## Changing the Domain

The domain is set in `group_vars/all/vars.yml`:

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

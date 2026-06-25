# Project Structure

## Table of Contents

- [Repository layout](#repository-layout)
- [Documentation tree](#documentation-tree)
- [Role layout](#role-layout)
- [Key files](#key-files)

---

## Repository layout

```
deployment_and_installation/
│
├── ansible.cfg                    # Inventory path + vault password file location
├── README.md                      # Quick reference with links to /docs
│
├── docs/                          # Full documentation (this directory)
│
├── inventories/
│   ├── hosts.yml                  # Inventory with real IPs — gitignored, never commit.
│   │                              #   servers (parent) → BackEnd + FrontEnd (children).
│   │                              #   Each host defined once; add backend2 here to scale out.
│   └── hosts_template.yml         # Template for hosts.yml — copy this and fill in IPs
│
├── group_vars/
│   ├── vars_template.yml          # Template for all/vars.yml — committed
│   ├── vault_template.yml         # Template for all/vault.yml — committed
│   └── all/                       # Ansible auto-loads every .yml file in this directory
│       ├── vars.yml               # Non-secret config values (username, port, key name) — gitignored
│       └── vault.yml              # AES-256 vault-encrypted secrets (passwords) — gitignored
│
├── ssh_keys/
│   ├── adempiere_installation_key      # SSH private key — gitignored, never commit
│   └── adempiere_installation_key.pub  # SSH public key — gitignored, deployed to servers by serversconf
│
│                                  # --- Orchestration playbooks ---
│                                  # Chain individual playbooks into full deployment sequences.
│                                  # Run one of these to execute multiple steps with a single command.
├── main.yml                       # Base setup only: genkey → serversprep → so-updates → serversconf → deploy-vim → install-docker
├── main-w-traefik.yml             # Full end-to-end: base setup + deploy-traefik + deploy-adempiere
│
│                                  # --- Individual playbooks ---
│                                  # Each does exactly one thing. Can be run standalone or called by an orchestration playbook.
├── genkey.yml                     # Generate RSA keypair on the control node (localhost); stores it in ssh_keys/
├── serversprep.yml                # Distribute SSH public key to all servers servers
├── so-updates.yml                 # OS dist-upgrade + conditional reboot
├── serversconf.yml                # Server hardening, user creation, SSH config
├── install-docker.yml             # Docker CE + Compose plugin
├── deploy-vim.yml                 # Vim editor + plugins
├── deploy-adempiere.yml           # ADempiere container stack (BackEnd only)
├── deploy-traefik.yml             # Traefik reverse proxy (FrontEnd only)
├── serverswap.yml                 # Swap file + kernel tuning; size from group_vars/BackEnd.yml and FrontEnd.yml
├── deploy-crontab.yml             # Crontab entries for ADempiere start/stop/restart (BackEnd only)
├── adempiere-restoredb.yml        # PostgreSQL backup restore (BackEnd, on demand)
│
└── roles/
    ├── genkey/                    # Generate RSA keypair
    ├── serversprep/               # SSH key distribution to remote servers
    ├── so-updates/                # OS update + reboot handler
    ├── serversconf/               # Full server hardening
    ├── install-docker/            # Docker CE from official repo
    ├── deploy-vim/                # Vim + plugins (vim-airline, nerdtree, fzf, fugitive…)
    ├── deploy-adempiere/          # ADempiere container stack deployment
    ├── deploy-traefik/            # Traefik + socket-proxy deployment
    ├── adempiere-restoredb/       # PostgreSQL dump restore
    ├── deploy-containers/         # Generic container deployment example (nginx)
    ├── serverswap/                # Swap file creation and kernel tuning (vm.swappiness)
    └── deploy-crontab/            # Crontab: @reboot start, 23:50 stop, 23:55 restart
```

---

## Documentation tree

```
docs/
│
├── Getting started
│   ├── getting-started.md         Deployment timeline + step-by-step walkthrough
│   ├── installation.md            Installation reference — per-playbook explanation
│   └── running.md                 Playbook and script command reference
│
├── Architecture & design
│   ├── architecture.md            Network layout, two-server model, design decisions
│   ├── how-it-works.md            Runtime behaviour: BackEnd stack, FrontEnd Traefik, usage
│   ├── technologies.md            Ansible, Traefik, Docker — concepts and rationale
│   ├── relationships.md           Playbooks ↔ roles ↔ inventory group relationships
│   └── project-structure.md       Repository directory tree and file purposes (this file)
│
├── Configuration & secrets
│   ├── variables.md               Complete variable reference (mandatory/optional/examples)
│   ├── configuration.md           ansible.cfg, inventory, connection user per playbook
│   ├── vault.md                   Ansible Vault: create, encrypt, edit, rekey
│   └── security.md                Security notes and hardening summary
│
├── Operations & maintenance
│   ├── operations.md              Day-2 tasks: update, restart, backup, add customer
│   ├── testing.md                 Dry-run guide, syntax checks, connectivity tests
│   ├── troubleshooting.md         Problem resolution by symptom
│   └── known-issues.md            Known issues and technical debt
│
└── Demos & status
    ├── demo.md                    Real deployment output excerpts (annotated)
    └── traefik-status.md          Traefik FrontEnd: what works, what is missing, contributions
```

Root-level documentation files:

```
README.md          Entry point: overview, control node, quick start, running the deployment
CONTRIBUTING.md    How to contribute: setup, check mode, branching, PR guide
```

---

## Role Layout

Every role follows the standard Ansible role structure:

```
roles/<role-name>/
├── tasks/
│   └── main.yml        # Entry point; some roles include sub-task files (start.yml, ensure-healthy.yml…)
├── defaults/
│   └── main.yml        # Lowest-priority variables — safe fallbacks the operator is expected to override
│                       # (e.g. install_path, repo_url, repo_version)
├── vars/
│   └── main.yml        # Higher-priority role constants — treated as fixed by the role author,
│                       # only overridable via CLI -e flags. Used here for vault-encrypted secrets.
├── templates/
│   └── *.j2            # Jinja2 templates rendered and deployed to target servers
├── files/              # Static files copied to target servers as-is
├── handlers/
│   └── main.yml        # Handlers triggered by notify: (e.g. restart SSH)
├── meta/
│   └── main.yml        # Metadata (author, supported platforms, dependencies)
└── tests/
    ├── inventory
    └── test.yml
```

---

## Key Files

| File | Purpose |
|---|---|
| `inventories/hosts.yml` | Inventory with real server IPs — gitignored; use `hosts_template.yml` as reference |
| `group_vars/all/vars.yml` | Non-secret config values (username, SSH port, key name) — gitignored; copy from `group_vars/vars_template.yml` |
| `group_vars/all/vault.yml` | Vault-encrypted secrets (passwords) — gitignored; copy from `group_vars/vault_template.yml` |
| `ssh_keys/adempiere_installation_key.pub` | Project SSH public key — gitignored; deployed to servers by `serversconf` |
| `roles/serversconf/files/public_keys/present/admin/` | SSH public keys deployed to all servers as authorized admin keys; populated by `genkey.yml` |
| `roles/adempiere-restoredb/files/` | PostgreSQL backup files (`.sql.gz`) to be restored |
| `roles/deploy-adempiere/templates/override.env.j2` | Generates the Docker Compose environment file with runtime values |
| `roles/deploy-traefik/templates/app-adempiere.yaml.j2` | Traefik routing rules for ADempiere |
| `roles/deploy-traefik/vars/main.yml` | Cloudflare credential placeholders — real values go in `group_vars/all/vault.yml`; see [security.md](security.md) |

---

[← Architecture](architecture.md) | [Next: Vault Management →](vault.md)

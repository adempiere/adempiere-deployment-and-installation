# Project Structure

```
deployment_and_installation/
│
├── ansible.cfg                    # Inventory path + vault password file location
├── README.md                      # Quick reference with links to /docs
│
├── docs/                          # Full documentation (this directory)
│
├── inventories/
│   └── hosts                      # Static inventory: server IPs and groups
│
├── group_vars/
│   └── all.yml                    # AES-256 vault-encrypted secrets (passwords, API keys)
│
├── Orchestration playbooks
├── main.yml                       # Full run: genkey → serversprep → so-updates → serversconf → deploy-vim → install-docker
├── main-w-traefik.yml             # Full end-to-end: base setup + deploy-traefik + deploy-adempiere
│
├── Individual playbooks
├── genkey.yml                     # Generate RSA keypair on the control node (localhost)
├── serversprep.yml                # Distribute SSH public key to all contabo servers
├── so-updates.yml                 # OS dist-upgrade + conditional reboot
├── serversconf.yml                # Server hardening, user creation, SSH config
├── install-docker.yml             # Docker CE + Compose plugin
├── deploy-vim.yml                 # Vim editor + plugins
├── deploy-adempiere.yml           # ADempiere container stack (BackEnd only)
├── deploy-traefik.yml             # Traefik reverse proxy (FrontEnd only)
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
    └── serverswap/                # ⚠ EMPTY — stub, not implemented
```

---

## Role Layout

Every role follows the standard Ansible role structure:

```
roles/<role-name>/
├── tasks/
│   └── main.yml        # Entry point; some roles include sub-task files (start.yml, wait.yml…)
├── defaults/
│   └── main.yml        # Default variable values — override these to customize behavior
├── vars/
│   └── main.yml        # Role-level variables (higher precedence than defaults)
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
| `group_vars/all.yml` | Vault-encrypted secrets shared across all hosts |
| `roles/serversconf/files/public_keys/present/admin/` | SSH public keys deployed to all servers as authorized admin keys |
| `roles/adempiere-restoredb/files/` | PostgreSQL backup files (`.sql.gz`) to be restored |
| `roles/deploy-adempiere/templates/override.env.j2` | Generates the Docker Compose environment file with runtime values |
| `roles/deploy-traefik/templates/app-adempiere.yaml.j2` | Traefik routing rules for ADempiere |
| `roles/deploy-traefik/vars/main.yml` | ⚠ Contains Cloudflare credentials — see [security.md](security.md) |

---

[← Architecture](architecture.md) | [Next: Vault & Secrets →](vault.md)

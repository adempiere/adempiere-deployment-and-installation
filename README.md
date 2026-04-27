# ADempiere Deployment & Installation

- This project automates the deployment of [ADempiere ERP](https://github.com/adempiere/adempiere) onto Linux VPS servers using [Ansible](https://docs.ansible.com/).
- It covers everything from the first SSH connection to a freshly provisioned server, through OS hardening and Docker installation, to a fully running, TLS-secured ADempiere instance.

---

## The Scenario

- You are working on your **local machine** (the *control node*).
- You have two Linux VPS servers — one serves as the application backend, one as the public-facing frontend.
- For a first-time setup, the servers need to be reachable via SSH. Root access is required for the initial hardening steps; subsequent steps use a dedicated non-root user.

```
                                    FrontEnd VPS  (<frontend_ip>)
Your local machine  ──── SSH ────►  Public-facing server.
                    │               Runs Traefik: receives internet traffic,
                    │               terminates HTTPS, forwards to BackEnd.
                    │                         │
                    │                         │ HTTP (internal)
                    │                         ▼
                    │               BackEnd VPS   (<backend_ip>)
                    └──── SSH ────► Application server.
                                    Runs ADempiere ERP + PostgreSQL database.
                                    ⚠ Also directly reachable from the internet
                                      unless the hosting provider's firewall
                                      restricts access. No firewall is configured
                                      by this project.
```

By the end of this automation, the following will be in place:

- Both servers are **hardened**: SSH runs on a custom port, root login is disabled, only key-based authentication is allowed, automatic security updates are enabled.  
- Both servers have **Docker CE** installed.  
- The **BackEnd** server runs the ADempiere ERP container stack (application + PostgreSQL database), cloned from the Systemhaus Westfalia GitHub repository.  
- The **FrontEnd** server runs **Traefik**, a reverse proxy that receives HTTPS traffic from the internet, terminates TLS using a certificate automatically issued by Let's Encrypt via the Cloudflare DNS API, and forwards requests to the BackEnd.  
- The system is reachable at the domain configured in `group_vars/all/vars.yml`.

Configuration is split across two gitignored files under `group_vars/all/`:  
- `vars.yml` — plain-text deployment values (SSH port, username, key path). Copy from `group_vars/vars_template.yml`.  
- `vault.yml` — AES-256 encrypted secrets (passwords, API tokens). Copy from `group_vars/vault_template.yml` and encrypt with `ansible-vault encrypt`.  

The templates live one level up in `group_vars/` (not inside `all/`) because Ansible auto-loads every `.yml` file it finds in `group_vars/all/` — placing templates there would cause their placeholder values to override your real credentials.

The vault password must be stored in `~/.vault_pass.txt` on the control node; `ansible.cfg` references this file so Ansible decrypts the vault automatically on every run.  
**Change the vault password before deploying to production.** See [docs/vault.md](docs/vault.md).

You run all commands from your local machine.  
Ansible connects to the servers over SSH and handles everything remotely.

---

## Ansible Building Blocks

Ansible projects are built from a small set of composable concepts. Here is how they relate to each other:

```
Control Node (your local machine)
│
├── ansible.cfg                  ← global settings: inventory path, vault password file
│
├── inventories/hosts            ← list of target servers, organised into named groups
│
├── group_vars/                  ← variables shared across a group of hosts
│   ├── vars_template.yml        ← reference template for all/vars.yml — committed
│   ├── vault_template.yml       ← reference template for all/vault.yml — committed
│   └── all/                     ← Ansible auto-loads every .yml file here
│       ├── vars.yml             ← plain-text config values (SSH port, username) — gitignored
│       └── vault.yml            ← AES-256 encrypted secrets (passwords) — gitignored
│
├── Playbook  (*.yml)            ← entry point: "run these roles on these hosts"
│   ├── hosts: <group>           ← which inventory group to target
│   ├── become: true/false       ← whether to escalate privileges (sudo)
│   ├── pre_tasks:               ← steps that run before roles (e.g. set connection vars)
│   └── roles: [role-a, role-b]  ← delegates work to one or more roles
│
└── roles/<name>/                ← self-contained, reusable unit of work
    ├── tasks/main.yml           ← the steps to execute (the "what")
    ├── defaults/main.yml        ← lowest-priority variable defaults (always overridable)
    ├── vars/main.yml            ← higher-priority role constants
    ├── templates/*.j2           ← Jinja2 templates — rendered with variables, copied to server
    ├── files/                   ← static files copied to the server as-is
    ├── handlers/main.yml        ← triggered by notify: directives (e.g. restart SSH)
    └── meta/main.yml            ← role metadata and inter-role dependencies
```

**Variable precedence** (highest wins):

```
CLI  -e "key=value"          ← highest — always overrides everything
     │
     ▼
roles/<name>/vars/main.yml   ← role-level constants
     │
     ▼
group_vars/all/vars.yml      ← config values (domain, port, username…)
     │
     ▼
group_vars/all/vault.yml     ← encrypted secrets (passwords, API tokens)
     │
     ▼
roles/<name>/defaults/main.yml  ← lowest — safe defaults, meant to be overridden
```

For the detailed relationships between the specific playbooks, roles, and inventory groups in this project, see [docs/relationships.md](docs/relationships.md).

---

## Quick Start

**One-time setup** (do this once after cloning):

```bash
# 1. Install required Ansible collections
ansible-galaxy collection install community.docker community.postgresql community.crypto

# 2. Create the vault password file
echo "YourVaultPassword" > ~/.vault_pass.txt && chmod 600 ~/.vault_pass.txt

# 3. Configure your deployment
cp group_vars/vars_template.yml group_vars/all/vars.yml   # fill in IPs, domain, SSH port
cp group_vars/vault_template.yml group_vars/all/vault.yml # fill in passwords and tokens
ansible-vault encrypt group_vars/all/vault.yml
cp inventories/hosts_template.yml inventories/hosts.yml   # fill in server IPs
```

**Deploy a BackEnd server** (fresh server, port 22, root access):

```bash
./deploy-backend.sh
```

**Restore the database** (after deploy, if needed):

```bash
./restore-db.sh
```

For the full walkthrough including dry runs and verification steps, see [docs/getting-started.md](docs/getting-started.md).

---

## Documentation

| Topic | File |
|---|---|
| Technologies: Ansible, Traefik, Docker | [docs/technologies.md](docs/technologies.md) |
| Architecture & network layout | [docs/architecture.md](docs/architecture.md) |
| System requirements | [docs/requirements.md](docs/requirements.md) |
| Project structure | [docs/project-structure.md](docs/project-structure.md) |
| File relationships — playbooks, roles, inventory | [docs/relationships.md](docs/relationships.md) |
| Vault management | [docs/vault.md](docs/vault.md) |
| Configuration reference | [docs/configuration.md](docs/configuration.md) |
| Complete variable reference | [docs/variables.md](docs/variables.md) |
| Getting started — first deployment | [docs/getting-started.md](docs/getting-started.md) |
| Installation — step by step | [docs/installation.md](docs/installation.md) |
| Running the system & playbook reference | [docs/running.md](docs/running.md) |
| Operations & day-2 tasks | [docs/operations.md](docs/operations.md) |
| Testing & debugging guide | [docs/testing.md](docs/testing.md) |
| Debugging & troubleshooting | [docs/troubleshooting.md](docs/troubleshooting.md) |
| Known issues & technical debt | [docs/known-issues.md](docs/known-issues.md) |
| Security notes | [docs/security.md](docs/security.md) |
| Files explained — per-file deep dives | [docs/files-explained.md](docs/files-explained.md) |

---

## License

MIT-0 — See [SPDX](https://spdx.org/licenses/MIT-0.html)

---

[Next: Technologies →](docs/technologies.md)

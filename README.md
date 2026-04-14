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
- The system is reachable at the domain configured in `group_vars/all.yml`.

Sensitive values (passwords, API tokens) are stored encrypted using **Ansible Vault**. Deployment-specific but non-secret values (IPs, domain, SSH port) are kept in a local file that is never committed to the repository. See [docs/vault.md](docs/vault.md).

You run all commands from your local machine. Ansible connects to the servers over SSH and handles everything remotely.

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
│   └── all.yml                  ← vault-encrypted secrets + deployment values (IPs, domain, port)
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
group_vars/all.yml           ← vault secrets + override values
     │
     ▼
roles/<name>/defaults/main.yml  ← lowest — safe defaults, meant to be overridden
```

For the detailed relationships between the specific playbooks, roles, and inventory groups in this project, see [docs/relationships.md](docs/relationships.md).

---

## Documentation

| Topic | File |
|---|---|
| Technologies: Ansible, Traefik, Docker | [docs/technologies.md](docs/technologies.md) |
| System requirements | [docs/requirements.md](docs/requirements.md) |
| Architecture & network layout | [docs/architecture.md](docs/architecture.md) |
| Project structure | [docs/project-structure.md](docs/project-structure.md) |
| File relationships — playbooks, roles, inventory | [docs/relationships.md](docs/relationships.md) |
| Secrets & Vault management | [docs/vault.md](docs/vault.md) |
| Configuration reference | [docs/configuration.md](docs/configuration.md) |
| Getting started — first deployment | [docs/getting-started.md](docs/getting-started.md) |
| Installation — step by step | [docs/installation.md](docs/installation.md) |
| Running the system & playbook reference | [docs/running.md](docs/running.md) |
| Operations & day-2 tasks | [docs/operations.md](docs/operations.md) |
| Testing & debugging guide | [docs/testing.md](docs/testing.md) |
| Debugging & troubleshooting | [docs/troubleshooting.md](docs/troubleshooting.md) |
| Known issues & technical debt | [docs/known-issues.md](docs/known-issues.md) |
| Security notes | [docs/security.md](docs/security.md) |
| Complete variable reference | [docs/variables.md](docs/variables.md) |

---

## License

MIT-0 — See [SPDX](https://spdx.org/licenses/MIT-0.html)

---

[Next: Technologies →](docs/technologies.md)

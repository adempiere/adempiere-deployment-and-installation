# File Relationships

This document shows the structural relationships between all components of this Ansible project.

---

## 1. Inventory → Playbook → Role

An Ansible project connects three layers:  
- the **inventory** (which servers exist and how they are grouped),  
- the **playbooks** (which group to target and which role to run), and  
- the **roles** (the actual work to be done).  

This section shows those connections — first through a concrete example, then as a complete project map.

---

### 1.1 Example — tracing one full path

To make the layer structure tangible, this subsection traces a single playbook — `deploy-adempiere.yml`
— through all its connections:  
- where it gets its variables from,  
- which server it targets,  
- which role it delegates to, and  
- how that role's internal components feed into each other before anything is executed on the server.

```
┌─────────────────────┐  provides   ┌───────────────────────────┐  delegates  ┌─────────────────────┐
│  group_vars/all/    │  variables  │                           │     to      │  roles/             │
│  vars.yml+vault.yml │------------>│  deploy-                  │------------>│  deploy-adempiere/  │
│  contains:          │             │  adempiere.yml            │             │                     │
│  vars + secrets,    │             │                           │             │  contains:          │
│  passwords,SSH port │             │  defines:                 │             │  tasks/main.yml     │
└─────────────────────┘             │  hosts: BackEnd           │             │  defaults/main.yml  │
        VARS                        │  user: adempiere_username │             │  templates/         │
┌─────────────────────┐  selects    │  role to execute          │             └──────────┬──────────┘ 
│inventories/hosts.yml│  target     │                           │                        │ ROLE
│                     │             │                           │                        │
│                     │------------>│                           │                 to BackEnd VPS
│  contains:          │             └───────────────────────────┘                 (see detail below)
│  BackEnd group      │                      PB                                          │
│  <backend_ip>       │                                                                  │
└─────────────────────┘                                                                  │
        INV                                                                              │
                                                                                         ▼
┌─────────────────────┐  default    ┌──────────────────────┐                 ┌─────────────────────┐
│  roles/             │   values    │  roles/              │  executed on    │  BackEnd VPS        │
│  deploy-adempiere/  │------------>│  deploy-adempiere/   │---------------->│                     │
│  defaults/main.yml  │             │  tasks/main.yml      │                 │  runs:              │
│                     │  rendered   │                      │                 │  ADempiere +        │
│  roles/             │     by      │  runs:               │                 │  PostgreSQL         │
│  deploy-adempiere/  │------------>│  - clone repo        │                 │  containers         │
│  templates/         │             │  - compose up        │                 │                     │
└─────────────────────┘             └──────────────────────┘                 └─────────────────────┘
    ROLE (internals)                      ROLE (tasks)                             SERVER
```

**How the three role components interact:**

- **`defaults/main.yml`** — declares variable names and their default values (e.g. `repo_url`,
  `install_path`, `be_user`).  
  It contains no executable steps — it is purely a list of
  key-value pairs.  
  Tasks read these values at runtime.  
  Because they are *defaults*, any of them
  can be overridden from outside the role (e.g. from `group_vars` or the command line).

- **`templates/override.env.j2`** — a text file with `{{ variable }}` placeholders (Jinja2
  syntax).  
  It is not executed and does nothing on its own.  
  It only becomes useful when a task
  renders it: Ansible reads the template, substitutes every `{{ variable }}` with its actual
  value (sourced from `defaults/main.yml`, `group_vars`, or the vault), and writes the resulting
  file to the target server.

- **`tasks/main.yml`** — the only component that actually *does* something.  
  It reads the
  variables from `defaults/main.yml`, calls the template rendering step (which produces
  `override.env` on the server from `override.env.j2`), clones the repository, and starts the
  Docker Compose stack.  
  In short: tasks *use* defaults and *render* templates — defaults and
  templates are passive inputs; tasks are the active executor.

---

### 1.2 Full project map

With the example above as a reference, this subsection applies the same structure to every playbook
and role in the project.  

It is split into three views (A, B, C), each looking at the same files from
a different angle:   
- A shows the servers,   
- B shows how each playbook connects a server group to a role, and  
- C shows how orchestration playbooks chain individual playbooks together into full deployment sequences.

**A — Inventory Groups**

```
GROUP             SERVERS
────────────────  ──────────────────────────────────────
servers           <backend_ip> + <frontend_ip> (both)
BackEnd           <backend_ip>
FrontEnd          <frontend_ip>
ansible_test      <test_ip>
```

- These are the logical server groups defined in `inventories/hosts.yml`.  
- Every playbook must name one of these groups in its `hosts:` line to know which servers to connect to.  
- `servers` covers both servers and is used for base setup tasks.  
- `BackEnd` and `FrontEnd` are subsets used for application-level deployments.  
- `ansible_test` is a local VM used to test playbooks safely without touching production.

---

**B — Individual Playbooks → Host Groups → Roles**

```
HOST GROUP                     PLAYBOOK                       ROLE
─────────────────────────────  ─────────────────────────────  ─────────────────────────
localhost                      genkey.yml                 --> genkey
servers (both servers)         serversprep.yml            --> serversprep
                               so-updates.yml             --> so-updates
                               serversconf.yml            --> serversconf
                               install-docker.yml         --> install-docker
                               deploy-vim.yml             --> deploy-vim
BackEnd  (<backend_ip>)        deploy-adempiere.yml       --> deploy-adempiere
                               adempiere-restoredb.yml    --> adempiere-restoredb
FrontEnd (<frontend_ip>)       deploy-traefik.yml         --> deploy-traefik
ansible_test (<test_ip>)       any playbook + --limit ansible_test
```

This is the core mapping of the project.  
- Each individual playbook does exactly one thing: it selects a host group from A and delegates all work to one role.  
- The playbook itself contains no logic — it is the connector between *where* (host group) and *what* (role).  
- The role in turn contains all the actual tasks, templates, and handlers.

---

**C — Orchestration Playbooks → Individual Playbooks** (imports, in order)

Every `.yml` file at the root of the project is a playbook — including `genkey.yml`,
`serversprep.yml`, and all the others listed in B.  
Ansible allows one playbook to call another
using `import_playbook:`.  
Orchestration playbooks use exactly this mechanism: they contain no
tasks of their own, only a list of `import_playbook:` statements that call the individual
playbooks from B one by one.

Each row below shows which individual playbooks an orchestration playbook imports, and in which
order they run.  
The order is top-to-bottom: each playbook runs after the previous one finishes.  
None of the individual playbooks import from each other — they are all called independently by
the orchestration playbook.

```
PLAYBOOK                       IMPORTS (step 1, step 2, step 3 ...)
─────────────────────────────  ──────────────────────────────────────────────────────
main.yml                   --> 1. genkey.yml
(full base setup)              2. serversprep.yml
                               3. so-updates.yml
                               4. serversconf.yml
                               5. deploy-vim.yml
                               6. install-docker.yml

main-backend.yml (TO-DO)   --> 1. main.yml  (runs all 6 steps above)
(base + BackEnd app)           2. deploy-adempiere.yml

main-frontend.yml (TO-DO)  --> 1. main.yml  (runs all 6 steps above)
(base + FrontEnd proxy)        2. deploy-traefik.yml
```

Orchestration playbooks contain no logic of their own.  
They simply call individual playbooks from B
in a fixed order, so the operator can run a complete deployment sequence with a single command
instead of running each playbook manually.  
They depend entirely on B — if an individual playbook is
broken, the orchestration playbook that imports it will also fail at that step.

---

**Relationship between A, B and C**

- A defines **where** (which servers).  
- B defines **what** (which role runs where).  
- C defines **in which order** (which playbooks to chain). Running any playbook from B or C always requires A to be
correctly configured first.

---

## 2. Role Internal Anatomy

Every role follows the same directory structure.  
The table shows which components are actively used per role.

| Role | tasks | defaults | vars | templates | handlers | files |
|---|---|---|---|---|---|---|
| `genkey` | ✓ | ✓ | ✓ | — | — | — |
| `serversprep` | ✓ | ✓ | ✓ | — | — | — |
| `so-updates` | ✓ | ✓ | ✓ | — | — | — |
| `serversconf` | ✓ | ✓ | ✓ | ✓ (5) | ✓ (2) | ✓ (SSH pub keys) |
| `install-docker` | ✓ | ✓ | ✓ | — | — | — |
| `deploy-vim` | ✓ | ✓ | ✓ | — | — | — |
| `deploy-adempiere` | ✓ + sub-tasks | ✓ | ✓ | ✓ (1) | — | — |
| `deploy-traefik` | ✓ | ✓ | ✓ | ✓ (6) | — | — |
| `adempiere-restoredb` | ✓ | ✓ | ✓ | — | — | ✓ (.sql.gz dumps) |
| `deploy-containers` | ✓ | ✓ | ✓ | — | — | — |
| `serverswap` | ✓ | ✓ | — | — | — | — |
| `deploy-crontab` | ✓ | ✓ | — | ✓ (2) | — | — |

---

## 3. serversconf — Internal Task Flow

`serversconf` is the most complex role. It runs on both servers (group `servers`) during initial
setup. Tasks run in this order:

```
STEP  TASK                               DETAIL
────  ─────────────────────────────────  ────────────────────────────────────────────────
1     apt cache update
2     Install 35+ packages
3     Ensure en_US.UTF-8 locale
4     Create admin user
5     Add user to sudo group
6     Grant passwordless sudo
7     Deploy .bashrc from template       for root + admin user
8     Deploy SSH public keys             for root + admin user
9     Deploy unattended-upgrades config  02periodic.j2 + 50unattended-upgrades.j2
10    Create systemd override dir        /etc/systemd/system/ssh.socket.d
11    Override SSH socket port           override.conf.j2
         --> notify: Handler: restart ssh.socket  (Ubuntu only)
12    SSH hardening                      10 sshd_config rules
         --> notify: Handler: Restart SSH
13    Set HostKeyAlgorithms              ed25519 + rsa-sha2-*
14    Set KexAlgorithms                  curve25519 + DH groups
15    Set Ciphers                        chacha20 + aes-gcm + aes-ctr
16    Set MACs                           hmac-sha2-etm + umac-etm
```

---

## 4. deploy-adempiere — Internal Task Flow

`deploy-adempiere` runs on `BackEnd` only.

The relationship between the three main files is:

```
deploy-adempiere.yml
  │  sets: hosts=BackEnd, become=true, connection credentials
  │
  └──> roles/deploy-adempiere/tasks/main.yml   (role entry point)
         │  orchestrates all steps; reads defaults/main.yml and renders templates/
         │
         ├──> start.yml    (conditionally included — only if container not running)
         │      runs start-all.sh to bring up the Docker Compose stack
         │
         ├──> ensure-healthy.yml  (conditionally included — only if container not running)
         │      polls until container is created and running; restarts nginx if it
         │      crashed due to a first-run DNS timing issue
         │
         ├──> validate.yml (always included)
         │      checks for containers in bad state (Exited/Restarting/Dead)
         │
         └──> status.yml   (always included)
                prints docker ps table for operator confirmation
```

`deploy-adempiere.yml` contains no task logic — it only defines *where* to connect and *which role* to invoke. All task logic lives in `tasks/main.yml` and its sub-task files. `start.yml` is never called directly; it is always included by `main.yml` via `include_tasks`.

The idempotency guard is based on real system state — not a sentinel file:

```
STEP  TASK                               DETAIL
────  ─────────────────────────────────  ────────────────────────────────────────────────
1     Gather network facts               network subset only — used in override.env.j2
2     Ensure install directory exists    /opt/development, owned by adempiere_username
3     Clone or update repository         ansible.builtin.git, update: yes — always fetches
                                         latest commits from {{ repo_version }} branch
4     Generate override.env              rendered from override.env.j2, mode 0600
5     Check if container is running      docker ps (running only, not -a)
      ├── container absent
      │     5a. start.yml   — run start-all.sh (docker compose up)
      │     5b. ensure-healthy.yml — poll until container appears and is running;
      │                              restart nginx if it crashed on first run
      └── container present              --> skip 5a and 5b; stack already running
6     validate.yml                       check for Exited/Restarting/Dead containers
7     status.yml                         print docker ps table
```

**Why real state instead of a sentinel file:**
A sentinel file records what Ansible did, not what is actually true on the server. If the stack crashes after a successful deployment, the sentinel would say "runned" and the playbook would skip restart. The container-state check reflects actual reality: if the container is gone, the next run starts it again automatically — no manual file deletion required.

---

## 5. deploy-traefik — Internal Task Flow

`deploy-traefik` runs on `FrontEnd` only. It deploys two containers: `traefik` and `socket-proxy`.

```
STEP  TASK                               DETAIL
────  ─────────────────────────────────  ────────────────────────────────────────────────
1     Create Docker bridge network       name: 'gateway'
2     Create container directories       /docker/traefik, /docker/socket-proxy
3     Create traefik subdirs             config/, certs/, logs/
4     Deploy .env from template
5     Deploy docker-compose.yml          traefik  (traefik-docker-compose.yml.j2)
6     Deploy docker-compose.yml          socket-proxy  (socket-docker-compose.yml.j2)
7     Deploy Traefik config files        tls-opts.yml
                                         middlewares-secure-headers.yaml
                                         traefik.yaml
                                         app-adempiere.yaml
8     Start socket-proxy                 docker compose up
9     Start traefik                      docker compose up
```

---

## 6. Variable Precedence

Ansible resolves variables in this order (highest wins):

```
CLI -e flags  (highest)
        │
        ▼
roles/<role>/vars/main.yml        ← role-level constants
        │
        ▼
group_vars/all/vars.yml           ← deployment values (IPs, domain, SSH port)
        │
        ▼
group_vars/all/vault.yml          ← vault-encrypted secrets (passwords, API tokens)
        │
        ▼
roles/<role>/defaults/main.yml    ← role defaults (lowest — always overridable)
```

> Variables are split across `group_vars/all/vars.yml` (plain-text config) and `group_vars/all/vault.yml` (AES-256 encrypted secrets). Both are gitignored; use the `*_template.yml` files as reference.

---

## 7. Orchestration Playbook Flows

This section shows the step-by-step execution order of each orchestration playbook, with a
description of what each imported playbook does and which server it targets.

---

### main.yml — Base setup (both servers)

```
STEP  PLAYBOOK              WHAT IT DOES                                       TARGET
────  ────────────────────  ─────────────────────────────────────────────────  ───────────────────
1     genkey.yml            Generate RSA keypair                               localhost
2     serversprep.yml       Distribute SSH public key to both servers          servers (root)
3     so-updates.yml        OS dist-upgrade + conditional reboot               servers (root)
4     serversconf.yml       Server hardening, user creation, SSH config        servers (root)
5     deploy-vim.yml        Vim + plugins                                      servers (adempiere_username)
6     install-docker.yml    Docker CE + Compose plugin                         servers (adempiere_username)
```

> After `main.yml`, servers are hardened and Docker-ready. No application is deployed yet.
> Use `deploy-adempiere.yml` and/or `deploy-traefik.yml` separately.

---

### main-w-traefik.yml — Full end-to-end deployment

```
STEP  PLAYBOOK              WHAT IT DOES                                       TARGET
────  ────────────────────  ─────────────────────────────────────────────────  ───────────────────
1     genkey.yml            Generate RSA keypair                               localhost
2     serversprep.yml       Distribute SSH public key to both servers          servers (root)
3     so-updates.yml        OS dist-upgrade + conditional reboot               servers (root)
4     serversconf.yml       Server hardening, user creation, SSH config        servers (root)
5     install-docker.yml    Docker CE + Compose plugin                         servers (adempiere_username)
6     deploy-traefik.yml    Traefik reverse proxy                              FrontEnd (adempiere_username)
7     deploy-adempiere.yml  ADempiere + PostgreSQL container stack             BackEnd (adempiere_username)
```

> Traefik (step 6) is deployed before ADempiere (step 7) so the proxy is ready when ADempiere starts.

---

### main-backend.yml — Base setup + BackEnd app (pending)

```
STEP  PLAYBOOK              WHAT IT DOES
────  ────────────────────  ─────────────────────────────────────────────────
1     main.yml              Runs all 6 base setup steps (see main.yml above)
2     deploy-adempiere.yml  ADempiere + PostgreSQL container stack
```

---

### main-frontend.yml — Base setup + FrontEnd proxy (pending)

```
STEP  PLAYBOOK              WHAT IT DOES
────  ────────────────────  ─────────────────────────────────────────────────
1     main.yml              Runs all 6 base setup steps (see main.yml above)
2     deploy-traefik.yml    Traefik reverse proxy
```

---

### Individual playbooks — which user and port they require

```
GROUP         PLAYBOOK                   USER        PORT
────────────  ─────────────────────────  ──────────  ──────────────
localhost     genkey.yml                 —           —
────────────────────────────────────────────────────────────────────
servers       serversprep.yml            root        22
              so-updates.yml             root        22
              serversconf.yml            root        22
────────────────────────────────────────────────────────────────────
servers       install-docker.yml         adempiere_username   custom_sshport
              deploy-vim.yml             adempiere_username   custom_sshport
BackEnd       deploy-adempiere.yml       adempiere_username   custom_sshport
              adempiere-restoredb.yml    adempiere_username   custom_sshport
FrontEnd      deploy-traefik.yml         adempiere_username   custom_sshport
```

> ⚠ `serversconf.yml` changes the SSH port mid-play. All playbooks that run as `adempiere_username` must
> run AFTER `serversconf.yml` has completed — otherwise Ansible will try to connect on the new
> port before the server has switched to it.

---

[← Running the System](running.md) | [← Project Structure](project-structure.md)

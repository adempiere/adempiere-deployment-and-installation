# Running the System

## Provisioning Scripts

| Script | Description |
|---|---|
| `deploy-backend.sh` | Full BackEnd provisioning from a clean server reset — runs all steps in order |

```bash
./deploy-backend.sh           # live run
./deploy-backend.sh --check   # dry run — shows what would change, no writes
```

Use `deploy-backend.sh` after resetting the backend server. It deletes the old SSH keypair, regenerates it, and runs all playbooks in the correct order. See [files-explained.md](files-explained.md) for details.

---

## Playbook Reference

| Playbook | Target | Description |
|---|---|---|
| `genkey.yml` | localhost | Generate RSA keypair |
| `serversprep.yml` | servers | Distribute SSH key |
| `so-updates.yml` | servers | OS update + reboot |
| `serversconf.yml` | servers | Server hardening |
| `install-docker.yml` | servers | Install Docker CE |
| `deploy-vim.yml` | servers | Vim + plugins |
| `deploy-adempiere.yml` | BackEnd | ADempiere container stack |
| `deploy-traefik.yml` | FrontEnd | Traefik reverse proxy |
| `adempiere-restoredb.yml` | BackEnd | PostgreSQL backup restore |
| `main.yml` | various | Orchestrates: genkey → serversprep → so-updates → serversconf → deploy-vim → install-docker |
| `main-w-traefik.yml` | various | Orchestrates full setup: genkey → serversprep → so-updates → serversconf → install-docker → deploy-traefik → deploy-adempiere |

---

## Running a Single Playbook

```bash
ansible-playbook <playbook-name>.yml
```

---

## Useful Flags

### Dry run (check mode)

Shows what Ansible *would* do without making any changes. Note: `command` and `shell` tasks are skipped in check mode.

```bash
ansible-playbook serversconf.yml --check
ansible-playbook serversconf.yml --check --diff   # also shows file diffs
```

### Limit to a specific host

```bash
ansible-playbook so-updates.yml --limit <backend_ip>
ansible-playbook deploy-adempiere.yml --limit ansible_test
```

### Start from a specific task

```bash
ansible-playbook serversconf.yml --start-at-task "SSH hardening"
```

### Verbosity

```bash
ansible-playbook deploy-adempiere.yml -v      # basic
ansible-playbook deploy-adempiere.yml -vv     # more detail
ansible-playbook deploy-adempiere.yml -vvv    # connection debugging
ansible-playbook deploy-adempiere.yml -vvvv   # full network traffic
```

### Override a variable at the command line

```bash
ansible-playbook deploy-adempiere.yml -e "repo_version=main"
ansible-playbook deploy-traefik.yml -e "traefik_log_level=INFO"
```

---

## Checking Connectivity

```bash
# Ping all hosts
ansible all -m ping

# Ping only BackEnd (after serversconf — adempiere_username user, custom port)
ansible BackEnd -m ping \
  -e "ansible_user=westfalia" -e "ansible_port=10099"
```

---

## Inspecting Variables and Host Configuration

Three commands, each showing a different scope. The first two read **local files only** — no SSH needed. The third connects to the remote host via SSH.

**1. Inventory variables for a host** — what `group_vars`, `host_vars`, and the inventory file contribute. Fast, always works, no SSH:
```bash
ansible-inventory --host backend
```

**2. All Ansible variables the host will use during a play** — inventory variables plus any cached facts. Useful to verify a variable like `{{ install_path }}` or `{{ be_user }}` resolves correctly before running. No SSH:
```bash
ansible backend -m debug -a "var=hostvars[inventory_hostname]"
```

**3. Complete remote host configuration** — OS, kernel, CPU, memory, network interfaces, disk, and all system facts gathered live from the server. Requires SSH (pass port and user after serversconf has run):
```bash
ansible backend -m setup -e "ansible_port={{ custom_sshport }}" -e "ansible_user={{ adempiere_username }}"
```

---

## Syntax Check (no execution)

```bash
ansible-playbook main.yml --syntax-check
ansible-playbook deploy-traefik.yml --syntax-check
```

---

## List Tasks Without Running

```bash
ansible-playbook serversconf.yml --list-tasks
ansible-playbook deploy-adempiere.yml --list-tasks
```

---

## Common Scenarios

### Scenario 1 — Full first-time setup (both servers)

Run this sequence once when provisioning both servers from scratch:

```bash
# 1. Generate SSH keypair on the control node
ansible-playbook genkey.yml

# 2. Distribute the public key to both servers (uses root password from vault)
ansible-playbook serversprep.yml

# 3. Run the full base setup: OS updates, hardening, vim, Docker
ansible-playbook main.yml

# 4. Deploy ADempiere on BackEnd
ansible-playbook deploy-adempiere.yml

# 5. Deploy Traefik on FrontEnd
ansible-playbook deploy-traefik.yml
```

Or use the orchestration playbooks (TO-DO — not yet created):

```bash
ansible-playbook main-backend.yml   # base setup + BackEnd app
ansible-playbook main-frontend.yml  # base setup + FrontEnd proxy
```

---

### Scenario 2 — BackEnd only (no FrontEnd / no Traefik)

Use this when you want ADempiere running without a reverse proxy, e.g. for internal use or testing.

```bash
# Base setup (if not already done)
ansible-playbook main.yml

# Deploy ADempiere on BackEnd
ansible-playbook deploy-adempiere.yml
```

ADempiere will be reachable directly at the BackEnd IP on its application port.  
Make sure the hosting provider's firewall allows that port from your IP.

---

### Scenario 3 — FrontEnd only (add Traefik to an existing BackEnd)

Use this when the BackEnd is already running and you only need to add or re-configure the reverse proxy.

```bash
ansible-playbook deploy-traefik.yml
```

---

### Scenario 4 — Re-deploy ADempiere after a code update

```bash
# Pull new repo version and restart containers
ansible-playbook deploy-adempiere.yml -e "repo_version=main"
```

---

### Scenario 5 — Restore PostgreSQL from backup

Place the `.sql.gz` backup file in `roles/adempiere-restoredb/files/`, then:

```bash
ansible-playbook adempiere-restoredb.yml
```

---

### Scenario 6 — Apply OS security updates

```bash
ansible-playbook so-updates.yml
```

Servers reboot automatically if the kernel was updated.

---

### Scenario 7 — Test against a local VM (without touching production)

```bash
# Limit to the ansible_test group (see inventories/hosts.yml)
ansible-playbook serversconf.yml --limit ansible_test
ansible-playbook deploy-adempiere.yml --limit ansible_test
```

---

[← Installation](installation.md) | [Next: Operations →](operations.md)

# Demo — Real Deployment Output

## Table of Contents

- [About this demo](#about-this-demo)
- [deploy-backend.sh — full BackEnd run](#deploy-backendsh--full-backend-run)
  - [Script startup and pre-flight](#script-startup-and-pre-flight)
  - [Step 2: serversprep.yml — SSH key distribution](#step-2-serversprepyml--ssh-key-distribution)
  - [Step 3: so-updates.yml — OS update and reboot](#step-3-so-updatesyml--os-update-and-reboot)
  - [Step 4: serversconf.yml — Server hardening](#step-4-serversconfyml--server-hardening)
  - [Step 5: serverswap.yml — Swap configuration](#step-5-serverswapyml--swap-configuration)
  - [Step 6: install-docker.yml — Docker installation](#step-6-install-dockeryml--docker-installation)
  - [Step 7: deploy-adempiere.yml — ADempiere container stack](#step-7-deploy-adempiereyml--adempiere-container-stack)
  - [Step 8: deploy-crontab.yml — Crontab](#step-8-deploy-crontabyml--crontab)
  - [Completion summary](#completion-summary)
- [restore-db.sh — database restore run](#restore-dbsh--database-restore-run)
- [What the output columns mean](#what-the-output-columns-mean)

---

## About this demo

This page shows excerpts from a real successful deployment run.

Sensitive values have been replaced with placeholders:
- Server IP → `<backend_ip>`
- Admin username → `<your-admin-username>`
- Timezone → `<your-timezone>`
- Locale → `<your-locale>`

The full log is written to `logs/deploy-backend-<timestamp>.log` on your control node.  
See [docs/running.md](running.md) for the complete script reference.

---

## `deploy-backend.sh` — full BackEnd run

### Script startup and pre-flight

```
================================================================
  LIVE RUN — changes will be made on the backend server

  Target BackEnd server(s):
      backend1  →  <backend_ip>
  Prerequisites:
    - All servers above are reachable on port 22 as root with password auth
    - ~/.vault_pass.txt exists (used automatically via ansible.cfg)

  Type YES to continue:
================================================================

>>> Pre-flight: removing stale known_hosts entry for <backend_ip>
/home/user/.ssh/known_hosts updated.

>>> Step 0: SSH keypair already exists at ssh_keys/adempiere_installation_key

  ┌─────────────────────────────────────────────────────────────────┐
  │  WARNING                                                        │
  │  Deleting this keypair will lock you out of ANY server that     │
  │  already has the current public key deployed.                   │
  │  Only answer YES if this is a full server reset and no other    │
  │  servers are using this keypair.                                │
  └─────────────────────────────────────────────────────────────────┘

  Delete and regenerate the keypair? [yes/NO]:   Keeping existing keypair.

>>> Step 1: genkey.yml — Skipped (existing keypair kept)
```

---

### Step 2: `serversprep.yml` — SSH key distribution

Distributes the project's public key to the server as `root` on port 22. After this step, all subsequent playbooks connect as `adempiere_username` using the key — no password needed.

```
>>> Step 2: serversprep.yml — Distribute SSH key to BackEnd

PLAY [servers] *****************************************************************

TASK [Assign user for role] ****************************************************
ok: [backend1]

TASK [Add host fingerprint to known_hosts] *************************************
changed: [backend1 -> localhost]

TASK [serversprep : Add host fingerprint to known_hosts] ***********************
changed: [backend1]

TASK [serversprep : INFO: Set authorized key on remote] ************************
ok: [backend1] => {
    "msg": "user=root | key=ssh_keys/adempiere_installation_key.pub"
}

TASK [serversprep : Set authorized key on remote] ******************************
changed: [backend1]

PLAY RECAP *********************************************************************
backend1                   : ok=6    changed=3    unreachable=0    failed=0    skipped=0

PLAYBOOK RECAP *****************************************************************
Playbook run took 0 days, 0 hours, 0 minutes, 31 seconds
```

---

### Step 3: `so-updates.yml` — OS update and reboot

Runs `apt dist-upgrade`, checks whether a reboot is required, and reboots if it is. Waits up to 5 minutes for the server to come back before continuing.

```
>>> Step 3: so-updates.yml — OS update + reboot

TASK [so-updates : INFO: Update all packages] **********************************
ok: [backend1] => {
    "msg": "host=backend1 | dist-upgrade + autoremove"
}

TASK [so-updates : Update all packages on a Debian/Ubuntu] *********************
ok: [backend1]

TASK [so-updates : Reboot the server and wait for it to come back] *************
changed: [backend1]

TASK [so-updates : Verify new update (optional)] *******************************
changed: [backend1]

TASK [so-updates : Display new kernel version] *********************************
ok: [backend1] => {
    "uname_result.stdout_lines": [
        "Linux 6.12.86+deb13-cloud-amd64 x86_64"
    ]
}

PLAY RECAP *********************************************************************
backend1                   : ok=9    changed=2    unreachable=0    failed=0    skipped=0

Playbook run took 0 days, 0 hours, 1 minutes, 19 seconds
```

---

### Step 4: `serversconf.yml` — Server hardening

The most comprehensive step. Creates the admin user, deploys SSH keys, installs packages, sets the locale and timezone, configures unattended upgrades, and hardens SSH (custom port, key-only auth, no root login, modern cipher suites). SSH restarts at the end — the server is no longer reachable on port 22 after this.

```
>>> Step 4: serversconf.yml — Server hardening

TASK [serversconf : Install basic packages] ************************************
changed: [backend1]

TASK [serversconf : INFO: Ensure a locale exists] ******************************
ok: [backend1] => {
    "msg": "locale=<your-locale>"
}

TASK [serversconf : INFO: Create user] *****************************************
ok: [backend1] => {
    "msg": "user=<your-admin-username> | shell=/bin/bash | home=/home/<your-admin-username>"
}

TASK [serversconf : Create user] ***********************************************
changed: [backend1]

TASK [serversconf : Add user to sudo group] ************************************
changed: [backend1]

TASK [serversconf : Allow passwordless sudo for the user (Debian/Ubuntu)] ******
changed: [backend1]

TASK [serversconf : Add ADMIN ssh-keys] ****************************************
ok: [backend1] => (item=['root', '…/adempiere_installation_key.pub'])
changed: [backend1] => (item=['<your-admin-username>', '…/adempiere_installation_key.pub'])

TASK [serversconf : Create unattended-upgrades configuration files] ************
changed: [backend1]

TASK [serversconf : INFO: Deploy SSH hardening override] ***********************
ok: [backend1] => {
    "msg": "dest=/etc/ssh/sshd_config.d/01-hardening.conf | PasswordAuthentication=no | PermitRootLogin=no"
}

TASK [serversconf : INFO: SSH hardening] ***************************************
ok: [backend1] => {
    "msg": "file=/etc/ssh/sshd_config | port=<custom_sshport> | PasswordAuthentication=no | PermitRootLogin=no | MaxAuthTries=3"
}

TASK [serversconf : SSH hardening] *********************************************
changed: [backend1] => (item={'regexp': '^PermitRootLogin', 'line': 'PermitRootLogin no'})
changed: [backend1] => (item={'regexp': '^(#)?Port', 'line': 'Port <custom_sshport>'})
... (additional hardening items) ...

RUNNING HANDLER [serversconf : Restart SSH] ************************************
changed: [backend1]

PLAY RECAP *********************************************************************
backend1                   : ok=34   changed=18   unreachable=0    failed=0    skipped=1

Playbook run took 0 days, 0 hours, 5 minutes, 27 seconds

TASKS RECAP ********************************************************************
serversconf : SSH hardening -------------------------------------------- 71.58s
serversconf : Install basic packages ----------------------------------- 36.12s
serversconf : Create bashrc -------------------------------------------- 32.30s
serversconf : Create unattended-upgrades configuration files ----------- 31.25s
...
```

---

### Step 5: `serverswap.yml` — Swap configuration

Creates an 8 GB swap file on the BackEnd server (`swap_size_mb: 8192` from `group_vars/BackEnd.yml`), adds it to `/etc/fstab`, and tunes `vm.swappiness=10` to favour RAM over swap.

```
>>> Step 5: serverswap.yml — Configure swap

TASK [serverswap : INFO: Swap status] ******************************************
ok: [backend1] => {
    "msg": [
        "host=backend1",
        "current_mb=0",
        "target_mb=8192",
        "action=create"
    ]
}

TASK [serverswap : Allocate swap file] *****************************************
changed: [backend1]

TASK [serverswap : Format swap file] *******************************************
changed: [backend1]

TASK [serverswap : Enable swap] ************************************************
changed: [backend1]

TASK [serverswap : Set vm.swappiness (use RAM first, swap only under pressure)] ***
changed: [backend1]

PLAY RECAP *********************************************************************
backend1                   : ok=11   changed=7    skipped=2

Playbook run took 0 days, 0 hours, 1 minutes, 18 seconds
```

---

### Step 6: `install-docker.yml` — Docker installation

Adds the official Docker repository, installs Docker CE 28.x (pinned to prevent automatic upgrade to 29+), and starts the Docker service.

```
>>> Step 6: install-docker.yml — Install Docker

TASK [install-docker : INFO: Validate supported OS] ****************************
ok: [backend1] => {
    "msg": "distribution=Debian | os_family=Debian"
}

TASK [install-docker : Set Docker repo base URL and GPG URL depending on distro] ***
ok: [backend1]

TASK [install-docker : INFO: Find latest Docker 28.x version] ******************
ok: [backend1] => {
    "msg": "searching apt-cache madison for Docker 5:28.x"
}

TASK [install-docker : INFO: Install Docker 28.x and Docker Compose] ***********
ok: [backend1] => {
    "msg": "version=5:28.5.2-1~debian.13~trixie | packages=docker-ce,docker-ce-cli,containerd.io,buildx-plugin,compose-plugin"
}

TASK [install-docker : Install Docker 28.x and Docker Compose] *****************
changed: [backend1]

TASK [install-docker : Hold Docker packages at 28.x to prevent automatic upgrade to 29+] ***
changed: [backend1] => (item=docker-ce)
changed: [backend1] => (item=docker-ce-cli)

TASK [install-docker : Ensure Docker service is enabled and started] ***********
ok: [backend1]

PLAY RECAP *********************************************************************
backend1                   : ok=27   changed=7    skipped=1

Playbook run took 0 days, 0 hours, 2 minutes, 30 seconds
```

---

### Step 7: `deploy-adempiere.yml` — ADempiere container stack

The longest step. Clones the ADempiere repository, generates the environment file, and starts the container stack. On a fresh server the stack runs twice: the first run initialises the database and pulls all images (~524 seconds); the stack is then stopped and restarted cleanly so all containers come up in the correct order.

```
>>> Step 7: deploy-adempiere.yml — Deploy ADempiere

TASK [deploy-adempiere : INFO: Clone or update adempiere-ui-gateway repository] ***
ok: [backend1] => {
    "msg": "repo=https://github.com/Systemhaus-Westfalia/adempiere-ui-gateway.git | branch=adempiere-trunk | dest=/opt/development/adempiere-ui-gateway"
}

TASK [deploy-adempiere : Clone or update adempiere-ui-gateway repository] ******
changed: [backend1]

TASK [deploy-adempiere : Generate override.env file] ***************************
changed: [backend1]

TASK [deploy-adempiere : INFO: Run start-all.sh (first run — initializes DB and pulls images)] ***
ok: [backend1] => {
    "msg": "chdir=/opt/development/adempiere-ui-gateway/docker-compose | first run: DB init + image pull"
}

TASK [deploy-adempiere : Run start-all.sh (first run — initializes DB and pulls images)] ***
changed: [backend1]    # <-- this takes ~9 minutes on first install

TASK [deploy-adempiere : Wait until ZK has been running stably for at least 60 seconds] ***
FAILED - RETRYING: [backend1]: Wait until ZK ... (20 retries left).
ok: [backend1]         # <-- normal; ZK starts slowly on first run

TASK [deploy-adempiere : Stop stack before clean restart] **********************
changed: [backend1]

TASK [deploy-adempiere : Run start-all.sh (second run — clean start with initialized DB)] ***
changed: [backend1]

TASK [deploy-adempiere : Report OK if all services look healthy] ***************
ok: [backend1] => {
    "msg": "OK: postgresql=running, zk=running"
}

TASK [deploy-adempiere : Print docker ps table (first 20 lines)] ***************
ok: [backend1] => {
    "msg": [
        "NAMES                                        STATUS",
        "adempiere-ui-gateway.nginx-ui-gateway        Up 51 seconds",
        "adempiere-ui-gateway.kafdrop                 Up 55 seconds",
        "adempiere-ui-gateway.envoy-grpc-proxy        Up 2 minutes (healthy)",
        "adempiere-ui-gateway.kafka                   Up 2 minutes (healthy)",
        "adempiere-ui-gateway.report-engine           Up 3 minutes (healthy)",
        "adempiere-ui-gateway.keycloak-service        Up 2 minutes",
        "adempiere-ui-gateway.vue-grpc-server         Up 2 minutes (healthy)",
        "adempiere-ui-gateway.processor               Up 3 minutes (healthy)",
        "adempiere-ui-gateway.zk                      Up 2 minutes",
        "adempiere-ui-gateway.dictionary-rs            Up 53 seconds (healthy)",
        "adempiere-ui-gateway.opensearch              Up 3 minutes (healthy)",
        "adempiere-ui-gateway.zookeeper               Up 3 minutes (healthy)",
        "adempiere-ui-gateway.s3-storage              Up 3 minutes (healthy)",
        "adempiere-ui-gateway.postgresql              Up 3 minutes (healthy)",
        "adempiere-ui-gateway.vue-ui                  Up 3 minutes (healthy)",
        "adempiere-ui-gateway.site                    Up 3 minutes"
    ]
}

PLAY RECAP *********************************************************************
backend1                   : ok=39   changed=6    skipped=4

Playbook run took 0 days, 0 hours, 14 minutes, 12 seconds

TASKS RECAP ********************************************************************
deploy-adempiere : Run start-all.sh (first run) ----------------------- 524.16s
deploy-adempiere : Run start-all.sh (second run) ---------------------- 147.68s
deploy-adempiere : Clone or update repository --------------------------- 33.51s
```

---

### Step 8: `deploy-crontab.yml` — Crontab

Deploys the start/stop/restart scripts and installs three crontab entries: start at `@reboot`, stop at `23:50`, restart at `23:55`.

```
>>> Step 8: deploy-crontab.yml — Configure crontab

TASK [deploy-crontab : INFO: Crontab configuration] ****************************
ok: [backend1] => {
    "msg": [
        "host=backend1",
        "crontab_enabled=True",
        "jobs=['adempiere start on reboot', 'adempiere daily stop', 'adempiere daily restart']"
    ]
}

TASK [deploy-crontab : Deploy start script from template] **********************
changed: [backend1]

TASK [deploy-crontab : Deploy stop script from template] ***********************
changed: [backend1]

TASK [deploy-crontab : Install crontab entries] ********************************
changed: [backend1] => (item={'name': 'adempiere start on reboot', 'special_time': 'reboot', ...})
changed: [backend1] => (item={'name': 'adempiere daily stop', 'hour': '23', 'minute': '50', ...})
changed: [backend1] => (item={'name': 'adempiere daily restart', 'hour': '23', 'minute': '55', ...})

PLAY RECAP *********************************************************************
backend1                   : ok=6    changed=5

Playbook run took 0 days, 0 hours, 1 minutes, 3 seconds
```

---

### Completion summary

```
================================================================
  BackEnd provisioning complete.
================================================================
```

Total wall-clock time for a clean first install: approximately **25–30 minutes** (varies with server speed, network, and image pull times).

---

## `restore-db.sh` — database restore run

Run after the ADempiere stack is up and running. Uploads the backup archive from the control node, decompresses it on the BackEnd, drops and recreates the `adempiere` database, and restores the SQL dump inside the PostgreSQL container via `docker exec`.

```
================================================================
  ADempiere — Database Restore
================================================================

  Source file  : /path/to/backups/my-backup-20260101.sql.gz
  Format       : gz  →  dump file: my-backup-20260101.sql
  Destination  : /opt/development/adempiere-ui-gateway/docker-compose/postgresql/postgres_backups/
  Keep archive : True

  Backend host(s) (from inventory):
    backend1  →  <backend_ip>
  Container    : adempiere-ui-gateway.postgresql
  Database     : adempiere  (owner: adempiere)
  Superuser    : postgres  (via docker exec — no TCP auth)

  !! WARNING: This will OVERWRITE the 'adempiere' database. !!
  !! This operation cannot be undone.                       !!

  Type YES to proceed with the restore:
================================================================

>>> adempiere-restoredb.yml — Restore database

TASK [adempiere-restoredb : INFO: DB restore — configuration summary] **********
ok: [backend1] => {
    "msg": [
        "source   : /path/to/backups/my-backup-20260101.sql.gz",
        "dest     : /opt/development/.../postgres_backups/my-backup-20260101.sql.gz",
        "format   : gz | dump file: my-backup-20260101.sql",
        "container: adempiere-ui-gateway.postgresql",
        "database : adempiere | owner=adempiere | superuser=postgres",
        "keep_restore_file: True"
    ]
}

TASK [adempiere-restoredb : Copy backup file from control node to backend] *****
changed: [backend1]    # <-- transfer time depends on file size and network speed

TASK [adempiere-restoredb : Decompress backup file (gz)] ***********************
changed: [backend1]

TASK [adempiere-restoredb : INFO: Drop and recreate database] ******************
ok: [backend1] => {
    "msg": "DROP DATABASE IF EXISTS adempiere | CREATE DATABASE adempiere WITH OWNER adempiere"
}

TASK [adempiere-restoredb : Drop adempiere database] ***************************
changed: [backend1]

TASK [adempiere-restoredb : Create adempiere database] *************************
changed: [backend1]

TASK [adempiere-restoredb : Restore SQL dump into adempiere database] **********
changed: [backend1]    # <-- restore time depends on DB size; typically 1–5 minutes

TASK [adempiere-restoredb : Remove decompressed dump file] *********************
changed: [backend1]

PLAY RECAP *********************************************************************
backend1                   : ok=25   changed=10   skipped=3

Playbook run took 0 days, 0 hours, 5 minutes, 55 seconds

TASKS RECAP ********************************************************************
adempiere-restoredb : Copy backup file from control node to backend --- 134.96s
adempiere-restoredb : Restore SQL dump into adempiere database --------- 117.19s
adempiere-restoredb : Decompress backup file (gz) ----------------------- 24.36s
...

================================================================
  Database restore complete.
================================================================
```

---

## What the output columns mean

Ansible uses a consistent output format. Each task line shows the result code and the host name:

| Result | Meaning |
|---|---|
| `ok` | Task ran successfully; no change was needed (idempotent). |
| `changed` | Task ran and made a change on the target host. |
| `skipped` | Task conditions were not met — intentionally not run. |
| `failed` | Task failed. The play stops (unless `ignore_errors` is set). |
| `FAILED - RETRYING` | Task is retrying — not a failure; expected during wait loops. |

The `PLAY RECAP` at the end of each playbook summarises these counts across all hosts.

The `TASKS RECAP` (timing profile) lists the slowest tasks in descending order — useful for understanding where time is spent and for identifying unexpected slowdowns.

---

[← Known Issues](known-issues.md) | [← Back to README](../README.md)

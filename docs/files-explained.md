# Files Explained

Detailed explanations of individual project files — what each one does, why it is structured that way, and what to watch out for.  
Each section covers one file: its name, location, and a full description.

---

## deploy-backend.sh

**Name:** `deploy-backend.sh`  
**Location:** project root

**Description:**

Shell script that provisions the BackEnd server from scratch after a reset. Runs all playbooks in the correct order with a single command:

```bash
./deploy-backend.sh           # live run
./deploy-backend.sh --check   # dry run
```

**Step sequence:**

| Step | Playbook | Notes |
|---|---|---|
| 0 | *(local)* | Deletes old SSH keypair from `ssh_keys/` — skipped in `--check` mode |
| 1 | `genkey.yml` | Generates a fresh RSA keypair on the control node |
| 2 | `serversprep.yml --limit BackEnd` | Distributes the public key to the server (root, port 22) |
| 3 | `so-updates.yml --limit BackEnd` | OS update + reboot |
| 4 | `serversconf.yml --limit BackEnd` | Full server hardening |
| 5 | `install-docker.yml --limit BackEnd` | Docker CE (pinned to 28.x) |
| 6 | `deploy-adempiere.yml` | ADempiere container stack |

**Why Step 0 deletes the keypair:**  
`genkey.yml` uses `state: present` — it will not overwrite an existing keypair. After a server reset the old public key is gone from the server anyway, so keeping the old keypair on the control node would cause `serversprep.yml` to deploy a key that already existed. Deleting it first ensures a truly clean start.

**`--check` mode caveat:**  
`so-updates.yml` reboot tasks use `shell`/`command` and are skipped by Ansible in check mode — the dry run will not reflect the post-reboot state.

**Live run safety:**  
In live mode the script requires typing `YES` before proceeding, to prevent accidental runs against a production server.

---

## roles/genkey/tasks/main.yml

**Name:** `main.yml`  
**Location:** `roles/genkey/tasks/main.yml`

**Description:**

The entry point for the `genkey` role, which is invoked by `genkey.yml`. It runs on `localhost` (the control node), not on any remote server. It contains four tasks:

**Task 0 — Create the `ssh_keys/` directory**  
Ensures `<project_root>/ssh_keys/` exists with mode `0700` before generating anything.

**Task 1 — Generate the keypair**  
Uses `community.crypto.openssh_keypair` to create the keypair at:
```
ssh_keys/adempiere_installation_key        (private — gitignored)
ssh_keys/adempiere_installation_key.pub    (public  — gitignored)
```
The key name comes from the `key_name` variable (`roles/genkey/defaults/main.yml`); key size from `key_size` (default: 4096 bits).  
`state: present` means the task is idempotent: if the keypair already exists it is left untouched — no overwrite.

**Task 2 — Copy the public key into the role**  
Copies `ssh_keys/adempiere_installation_key.pub` to `roles/serversconf/files/public_keys/present/admin/<hostname>.pub`, using the control node's hostname (`ansible_facts['nodename']`) as the filename.  
The `serversconf` role picks up all `.pub` files from that directory via a glob and deploys them to the remote servers' `authorized_keys`.

**Task 3 — Confirm (debug)**  
Prints the path and comment of the generated key. Purely informational — no side effect.

**Behaviour under `--check` (dry run):**  
All four tasks support check mode.  
Task 1 reports `changed` if no key exists yet, `ok` if it does — without writing anything.  
Tasks 0 and 2 also simulate without writing.  
Task 3 always runs. The dry run is accurate for this role.

**Why this matters:**  
`genkey.yml` must be the first playbook run in a fresh deployment.  
Without the keypair in place, `serversconf` cannot populate `authorized_keys` and subsequent playbooks that connect as the `adempiere_username` user will fail authentication.

**Why a dedicated key inside the project (not `~/.ssh/id_rsa`):**  
Using the OpenSSH default `~/.ssh/id_rsa` is simpler (no configuration needed) but risky on a developer's workstation that already has an `id_rsa` for GitHub or personal SSH — `state: present` would silently reuse it.  
A dedicated named key inside the project is isolated, portable, and self-contained: the public key travels with the repository and a new operator only needs to run `genkey.yml` once after cloning.  
The private key is referenced via `ansible_ssh_private_key_file` in `group_vars/all/vars.yml` so all playbooks pick it up automatically without any extra flags.

**`id_rsa` vs. dedicated key — trade-offs (documented for context):**

| | `~/.ssh/id_rsa` | `ssh_keys/adempiere_installation_key` (current) |
|---|---|---|
| Configuration needed | None — picked up automatically | `ansible_ssh_private_key_file` in `group_vars/all/vars.yml` |
| Risk of reusing wrong key | Yes — silently reuses existing `id_rsa` | No — always the right key |
| Passphrase risk | Existing `id_rsa` may have one, breaking unattended runs | Generated without passphrase specifically for automation |
| Key isolation | Shared across all purposes | Independent — rotate or revoke without affecting anything else |
| Self-contained for GitHub | No | Yes — `genkey.yml` generates the right key in the right place; new operators just run it once after cloning |

---

## serversprep.yml

**Name:** `serversprep.yml`  
**Location:** project root

**Description:**  

- The playbook that prepares a freshly provisioned server for all subsequent Ansible connections.  
- It targets the `servers` group (both BackEnd and FrontEnd) and must run before any other playbook that connects via SSH.

It does two things before invoking the role:

**pre_task 1 — Set connection credentials**  
- Sets `ansible_user: root` and `ansible_password` from the vault (`root_user_password`).  
- This is how Ansible connects to a server that has not yet been hardened — root login with password on port 22.

**pre_task 2 — Add server fingerprint to known_hosts**  
- Runs `ssh-keyscan` against the server IP and writes the result to `~/.ssh/known_hosts` on the control node (`delegate_to: localhost`).  
- Without this, SSH would prompt "unknown host" and the playbook would hang or fail.

Then calls the `serversprep` role, which installs the project's public key (`ssh_keys/adempiere_installation_key.pub`) into root's `authorized_keys` on the remote server.  
From this point on, all subsequent playbooks authenticate via keypair — the vault password is no longer needed for SSH.

**Why `gather_facts: false`:**  
- Facts are gathered via SSH.  
- On a brand-new server, the fingerprint is not yet in `known_hosts`, so an SSH connection would fail before facts could be collected.  
- Setting `gather_facts: false` lets the `pre_tasks` handle fingerprinting first.

**Why this matters — the bootstrap problem:**  
- Ansible needs SSH access to do anything on a remote server.  
- But a freshly provisioned server only allows root login with a password on port 22 — none of the keypair-based authentication that all other playbooks rely on is in place yet.  
- `serversprep.yml` is the bridge: it uses the one-time root+password credentials to install the keypair, and after that the password is never needed again.  
- This is the only playbook in the project that uses password-based SSH authentication.

**Sequence dependency:**  
- `genkey.yml` must have run before `serversprep.yml` — the public key it installs comes from `ssh_keys/adempiere_installation_key.pub`, which `genkey.yml` generates.  
- If the keypair does not exist, `serversprep.yml` will fail.

**If you have previously SSH'd to the server manually:**  
The fingerprint will already be in `~/.ssh/known_hosts`. This is not a problem for a real run, but if you want to test the full flow (including the fingerprint-adding task), remove it first:

```bash
ssh-keygen -R <backend_ip>
ssh-keygen -R <frontend_ip>
```

The IPs are in `inventories/hosts.yml`. After running `serversprep.yml`, the fingerprint will be re-added automatically.

---

## roles/serversprep/tasks/main.yml

**Name:** `main.yml`  
**Location:** `roles/serversprep/tasks/main.yml`

**Description:**

Two tasks that run on the remote server after the playbook's `pre_tasks` have established the connection:

**Task 1 — Add fingerprint (remote side)**  
- A second `known_hosts` call, this time running on the remote server rather than the control node.  
- In practice the `pre_tasks` version (which runs on `localhost`) is the one that matters for Ansible connectivity; this task is redundant and may be removed in a future cleanup.

**Task 2 — Install the public key on the server**  
- Adds `ssh_keys/adempiere_installation_key.pub` to root's `authorized_keys` on the remote server. 
- After this step, all subsequent playbooks can authenticate as root using the project keypair instead of the vault password — and once `serversconf.yml` runs and disables password auth entirely, this key becomes the only way in.

**Key path:**  
- Uses `playbook_dir + '/ssh_keys/' + key_name + '.pub'` — consistent with the `genkey` role.  
- If `genkey.yml` has not been run first, this lookup will fail.

**Behaviour under `--check` (dry run):**  
`known_hosts` and `authorized_key` both support check mode and will report `changed` or `ok` without making changes. The dry run is accurate for this role.

---

## inventories/hosts.yml and inventories/hosts_template.yml

**Names:** `hosts.yml`, `hosts_template.yml`  
**Location:** `inventories/`

**Description:**

The Ansible inventory — the file that tells Ansible which servers exist, what their IP addresses are, and which groups they belong to.

`hosts.yml` is **gitignored** and never committed. It contains the real IP addresses of your servers. Every operator creates their own copy after cloning:

```bash
cp inventories/hosts_template.yml inventories/hosts.yml
# then fill in your real IPs
```

`hosts_template.yml` **is committed** to the repository. It has the same structure but uses `<placeholder>` values instead of real IPs. It is the reference and starting point for new operators.

**Structure:**

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

**Groups:**

| Group | Purpose |
|---|---|
| `servers` | Both servers — base setup: OS hardening, Docker, SSH config |
| `BackEnd` | ADempiere application + PostgreSQL server only |
| `FrontEnd` | Traefik reverse proxy server only |
| `ansible_test` | Optional local lab VM; not part of `servers` |

**Why `BackEnd` and `FrontEnd` entries look empty:**

```yaml
    BackEnd:
      hosts:
        backend:        ← no ansible_host here
```

This is not an error. `backend` is already defined with its IP under `servers`. Listing it again under `BackEnd` without repeating `ansible_host` just adds it to a second group — Ansible merges the group memberships and the variables from both. The IP is defined once and used everywhere.

**Adding a second BackEnd server:**

The template includes a commented-out `backend2` block. To activate it: uncomment the block under `servers`, set the IP, and also uncomment `backend2` under `BackEnd`. No other files need to change — playbooks that target `BackEnd` will automatically include the new host.

**Why IPs are here and not in `host_vars/`:**

`host_vars/<hostname>.yml` is valid Ansible practice and makes sense when a host has many host-specific variables. In this project the only host-specific value is the IP address (`ansible_host`). Placing it directly in the inventory keeps everything in one file — one file to copy, one file to fill in, one file to gitignore.

---

## so-updates.yml

**Name:** `so-updates.yml`  
**Location:** project root

**Description:**  

- Runs a full OS dist-upgrade on the target servers and reboots if a new kernel was installed.  
- Waits automatically for the server to come back before continuing.

**Why `gather_facts: false`:**  

- This playbook connects as `root` using the vault password, set via `set_fact` in `pre_tasks`.  
- With `gather_facts: true`, Ansible would attempt to connect to collect OS facts *before* `pre_tasks` run — at that point `ansible_user` is not yet set, so the connection would use the control node's current OS user instead of root and fail.  
- Setting `gather_facts: false` ensures `pre_tasks` run first and establish the correct connection user before any remote contact is made.  
- The `so-updates` role does not use OS facts, so disabling fact gathering has no downside.

---

## serversconf.yml

**Name:** `serversconf.yml`  
**Location:** project root

**Description:**  

- Hardens the SSH configuration, creates the admin user (`adempiere_username`), installs base packages, configures unattended security updates, and deploys the project SSH public key to both `root` and the admin user.  
- After this playbook runs, root login is disabled and SSH moves to the custom port — all subsequent playbooks connect as `adempiere_username` on that port.

**Why `gather_facts: true` with play-level `vars:`:**  

- The `serversconf` role needs OS facts: its SSH restart handler checks `ansible_facts['distribution']` to decide whether to restart `ssh.socket` (Ubuntu) or `ssh` (Debian). Facts require an SSH connection — and with `gather_facts: true`, Ansible connects to gather facts *before* `pre_tasks` run.  
- This means `set_fact` in `pre_tasks` would be too late to set `ansible_user` for that initial connection.

The solution is to set the connection variables at the play level using `vars:`:

```yaml
vars:
  ansible_user: "root"
  ansible_password: "{{ root_user_password }}"
```

Play-level `vars:` are evaluated before `gather_facts`, so the correct user is in place for the very first connection.

**Why `01-hardening.conf` and not `99-hardening.conf`:**

Debian's `/etc/ssh/sshd_config` has `Include /etc/ssh/sshd_config.d/*.conf` at the **top** of the file. OpenSSH uses **first-match-wins**: the first time a directive appears wins; later occurrences are ignored. Because drop-in files are included in alphabetical order, `50-cloud-init.conf` (which hosting providers such as Contabo ship with `PasswordAuthentication yes`) is read **before** a `99-hardening.conf` — so the cloud-init value would win. Naming the drop-in `01-hardening.conf` ensures it is read first and its `PasswordAuthentication no` / `PermitRootLogin no` are the ones that take effect.

Use `sudo sshd -T | grep -E "permitrootlogin|passwordauthentication"` to verify the effective config — never grep individual files, as drop-in interactions make that misleading.

**`--check` mode behaviour — "Add ADMIN ssh-keys":**  

- During a dry run, the "Create user" task does not actually create the user on the server.  
- The subsequent "Add ADMIN ssh-keys" task therefore cannot resolve the user's home directory for `adempiere_username` and reports a failure.  
- This is suppressed with `ignore_errors: "{{ ansible_check_mode }}"` — the error is ignored only in check mode; in a real run the user exists and the task succeeds normally.

---

## install-docker.yml

**Name:** `install-docker.yml`  
**Location:** project root

**Description:**

Installs Docker CE and Docker Compose plugin on both BackEnd and FrontEnd servers. Must run after `serversconf.yml` — it connects as `adempiere_username` on the custom SSH port, which only exists after `serversconf` has run.

**Why `gather_facts: true` with play-level `vars:`:**

The role needs OS facts to construct the correct Docker APT repository URL and GPG key path — Ubuntu and Debian use different base URLs. Since `gather_facts: true` connects before `pre_tasks` run, connection credentials must be set at the play level via `vars:` (not via `set_fact` in `pre_tasks`). Play-level `vars:` are evaluated before the initial SSH connection is made.

**Why the admin user is NOT added to the `docker` group:**

Membership in the `docker` group is equivalent to unrestricted root access — any user in that group can run `docker run --rm -v /:/host alpine chroot /host` and become root without a password. All Docker commands in this project run via `sudo`, which preserves the audit trail and requires the sudo password. The role ensures the `docker` group exists (required by the Docker daemon) but deliberately does not add `adempiere_username` to it.

---

## roles/install-docker/tasks/main.yml

**Name:** `main.yml`  
**Location:** `roles/install-docker/tasks/main.yml`

**Description:**

Installs Docker CE from Docker's official APT repository. The role supports both Debian and Ubuntu and auto-detects the distribution at runtime.

**Task 1 — Validate OS**  
Asserts that the target is Debian or Ubuntu. Fails immediately with a clear message on any other OS, rather than proceeding and failing later with a cryptic APT error.

**Task 2 — Set distro-specific variables**  
Constructs `docker_repo_base`, `docker_gpg_url`, and `docker_arch` from Ansible facts. The architecture mapping (`x86_64` → `amd64`, `aarch64` → `arm64`) is needed because Docker's repository uses Debian-style architecture names while Ansible reports Linux kernel names.

**Tasks 3–4 — APT dependencies**  
Updates the cache and installs prerequisites (`curl`, `ca-certificates`, `python3-debian`, `git`, etc.) needed for the Docker GPG key download and repository configuration.

**Tasks 5–6 — GPG key**  
Creates `/etc/apt/keyrings/` and downloads Docker's official GPG key to `/etc/apt/keyrings/docker.asc`. Signing the repository with a downloaded key (rather than relying on the OS keyring) is Docker's own recommended installation method.

**Task 7 — Add Docker APT repository**  
Uses `ansible.builtin.deb822_repository` to write a `.sources` file in modern Deb822 format. The `architectures` filter is applied here too — Docker's repository requires `amd64` not `x86_64`.

**Task 8 — Update cache and install Docker**  
Installs `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, and `docker-compose-plugin` from the newly added repository.

**Task 9 — Enable Docker service**  
Ensures the Docker daemon starts now and on every boot.

**Task 10 — Create `/docker` directory**  
Creates `/docker` (mode `0755`) as the base directory for container configuration on the FrontEnd server. Harmless on BackEnd.

**Task 11 — Ensure docker group exists**  
Creates the `docker` OS group if it does not already exist. Required by the Docker daemon. The admin user is intentionally not added to this group — see `install-docker.yml` above.

---

## deploy-adempiere.yml

**Name:** `deploy-adempiere.yml`  
**Location:** project root

**Description:**

Clones the `adempiere-ui-gateway` repository and starts the Docker Compose stack on the BackEnd server. Must run after `install-docker.yml`.

Connects as `adempiere_username` on the custom SSH port via `set_fact` in `pre_tasks`. Uses `gather_facts: false` because the role's network facts are gathered explicitly inside the role with `ansible.builtin.setup` — this avoids the gather_facts timing problem while still making facts available where needed.

**Sequence dependency:**  
`install-docker.yml` must have completed successfully. Docker CE must be present and the daemon must be running before this playbook can start containers.

---

## roles/deploy-adempiere/tasks/main.yml

**Name:** `main.yml`  
**Location:** `roles/deploy-adempiere/tasks/main.yml`

**Description:**

Orchestrates the full ADempiere deployment in eight steps.

**Task 1 — Gather network facts**  
Explicitly gathers the `network` subset of facts. Used in `override.env.j2` to inject the server's IP address into the Docker Compose environment. Gathering only the network subset is faster than a full fact collection.

**Task 2 — Ensure development directory exists**  
Creates `{{ install_path }}` (default: `/opt/development`) owned by `{{ be_user }}`. Uses `become: true` to create a system-level directory. Idempotent — does nothing if the directory already exists.

**Task 3 — Clone or update repository**  
Clones `adempiere-ui-gateway` from GitHub using `ansible.builtin.git` with `update: yes` and `force: yes`. On every run, Ansible fetches the latest commits from the remote branch (`{{ repo_version }}`). `force: yes` is required because subsequent tasks write `override.env` and `start-all.sh` generates `.env` inside the repo directory — git sees these as local modifications and refuses to update without it. Both files are regenerated by later tasks so discarding them is safe.

**Task 4 — Generate override.env**  
Renders `templates/override.env.j2` into `{{ install_path }}/adempiere-ui-gateway/docker-compose/override.env` with mode `0600` (owner-read only). This file contains database passwords and URLs and must never be world-readable. The `override.env` is read by `start-all.sh` to inject environment-specific values into the Docker Compose stack.

**Task 5 — Check if container is already running**  
Runs `docker ps` (running containers only, not `docker ps -a`) filtered by `{{ adempiere_container_filter }}`. Registers the result. No state change.

**Tasks 6a — Include start.yml and ensure-healthy.yml (conditional)**  
Included only if the container is not already running (task 5 returned empty output). This is the idempotency guard: if the stack is already up, it is not restarted. The condition is based on real system state — not a sentinel file — so it self-corrects: if the stack crashed and the container disappeared, the next run will start it again automatically.

**Tasks 6b — Include validate.yml and status.yml (always)**  
Run unconditionally on every playbook execution. `validate.yml` checks for containers in a bad state (`Exited` with non-zero code, `Restarting`, `Dead`). `status.yml` prints a `docker ps` table for operator confirmation.

---

## roles/deploy-adempiere/tasks/start.yml

**Name:** `start.yml`  
**Location:** `roles/deploy-adempiere/tasks/start.yml`

**Description:**

Runs `start-all.sh` — the shell script shipped inside the `adempiere-ui-gateway` repository that brings up the full Docker Compose stack.

**Why `environment: PWD:`**  
`ansible.builtin.command` does not spawn a shell, so standard shell environment variables — including `PWD` — are not set. Docker Compose uses `$PWD` internally to resolve relative paths in volume mounts. When `$PWD` is absent, Docker Compose warns and defaults to a blank string, causing relative paths to resolve incorrectly and containers to fail silently. Setting `PWD` explicitly to the same path as `chdir` restores the expected behaviour.

**Why `changed_when: true`**  
`ansible.builtin.command` cannot detect whether the underlying operation made a change. `start-all.sh` always exits 0 whether or not it started new containers. Marking the task as always-changed is honest — the script was executed and the system state may have changed — and ensures Ansible handlers (if any) are notified.

---

## roles/deploy-adempiere/tasks/ensure-healthy.yml

**Name:** `ensure-healthy.yml`  
**Location:** `roles/deploy-adempiere/tasks/ensure-healthy.yml`

**Description:**

Confirms the Docker Compose stack is fully operational after `start.yml` runs, and corrects the one known first-run timing failure automatically. Called by `main.yml` via `include_tasks`, always after `start.yml` and never independently.

**Task 1 — Wait until container is created**  
Polls `docker ps -a` (all states) filtering by `{{ adempiere_container_filter }}` until the container name appears. Uses `retries: 30` with `delay: 10` — up to 5 minutes. This confirms Docker Compose created the container; it does not yet confirm the container is running.

**Task 2 — Wait until at least one stack container is running**  
Polls `docker ps` (running containers only, no `-a`) filtering by `{{ adempiere_container_filter }}` until at least one container name appears. Same retry budget. `ignore_errors: true` allows the play to continue even if this times out — `validate.yml` will then catch the bad state and fail with a clear message. Note: individual container names in this stack follow the pattern `adempiere-ui-gateway.<service>`, so `docker inspect adempiere-ui-gateway` would fail (no such exact name exists); the filter-based approach is correct here.

**Tasks 3–5 — Nginx first-run recovery**  
On the very first deployment, Docker must pull 20+ images in parallel. The nginx gateway container initialises quickly (small image) and tries to resolve upstream hostnames (`adempiere-zk`, etc.) before the heavier containers are registered in Docker's internal DNS — causing nginx to exit with code `1`. On subsequent runs all images are cached and containers start nearly simultaneously, so this issue does not occur.

- Task 3 inspects the nginx exit code.
- Task 4 restarts nginx if the exit code is `1` — conditioned so it is a no-op on normal runs.
- Task 5 waits up to 75 seconds for nginx to reach `running` state — also skipped on normal runs.

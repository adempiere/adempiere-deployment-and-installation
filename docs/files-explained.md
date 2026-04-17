# Files Explained

Detailed explanations of individual project files — what each one does, why it is structured that way, and what to watch out for.  
Each section covers one file: its name, location, and a full description.

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
ssh_keys/adempiere_installation_key.pub    (public  — tracked by git)
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
Without the keypair in place, `serversconf` cannot populate `authorized_keys` and subsequent playbooks that connect as the `westfalia` user will fail authentication.

**Why a dedicated key inside the project (not `~/.ssh/id_rsa`):**  
Using the OpenSSH default `~/.ssh/id_rsa` is simpler (no configuration needed) but risky on a developer's workstation that already has an `id_rsa` for GitHub or personal SSH — `state: present` would silently reuse it.  
A dedicated named key inside the project is isolated, portable, and self-contained: the public key travels with the repository and a new operator only needs to run `genkey.yml` once after cloning.  
The private key is referenced via `ansible_ssh_private_key_file` in `group_vars/all.yml` so all playbooks pick it up automatically without any extra flags.

**`id_rsa` vs. dedicated key — trade-offs (documented for context):**

| | `~/.ssh/id_rsa` | `ssh_keys/adempiere_installation_key` (current) |
|---|---|---|
| Configuration needed | None — picked up automatically | `ansible_ssh_private_key_file` in `group_vars/all.yml` |
| Risk of reusing wrong key | Yes — silently reuses existing `id_rsa` | No — always the right key |
| Passphrase risk | Existing `id_rsa` may have one, breaking unattended runs | Generated without passphrase specifically for automation |
| Key isolation | Shared across all purposes | Independent — rotate or revoke without affecting anything else |
| Self-contained for GitHub | No | Yes — public key committed alongside the playbooks |

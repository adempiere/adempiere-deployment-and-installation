# Contributing

## Table of Contents

- [Getting started](#getting-started)
- [Running in check mode before making changes](#running-in-check-mode-before-making-changes)
- [Branching model](#branching-model)
- [Opening a pull request](#opening-a-pull-request)
- [Primary contribution opportunity — Traefik FrontEnd completion](#primary-contribution-opportunity--traefik-frontend-completion)
- [Code style and conventions](#code-style-and-conventions)

---

## Getting started

1. Fork and clone the repository.

2. Create the required local configuration files (they are gitignored and never committed):

   ```bash
   cp group_vars/vars_template.yml   group_vars/all/vars.yml
   cp group_vars/vault_template.yml  group_vars/all/vault.yml
   cp inventories/hosts_template.yml inventories/hosts.yml
   cp roles/serversconf/vars_template.yml roles/serversconf/vars/main.yml
   ```

3. Fill in your values. See [docs/variables.md](docs/variables.md) for a description of every variable.

4. Create and encrypt the vault files:

   ```bash
   echo "YourVaultPassword" > ~/.vault_pass.txt && chmod 600 ~/.vault_pass.txt
   ansible-vault encrypt group_vars/all/vault.yml
   ansible-vault encrypt roles/serversconf/vars/main.yml
   ```

5. Install the required Ansible collections:

   ```bash
   ansible-galaxy collection install community.docker community.postgresql community.crypto
   ```

6. Generate an SSH keypair for the project:

   ```bash
   ansible-playbook genkey.yml
   ```

---

## Running in check mode before making changes

Always verify your changes with a dry run before applying them to a real server:

```bash
# Syntax check — no execution, no SSH connection
ansible-playbook main.yml --syntax-check

# Dry run — shows what would change, no writes
./deploy-backend.sh --check

# Dry run for a single playbook
ansible-playbook serversconf.yml --check --diff
```

`--check` mode skips `command` and `shell` tasks, so the output is approximate for those tasks. It is still reliable for catching variable errors, template rendering issues, and structural problems.

See [docs/testing.md](docs/testing.md) for the full testing guide.

---

## Branching model

| Branch | Purpose |
|---|---|
| `main` | Stable, tested deployments. All new work starts here. |
| `migration/shw-to-adempiere-org` | Anonymization and link updates for the ADempiere community release. Not a base for new features. |

Create a feature branch from `main`:

```bash
git checkout -b feature/my-improvement
```

Test your changes on a real or local test server before opening a PR. The `ansible_test` inventory group in `hosts.yml` is intended for this purpose — point it at a local VM or a disposable VPS.

---

## Opening a pull request

1. Make sure `ansible-playbook main.yml --syntax-check` passes.
2. If you changed any role or playbook, test it with `--check` and ideally on a real host.
3. Do not commit `group_vars/all/vars.yml`, `group_vars/all/vault.yml`, `inventories/hosts.yml`, or `ssh_keys/` — these are gitignored for good reason.
4. Keep commit messages concise. Describe what changed and why; omit server names, IP addresses, and AI tool references.
5. Open the PR against `main`. Include a short description of what the change does and how you tested it.

---

## Primary contribution opportunity — Traefik FrontEnd completion

The highest-impact open work in this project is completing the **Traefik FrontEnd workflow**. The BackEnd deployment is well-tested and fully scripted; the FrontEnd is working but incomplete. See [docs/traefik-status.md](docs/traefik-status.md) for the full status.

The three open items are:

| Item | Description |
|---|---|
| `deploy-frontend.sh` | Orchestration script mirroring `deploy-backend.sh` — prompts, pre-flight checks, ordered playbook execution, logging, `--check` support |
| Dashboard authentication | `basicAuth` middleware in `traefik.yaml.j2`; credentials in vault |
| Other DNS providers | Test and document `traefik_dns_provider` with Route 53, DigitalOcean, etc. |

If you pick up one of these, please open an issue first to coordinate and avoid duplicate effort.

---

## Code style and conventions

- **YAML indentation:** 2 spaces throughout.
- **Task names:** every task must have a `name:`. Use the format `role-name : Short description of what the task does`.
- **INFO tasks:** tasks that print diagnostic output use the pattern `role-name : INFO: What is being logged` and `ansible.builtin.debug` with `msg:`. These run before the actual task so the log is readable even if the task fails.
- **Variables:** role constants go in `roles/<name>/vars/main.yml`; user-overridable defaults go in `roles/<name>/defaults/main.yml`. Never hardcode values that belong in `group_vars/all/vars.yml`.
- **Secrets:** never commit secrets. Real values for passwords, API tokens, or private keys must live in gitignored files.
- **Idempotency:** every task should be safe to re-run. Avoid tasks that always report `changed`.
- **Handlers:** use `notify:` + a handler for service restarts — do not restart services inline.

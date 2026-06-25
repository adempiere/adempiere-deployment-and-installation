# Traefik FrontEnd — Status and Contribution Guide

## Table of Contents

- [What `deploy-traefik` does](#what-deploy-traefik-does)
- [Current state — what works](#current-state--what-works)
- [Known gaps — what is still missing](#known-gaps--what-is-still-missing)
- [Before you enable Traefik](#before-you-enable-traefik)
- [Contribution invitation](#contribution-invitation)

---

## What `deploy-traefik` does

The `deploy-traefik` role deploys a Traefik reverse proxy on the FrontEnd VPS. Traefik sits in front of the ADempiere BackEnd and provides:

- **TLS termination** — HTTPS on port 443, certificate automatically issued and renewed by Let's Encrypt using the Cloudflare DNS-01 challenge
- **HTTP-to-HTTPS redirect** — plain HTTP on port 80 redirects automatically to HTTPS
- **Routing** — inspects the `Host` header of incoming requests and forwards to the correct BackEnd server
- **Multi-tenancy** — can route multiple domains (one per customer) to different BackEnd servers from a single FrontEnd
- **Dashboard** — a read-only web UI showing live routing configuration and health status

The role deploys two containers on the FrontEnd:
- `traefik` — the reverse proxy itself
- `socket-proxy` — a read-only proxy for the Docker socket API, so Traefik can discover containers without full daemon access

Traefik is configured in `roles/deploy-traefik/templates/traefik.yaml.j2`. Routing rules for ADempiere live in `roles/deploy-traefik/templates/app-adempiere.yaml.j2`.

---

## Current state — what works

| Feature | Status |
|---|---|
| Traefik container deployment | ✓ Working |
| Socket proxy deployment | ✓ Working |
| TLS certificate via Let's Encrypt + Cloudflare DNS-01 | ✓ Working |
| Automatic certificate renewal | ✓ Working (Traefik handles this internally) |
| HTTP → HTTPS redirect | ✓ Working |
| Routing to ADempiere BackEnd | ✓ Working |
| Multi-BackEnd load balancing | ✓ Working (add hosts to the BackEnd group) |
| Traefik dashboard (unauthenticated) | ✓ Working — but see gap #2 below |
| DNS provider: Cloudflare | ✓ Tested |
| DNS provider: other | ? Untested — other Traefik-supported providers should work in theory |

---

## Known gaps — what is still missing

### Gap 1 — No `deploy-frontend.sh` orchestration script

The BackEnd has `deploy-backend.sh` — a single script that handles keypair setup, pre-flight checks, known_hosts cleanup, confirmation prompts, and runs all playbooks in the correct order.

The FrontEnd has no equivalent entry point. The operator must run the individual playbooks manually:

```bash
ansible-playbook serversprep.yml    --limit FrontEnd
ansible-playbook so-updates.yml     --limit FrontEnd
ansible-playbook serversconf.yml    --limit FrontEnd
ansible-playbook serverswap.yml     --limit FrontEnd
ansible-playbook install-docker.yml --limit FrontEnd
ansible-playbook deploy-traefik.yml
```

A `deploy-frontend.sh` script that wraps these steps — with the same safety prompts and logging as `deploy-backend.sh` — would significantly improve the operator experience.

### Gap 2 — Traefik dashboard has no authentication

The dashboard is enabled by default (`traefik_dashboard_enabled: true`) and exposed on port `traefik_dashboard_port` (default: `28080`) with `api.insecure: true`.

**Risk:** Anyone who can reach `<FrontEnd-IP>:28080` can view the full routing configuration.

**Recommended fix:** Protect the dashboard with a Traefik `basicAuth` middleware, or disable it in production by setting `traefik_dashboard_enabled: false`.

See [known-issues.md](known-issues.md#4-traefik-dashboard-has-no-authentication) for details.

### Gap 3 — DNS must be set up manually before deployment

Let's Encrypt validates domain ownership immediately when Traefik starts for the first time. If the domain's DNS does not already point to the FrontEnd IP, the certificate request fails and Traefik cannot start.

**What needs to happen before running `deploy-traefik.yml`:**
1. Create a DNS A record pointing `<dns_domain>` (and any subdomains you use) to the FrontEnd VPS IP
2. Wait for DNS propagation (typically a few minutes — verify with `dig <dns_domain> +short`)
3. Only then run `deploy-traefik.yml`

This is a manual prerequisite that cannot be automated by this project.

---

## Before you enable Traefik

To enable Traefik, set `deploy_traefik: true` in `group_vars/all/vars.yml`.

Before doing so, work through this checklist:

- [ ] DNS A record for `<dns_domain>` pointing to the FrontEnd IP is live and propagated
- [ ] `dns_domain` is set correctly in `group_vars/all/vars.yml`
- [ ] `cloudflare_token` (DNS:Edit permission) is set in `group_vars/all/vault.yml`
- [ ] `cloudflare_email` is set in `group_vars/all/vault.yml`
- [ ] You have decided what to do about the unauthenticated dashboard (disable it or plan to protect it)
- [ ] You are aware there is no `deploy-frontend.sh` — you will run the playbooks manually

If any item is not satisfied, leave `deploy_traefik: false` until it is.

---

## Contribution invitation

The Traefik FrontEnd workflow is **functional but incomplete**. The gaps above are well-defined and scoped — they are a natural starting point for a first contribution to this project.

The most impactful open items are:

1. **`deploy-frontend.sh`** — Create a `deploy-frontend.sh` script mirroring `deploy-backend.sh`:
   - Run the FrontEnd playbooks in the correct order with the same safety prompts
   - Add pre-flight checks (vault password file, DNS resolution for `dns_domain`, FrontEnd reachability on port 22)
   - Log output to `logs/deploy-frontend-<timestamp>.log`
   - Support `--check` flag for dry-run mode

2. **Dashboard authentication** — Add a `basicAuth` middleware to `roles/deploy-traefik/templates/traefik.yaml.j2` and store the credentials in `group_vars/all/vault.yml`

3. **Other DNS providers** — Test and document the `traefik_dns_provider` variable with providers other than Cloudflare (Route 53, DigitalOcean, etc.)

Please read [CONTRIBUTING.md](../CONTRIBUTING.md) before opening a pull request.

---

[← Known Issues](known-issues.md) | [← Back to README](../README.md)

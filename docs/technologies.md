# Technologies Used

## Ansible

Ansible is an agentless IT automation tool.  
You write **playbooks** (YAML files) that describe the desired state of your infrastructure.  
Ansible  
- connects to target machines over SSH  
- executes the tasks, and  
- ensures the system matches the declared state — without installing anything on the remote servers.

Key concepts used in this project:

| Concept | What it is |
|---|---|
| **Playbook** | A YAML file defining a sequence of tasks to run on a set of hosts |
| **Role** | A reusable, self-contained unit of tasks, templates, and variables |
| **Inventory** | A file listing the servers Ansible manages, organized into groups |
| **Vault** | Ansible's built-in encryption for storing secrets (passwords, tokens) |
| **Template** | A Jinja2 file rendered on the fly with variable substitution before being deployed |
| **Handler** | A task that runs only when triggered by a `notify`, typically to restart a service |

**Official documentation:** https://docs.ansible.com/

---

## Traefik

Traefik is a modern reverse proxy and load balancer designed for containerized environments. Unlike traditional proxies (nginx, HAProxy), Traefik discovers services automatically by watching the Docker daemon, and can obtain and renew TLS certificates from Let's Encrypt without any manual configuration.

Key concepts used in this project:

| Concept | What it is |
|---|---|
| **EntryPoint** | A network port Traefik listens on (`:80`, `:443`) |
| **Router** | A rule that matches incoming requests (e.g. by hostname) and forwards them to a service |
| **Service** | The backend that handles matched requests (an IP address and port) |
| **Middleware** | Optional processing applied to requests/responses (headers, redirects, auth) |
| **CertificateResolver** | Configuration for automatic TLS certificate issuance via ACME (Let's Encrypt) |
| **DNS Challenge** | A way to prove domain ownership by creating a DNS TXT record — used here via the Cloudflare API, so no public HTTP port is required for cert issuance |
| **Socket Proxy** | A separate container that gives Traefik read-only access to the Docker API, preventing a compromised Traefik from controlling the Docker daemon |

**Official documentation:** https://doc.traefik.io/traefik/

---

## Docker & Docker Compose

Docker packages applications into containers. Docker Compose defines multi-container stacks in a single `docker-compose.yml` file.

This project installs Docker CE from the official Docker repository (not the distribution default) and uses the Compose plugin (`docker compose`, not the legacy `docker-compose`).

**Official documentation:** https://docs.docker.com/

---

[← Back to README](../README.md) | [Next: Requirements →](requirements.md)

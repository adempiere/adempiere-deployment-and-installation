# System Requirements

## Table of Contents

- [Control Node (your local machine — runs Ansible)](#control-node-your-local-machine--runs-ansible)
- [Target Servers (VPS)](#target-servers-vps)
- [External Services](#external-services)

---

## Control Node (your local machine — runs Ansible)

| Requirement | Details |
|---|---|
| OS | Linux or macOS (Windows requires WSL2) |
| Ansible | 2.14 or newer |
| Python | 3.9 or newer |
| SSH client | OpenSSH |
| Ansible collections | `community.docker`, `community.postgresql`, `community.crypto` |
| `sshpass` | Required for password-based SSH authentication (used during initial server setup) |

Install required tools and collections:
```bash
sudo apt install sshpass
ansible-galaxy collection install community.docker community.postgresql community.crypto
```

---

## Target Servers (VPS)

| Requirement | Details |
|---|---|
| OS | Ubuntu 22.04 LTS or Debian 12 |
| Architecture | amd64 (x86_64) or arm64 |
| RAM | 4 GB minimum, 8 GB recommended |
| Disk | 40 GB minimum |
| Initial access | Root SSH on port 22 with password (only for the first run) |
| Internet | Required — Docker images, GitHub, Let's Encrypt are all downloaded at runtime |

The `install-docker` role explicitly validates that the OS is Debian or Ubuntu and will fail with a clear error message on other distributions.

---

## External Services

| Service | Purpose | Required |
|---|---|---|
| Cloudflare | DNS provider + API for TLS certificate issuance | Yes (for Traefik TLS) |
| GitHub | Source for the `adempiere-ui-gateway` repository | Yes |
| Let's Encrypt | TLS certificate authority (contacted automatically by Traefik) | Yes (for Traefik TLS) |

### Cloudflare API Token

You need a Cloudflare API token with permission `Zone → DNS → Edit` scoped to your domain zone.

Generate one at: **Cloudflare Dashboard → My Profile → API Tokens → Create Token**

---

[← Technologies](technologies.md) | [Next: Architecture →](architecture.md)

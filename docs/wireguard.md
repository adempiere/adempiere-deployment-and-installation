# WireGuard VPN — Architecture and Configuration Guide

## Purpose

WireGuard provides the secure tunnel between each Windows POS machine (at any
customer location) and the ADempiere backend server (cloud). The POS printing
feature requires this tunnel to be in place so the POS client can reach the server
and, when needed, so the server can initiate connections back to devices at the
customer site (e.g. a receipt printer on the local LAN).

---

## Topology

```
ADempiere backend (cloud)
  ┌──────────────────────────────────┐
  │  WireGuard SERVER                │
  │  VPN address : 10.8.0.1         │
  │  Listen port : 51820/UDP        │
  └──────────────┬───────────────────┘
                 │  encrypted UDP tunnel
     ┌───────────┘
     │
Windows POS machine (customer site)
  ┌──────────────────────────────────┐
  │  WireGuard CLIENT (peer)         │
  │  VPN address : 10.8.0.x/32      │
  │  Local LAN   : 192.168.y.0/24   │
  └──────────────────────────────────┘
         │  (local network)
      Printer / other LAN devices
```

One WireGuard server serves all POS clients across all customer locations.
Each Windows POS machine is a separate peer with its own unique VPN address.

---

## Key management

| Key | Location | Shared with |
|---|---|---|
| Server private key | `/etc/wireguard/server_private.key` on server; source: `ssh_keys/wireguard_server_private.key` on control node | Nobody — never leaves the server |
| Server public key | `ssh_keys/wireguard_server_public.key` on control node | **All POS clients** — embedded in every client config |
| Client private key | Generated on each Windows PC | Nobody — stays on that PC |
| Client public key | Generated on each Windows PC | Added to the server as a peer entry in `wg0.conf` |

The server key pair is stable across server reinstalls by default. Regenerating it
requires updating every POS client configuration — avoid unless the key is compromised.

---

## No separate "gateway device" needed

Some WireGuard documentation describes a scenario where a dedicated device (a Raspberry
Pi, a router, or a spare computer) must be placed on the local network to act as a
VPN gateway for devices that cannot run WireGuard themselves. **This does not apply here.**

In this setup the Windows POS machine itself is the WireGuard peer. It runs the
WireGuard client directly and therefore already bridges the VPN and its own local LAN.
No additional device is required.

---

## AllowedIPs — the routing question that does matter

`AllowedIPs` is the WireGuard setting that controls which IP ranges are routed through
a given tunnel. It must be set correctly on both sides.

### On the server — peer entries in `wg0.conf`

Each peer (Windows POS machine) has an entry like:

```
[Peer]
# <customer name / location>
PublicKey  = <client public key>
AllowedIPs = 10.8.0.2/32
```

**`AllowedIPs = 10.8.0.2/32`** means: route only the peer's VPN address through this
tunnel. This is sufficient if all communication is initiated from the Windows PC toward
the server (the typical case for a POS client fetching data or sending print requests).

**If the ADempiere server needs to initiate connections to a printer on the customer's
local LAN** (server-push printing), the server must also be able to route traffic for
that LAN. In that case, extend the peer's `AllowedIPs`:

```
[Peer]
# <customer name / location>
PublicKey  = <client public key>
AllowedIPs = 10.8.0.2/32, 192.168.1.0/24
```

This tells the WireGuard server: to reach anything in `192.168.1.0/24`, send it
through the tunnel to this Windows PC, which will forward it to the local LAN.

**Each peer must have a unique set of IPs.** Two peers cannot both claim the same
LAN subnet in `AllowedIPs` — WireGuard cannot decide which tunnel to use.

### On the Windows POS client

The client configuration controls which traffic the Windows PC sends through the tunnel:

```
[Interface]
PrivateKey = <client private key>
Address    = 10.8.0.2/32
DNS        = (optional)

[Peer]
PublicKey  = <server public key>            ← same for all clients
Endpoint   = <server IP or domain>:51820
AllowedIPs = 10.8.0.0/24                   ← route VPN subnet through tunnel
```

`AllowedIPs = 10.8.0.0/24` means: only traffic destined for other VPN addresses goes
through the tunnel; all other traffic (internet, local LAN) uses the normal default
gateway. This is called **split tunnelling** and is the recommended configuration for
POS clients — it avoids routing all internet traffic through the server.

If the server needs to reach the local LAN and the Windows PC is to act as the
gateway for that subnet, the Windows PC must also have **IP forwarding** enabled.
On Windows this is done via the registry or the WireGuard client's `PostUp` hooks.

---

## Adding a new POS client (peer registration)

1. On the Windows PC, generate a key pair:
   ```
   wg genkey | tee client_private.key | wg pubkey > client_public.key
   ```

2. On the server, add a `[Peer]` block to `/etc/wireguard/wg0.conf`:
   ```
   [Peer]
   # <customer name / location>
   PublicKey  = <content of client_public.key>
   AllowedIPs = 10.8.0.x/32         # assign the next free VPN address
   ```
   Then reload without dropping existing connections:
   ```
   sudo wg syncconf wg0 <(wg-quick strip wg0)
   ```

3. On the Windows PC, install WireGuard and create a tunnel config with:
   - `PrivateKey` = content of `client_private.key`
   - `Address` = `10.8.0.x/32` (matching the AllowedIPs assigned above)
   - `[Peer]` `PublicKey` = content of `ssh_keys/wireguard_server_public.key`
   - `Endpoint` = `<server public IP or domain>:51820`
   - `AllowedIPs` = `10.8.0.0/24` (or extend if server-push printing is needed)

---

## Firewall requirements

| Machine | Protocol | Port | Direction | Purpose |
|---|---|---|---|---|
| Backend server | UDP | 51820 | Inbound | WireGuard peer connections |
| Windows POS | (none) | — | — | Outbound only; no inbound rule needed |

The server port (51820 by default, configurable via `wireguard_port` in `vars.yml`)
must be open in the cloud provider's firewall (Contabo, Hetzner, AWS, etc.).
`deploy-backend.sh` pauses after installing WireGuard and prompts for this action.

---

## Ansible variables

| Variable | File | Description |
|---|---|---|
| `wireguard_enabled` | `group_vars/BackEnd.yml` | `true` to install; `false` to skip |
| `wireguard_port` | `group_vars/all/vars.yml` | UDP listen port (default 51820) |
| `wireguard_server_address` | `group_vars/all/vars.yml` | Server VPN interface address (default `10.8.0.1/24`) |

Server key files (gitignored, never committed):

| File | Purpose |
|---|---|
| `ssh_keys/wireguard_server_private.key` | Deployed to `/etc/wireguard/server_private.key` on the server |
| `ssh_keys/wireguard_server_public.key` | Distributed to all POS clients as the server public key |

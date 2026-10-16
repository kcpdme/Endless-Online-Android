# Hosted development world

The Android app defaults to **wss://eo.kcpd.top/ws**. This connects through
Cloudflare and Caddy HTTPS to the real etheos server on the existing AWS host.
The hosted world uses its own persistent database and password salt. Local
computer test accounts and offline device saves are separate.

The three systemd services run as the dedicated `astervale` user:

| Service | Purpose | Private listener |
| --- | --- | --- |
| `aster-vale-world` | Authoritative pinned etheos world | `127.0.0.1:8078` |
| `aster-vale-gateway` | EO session / JSON adapter | `127.0.0.1:8079` |
| `aster-vale-websocket` | WebSocket transport | `127.0.0.1:8180` |

Caddy routes only `/ws` and `/healthz` to the WebSocket service. The web root
returns a short connection notice. It does not serve runtime data, credentials,
databases or archives. The proxied `eo.kcpd.top` DNS A record points to the
existing host; no new paid infrastructure was created. The original Caddy
configuration was backed up before appending the separate site import.

## Operations

Use the existing `AwsHosting` SSH alias with the working private key. Keys and
Cloudflare tokens are never included in this repository. On the host:

```sh
sudo systemctl status aster-vale-world aster-vale-gateway aster-vale-websocket
sudo journalctl -u aster-vale-world -n 50
curl -fsS http://127.0.0.1:8180/healthz
```

Public health: https://eo.kcpd.top/healthz . Runtime data is under
`/opt/aster-vale/runtime`; adapter code is under `/opt/aster-vale/app/server`.
The verified Python dependency lives in `/opt/aster-vale/python`.

For adapter updates, copy reviewed code, then restart the gateway and WebSocket
services. This disconnects active players; etheos retains their progress. A
world-server update needs a planned restart. Preserve `database.sdb` and
`config.local.ini` together: replacing the password salt invalidates existing
password hashes. Use SQLite's backup API or stop the world service before
copying a database. Never replace a live database with a local test fixture.

The checked-in service and Caddy files document the installed configuration.
To reproduce on another host, stage the pinned compiled etheos runtime with
its world/config/language files, create a fresh private config/salt and SQLite
schema, install the adapter source and verified WebSocket dependency, and adapt
paths/domain before installing these units. Original game assets remain outside
the public source repository.

## Verified scope

Normal TLS validation passed both through Cloudflare and directly to Caddy
using the domain's SNI. The real Godot scene passed public WSS login, character
entry, Aeven -> map4 -> Aeven, gear updates and offline-save isolation. Native
ports listen only on loopback. The existing Caddy service remained active.

This is a development world with a twelve-session capacity limit. Shops,
quests, chat, trading, spells, expanded character appearances, account recovery,
public abuse monitoring and load testing remain separate milestones.

References: [Caddy WebSocket reverse proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy),
[Cloudflare WebSockets](https://developers.cloudflare.com/network/websockets/),
[websockets server API](https://websockets.readthedocs.io/en/17.2/reference/sync/server.html).

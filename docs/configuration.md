# Configuration

Two ways to configure the same stack. The app writes its compose file from the
panel at every start, so the running stack always matches what the panel shows.
The terminal bundle in [local/](../local/) reads `.env` instead.

## The panel

| Setting | Default | Notes |
| --- | --- | --- |
| Port | 54040 | Apply, then restart. |
| Image tag | `auto` | `auto` runs the newest published release. Type a tag to pin one. |
| Public access | Off | Off, a quick tunnel, or a tunnel from your Cloudflare account. |
| Start at login | Off | Brings the relay back after a reboot. |
| Erase stored data | | Deletes the relay database and every blob. |

The app's generated compose file, which is readable and is overwritten at every
start:

```
~/Library/Application Support/WealdRelayHost/compose.yml
```

A named tunnel's token lives in `.env` beside it, owner readable only, and is
held in your login keychain rather than in the compose file.

## `local/.env`

| Variable | Default | What it does |
| --- | --- | --- |
| `WEALD_RELAY_PORT` | `54040` | The port the relay answers on, published to loopback only. |
| `WEALD_RELAY_TAG` | `auto` | Which published image to run. `auto` resolves the newest release tag at start; a tag such as `wealdrelay-v0.1.5` pins one. |
| `POSTGRES_PASSWORD` | `weald` | Protects ciphertext at rest. |
| `WEALD_RELAY_RETENTION_DAYS` | `unlimited` | Drop envelopes older than this. |
| `WEALD_RELAY_MAX_STORAGE_GB` | `unlimited` | Refuse writes past this size. |

## What the relay itself reads

Set by the compose file, not by hand. Listed because a self-hoster reading the
compose file deserves to know what each line is for.

| Variable | Value here | Why |
| --- | --- | --- |
| `WEALD_RELAY_DATABASE_URL` | the `db` service | Envelope log, group heads, key packages, quotas. Required. |
| `WEALD_RELAY_STORAGE_URL` | `file:///var/lib/weald/blobs` | Encrypted media. A directory rather than S3, which the relay supports for single node installs. |
| `WEALD_RELAY_LISTEN` | `0.0.0.0:<port>` | Inside the container. The published port is loopback. |
| `WEALD_RELAY_HOSTNAME` | `localhost`, or the tunnel hostname | What the relay calls itself in the links it mints. |
| `WEALD_RELAY_TLS` | `off` | Nothing terminates TLS in front of a loopback relay. Behind a tunnel the edge does, which is the documented proxy posture and not a downgrade. |

`WEALD_RELAY_REDIS_URL` is deliberately unset: with one relay process, the binary
uses in process fanout and Redis would be a container doing nothing.

## Version and provenance

The relay reports what is actually running, and Weald's encryption panel shows
it, so a pinned tag can be checked rather than trusted:

```bash
docker exec -it weald-relay-host-relay-1 wealdrelay --version
```

Relay source, Apache 2.0, rebuildable and digest matchable:
[Weald-Protocol/wealdrelay](https://github.com/Weald-Protocol/wealdrelay).

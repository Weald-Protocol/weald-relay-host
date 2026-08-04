# Quickstart

Five minutes to your own relay, on this Mac, with no account anywhere.

## 1. A Docker engine

[Docker Desktop](https://www.docker.com/products/docker-desktop/) or
[OrbStack](https://orbstack.dev). Open it once so the engine is running. This is
the only prerequisite.

## 2. The app

```bash
git clone https://github.com/Weald-Protocol/weald-relay-host.git
cd weald-relay-host
./scripts/build-app.sh
open build
```

Drag **Weald Relay Host.app** into `/Applications` and launch it. A white **W**
appears in the menu bar. Prefer a terminal? Use [local/](../local/) instead.

## 3. Start relay

Click the **W**, then **Start relay**. The first start pulls the relay image and
runs its migrations, so give it a minute. A green dot means the socket answered a
real health check.

## 4. Paste the URL into Weald

```
ws://127.0.0.1:54040/relay
```

Click the URL row in the panel to copy it. In the Weald Mac app, open the
project's relay settings and paste.

## 5. Claim the workspace

A brand new relay has no members, so it mints one bootstrap invite. The panel
shows it as **First device link** and **One-time code**. Copy the code somewhere
safe, open the link from Weald, and that device becomes the workspace owner.

The code is minted once and the relay keeps only a hash of it, so it cannot be
shown again. If you lose it before any device claims the workspace, erase stored
data and start over.

## Then what

- Another machine or a phone: [remote-access.md](remote-access.md)
- Change the port, pin a version, set quotas: [configuration.md](configuration.md)
- Keep it safe: [backup-restore.md](backup-restore.md)
- Something is wrong: [troubleshooting.md](troubleshooting.md)

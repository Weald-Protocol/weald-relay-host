# A local relay without the app

The menu bar app is the easy path. This is the same stack in a terminal, for a
Linux box, a headless Mac mini, or anyone who would rather read a compose file
than trust a toggle.

Prerequisite: Docker with the compose plugin, running.

```bash
git clone https://github.com/Weald-Protocol/weald-relay-host.git
cd weald-relay-host/local
./weald-relay up
```

That prints the URL to paste into Weald and, on a brand new relay, the first
device link and its one-time code:

```
This Mac  ws://127.0.0.1:54040/relay

First device link  http://127.0.0.1:54040/join/8f2c...
One-time code      3f9a-2d17-bb04
```

Copy the code before you close the terminal. It is minted once and the relay
keeps only a hash of it.

## Commands

| | |
| --- | --- |
| `./weald-relay up` | Start, wait for the socket, print the URL and the invite. |
| `./weald-relay status` | Whether the socket answers, plus container state. |
| `./weald-relay url` | The URL to paste into Weald. |
| `./weald-relay invite` | The first device link, while the workspace is unclaimed. |
| `./weald-relay logs` | Follow the relay log. `logs db` for Postgres. |
| `./weald-relay upgrade` | Pull the newest image and restart. |
| `./weald-relay backup` | A dated tarball of the database and the blobs. |
| `./weald-relay restore FILE` | Put a tarball back. |
| `./weald-relay down` | Stop, keep the data. |
| `./weald-relay erase` | Stop, delete the data. |
| `./weald-relay doctor` | Check the prerequisites and name what is wrong. |

## Settings

Everything is in `.env`, created from `.env.example` on first run. Port, image
tag, database password, retention and storage quota. See
[docs/configuration.md](../docs/configuration.md).

## Reaching it from another machine

This bundle publishes the relay on loopback only, and a Weald client refuses a
plaintext socket to anything that is not literally loopback, so as written it
serves this machine and nothing else. To reach it from elsewhere, put a tunnel
or a TLS terminator in front: [docs/remote-access.md](../docs/remote-access.md).

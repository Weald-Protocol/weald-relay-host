# Troubleshooting

Start here, with the terminal bundle:

```bash
cd local && ./weald-relay doctor
```

**"Docker is not running."** Open Docker Desktop or OrbStack and wait for it to
finish starting. The engine, not just the app window.

**"That port is taken."** Something else holds 54040. Change the port in Settings
and restart, or in `local/.env`.

**The first start takes forever.** It is pulling the relay image and the Postgres
image and running migrations. A minute is normal on a first run and a few seconds
after that.

**Green dot, but Weald will not connect.** For a local relay the URL is `ws://`
and not `wss://`, the host is `127.0.0.1` and not `localhost`, and the port has to
match the panel.

**No first device link.** It appears only while the workspace has no members. If a
device already claimed it, that is the expected state and nothing is broken. If
nothing ever claimed it and you lost the code, erase stored data and start over.

**The public address is still an IP.** The tunnel has not been accepted yet. Give
it a few seconds on a first start, since the image has to be pulled, then read the
tunnel log.

**"That tunnel token was not accepted."** Copy it again from the tunnel's page in
Cloudflare Zero Trust. It is the long token from the install command, not the
tunnel's ID.

**The public URL returns 502.** A named tunnel's ingress rule points somewhere
else. It has to be `http://relay:54040`, using the compose service name, with the
port matching the panel.

**The relay restarts in a loop.** Read its log. The usual cause is a database that
did not come up, and the compose file already waits for a healthy Postgres, so a
loop here usually means a disk that is full.

**Raw logs.**

```bash
cd ~/Library/Application\ Support/WealdRelayHost   # the app
docker compose -f compose.yml logs -f relay
docker compose -f compose.yml logs -f db
docker compose -f compose.yml logs -f tunnel

cd local && ./weald-relay logs                     # the terminal bundle
```

**Start over completely.** Erase stored data in the app, or `./weald-relay erase`.
That deletes the database and the blobs and mints a fresh bootstrap invite on the
next start. Client devices keep their own copies.

# Backup and restore

Two things hold state: the Postgres volume and the blob volume. Both hold
ciphertext only, because the relay is blind, so a backup can go anywhere,
including a provider you would not otherwise trust.

Clients keep their own full copy and reconcile the delta on the next connect, so
a restore from a slightly stale backup heals itself.

## With the terminal bundle

```bash
cd local
./weald-relay backup                       # weald-relay-backup-20260609-141233.tar
./weald-relay restore weald-relay-backup-20260609-141233.tar
```

Put the first line in a cron job or a launchd agent and keep the tarballs
somewhere other than this Mac.

## With the app

The app's compose project is `weald-relay-host`, so its volumes are
`weald-relay-host_db` and `weald-relay-host_blobs`.

```bash
cd ~/Library/Application\ Support/WealdRelayHost

# database
docker compose -f compose.yml exec -T db \
  pg_dump -U weald -Fc weald_relay > weald-db.dump

# blobs
docker run --rm -v weald-relay-host_blobs:/blobs:ro -v "$PWD:/out" alpine:3.20 \
  tar -cf /out/weald-blobs.tar -C /blobs .
```

Restore is the same two in reverse, with the relay stopped:

```bash
docker compose -f compose.yml stop relay

docker compose -f compose.yml exec -T db psql -U weald -d postgres \
  -c 'DROP DATABASE IF EXISTS weald_relay' -c 'CREATE DATABASE weald_relay'
docker compose -f compose.yml exec -T db \
  pg_restore -U weald -d weald_relay < weald-db.dump

docker run --rm -v weald-relay-host_blobs:/blobs -v "$PWD:/in:ro" alpine:3.20 \
  sh -c 'tar -xf /in/weald-blobs.tar -C /blobs && chown -R 65532:65532 /blobs'

docker compose -f compose.yml up -d
```

The `chown` matters: the relay image is distroless and runs as uid 65532, so it
cannot fix ownership of files a root shell wrote.

## Moving to another machine

Restore both volumes there, start the relay, and point the client at the new
address. A workspace's identity is anchored to its genesis entry rather than to a
hostname, so changing address is a settings change and not a new workspace.

## What a backup does not contain

Any key that could read anything. Message keys never leave the client, so a relay
backup without a member device is a pile of ciphertext with no way in, which is
the point.

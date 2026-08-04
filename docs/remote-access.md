# Reaching your relay from another machine

Two things stand between a relay on a laptop and a phone across town. A Weald
client refuses a plaintext socket to anything that is not literally loopback, so
`ws://` works on the host Mac and nowhere else, and a home router does not
forward a port because you would like it to.

## The button

In the app, press **Open a public door**. Both problems go away at once.

That adds a `cloudflared` container to the stack, which dials out to Cloudflare
and is handed a hostname. Nothing is forwarded, no port is opened, your IP is
never published, and TLS terminates at Cloudflare's edge, so the panel can show a
URL that actually connects:

```
wss://detail-literally-monday-austin.trycloudflare.com/relay
```

Paste it into Weald from anywhere. The first device link moves to the same
hostname, so an invite minted before the tunnel existed still opens.

## Quick, or your own

**Quick** is that button. No account, no token, nothing to configure. The catch
is in the name: Cloudflare mints the hostname at connect time and a different one
at the next start, so it suits a demo or a weekend and not a workspace you intend
to keep.

**My tunnel** keeps one hostname forever. In
[Cloudflare Zero Trust](https://one.dash.cloudflare.com), create a tunnel, point
its public hostname at `http://relay:54040`, then paste the token and that
hostname into Settings. The token goes to your login keychain and never into the
compose file. This is the one to use for real.

## Without the app

The [local/](../local/) bundle publishes on loopback only. To open a door, put
one of these in front of it:

- **A Cloudflare tunnel.** Add a `cloudflare/cloudflared` service to
  `local/compose.yml` on the same network, running
  `tunnel --no-autoupdate --url http://relay:54040`, and read the hostname out of
  its log.
- **Your own TLS.** Caddy or nginx with a real certificate, proxying to the relay,
  with the relay left on `WEALD_RELAY_TLS=off` behind it. For a VPS with a public
  hostname, the relay repository ships a Caddy bundle that does this.
- **A private network.** Tailscale or WireGuard, with the relay bound to that
  interface and no public ingress at all. Clients use the network's own TLS or a
  private CA they are told to trust.

## Or a router, if you insist

Forward the port, put your own TLS in front, and expect the IP to move whenever
your ISP feels like it. The tunnel is easier and safer, which is why it is the
button.

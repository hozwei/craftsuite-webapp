# Reverse proxy

`craft-web` speaks plain HTTP on `CRAFT_PORT`. A reverse proxy in front of it serves
`https://craft.example.com` with a valid certificate and forwards everything to that port.

## Must

- **HTTPS.** The session cookie is `Secure` with the `__Host-` prefix, and the translator only
  works in a secure context. Redirect HTTP to HTTPS.
- **Forward every path** (`/`, `/oauth2/…`, `/<app>/…`) to `http://<host>:CRAFT_PORT`, unchanged.
- **Leave the security headers alone.** Do not add `X-Frame-Options` (it would block Nextcloud
  from framing the apps) and do not add a `Content-Security-Policy` of your own (`craft-web`
  already sends `frame-ancestors` on every response; two policies would both apply).
- **Do not cache.** Everything sits behind a sign-in: a shared cache in the proxy would hand
  files to people without a session. Turn off any "cache assets" feature for this host.

## May

- HSTS (`Strict-Transport-Security`) is fine and recommended.
- `X-Forwarded-For` and `X-Forwarded-Proto` do no harm. WebSockets are not used.
- No request bodies larger than a few kilobytes are sent: the apps never upload files here. Saves
  from the Nextcloud editor go to Nextcloud, whose own reverse proxy must take large requests
  for SoundCraft's sessions ([nextcloud.md](nextcloud.md#soundcraft-sessions)).

## Examples

**nginx**

```nginx
server {
  listen 443 ssl;
  http2 on;
  server_name craft.example.com;
  ssl_certificate     /etc/ssl/craft.example.com/fullchain.pem;
  ssl_certificate_key /etc/ssl/craft.example.com/privkey.pem;
  add_header Strict-Transport-Security "max-age=63072000" always;

  location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
  }
}
```

**Caddy**

```caddy
craft.example.com {
  reverse_proxy 127.0.0.1:8080
}
```

**Nginx Proxy Manager**: a proxy host for `craft.example.com`, scheme `http`, the Docker host's
address and `CRAFT_PORT`; *Cache Assets* **off**, *Websockets Support* off, *Block Common
Exploits* as you like. On the SSL tab: a certificate, *Force SSL*, *HTTP/2*, *HSTS*. Nothing on
the *Custom locations* and *Advanced* tabs.

## Check

From any machine:

```sh
curl -sI https://craft.example.com/
```

Expect `302` with a `location:` at your provider's authorization endpoint, a
`content-security-policy: frame-ancestors …` line, and no `x-frame-options` line. A `502` or `504`
means the proxy does not reach `CRAFT_PORT`; see [troubleshooting.md](troubleshooting.md).

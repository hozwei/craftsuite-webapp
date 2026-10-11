# Configuration

All settings live in `.env` next to `compose.yaml` (start from `.env.example`). Docker Compose
reads it on every `docker compose` command; after a change, apply it with:

```sh
docker compose up -d
```

`.env` holds two secrets: keep it readable for you only (`chmod 600 .env`) and out of version
control (it is in `.gitignore`). Values are plain text; put a value in single quotes if it
contains `$`, `#`, a backslash or spaces.

The *Default* columns give the value `compose.yaml` uses when a setting is missing or empty;
`.env.example` fills in example values for some of them.

## Where the apps are served

| Setting | Default | Meaning |
|---|---|---|
| `CRAFT_HOST` | – (required) | Public host name of the apps, without `https://`. The sign-in redirect URL is `https://<CRAFT_HOST>/oauth2/callback`. |
| `CRAFT_PORT` | `8080` | Where `craft-web` is published on the host: a port (`8080`, all interfaces) or `127.0.0.1:8080` (this host only). Your reverse proxy forwards to it. |
| `CRAFT_DATA_DIR` | `./data` | Folder for the app releases, the updater's state and the layer bundle. It and everything in it must belong to `CRAFT_USER` (`chown -R`) and stay readable for others (`chmod 755`; `craft-web` reads it as user 101, and the updater keeps the mode). If it is missing, Docker creates it for root and the updater cannot write. |
| `CRAFT_USER` | `1000:1000` | User and group the updater runs as. |
| `TZ` | `UTC` | Time zone of the updater: its log times, `CRAFT_UPDATE_TIME` and the times on the start page. |

## Sign-in

| Setting | Default | Meaning |
|---|---|---|
| `CRAFT_OIDC_ISSUER_URL` | – (required) | The provider's issuer, character for character as its `/.well-known/openid-configuration` states it, with plain slashes (the JSON may show them as `\/`); for Nextcloud `https://cloud.example.com`, without a slash at the end. oauth2-proxy fetches the discovery document at start and stops if that fails. |
| `CRAFT_OIDC_CLIENT_ID` | – (required) | The client ID you created at the provider. |
| `CRAFT_OIDC_CLIENT_SECRET` | – (required) | Its secret. |
| `CRAFT_COOKIE_SECRET` | – (required) | 32 random bytes in URL-safe base64: `openssl rand -base64 32 \| tr -- '+/' '-_'`. Signs and encrypts the session cookie; changing it signs everybody out. |
| `CRAFT_SESSION_LIFETIME` | `12h` | How long a sign-in lasts, from the moment of signing in (`12h`, `168h`, …). See the trade-off below. |

The client needs the authorization code flow; oauth2-proxy uses PKCE (`S256`) and asks only for the
scope `openid`. It takes the user's `sub` claim as the identity, so accounts without an e-mail
address work. Access is decided at the provider: limit the client to the users or group that may
use the apps.

**Session lifetime.** A session is not re-checked at the provider while it lasts: after removing
someone from the group, or after signing out of the provider, the session stays valid until it
ends. Shorter is stricter; longer means fewer sign-ins. When the provider is your Nextcloud and
the person is signed in there, a new sign-in is only a redirect without a prompt, so the default
of 12 hours costs little.

## Updates

| Setting | Default | Meaning |
|---|---|---|
| `CRAFT_UPDATE_TIME` | `07:00` | Daily update time (`HH:MM`, in `TZ`; anything else is replaced by `07:00`, with a line in the log). The updater also runs when its container starts, and an hour after a failed run (up to three times). Choose a time after your backups. |
| `CRAFT_MIN_AGE_HOURS` | `24` | A release is taken only when it is at least this many hours old, so that bad releases can be withdrawn first. With the canary check on, the first run of the layer's canary after a release must also have reported no failure ([how-it-works.md](how-it-works.md#the-canary), including its limits). `0` takes the newest qualifying release at once (for one manual run, see [operations.md](operations.md#update-now)). |
| `CRAFT_APPS` | `pdfcraft photocraft vectorcraft designcraft` | The apps to serve, separated by spaces. Each must publish `<app>-web-<version>.zip` in its releases at `github.com/storytold/<app>`. Removing one stops its updates and drops it from the start page, but it stays reachable at `/<app>/` until you delete it: `docker exec craft-update sh -c 'rm -rf /craft/www/<app> /craft/www/releases/<app>-* /craft/state/<app>.*'`. |

## Start page

| Setting | Default | Meaning |
|---|---|---|
| `CRAFT_LANGUAGE` | `en` | Language of the start page: `en` or `de`. |
| `CRAFT_LINK_URL` | empty | Optional button at the top right, for example to your Nextcloud Files (`https://cloud.example.com/apps/files/`). Empty: no button. |
| `CRAFT_LINK_LABEL` | `Nextcloud` | The button's text. |

The start page lists each app with its icon and version, a short help on saving, and the time of
the last update check. After a failed check it shows a notice. With the Nextcloud integration on it
also tells people how to open files from Nextcloud.

## Nextcloud integration

All three of the first settings are needed for the integration; see
[nextcloud.md](nextcloud.md#2-open-files-from-nextcloud).

| Setting | Default | Meaning |
|---|---|---|
| `CRAFTSUITE_ALLOWED_ORIGINS` | empty | The origins of the Nextcloud servers that may frame the apps, separated by spaces: `https://host` or `https://host:port`, exactly as the browser shows them, without a path or a slash at the end. It goes into the `frame-ancestors` header and into the translator; `craft-web` refuses to start with anything else. Empty: no site may frame the apps (`frame-ancestors 'none'`). |
| `CRAFTSUITE_LAYER_VERSION` | empty | The release of [nextcloud-craftsuite-layer](https://github.com/hozwei/nextcloud-craftsuite-layer) whose translator the updater adds, such as `0.1.0`. Empty: the apps are served without the translator. Use the same version as the Nextcloud app. |
| `CRAFTSUITE_LAYER_SHA256` | empty | The SHA-256 of that release's `craftsuite-layer-hosting-<version>.tar.gz`, from its `SHA256SUMS` file. The updater refuses a bundle with another checksum. |
| `CRAFTSUITE_LAYER_REPO` | `hozwei/nextcloud-craftsuite-layer` | Where the bundle and the canary issues come from (`owner/repository` on GitHub), for a fork. |
| `CRAFTSUITE_CANARY` | `on` | `off`: take app releases without looking at the layer's canary (no waiting for open issues, no canary hold). |

For nextcloud-craftsuite-layer 0.1.0 the checksum is
`8aafbc59cee7a3bad95b0ab03be6c7dce23f0be178e461142266246988639017`. For another release, take it
from that release's `SHA256SUMS`:

```sh
curl -fsSL https://github.com/hozwei/nextcloud-craftsuite-layer/releases/download/v0.1.0/SHA256SUMS
```

## Fixed settings

These are part of `compose.yaml` and need no change: the cookie name `__Host-craft` (`Secure`,
`HttpOnly`, `SameSite=Lax`, host-only), PKCE, the scope `openid`, a CSRF cookie per sign-in (so
that several tabs can sign in at the same time), the image versions, the memory limits and the
health checks.

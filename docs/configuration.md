# Configuration

All settings live in `.env` next to `compose.yaml` (start from `.env.example`). Docker Compose
reads it on every `docker compose` command; after a change, apply it with:

```sh
docker compose up -d
```

`.env` holds two secrets: keep it readable for you only (`chmod 600 .env`) and out of version
control (it is in `.gitignore`). Values are plain text; put a value in single quotes if it
contains `$`, `#` or a backslash (spaces between words need no quotes).

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
| `CRAFT_MIN_AGE_HOURS` | `24` | A release is taken only when it is at least this many hours old (a whole number, at most 999999), so that bad releases can be withdrawn first. With the canary check on, the first run of the layer's canary for your layer version after a release must also have tested it and passed for its app ([how-it-works.md](how-it-works.md#the-canary), including its limits); two to three days also let the next canary run hold the release back if it fails for the app. `0` takes the newest qualifying release at once (for one manual run, see [operations.md](operations.md#update-now)). |
| `CRAFT_APPS` | `auto` | The apps to serve: `auto`, app ids and `-<app>`, separated by spaces (see [the app list](#the-app-list) below). Each app must publish `<app>-web-<version>.zip` in its GitHub releases. |

### The app list

`CRAFT_APPS` takes these words:

- `auto`: the apps in the app list of the pinned layer release (`apps.json` in its hosting bundle,
  nextcloud-craftsuite-layer 0.5.0 and later), in its order. With layer 0.5.2 these are the twelve
  apps from PdfCraft to SoundCraft. An app that a later layer release adds is served once you use
  that release, without a change here.
- `-<app>` leaves an app out: `auto -lightcraft`.
- `<app>` adds an app: `auto <app>` serves one that the app list does not have, and a list of app
  ids alone, such as `pdfcraft photocraft`, serves exactly these.
- Empty, missing, or nothing but exclusions: `auto` (with the exclusions).

A word that is none of these is an error of the run and is ignored; a list of nothing but such
words keeps the installed apps. Without the Nextcloud
integration (`CRAFTSUITE_LAYER_VERSION` empty) there is no app list: `auto` then stands for the
apps already installed, with a line in the log, and on a new data folder for none, which is an
error; name the apps instead. With a layer before 0.5.0, `auto` is an error of every run (the
installed apps are still kept up to date): name the apps there too.

For each app it has, the app list gives:

- the name, the short text (in `CRAFT_LANGUAGE`, else English) and the colour on the start page;
- the repository on GitHub its releases come from (`repo`); an app it does not have is taken from
  `github.com/storytold/<app>`;
- the startup timeout (`startupTimeout`): 180000 ms for LightCraft and EffectCraft, unless
  `CRAFTSUITE_STARTUP_TIMEOUTS` has an entry for the app ([below](#nextcloud-integration));
- the oldest release the layer's adapter handles (`minVersion`): older releases are never taken.
  A version below it that is being served (after a rollback, say, or when a newer layer raises
  it) runs without the translator, and every run reports an error until a newer release is taken;
  `--status` shows `Nextcloud - (older than <minVersion>, the oldest the layer handles)`.

Every value is checked first. An invalid colour, name, text or timeout is not used. An app whose
entry has an invalid repository or `minVersion` gets no update, and its served version stays as it is,
with an error on every run (with `auto` and named in `CRAFT_APPS` alike). An app named in
`CRAFT_APPS` that the list does not have is not tested by the layer's canary, so only
`CRAFT_MIN_AGE_HOURS` applies to it. When the app list cannot be read, nothing changes and the
start page keeps the last one that could. Without an app list (a layer before 0.5.0), the start
page shows the app ids, without texts and colours, and no `minVersion` applies.
the app ids, without texts and colours, and no `minVersion` applies.

An app that is served but not in the list stays reachable at `/<app>/`, but is not on the start
page and gets no updates. One that the layer's app list no longer has (with `auto`) also loses the
translator, which no longer fits it; one you left out (`-<app>`, or not named in a list of ids) is
left as it is. Each run logs it; to delete it, see
[operations.md](operations.md#removing-an-app).

## Start page

| Setting | Default | Meaning |
|---|---|---|
| `CRAFT_LANGUAGE` | `en` | Language of the start page: `en` or `de`. |
| `CRAFT_LINK_URL` | empty | Optional button at the top right, for example to your Nextcloud Files (`https://cloud.example.com/apps/files/`). Empty: no button. |
| `CRAFT_LINK_LABEL` | `Nextcloud` | The button's text. |

The start page lists each app with its icon, name, short text and version, in the order of
`CRAFT_APPS` (for `auto`, that of the app list), a short help on saving, and the time of the last
update check. Names, texts and colours come from the layer's app list. After a failed check it
shows a notice; while no app is installed, it says so instead, also after a check without errors.
While a canary failure holds back new releases, a notice names the apps and links the issue. With
the Nextcloud integration on it also tells people how to open files from Nextcloud.

## Nextcloud integration

All three of the first settings are needed for the integration; see
[nextcloud.md](nextcloud.md#2-open-files-from-nextcloud).

| Setting | Default | Meaning |
|---|---|---|
| `CRAFTSUITE_ALLOWED_ORIGINS` | empty | The origins of the Nextcloud servers that may frame the apps, separated by spaces: `https://host` or `https://host:port`, exactly as the browser shows them, without a path or a slash at the end. It goes into the `frame-ancestors` header and into the translator; `craft-web` refuses to start with anything else. Empty: no site may frame the apps (`frame-ancestors 'none'`). |
| `CRAFTSUITE_LAYER_VERSION` | empty | The release of [nextcloud-craftsuite-layer](https://github.com/hozwei/nextcloud-craftsuite-layer) whose translator the updater adds, such as `0.5.2`; its hosting bundle also brings the app list (0.5.0 and later). `auto` (from 0.5.0 on): follow the layer's releases, each checked against GitHub's checksum, its canary and the translator protocol of the layer in use ([how-it-works.md](how-it-works.md#the-layer-bundle)). Empty: the apps are served without the translator. The Nextcloud app works with any layer release of the same translator protocol (version 1 since 0.1.0). |
| `CRAFTSUITE_LAYER_SHA256` | empty | The SHA-256 of that release's `craftsuite-layer-hosting-<version>.tar.gz`, from its `SHA256SUMS` file. The updater refuses a bundle with another checksum. Not used with `auto`. |
| `CRAFTSUITE_LAYER_REPO` | `hozwei/nextcloud-craftsuite-layer` | Where the bundle and the canary's runs, issues and tested translators come from (`owner/repository` on GitHub), for a fork. |
| `CRAFTSUITE_CANARY` | `on` | `off`: take app releases without looking at the layer's canary (no waiting for a run or for open issues, no canary hold). |
| `CRAFTSUITE_STARTUP_TIMEOUTS` | empty | How long the translator waits for an app to start, counted from the page's `load` event: entries `<app>=<milliseconds>` (1 to 2147483647), separated by spaces. An entry overrides the app list's `startupTimeout` for its app; apps with neither get the translator's default of 60 seconds. The app list recommends 180000 for LightCraft and EffectCraft, which download their `.wasm` (LightCraft also a font) while this time runs; 60 seconds are too short below about 3 Mbit/s for LightCraft (about 24 MB with gzip) and about 2.4 Mbit/s for EffectCraft (about 18 MB). FilmCraft fits into 60 seconds down to about 2 Mbit/s: add `filmcraft=180000` for users on slow connections. With a layer before 0.5.0 there is no app list: set `lightcraft=180000 effectcraft=180000` yourself. A changed value reaches the served versions on the next run. An invalid entry is an error of the run (`layer: ERROR - CRAFTSUITE_STARTUP_TIMEOUTS takes entries …`), and new releases wait. With layer 0.1.0 no timeout is passed (the value is still checked). |

For nextcloud-craftsuite-layer 0.5.2 the checksum is
`d12fc3fdf62ea2549551218dc7b5c9788308e3c641f51cbc4e4ea204cba557fe`. For another release, take it
from that release's `SHA256SUMS`:

```sh
curl -fsSL https://github.com/hozwei/nextcloud-craftsuite-layer/releases/download/v0.5.2/SHA256SUMS
```

## Fixed settings

These are part of `compose.yaml` and need no change: the cookie name `__Host-craft` (`Secure`,
`HttpOnly`, `SameSite=Lax`, host-only), PKCE, the scope `openid`, a CSRF cookie per sign-in (so
that several tabs can sign in at the same time), the image versions, the memory limits and the
health checks.

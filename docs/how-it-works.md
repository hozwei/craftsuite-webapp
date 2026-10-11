# How it works

## The three containers

| Container | Image | Job |
|---|---|---|
| `craft-web` | `nginxinc/nginx-unprivileged:1.30-alpine-slim` | The only published port. Serves the start page and the apps from `CRAFT_DATA_DIR/www` (the data folder is mounted read-only) and sets the security and cache headers on every response. Asks `craft-gate` about each request first. |
| `craft-gate` | `quay.io/oauth2-proxy/oauth2-proxy:v7.15.5-alpine` | Holds the sign-in. Answers nginx's checks (`/oauth2/auth`: 202 signed in, 401 not), sends people without a session to the OpenID Connect provider and sets the session cookie after the sign-in. Not reachable from outside. |
| `craft-update` | built from `alpine:3.24` (`craftsuite-webapp-update:1`) | Runs once at start and then daily at `CRAFT_UPDATE_TIME`: fetches, checks and switches app releases, adds the Nextcloud translator, writes the start page. |

All three run with a read-only root file system, without Linux capabilities and with
`no-new-privileges`. The scripts of `craft-web` and `craft-update` are part of `compose.yaml`
itself (`command:`), so the one file is the whole configuration; their readable sources are in
[`src/`](../src) ([development.md](development.md)).

```mermaid
flowchart LR
  B[Browser] -->|HTTPS| P[Your reverse proxy]
  P --> W[craft-web<br>nginx]
  W -->|auth_request| G[craft-gate<br>oauth2-proxy]
  G -.->|sign-in| I[OpenID Connect provider]
  W --> F[(CRAFT_DATA_DIR/www)]
  U[craft-update] -->|daily| R[GitHub releases]
  U --> F
```

### A request

1. The reverse proxy terminates TLS and passes the request to `craft-web`.
2. nginx makes a sub-request to `craft-gate` at `/oauth2/auth`. With a valid session cookie the
   answer is 202 and nginx serves the file.
3. Without one the answer is 401, and nginx hands the request to oauth2-proxy's
   `/oauth2/sign_in`, which redirects the browser to the provider (there is no intermediate
   "Sign in with …" page). nginx passes the original address along, so after the sign-in the
   browser lands where it wanted to go, query string included.
4. The provider sends the browser back to `https://CRAFT_HOST/oauth2/callback`; oauth2-proxy sets
   the session cookie and redirects to the original address.

Only `/healthz` (for the container health check), `/oauth2/*` (the sign-in itself) and the 404
answers for `/releases/…` and hidden files are served without a session.

## The data folder

```text
CRAFT_DATA_DIR/
  www/                        served by craft-web
    index.html                start page, rewritten after every update run
    pdfcraft -> releases/pdfcraft-0.6.0        one symbolic link per app: the version served
    releases/pdfcraft-0.6.0/  one folder per kept version (current and previous)
    releases/pdfcraft-0.5.0/
    ...
  state/
    status                    OK <time> or ERROR <count> <time> of the last run
    <app>.previous            the version a rollback goes back to
    <app>.blocked             a version that is not taken, nor any lower one
    canary-since              per layer version: the time from which its canary failures count
    canary-failed             the canary issue that holds new releases (see below)
  layer/
    craftsuite-layer-hosting-<version>/        the pinned layer bundle (hosting/, translators/)
```

Everything in it can be rebuilt by the updater; there are no user files. Plan about 450 MB: one
set of the four apps takes about 215 MB with its compressed copies, and the previous version of
each app stays.

## The update run

For each app in `CRAFT_APPS`:

1. **List the releases.** One request to the GitHub API lists the app's last 30 releases. The
   layer's documentation suggests finding the newest release through the redirect of
   `github.com/<owner>/<app>/releases/latest` instead, to spare the API's limit of 60 requests per
   hour per IP address; the list is used here because it has what the checks below need: the
   publication times and GitHub's checksum (digest) of each file.
2. **Choose a release.** It qualifies when its tag is `vX.Y.Z`, it is neither a draft nor a
   pre-release, it has the assets `<app>-web-<version>.zip` and `SHA256SUMS.txt`, it was published
   at least `CRAFT_MIN_AGE_HOURS` ago, and its version is higher than the installed one and than a
   blocked one. If its files were replaced after publication, the age counts from the last upload.
   With the canary check on, the first canary run that tested it must have passed (below). The
   highest qualifying version is taken; the updater never moves to a lower version by itself.
3. **Hold back?** While a canary issue is open, after a canary failure, or while the layer bundle
   cannot be used, no new release is taken (see below). The installed version stays.
4. **Download and verify.** The zip and `SHA256SUMS.txt` come from
   `https://github.com/storytold/<app>/releases/download/v<version>/`. The zip's SHA-256 must
   match its line in `SHA256SUMS.txt` **and** the digest GitHub reports for the asset. Every entry
   must lie inside `<app>-web-<version>/`, without links and without `..`; after unpacking there
   must be nothing but files and folders, an `index.html` and at least one `.wasm`.
5. **Prepare.** The upstream hosting notes (`README.md`, `HOSTING.md`, `_headers`, `.htaccess`)
   are removed (the headers they describe are set by `craft-web`). The app icon is fetched from
   the app's repository at the same tag for the start page (cosmetic: without it the start page
   shows a letter tile). Apart from this and the translator, the release is served unchanged; its
   licence and notice files stay.
6. **Add the translator** (Nextcloud integration on): `inject-translator.sh` of the pinned layer
   adds two `<script>` tags after `<head>` and copies the translator files into
   `craftsuite-layer/`. Exit code 0: go on. Exit code 6 (the layer has no adapter for this app): go
   on without the translator. Any other code: **stop**; the release is not switched to and the
   installed version keeps running.
7. **Compress** `.html`, `.js`, `.mjs` and `.wasm` with `gzip -9` into `.gz` copies, which nginx
   serves directly (`gzip_static`).
8. **Switch** by replacing the symbolic link `www/<app>` in one atomic rename. Browsers get the new
   version on their next page load. The previous version is kept; older ones are deleted.
9. **Keep the served version current.** After that, the translator of the version being served is
   checked (`inject-translator.sh --check`) and updated in place if the layer version or
   `CRAFTSUITE_ALLOWED_ORIGINS` changed. This is how a new layer release reaches the apps without
   a new app release.

Afterwards the run writes `state/status` and the start page. Any error makes the status
`ERROR <count>`: the start page shows a red notice, `craft-update` turns unhealthy, the apps keep
running in their previous version, and the updater tries again an hour later (up to three times,
then at the next daily time). A run takes five API requests: one per app and one for the canary.
Machines behind the same public IP address share the limit of 60 per hour.

### The layer bundle

With `CRAFTSUITE_LAYER_VERSION` set, the updater downloads
`craftsuite-layer-hosting-<version>.tar.gz` and `SHA256SUMS` from the layer's release, checks
that the bundle's SHA-256 equals both `CRAFTSUITE_LAYER_SHA256` and its line in `SHA256SUMS`,
checks the archive's layout, and unpacks it to `layer/`. It does this again whenever the version,
the checksum or `CRAFTSUITE_LAYER_REPO` changes. The pinned checksum in your configuration means a
changed bundle on GitHub is refused, not used. Changing the version in `.env` is the only way to
move to another layer release; the old bundle is then removed.

### The canary

The layer's repository runs a canary every day at 04:23 UTC: it fetches the newest release of each
app, tests the translators of the layer's main branch against it, and opens an issue labelled
`canary` when that fails (a failing run while it is open comments on it; the next passing run
closes it). With the Nextcloud integration on and `CRAFTSUITE_CANARY=on`, the updater follows
three rules:

1. **While a `canary` issue is open, no new release is taken.** The run logs it; this is a normal
   wait, not an error. Only an app that is not installed yet counts as an error until then.
2. **A release is taken only if the first canary run after it tested and passed it.** That run
   is the first daily 04:23 UTC start after the release (after its last upload, if its files were
   replaced). The release must still have been the newest release of its app two hours after that
   start, so that the run tested it and not a newer one, and the run counts as passed when no
   `canary` issue was open three hours after the start. A release that was replaced by a newer one
   before that is never taken; the newer one is. A release whose first run failed is never taken,
   even if later runs pass.
3. **A failure holds new releases until you act.** A failure is a `canary` issue opened after the
   current `CRAFTSUITE_LAYER_VERSION` came into use (recorded in `state/canary-since`), or one that
   is still open after the first canary run since then (a failing run comments on the open issue
   instead of opening a new one). It holds every new release of every app, also after the issue
   is closed: the canary tests the layer's main branch,
   so a passing run after a fix there does not show that the pinned layer release handles the new
   app releases. The hold counts as an error, so the start page, the status and the health check
   show it. It ends when another layer version is in use (a bundle that fails its checks does
   not count; going back to a version keeps the time it first came into use, and so its failures),
   or when you confirm that the failure does not concern your layer version by removing
   `state/canary-since` ([operations.md](operations.md#the-canary-hold)); failures count again from
   that moment.

Limits: the check relies on the canary running on schedule. GitHub can delay scheduled runs and
turns schedules off after 60 days without activity in a repository; without runs there are no
issues, and releases are then taken as if they had passed. A new or rebuilt data folder knows no
earlier failures: failures count from its first run. GitHub keeps no earlier close time when an
issue is reopened, so a reopened canary issue counts as open from its creation to its last close.
Watch the layer's repository ([operations.md](operations.md#staying-informed)).

## Headers

`craft-web` sets these on every response, including oauth2-proxy's redirects and error pages and
nginx's own error pages:

| Header | Value | Why |
|---|---|---|
| `Content-Security-Policy` | `frame-ancestors <CRAFTSUITE_ALLOWED_ORIGINS>`, or `frame-ancestors 'none'` when that is empty | Only your Nextcloud may frame the apps and the sign-in pages; no other site may (with an empty list: nobody). |
| `X-Content-Type-Options` | `nosniff` | As the upstream builds ask for. |
| `Cache-Control` | `private, max-age=31536000, immutable` for successful answers (200, 206, 304) for `.js`, `.mjs` and `.wasm`, whose names carry a content hash; `no-cache` for everything else, including error answers, `index.html` and the translator files in `craftsuite-layer/`; oauth2-proxy's own value under `/oauth2/` | New releases and translator updates take effect on the next load; no shared cache keeps anything; an error is never cached. |

`X-Frame-Options` is never sent: it cannot allow another origin and would block Nextcloud. No
`Cross-Origin-Opener-Policy` or `-Embedder-Policy` either; the apps do not need them. `.wasm` is
served as `application/wasm`, so browsers compile it while downloading.

## Security model

- **No user files on the server.** The apps open and save files in the browser. With the
  Nextcloud integration, the file travels from the Nextcloud page to the framed app with
  `postMessage` and back the same way; Nextcloud stores it over WebDAV as the signed-in user. The
  server of the apps only ever sends static files.
- **The sign-in is the access control.** Who can sign in at your provider (for Nextcloud: the
  group the client is limited to) can use the apps; everybody else gets nothing but redirects to
  the provider. The session cookie is `__Host-craft`: host-only, `Secure`, `HttpOnly`,
  `SameSite=Lax`. A session lasts `CRAFT_SESSION_LIFETIME` from the sign-in; it is not checked
  against the provider again in that time, so signing out of the provider or leaving the group
  takes effect when it ends. To end all sessions at once, change `CRAFT_COOKIE_SECRET`.
- **What you trust.** The upstream releases, checked against two checksums from their own GitHub
  release (this protects against corrupted or partial downloads and swapped assets, not against a
  compromised upstream account), and the layer bundle, pinned by a checksum you put in `.env`.
  The minimum age gives the projects time to withdraw a bad release.
- **Framing.** Only the origins in `CRAFTSUITE_ALLOWED_ORIGINS` may frame anything on this host.
  The translator itself talks only to those origins (its own copy of the same list in
  `data-allowed-origins`) and stays inactive when the app is opened directly.
- **Containers.** Read-only, no capabilities, unprivileged users (`nginx` 101, `nobody` for
  oauth2-proxy, `CRAFT_USER` for the updater), memory limits. Only `craft-web` has a published
  port. The updater has write access to `CRAFT_DATA_DIR` only. `craft-web` finds `craft-gate`
  through Docker's internal DNS; its `ndots:1` option keeps that name from being looked up in your
  network's DNS while `craft-gate` is restarting, so no other machine can answer in its place.
- **The host name.** Never serve the apps under your Nextcloud's host name: code there could use
  the Nextcloud session. A separate host under the same registrable domain
  (`craft.example.com` next to `cloud.example.com`) is right; see
  [nextcloud.md](nextcloud.md#the-sign-in-cookie-and-the-frame).

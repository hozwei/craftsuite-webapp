# Troubleshooting

Start with `docker exec craft-update craft-update --status` and the logs of the container
concerned ([operations.md](operations.md#status-and-logs)).

## Signing in

| Symptom | Cause and fix |
|---|---|
| `craft-gate` restarts again and again; its log says `Failed to initialise OAuth2 Proxy` or something about the issuer | oauth2-proxy could not fetch `<issuer>/.well-known/openid-configuration` at start, or the issuer there differs from `CRAFT_OIDC_ISSUER_URL`. Compare character by character (plain slashes, none at the end, no `index.php`); check that the Docker host reaches the provider's public address (inside the same network this may need hairpin NAT or split DNS). |
| After the sign-in: an error page from oauth2-proxy with "CSRF" or status 500 | The sign-in took longer than 15 minutes, or cookies were blocked. Open `https://craft.example.com` again. If it stays, see the `craft-gate` log. |
| `invalid_client` in the `craft-gate` log | `CRAFT_OIDC_CLIENT_SECRET` does not match the client at the provider. Nextcloud then slows down further attempts from the address it sees for these requests (brute-force protection): after fixing the secret, `occ security:bruteforce:reset <ip>` with that address (your public IP if the request goes through hairpin NAT, else the Docker host's; Nextcloud's log names it). |
| Nextcloud shows "Access forbidden … not a member of the groups defined for the client" | The account is not in the group the client is limited to. |
| `https://craft.example.com` answers `502` or `504` | The reverse proxy does not reach `CRAFT_PORT`, or `craft-web` is not running (`docker compose ps`). |
| `craft-web` restarts; its log says `CRAFTSUITE_ALLOWED_ORIGINS …` | The value is not a list of origins: use `https://host` or `https://host:port`, separated by spaces (no commas, no path, no slash at the end). |
| `craft-web` answers `500` (and `502` under `/oauth2/`) | It cannot reach `craft-gate` (`docker logs craft-web`). Is `craft-gate` running and healthy? |
| Signed out at the provider, but the apps still open | Expected: the session at the gate lasts `CRAFT_SESSION_LIFETIME`. Sign out at `https://craft.example.com/oauth2/sign_out` as well. |

## Updates

| Log line of `craft-update` | Meaning and fix |
|---|---|
| `ERROR - cannot list the releases of storytold/<app> …` | No answer from `api.github.com`, the 60 requests per hour for your IP address are used up (other machines behind the same address count too), or the app name in `CRAFT_APPS` is wrong. The updater tries again in an hour. |
| `ERROR - checksum of … does not match, nothing changed` | The download differs from `SHA256SUMS.txt` or from GitHub's digest. Nothing was switched. If it repeats, look at the release on GitHub before doing anything else. |
| `ERROR - … has links or paths outside …` / `unexpected content in …` | The release archive does not have the expected layout. Nothing was switched; the app's maintainers may have changed their packaging. |
| `not installed yet, no release qualifies yet; a later run takes one` | First installation of an app whose releases are all younger than `CRAFT_MIN_AGE_HOURS`, not yet tested by the layer's canary, or blocked. A later run takes one; or update now ([operations.md](operations.md#update-now)). |
| `ERROR - no release v<version> with <app>-web-<version>.zip and SHA256SUMS.txt found` | The app's releases do not have the expected form (tag, web build, checksum file); check `CRAFT_APPS` and the app's releases on GitHub. |
| `layer: the canary reports a failure (<issue>), new releases wait while the issue is open` | Normal: the layer's canary has an open issue; new releases wait until it is closed. On a first installation the apps are not installed until then (`ERROR - <version> not installed: open canary issue`). |
| `layer: ERROR - the canary failed (<issue>) since layer <version> came into use …` and `<app>: <version> held back (canary failure)` | The canary failed since your layer version came into use (an issue opened since then, or one still open after the next canary run). No new release is taken until another layer version is in use or you confirm: [operations.md](operations.md#the-canary-hold). On a first installation the apps are not installed until then (`ERROR - <version> not installed: canary failure`). |
| `ERROR - cannot read the canary issues …` | The GitHub API did not answer. New releases wait; the updater tries again in an hour. |
| `layer: ERROR - checksum of craftsuite-layer-hosting-… does not match …` | `CRAFTSUITE_LAYER_SHA256` is not the checksum of that version's bundle. Copy it again from the release's `SHA256SUMS`. New releases wait until it is fixed. |
| `layer: ERROR - CRAFTSUITE_ALLOWED_ORIGINS is empty` | The layer is on but no Nextcloud origin is set. Set it, or empty `CRAFTSUITE_LAYER_VERSION`. |
| `inject-translator: error: invalid allowed origin …` and `translator not added to … (inject-translator.sh exit code 2)` | The translator refuses a value in `CRAFTSUITE_ALLOWED_ORIGINS` (https only, no path, international names in their `xn--` form). Until it is fixed, no release is switched to; on a first installation no app appears. |
| `translator not added to … (inject-translator.sh exit code 4)` | The release's `index.html` changed in a way the translator's injector does not handle. That release is not switched to; the layer needs an update. |
| `layer … has no adapter for <app>, … served without the Nextcloud integration` | This layer version does not support that app. It is served without the translator. |
| Every page answers `403` | `CRAFT_DATA_DIR` is not readable for others; `craft-web` reads it as user 101: `chmod 755 <CRAFT_DATA_DIR>`. |
| `ERROR - <folder> … must be writable for user …` | `CRAFT_DATA_DIR` or a folder in it does not belong to `CRAFT_USER`: `chown -R <CRAFT_USER> <CRAFT_DATA_DIR>`. |
| `craft-update is already running` | Another run is in progress (a manual one, or the retry an hour after an error). If none is, the lock is left from a killed run: restarting the container removes it. |
| `ERROR - state/<app>.blocked holds '…'` | The block file must hold a version such as `0.7.0`. |

## In Nextcloud

| Symptom | Cause and fix |
|---|---|
| No "Open in …" entries in Files | The app is not enabled for you (`occ app:list`, `occ config:app:get craftsuite_layer enabled`), or no address is set for that app (`occ config:list craftsuite_layer`), or the address is refused: see *Administration settings* → *Craft apps*. |
| The editor shows after 15 seconds "… has not answered yet" | The frame shows a sign-in (follow the link in the hint, sign in, reload), or the app may not be framed: `CRAFTSUITE_ALLOWED_ORIGINS` must contain your Nextcloud's address exactly as the browser shows it, and `--status` must show `Nextcloud yes`. Check the headers with `curl -sI https://craft.example.com/` (`frame-ancestors` with your Nextcloud, no `x-frame-options`). |
| "… did not start. Is it reachable at …?" after 90 seconds | The app does not load in the frame at all; same checks as above, and the browser console of the frame. |
| "… could not start: the app registered no drop target" / "failed to start" | The browser lacks WebGL 2 or the app failed to start; try the app directly at `https://craft.example.com/<app>/`. |

The editor page's messages are explained in the layer's
[Nextcloud app documentation](https://github.com/hozwei/nextcloud-craftsuite-layer/blob/v0.1.0/docs/nextcloud-app.md).

## The apps

| Symptom | Cause and fix |
|---|---|
| An app stays on its loading screen | Reload. If it stays, add `?webgl` to the address (forces WebGL 2); `?cpu` is the slowest, most compatible fallback. Both work in all four apps. |
| The start page shows a red notice | The last update run had an error; the apps run in their previous version. See the log of `craft-update`. |
| A new version does not appear | Browsers load it on the next page load; the update runs daily at `CRAFT_UPDATE_TIME` and takes a release only when it qualifies (age, canary). |

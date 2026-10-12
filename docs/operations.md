# Operations

Commands run on the Docker host. `docker exec` and `docker logs` work anywhere; `docker compose`
runs in the folder with `compose.yaml` and `.env`. The containers have fixed names: `craft-web`,
`craft-gate`, `craft-update`. On TrueNAS, see [truenas.md](truenas.md#everyday-commands) for the
`docker compose` steps.

## Status and logs

```sh
docker exec craft-update craft-update --status
```

```text
pdfcraft: 0.6.0 (previous 0.5.0, blocked -, Nextcloud yes)
photocraft: 0.7.0 (previous 0.6.0, blocked -, Nextcloud yes)
vectorcraft: 0.9.0 (previous 0.8.0, blocked -, Nextcloud yes)
designcraft: 0.6.0 (previous 0.5.0, blocked -, Nextcloud yes)
wordcraft: 0.5.0 (previous -, blocked -, Nextcloud yes)
gridcraft: 0.5.0 (previous -, blocked -, Nextcloud yes)
deckcraft: 0.5.0 (previous -, blocked -, Nextcloud yes)
cadcraft: 0.5.0 (previous -, blocked -, Nextcloud yes)
lightcraft: 0.6.0 (previous 0.5.0, blocked -, Nextcloud yes)
filmcraft: 0.6.0 (previous -, blocked -, Nextcloud yes)
effectcraft: 0.8.0 (previous 0.7.0, blocked -, Nextcloud yes)
layer: 0.2.0
OK 2026-10-12 07:00:41
```

Per app: the version served, the one a rollback goes back to, a blocked version, and whether the
served version carries the current translator (`yes`), not (`no`), or the integration is off
(`-`). Then the layer version, a `canary hold:` line if there is one, and the result of the last
run. `--status` changes nothing and makes no network requests.

```sh
docker compose ps
docker logs --tail 50 craft-update
docker logs --tail 50 craft-gate
docker logs --tail 50 craft-web
```

`craft-update` turns *unhealthy* when its last run had an error or is older than 26 hours.
`craft-gate` logs in UTC (its image has no time zone data); `craft-update` in `TZ`.

## Update now

The daily run takes a release only when it is `CRAFT_MIN_AGE_HOURS` old (and, with the canary
check, tested). To skip the minimum age, for example for an urgent fix:

```sh
docker exec -e CRAFT_MIN_AGE_HOURS=0 craft-update craft-update
```

The canary still applies; to skip it as well, add `-e CRAFTSUITE_CANARY=off`. The next daily run
keeps whatever is installed.

## Roll back

```sh
docker exec craft-update craft-update --rollback pdfcraft
```

Switches to the previous version (adding the current translator to it first) and blocks the
version you left: from now on only higher versions are taken. A second rollback has nothing to go
back to. To allow the blocked version again:

```sh
docker exec craft-update rm /craft/state/pdfcraft.blocked
```

## Hold back a release

To keep a release that is not installed yet from being taken (say you read about a problem),
block it in advance; the file holds a version such as `0.7.0`:

```sh
docker exec craft-update sh -c 'echo 0.7.0 > /craft/state/pdfcraft.blocked'
```

That version and every lower one are skipped; the next higher release is taken as usual.

## Adding apps

Add the app to `CRAFT_APPS` in `.env` (empty or missing: all eleven) and run
`docker compose up -d`. The run that follows installs, for each new app, the highest release that
qualifies: old enough by `CRAFT_MIN_AGE_HOURS` and, with the canary check, tested. If the newest
release is younger than `CRAFT_MIN_AGE_HOURS`, the app starts with an older one, possibly older
than the release the layer's adapters were checked against; the newest follows on a later run (or
[update now](#update-now)). While a canary issue is open or a canary failure holds new releases
([the canary hold](#the-canary-hold)), a new app is not installed, and each run reports it as an
error. With the Nextcloud integration on, also set the app's address in Nextcloud
([nextcloud.md](nextcloud.md#on-nextclouds-side), step 3).

## The canary hold

When the layer's canary has failed since your layer version came into use, `--status` shows
`canary hold: …` with the issue, every run logs an error, the start page shows a notice, and no
new app release is taken (see [how-it-works.md](how-it-works.md#the-canary)). Read the issue:

- **It concerns the apps** (a new app release breaks the translator): wait for a layer release with
  the fix, then [upgrade the layer](#upgrading-nextcloud-craftsuite-layer). That ends the hold.
- **It does not** (the issue says the test environment failed, or your layer version already has
  the fix): confirm, which also starts a run right away:

  ```sh
  docker exec craft-update sh -c 'rm -f /craft/state/canary-since && craft-update'
  ```

After either, failures count from that moment. While the issue is still open, new releases wait
(without an error); if it is still open after the next canary run (04:23 UTC plus three hours),
that run failed too and the hold comes back, so confirm again once it has passed (or run once with
`-e CRAFTSUITE_CANARY=off`). The releases whose first canary run failed stay skipped; later ones
are taken as usual.

## Upgrading nextcloud-craftsuite-layer

Translator and Nextcloud app come from the same layer release and move together. Read the
release's changelog first.

1. Take the checksum of the new hosting bundle from the release's `SHA256SUMS` (see
   [configuration.md](configuration.md#nextcloud-integration)) and set both values in `.env`:

   ```sh
   CRAFTSUITE_LAYER_VERSION=<version>
   CRAFTSUITE_LAYER_SHA256=<sha256 of craftsuite-layer-hosting-<version>.tar.gz>
   ```

2. Apply it. The updater starts, downloads and checks the bundle, and adds or updates the
   translator in the versions being served; when its run has finished, check:

   ```sh
   docker compose up -d
   docker compose logs -f update
   docker exec craft-update craft-update --status
   ```

3. Back up Nextcloud, then replace its app: download and check `craftsuite_layer-<version>.tar.gz`
   as in [nextcloud.md](nextcloud.md#on-nextclouds-side), delete the folder
   `custom_apps/craftsuite_layer`, unpack the new one, set its owner, then:

   ```sh
   occ upgrade
   occ app:list | grep craftsuite_layer
   ```

   The addresses of the apps stay, and so does a group restriction set with `app:enable -g`
   (`occ config:app:get craftsuite_layer enabled`); a plain `occ app:enable craftsuite_layer`
   would lift it. If the new release supports more apps, set their addresses
   ([nextcloud.md](nextcloud.md#on-nextclouds-side), step 3). Do steps 2 and 3 close together.

To go back, set the previous version and checksum again. For the Nextcloud app, the way back is
the backup from step 3: the layer's documentation does not cover installing an older app over a
newer one. Back at 0.1.0, PdfCraft, PhotoCraft, VectorCraft and DesignCraft get its translator
again; the seven newer apps are served without the Nextcloud integration, since 0.1.0 has no
adapter for them (`--status` shows `Nextcloud no`). No startup timeout is passed, since its
`inject-translator.sh` has no such option; `CRAFTSUITE_STARTUP_TIMEOUTS` can stay as it is.
EffectCraft keeps the layer's self-removing `sw.js` (it works, but not offline) until its next
release.

Before a Nextcloud major upgrade, install a layer release whose app supports the new version
first: the Nextcloud updater disables apps that do not declare it.

## Turning the Nextcloud integration off

1. In Nextcloud: `occ app:disable craftsuite_layer`. The Files entries are gone; the addresses
   stay for a later `occ app:enable`.
2. In `.env`, empty `CRAFTSUITE_LAYER_VERSION` and `CRAFTSUITE_ALLOWED_ORIGINS` (so that no site
   may frame the apps any more), then `docker compose up -d`.

New app releases then come without the translator. The versions being served keep it until their
next release; it does nothing, since no site may frame them. To remove it at once, with the layer
version that was in use (`docker exec craft-update ls /craft/layer`):

```sh
docker exec craft-update sh -c 'for a in $CRAFT_APPS; do sh /craft/layer/craftsuite-layer-hosting-0.2.0/hosting/inject-translator.sh -q --remove --app "$a" "/craft/www/$a"; done'
```

With 0.2.0 this also puts EffectCraft's own service worker back.

## Changing the Nextcloud address

Change `CRAFTSUITE_ALLOWED_ORIGINS` in `.env` and run `docker compose up -d`. `craft-web` starts
with the new `frame-ancestors`, and the updater rewrites the translator's list in the versions
being served.

## Staying informed

The pinned parts change only when you change them, so follow their releases. On GitHub, *Watch* →
*Custom* → *Releases* (and *Security alerts*) on
[hozwei/craftsuite-webapp](https://github.com/hozwei/craftsuite-webapp) and on
[hozwei/nextcloud-craftsuite-layer](https://github.com/hozwei/nextcloud-craftsuite-layer); add
*Issues* on the layer to hear about its canary (its issues labelled `canary`), or subscribe to the
releases feeds (`https://github.com/<owner>/<repo>/releases.atom`).

## Updating craftsuite-webapp

A new release of this repository brings, for example, a newer oauth2-proxy. Read
[CHANGELOG.md](../CHANGELOG.md), then:

```sh
git fetch --tags
git checkout v0.2.0
diff .env.example .env
docker compose up -d --build
```

Add any new settings from `.env.example` to `.env` before `up`. A `CRAFT_APPS` in `.env` keeps
the apps it names when a release supports more ([adding apps](#adding-apps)). To go back, check
out the previous tag and run `docker compose up -d --build` again. On TrueNAS, render the new
`compose.yaml` and paste it ([truenas.md](truenas.md#changing-settings)).

## Updating the containers

oauth2-proxy and nginx are pinned in `compose.yaml` (oauth2-proxy to a release, nginx to the 1.30
line). Security fixes within the nginx line and Alpine packages for the updater:

```sh
docker compose pull web gate
docker compose build --pull --no-cache update
docker compose up -d
```

When you change the updater's `dockerfile_inline`, also raise its image tag
(`craftsuite-webapp-update:2`, …); otherwise Docker keeps the old image.

## Backups and rebuilding

Nothing here holds user data. Keep `.env` (it has the two secrets) and know which release of this
repository you run. The data folder can be rebuilt at any time:

```sh
docker compose down
sudo rm -rf data/www data/state data/layer
docker compose up -d
```

The first run then takes the newest qualifying release of each app, which need not be the version
you had.

## Signing out and emergencies

- **Sign out:** sign out at the provider first, then open
  `https://craft.example.com/oauth2/sign_out`. In the other order, the redirect to the start page
  signs you in again at once, for a new `CRAFT_SESSION_LIFETIME`.
- **Block access right away:** `docker compose stop web`, or turn the host off in the reverse
  proxy.
- **End every session:** set a new `CRAFT_COOKIE_SECRET` and run `docker compose up -d`.
- **Take away one person's access:** remove them from the group at the provider. A running
  session stays valid until `CRAFT_SESSION_LIFETIME` has passed; end all sessions if that is too
  long.

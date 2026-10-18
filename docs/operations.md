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
pdfcraft: 0.8.0 (previous 0.7.1, blocked -, Nextcloud yes)
photocraft: 0.9.0 (previous 0.8.2, blocked -, Nextcloud yes)
vectorcraft: 0.11.0 (previous 0.10.0, blocked -, Nextcloud yes)
designcraft: 0.8.0 (previous 0.7.1, blocked -, Nextcloud yes)
wordcraft: 0.7.0 (previous 0.6.1, blocked -, Nextcloud yes)
gridcraft: 0.7.0 (previous 0.6.1, blocked -, Nextcloud yes)
deckcraft: 0.7.0 (previous 0.6.1, blocked -, Nextcloud yes)
cadcraft: 0.7.0 (previous 0.6.2, blocked -, Nextcloud yes)
lightcraft: 0.8.0 (previous 0.7.1, blocked -, Nextcloud yes)
filmcraft: 0.8.0 (previous 0.7.2, blocked -, Nextcloud yes)
effectcraft: 0.10.0 (previous 0.9.2, blocked -, Nextcloud yes)
soundcraft: 0.7.0 (previous -, blocked -, Nextcloud yes)
layer: 0.5.1
OK 2026-10-18 07:00:52
```

Per app of the list, and for every other app being served: the version served (`-` for one not
installed yet), the one a rollback goes back to, a blocked version, and whether the served version
carries the current translator (`yes`), not (`no`), or the integration is off (`-`). A version
below the app list's `minVersion` shows `Nextcloud - (older than <minVersion>, the oldest the layer
handles)`, and an app that is served but not in the list `, not in the app list` at the end. Then
the layer version, a `canary hold:` line if there is one, and the result of the last run.
`--status` changes nothing and makes no network requests.

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
back to. A previous version below the app list's `minVersion` gets no translator
(`pdfcraft: <version> is older than <minVersion>, the oldest release layer <version> handles (its app list): it runs without the Nextcloud integration`),
and every run reports an error until a higher release is taken. To allow the blocked version
again:

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

With `CRAFT_APPS=auto` (the default), the updater serves every app of the layer's app list: an
app that a new layer release adds comes when you
[upgrade the layer](#upgrading-nextcloud-craftsuite-layer). With a list of app ids, add the app's
id, or `auto`, to `CRAFT_APPS` in `.env` and run `docker compose up -d`
([configuration.md](configuration.md#the-app-list)).

The run that follows installs, for each new app, the highest release that qualifies: old enough
by `CRAFT_MIN_AGE_HOURS`, not below the app list's `minVersion` and, with the canary check,
tested. If the newest release is younger than `CRAFT_MIN_AGE_HOURS`, the app starts with an older
one, possibly older than the release the layer's adapters were checked against; the newest
follows on a later run (or [update now](#update-now)). With the canary check, though, an older
release qualifies only if it was still the newest of its app when the first canary run of your
layer version after it ended. If none qualifies, the app is missing, without an error, until its
newest release has passed its first run and is old enough
(`<app>: not installed yet, no release qualifies yet; a later run takes one (<version>: <reason>)`;
a release that cannot come is named with its reason instead, [troubleshooting.md](troubleshooting.md#updates)), or
`<app>: not installed yet, no release from <minVersion> on yet …` while all its releases are
older than `minVersion`). While an open canary issue names the app or a canary failure holds it
([the canary hold](#the-canary-hold)), a new app is not installed either; each run logs
`<app>: not installed yet, <version> waits (open canary issue)` (or `(canary failure)`), without
an error of its own.

With the Nextcloud integration on, Nextcloud gives the new app its entries at once if the address
for all apps is set (`apps_base_url`), otherwise once you set the app's own address
([nextcloud.md](nextcloud.md#on-nextclouds-side), step 3).

## Removing an app

Leave the app out of `CRAFT_APPS` in `.env` (`auto -<app>`, or remove its id from a list) and run
`docker compose up -d`. It then drops off the start page and gets no updates, but stays reachable
at `/<app>/`, with the translator it has, and every run logs
`<app>: <version> is served but not in the app list (CRAFT_APPS), so it gets no updates (operations.md, Removing an app)`.
An app that the layer's app list no longer has (with `auto`) is served the same way, but its
translator is removed
(`<app>: <version> is served, but the app list of layer <version> no longer has it: no updates and no Nextcloud integration (operations.md, Removing an app)`).
To delete it:

```sh
docker exec craft-update sh -c 'rm -rf /craft/www/<app> /craft/www/releases/<app>-* /craft/state/<app>.*'
```

In Nextcloud, switch the app off, so that Files no longer offers it (*Administration settings* →
*Craft apps*, or `occ config:app:set craftsuite_layer <app>_disabled --value=true --type=boolean`);
with a Nextcloud app before 0.5.0, delete its address instead
(`occ config:app:delete craftsuite_layer <app>_url`).

## The canary hold

When a canary run of your layer version has failed for some apps since that version came into
use, `--status` shows
`canary hold: the canary failed for <apps> (<link>) since layer <version> came into use; their new releases wait`
(or `canary hold: the canary failed (<link>) …` when it failed for every app), every run logs an
error, the start page shows a notice naming the apps, and no new release of those apps is taken;
the other apps are updated as usual ([how-it-works.md](how-it-works.md#the-canary), rule 3). Read
the issue (or the run, when it opened none):

- **It concerns the apps** (a new app release breaks the translator): wait for a layer release with
  the fix, then [upgrade the layer](#upgrading-nextcloud-craftsuite-layer). That ends the hold.
  The first canary run of the new layer version after the release that failed decides about it:
  if that run passed for the app and the release was still the app's newest, it comes by itself.
  To take a release anyway, [update now](#update-now) with `-e CRAFTSUITE_CANARY=off`; that run
  takes the newest release of every app in the list, untested.
- **It does not** (the issue says the test environment failed, or your layer version already has
  the fix): confirm, which also starts a run right away:

  ```sh
  docker exec craft-update sh -c 'rm -f /craft/state/canary-since && craft-update'
  ```

After either, failures count from that moment. While the issue is still open, the apps it names
wait (without an error); when the next run of your layer version fails for them again, the hold
comes back. After a confirmation, a release whose first run of your layer version failed for its
app stays out; later releases are taken as usual.

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

   With `CRAFT_APPS=auto`, an app that the new app list adds is installed in this run if one of
   its releases qualifies, and `--status` lists it. From now on only the canary runs of the new
   layer version count ([how-it-works.md](how-it-works.md#the-canary)): until its first run, new
   releases wait (`layer: no canary run has tested layer <version> yet; new releases wait for one`),
   and a release that the old version held back comes once that run has passed it, if it is still
   its app's newest release.

3. Back up Nextcloud. `occ upgrade` below also updates every App Store app that has an update
   pending, so first see which those are:

   ```sh
   occ app:update --showonly
   ```

   Then replace the app: download and check `craftsuite_layer-<version>.tar.gz` as in
   [nextcloud.md](nextcloud.md#on-nextclouds-side), delete the folder
   `custom_apps/craftsuite_layer`, unpack the new one, set its owner, then:

   ```sh
   occ upgrade
   occ app:list | grep craftsuite_layer
   occ config:app:get craftsuite_layer file_types
   ```

   From 0.3.0 on, the app has a repair step that registers its file types. Nextcloud 34 shows its
   line (`… file types registered, … existing files retyped.`) only with `occ upgrade -v`; if the
   web server's user cannot write Nextcloud's `config/` folder, that line says so instead
   (`Nextcloud's config folder cannot be written (see the log): …`), and the files whose
   extensions Nextcloud does not know keep Nextcloud's icons
   ([nextcloud.md](nextcloud.md#on-nextclouds-side)). Without `-v`, check with `file_types`: it
   shows, as JSON with `mappings` and `aliases`, the entries the app added (from 0.5.0 on, with
   `scraftz`). The addresses of the apps stay, and so does a group restriction set with
   `app:enable -g` (`occ config:app:get craftsuite_layer enabled`); a plain
   `occ app:enable craftsuite_layer` would lift it.

   From Nextcloud app 0.5.0 on, one address for all apps (`apps_base_url`) can stand for every
   app ([nextcloud.md](nextcloud.md#on-nextclouds-side), step 3). With it, an app that a new
   release of the Nextcloud app brings has its entries at once: switch it off
   (`<app>_disabled`) until the hosting serves it, or upgrade Nextcloud only after `--status`
   shows the app. Without it, set the new apps' addresses. Do steps 2 and 3 close together, step 2
   first.

To go back, set the previous version and checksum again. For the Nextcloud app, the layer's
documentation describes the way back
([Installing](https://github.com/hozwei/nextcloud-craftsuite-layer/blob/v0.5.2/docs/nextcloud-app.md#installing)):
put the older release's folder in place and run `occ upgrade` (tested from 0.5.0 to 0.4.2 and
back). The file types the newer version added go (`.scraftz`), and on 0.4.x an app that took its
address from `apps_base_url` has no entries; the backup from step 3 is for the App Store apps
that the same `occ upgrade` updated.

Back at a layer before 0.5.0 there is no app list: with `CRAFT_APPS=auto` every run reports an
error (the installed apps are still kept up to date), so name the apps in `CRAFT_APPS`, and set
`CRAFTSUITE_STARTUP_TIMEOUTS=lightcraft=180000 effectcraft=180000`
([configuration.md](configuration.md#the-app-list)). Those layers have no adapter for SoundCraft:
in the list, it is served without the Nextcloud integration (`--status` shows `Nextcloud no`).
Back at 0.1.0, PdfCraft, PhotoCraft, VectorCraft and DesignCraft get its translator again; the
newer apps are served without the Nextcloud integration, since 0.1.0 has no adapter for them. No
startup timeout is passed, since its `inject-translator.sh` has no such option. EffectCraft keeps
the layer's self-removing `sw.js` (it works, but not offline) until its next release.

Before a Nextcloud major upgrade, install a layer release whose app supports the new version
first: the Nextcloud updater disables apps that do not declare it.

## Turning the Nextcloud integration off

1. In Nextcloud: `occ app:disable craftsuite_layer`. The Files entries are gone; the addresses
   stay for a later `occ app:enable`.
2. In `.env`, empty `CRAFTSUITE_LAYER_VERSION` and `CRAFTSUITE_ALLOWED_ORIGINS` (so that no site
   may frame the apps any more), then `docker compose up -d`.

New app releases then come without the translator. Without the layer there is no app list:
`CRAFT_APPS=auto` then stands for the apps installed, which are still kept up to date; name an
app to add it ([configuration.md](configuration.md#the-app-list)). The versions being served keep
the translator until their next release; it does nothing, since no site may frame them. To remove
it at once from every app being served, with the injector of the layer version that was in use,
whose bundle stays in the data folder (`docker exec craft-update ls /craft/layer` shows it):

```sh
docker exec craft-update sh -c 'for l in /craft/www/*; do [ -L "$l" ] || continue; sh /craft/layer/craftsuite-layer-hosting-*/hosting/inject-translator.sh -q --remove --app "${l##*/}" "$l"; done'
```

From layer 0.2.0 on, this also puts EffectCraft's own service worker back.

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
git checkout v0.4.0
diff .env.example .env
docker compose up -d --build
```

Add any new settings from `.env.example` to `.env` before `up`, and follow the release's notes on
upgrading in the changelog (from 0.3.0: move to layer 0.5.0 or later in the same step, and set
`CRAFT_APPS=auto`). A list of app ids in `CRAFT_APPS` keeps serving the apps it names; `auto`
follows the layer's app list ([adding apps](#adding-apps)). To go back, check
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
you had. With the canary check, an older release qualifies only if it was still the newest of its
app when the first canary run of your layer version after it ended, and one older than all of the
canary's last 100 runs not at all, so an app can be missing, with the status `OK`, until
its newest release has passed its first run and is `CRAFT_MIN_AGE_HOURS` old. While no app is
installed, the start page says so: "No app is installed yet; the log of craft-update says why."
Without the Nextcloud integration, name the apps in `CRAFT_APPS` first: `auto` then stands for the
installed apps, and a rebuilt data folder has none.

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

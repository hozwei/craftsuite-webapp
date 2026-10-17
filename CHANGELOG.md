# Changelog

## [Unreleased]

## [0.4.1] - 2026-10-17

- **`tools/render-compose.sh --compact`** puts the updater into the YAML compressed (gzip, then
  base64), and the container unpacks it at start, byte for byte the same script. TrueNAS SCALE
  refuses a YAML of more than 64 KiB (the page reloads and says the session expired), and since
  0.4.0 the updater alone is larger; with `--compact` the YAML is about 44 KB. `compose.yaml` and
  the updater are unchanged from 0.4.0 ([truenas.md](docs/truenas.md#install)).

## [0.4.0] - 2026-10-17

The apps come from the app list of nextcloud-craftsuite-layer, SoundCraft joins, and the canary
is read per app and per layer version. Needs nextcloud-craftsuite-layer 0.5.0 or later for the app
list; `.env.example` names 0.5.1.

- **The app list.** `CRAFT_APPS=auto`, the new default, serves the apps that `apps.json` of the
  pinned layer release lists, in its order, so that an app a new layer release adds is served
  without a change here. `auto -lightcraft` leaves one out, `auto <app>` adds one, and a list of
  app ids works as before. An app that a later layer release no longer lists stays served, without
  updates and without the Nextcloud integration, until you remove it
  ([operations.md](docs/operations.md#removing-an-app)).
- **Values from the app list** replace the built-in ones: the name, the short German and English
  text and the colour on the start page (several colours change slightly), the startup timeout
  (180000 ms for LightCraft and EffectCraft) and the oldest release the layer's adapter handles
  (`minVersion`): older releases are never taken, and a version below it that is being served
  (after a rollback, say) runs without the translator, with an error, until a newer one is taken.
  Every value is checked first; an app whose entry is invalid gets no update. When the app list
  cannot be read, nothing changes, and the start page keeps the last one that could
  (`state/app-list`). An app named in `CRAFT_APPS` that the list does not have is not tested by the
  layer's canary: only the minimum age applies to it.
- **SoundCraft** (0.6.1 and later, with layer 0.5.0 and later): audio sessions, `.scraftz`.
- **`CRAFTSUITE_STARTUP_TIMEOUTS`** now defaults to empty; an entry still overrides the app
  list's value for its app.
- **The canary per app.** A failed canary run holds back only the apps its report names (the
  line `canary-result {...}` the layer writes into its `canary` issue since 0.5.0), or all apps
  when it names none or has no report. This applies to all three rules: an open issue holds the
  apps its reports and labels name, and a failure since the layer came into use holds those apps,
  with an error, until another layer version is in use or you confirm (a failure only of apps you
  do not serve is a log line, not an error). `state/canary-failed` gets a third line with the apps.
  Only reports written by the workflow (`github-actions[bot]`) count,
  and each one seen is kept in `state/canary-reports`, so that a later page of comments cannot
  lose it.
- **Only runs of the pinned layer count.** The updater reads the layer version each run tested from
  `translators/core.js` at the run's commit (on raw.githubusercontent.com, no API request, kept in
  `state/canary-layers`). A release is taken only if the first run of the pinned layer version
  after it tested and passed it. This replaces the rule that a release whose first run failed is
  never taken: after a fix in a new layer release, the first run of that release decides, so the
  releases a failure held back come by themselves once you move to it (0.3.0 needed a run without
  the canary). Runs of a newer layer release do not count either: releases that come out after it
  wait until you move to it, and three days after the newest run of your layer version this is an
  error that says so.
- **Stricter about what a run tested.** A run that is still running (also the re-run of an older
  one) holds the releases it is the first run for; a re-run that ended otherwise (`cancelled`,
  `timed_out`, ...) counts as failed for the apps its earlier attempts' reports name, else for all;
  a release that was not the highest version out when the run ended, or that the run's report
  says it did not fetch, counts as untested; when the list
  of the last 100 runs is full, a release older than all of them is not taken. For a release that
  waits, the log now says why (`... qualifies yet (<version>: <reason>)`), and says so when it
  will not come with this layer version.
- **A new app while a canary issue is open** waits without an error (0.3.0 reported one on every
  run).
- **GitHub requests:** fifteen API requests per run with twelve apps (one per app, the canary's
  runs, its issues and, while a failed run or a re-run is listed, the comments of the issues),
  and one plain download per new commit the canary ran on.
- The start page says "audio" in its tagline; a canary hold names the apps it holds.
- docs/operations.md: `occ upgrade` shows the Nextcloud app's repair step only with `-v`.

Upgrading from 0.3.0 ([docs/operations.md](docs/operations.md#updating-craftsuite-webapp)):

- Move to layer 0.5.0 or later in the same step: set `CRAFTSUITE_LAYER_VERSION` and
  `CRAFTSUITE_LAYER_SHA256` of the new release, and upgrade the Nextcloud app to the same version
  ([docs/nextcloud.md](docs/nextcloud.md#on-nextclouds-side)). There, one address for all apps
  (`apps_base_url`) gives new apps their entries without a setting of their own.
- Set `CRAFT_APPS=auto` (or remove the line) to serve every app the layer lists, SoundCraft
  included; an explicit list keeps serving the apps it names.
- Remove `CRAFTSUITE_STARTUP_TIMEOUTS=lightcraft=180000 effectcraft=180000` if you have it: the
  app list recommends the same values.
- With a layer before 0.5.0 there is no app list: name the apps in `CRAFT_APPS` and set
  `CRAFTSUITE_STARTUP_TIMEOUTS` yourself; the start page then shows the app ids without texts and
  colours, and no `minVersion` applies.
- Going back to 0.3.0 keeps the data folder: 0.3.0 reads the first two lines of
  `state/canary-failed` and ignores the new state files, and an app it does not list (SoundCraft)
  stays served without updates.
- Since 0.3.0 the documentation and `.env.example` named layer 0.4.2 (on `main` since 2026-10-16);
  they now name 0.5.1.

## [0.3.0] - 2026-10-12

Canary runs instead of a fixed schedule, and nextcloud-craftsuite-layer 0.4.0.

- The updater reads the runs of the layer's canary (`canary.yml` on `main`) instead of assuming a
  run at 04:23 UTC every day: GitHub starts scheduled runs late, skips some and turns schedules
  off after 60 days without activity. Runs that ended with `success` or `failure` count; a
  cancelled run tested nothing. A run starts at its creation (`created_at`): `run_started_at`
  resets on a re-run, and a re-run of failed jobs keeps the canary job's earlier result. A run
  passed if no `canary` issue was open at its check time, a minute after its end (but not after
  the next counted run's start, and never before its own end); a re-run only if none was open at
  any time during it. A release is taken only once the first counted run that started after it
  (after its last upload) has passed and no newer release of the app came out before that run
  ended. A run that failed without a `canary` issue (usually only the layer's look at the next
  Nextcloud release failed) counts as passed. Only the last 100 finished runs are looked at.
- A release whose first run did not pass is never taken, as in 0.2.0: later runs test the layer's
  main branch, not the pinned layer. The app's next release that passes its own first run is.
- A canary failure since the layer version came into use is an issue opened since then, or one
  open at the check time of the first counted run that started since then (for a re-run, at any
  time during it). Once found, it holds until another layer version is in use or you confirm, also
  when its run is re-run or drops out of the last 100 runs: `state/canary-failed` now has a second
  line with the layer version and time the failure belongs to.
- Without a canary run, new releases now wait; 0.2.0 took them as if they had passed. Every run
  logs the newest canary run (`layer: newest canary run started <time> (success)` or `(failure)`,
  followed by `, re-run`, then `, canary issue open` or `, no canary issue` where they apply,
  for example `(failure, no canary issue)`); when that run started more
  than three days ago, or there is none, it reports an error instead (status, start page, health
  check), which holds nothing: releases that an earlier run tested are still taken.
- A run makes up to thirteen GitHub API requests instead of twelve: one per app, the canary's runs
  and its issues. When the runs cannot be read, the run logs
  `layer: ERROR - cannot read the canary runs of …` and new releases wait
  (`<app>: <version> held back (canary runs not readable)`), as when the issues cannot be read.
- The start page says "No app is installed yet; the log of craft-update says why." whenever no app
  is installed, also after a run without errors: on a new data folder, that lasts until a release
  of an app has passed its first canary run and is `CRAFT_MIN_AGE_HOURS` old.
- Known limits ([docs/how-it-works.md](docs/how-it-works.md#the-canary)): a failed run without a
  `canary` issue also counts as passed when, rarely, its canary job was cancelled while the
  look-ahead failed, or its report job failed after a canary failure; a minimum age of two to three
  days leaves the next run time to report it (the default of 24 hours does not reliably). No GitHub
  token is sent. The error about a stopped canary ends only with a new counted run (a re-run of an
  older run does not count), or with the canary check off.
- Works with nextcloud-craftsuite-layer 0.4.0 (`.env.example` names it). Its hosting bundle has
  the same injector as 0.2.0 and translators 0.4.0, which can start eight of the apps in the
  language the Nextcloud app asks for; its Nextcloud app shows the entries only to the groups it
  is enabled for, and adds file type icons, a default app and "+ New" entries
  ([docs/nextcloud.md](docs/nextcloud.md#on-nextclouds-side)).

Upgrading from 0.2.0 ([docs/operations.md](docs/operations.md#updating-craftsuite-webapp)):

- Nothing to change in `.env` for the canary.
- Releases are taken only once the first canary run after them has tested and passed them; the
  installed versions stay.
- `CRAFT_MIN_AGE_HOURS` keeps its meaning. A release now also waits for its first canary run,
  whatever its age. The minimum age gives the projects time to withdraw a bad release and, at two
  to three days, the next canary run time to report a failure that the first one missed (see the
  known limits above); the default of 24 hours does not reliably cover the next run.
- Moving to layer 0.4.0 is optional: set `CRAFTSUITE_LAYER_VERSION=0.4.0` and its
  `CRAFTSUITE_LAYER_SHA256`, and upgrade the Nextcloud app to 0.4.0
  ([docs/operations.md](docs/operations.md#upgrading-nextcloud-craftsuite-layer)); `occ upgrade`
  also updates the App Store apps that have an update pending.
- A `state/canary-failed` left by 0.2.0 holds only if 0.3.0 finds the failure again. Going back to
  0.2.0 keeps the data folder as it is: 0.2.0 reads only the first line of that file.

## [0.2.0] - 2026-10-12

Seven more apps, and nextcloud-craftsuite-layer 0.2.0.

- The updater also follows WordCraft, GridCraft, DeckCraft, CADCraft, LightCraft, FilmCraft and
  EffectCraft; the default of `CRAFT_APPS` names all eleven apps. The start page shows each with
  its icon, colour and a description in English and German, under a new tagline. SoundCraft is
  not included: the layer does not support it (its web build can neither open nor save files).
- Works with nextcloud-craftsuite-layer 0.2.0 (`.env.example` names it), which has adapters for
  all eleven apps.
- New setting `CRAFTSUITE_STARTUP_TIMEOUTS`, default `lightcraft=180000 effectcraft=180000`: how
  long the translator waits for an app to start, in milliseconds, passed to `inject-translator.sh`
  on every call for that app (adding, `--check`, `--status`, rollback). LightCraft and EffectCraft
  load their `.wasm` while the translator's start timer runs, and its default of 60 seconds is too
  short below about 3 Mbit/s (LightCraft) and 2.4 Mbit/s (EffectCraft). A changed value updates
  the served versions on the next run. An invalid entry is an error, and new releases wait until
  it is fixed. Empty: no startup timeouts. The injector of layer 0.1.0 gets none.
- Before adding the translator, the updater removes the leftovers of a Cargo build from a release
  (LightCraft's zip holds its Cargo target folder) and Brotli copies (`*.br`); `.otf` files now
  get a `.gz` copy too.
- With layer 0.2.0, EffectCraft's service worker is replaced by the layer's worker that serves
  nothing, deletes the app's caches and unregisters itself: a worker registered by a direct visit
  would otherwise also control the Nextcloud frames.
- `craft-web` sends `Cache-Control: private, max-age=31536000, immutable` only for `.js`, `.mjs`
  and `.wasm` files whose names carry Trunk's content hash (before: for all of them except the
  translator files). Files that keep their names across releases, such as those of FilmCraft,
  LightCraft and EffectCraft, get `no-cache`, so browsers do not keep an old version next to a new
  `index.html`. `.otf` is served as `font/otf` and `.webmanifest` as `application/manifest+json`,
  both compressed, and HTML, plain text and JavaScript with `charset=utf-8`.

Upgrading from 0.1.0 ([docs/operations.md](docs/operations.md#updating-craftsuite-webapp)):

- An `.env` made from the 0.1.0 `.env.example` sets `CRAFT_APPS` to the four original apps and
  keeps serving only those. Name all eleven, as in `.env.example`, or remove the line. The next
  run installs each new app at its highest release that qualifies; that can be an older one while
  the newest is younger than `CRAFT_MIN_AGE_HOURS`, and the newest follows on a later run.
- The new apps open files from Nextcloud only with layer 0.2.0 on both sides: set
  `CRAFTSUITE_LAYER_VERSION=0.2.0` and its `CRAFTSUITE_LAYER_SHA256`, upgrade the Nextcloud app
  to 0.2.0 ([docs/operations.md](docs/operations.md#upgrading-nextcloud-craftsuite-layer)) and
  set its new keys `wordcraft_url`, `gridcraft_url`, `deckcraft_url`, `cadcraft_url`,
  `lightcraft_url`, `filmcraft_url` and `effectcraft_url`. The Nextcloud app 0.2.0 refuses app
  addresses with a query (`?…`). With layer 0.1.0 the new apps are served without the integration.
- `CRAFTSUITE_STARTUP_TIMEOUTS` is new; without it in `.env`, its default applies.
- If 0.1.0 served FilmCraft, LightCraft or EffectCraft, browsers may keep their files for up to a
  year (0.1.0 sent `immutable` for them): clear the cached files in those browsers once (not the
  site data, which holds what LightCraft and FilmCraft keep from direct visits).
- Going back to layer 0.1.0 needs no other change: the seven new apps are then served without the
  integration, and no startup timeout is passed. EffectCraft keeps the layer's self-removing
  `sw.js` (it works, but not offline) until its next release.
- Plan about 1.5 GB for the data folder instead of 450 MB. A run makes up to twelve GitHub API
  requests instead of five, of the 60 per hour that all machines behind the same public IP address
  share.

## [0.1.0] - 2026-10-11

First release.

- Compose file with three containers: nginx in front (`craft-web`), oauth2-proxy for the
  OpenID Connect sign-in behind it (`craft-gate`, asked per request through `auth_request`), and an
  Alpine updater (`craft-update`).
- The updater follows the GitHub releases of PdfCraft, PhotoCraft, VectorCraft and DesignCraft:
  highest version that is old enough, two checksums, archive checks, atomic switch, rollback,
  blocking, retries after errors.
- Optional Nextcloud integration with nextcloud-craftsuite-layer: pinned hosting bundle, translator
  added before compression and kept current in the served versions; app releases are taken only
  if the layer's canary reported no failure for them, and a canary failure holds new releases
  until another layer version is in use or the operator confirms. `frame-ancestors` on every
  response, including the sign-in pages.
- Start page in English or German.
- `tools/render-compose.sh` for TrueNAS SCALE custom apps and other single-file setups;
  `tools/build-compose.sh` builds `compose.yaml` from `src/`.

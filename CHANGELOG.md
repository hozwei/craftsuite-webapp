# Changelog

## [Unreleased]

- The documentation and `.env.example` use nextcloud-craftsuite-layer 0.4.2 instead of 0.4.0:
  `CRAFTSUITE_LAYER_VERSION=0.4.2` with the checksum of its hosting bundle, the download of the
  Nextcloud app and the links to the layer's documentation. Its translators handle the Craft
  releases of 2026-10-14 (0.4.1 handled those of 2026-10-12, 0.4.0 the earlier ones); its
  Nextcloud app only has a new version number. `compose.yaml` is unchanged.

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

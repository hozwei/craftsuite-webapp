# Changelog

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

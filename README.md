# craftsuite-webapp

Self-host the Craft web apps — **PdfCraft**, **PhotoCraft**, **VectorCraft**, **DesignCraft**,
**WordCraft**, **GridCraft**, **DeckCraft**, **CADCraft**, **LightCraft**, **FilmCraft**,
**EffectCraft** and **SoundCraft**, published by [storytold](https://github.com/storytold) — behind
a sign-in, keep them up to date from their GitHub releases, and let **Nextcloud** open files in
them.

Everything is one Docker Compose file with three small containers. The apps run entirely in the
browser: the server only hands out static files and never sees a user's documents.

```text
browser ──HTTPS──▶ your reverse proxy ──▶ web (nginx) ──▶ static files: start page and the apps
                                            │
                                            └─ asks about every request ──▶ gate (oauth2-proxy)
                                                                              │
                                         OpenID Connect provider (e.g. Nextcloud) ◀─ sign-in

update (daily) ──▶ GitHub releases: download, verify, add translator, compress, switch
```

## What you get

- **The twelve apps under one host name**, one path each: `https://craft.example.com/pdfcraft/`,
  `/photocraft/`, `/vectorcraft/`, `/designcraft/`, `/wordcraft/`, `/gridcraft/`, `/deckcraft/`,
  `/cadcraft/`, `/lightcraft/`, `/filmcraft/`, `/effectcraft/`, `/soundcraft/`, and a start page
  with all of them. With the Nextcloud integration on, the apps, their names, texts and colours
  and the oldest release of each that can be used come from the app list of
  nextcloud-craftsuite-layer (0.5.0 and later), so an app that a new layer release adds is served
  without a change here. FigCraft is not in it yet.
- **A sign-in in front of everything** (oauth2-proxy with any OpenID Connect provider; Nextcloud's
  `oidc` app works well). Nobody without an account at your provider reaches the apps.
- **Careful automatic updates.** Once a day the updater looks at each app's releases and takes
  the newest version that is a day old, whose checksum matches both the release's
  `SHA256SUMS.txt` and GitHub's digest, and whose archive holds nothing but the expected folder.
  It switches in one step and keeps the previous version for a one-command rollback; it never
  goes back to a lower version by itself.
- **Optional Nextcloud integration** through
  [nextcloud-craftsuite-layer](https://github.com/hozwei/nextcloud-craftsuite-layer): the updater
  adds the layer's small translator script to each app, the web server allows your Nextcloud to
  frame the apps, and Nextcloud gets "Open in PdfCraft" and friends. Files open from Nextcloud and
  save back to it, as the signed-in user, without a download. App releases are taken only once the
  first run of the layer's canary for your layer version after them has tested them and passed
  for their app; a canary failure holds back the new releases of the apps it names until you
  upgrade the layer or confirm, and a canary that stopped running is reported after three days
  (limits: [docs/how-it-works.md](docs/how-it-works.md#the-canary)).
- **Locked-down containers**: read-only file systems, no capabilities, unprivileged users; only
  the web container is reachable from outside.

## Requirements

- A Linux host with Docker Engine and Docker Compose 2.17 or later (for `dockerfile_inline`), or
  TrueNAS SCALE 24.10 or later with custom apps ([docs/truenas.md](docs/truenas.md)).
- A host name for the apps (`craft.example.com`) and a reverse proxy that serves it over HTTPS
  and forwards to this stack ([docs/reverse-proxy.md](docs/reverse-proxy.md)).
- An OpenID Connect provider, reachable from the Docker host at its public issuer URL (the gate
  fetches its configuration, keys and tokens; for a provider in the same network this may need
  hairpin NAT or split DNS). For Nextcloud as the provider and for the Nextcloud integration:
  Nextcloud 34 or 35, see [docs/nextcloud.md](docs/nextcloud.md).
- Outgoing HTTPS from the Docker host to `api.github.com`, `github.com`,
  `release-assets.githubusercontent.com` and `raw.githubusercontent.com`. With the twelve apps a
  run makes up to fifteen requests to the GitHub API, of the 60 per hour that all machines behind
  the same public IP address share.
- Browsers with WebGL 2. The apps are desktop-sized; a tablet works, a phone is cramped.

## Quick start

```sh
git clone https://github.com/hozwei/craftsuite-webapp.git
cd craftsuite-webapp
cp .env.example .env && chmod 600 .env
```

1. **Create an OpenID Connect client** at your provider with the redirect URL
   `https://craft.example.com/oauth2/callback`, and limit it to the people who may use the apps.
   For Nextcloud: [docs/nextcloud.md](docs/nextcloud.md#1-sign-in-with-nextcloud).
2. **Fill in `.env`**: at least `CRAFT_HOST`, `CRAFT_OIDC_ISSUER_URL`, `CRAFT_OIDC_CLIENT_ID`,
   `CRAFT_OIDC_CLIENT_SECRET` and a new `CRAFT_COOKIE_SECRET`:

   ```sh
   openssl rand -base64 32 | tr -- '+/' '-_'
   ```

   The Nextcloud integration stays off until you set its three values
   ([docs/nextcloud.md](docs/nextcloud.md#2-open-files-from-nextcloud)). Without it,
   `CRAFT_APPS=auto` has no app list to take the apps from: name them instead, such as
   `CRAFT_APPS=pdfcraft photocraft vectorcraft` ([docs/configuration.md](docs/configuration.md#the-app-list)).
   Every setting: [docs/configuration.md](docs/configuration.md).
3. **Create the data folder** for the user the updater runs as (`CRAFT_USER`, default 1000):

   ```sh
   mkdir -p data && sudo chown -R 1000:1000 data
   ```

4. **Start it:**

   ```sh
   docker compose up -d --build
   docker compose logs -f update
   ```

   The first run downloads the twelve apps (about 210 MB; about 580 MB on disk with the compressed
   copies; plan about 1.5 GB for the previous versions and updates) and writes the start page. An
   app whose releases are all too young, or not yet tested by the layer's canary, follows with a
   later run, and so does one that an open canary issue names (without an error).
5. **Point your reverse proxy** at port `CRAFT_PORT` (default 8080) and open
   `https://craft.example.com`. You are sent to your provider, sign in, and land on the start
   page.

Then, if you use Nextcloud: turn on the integration as described in
[docs/nextcloud.md](docs/nextcloud.md#2-open-files-from-nextcloud).

## Documentation

| Page | Contents |
|---|---|
| [docs/how-it-works.md](docs/how-it-works.md) | The three containers, the update procedure, the canary, the headers, the security model |
| [docs/configuration.md](docs/configuration.md) | Every setting in `.env` |
| [docs/reverse-proxy.md](docs/reverse-proxy.md) | What the reverse proxy must and must not do, with examples |
| [docs/nextcloud.md](docs/nextcloud.md) | Nextcloud as the sign-in provider, and opening files from Nextcloud |
| [docs/operations.md](docs/operations.md) | Status, logs, updating now, rollback, holding back a release, adding and removing apps, the canary hold, upgrading the layer and this stack, staying informed, backups |
| [docs/truenas.md](docs/truenas.md) | Running it as a TrueNAS SCALE custom app |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Symptoms, causes and fixes |
| [docs/development.md](docs/development.md) | Where the scripts live, building `compose.yaml`, checking a change |

## Versions

This release pins oauth2-proxy v7.15.5, nginx 1.30 (`nginxinc/nginx-unprivileged:1.30-alpine-slim`)
and Alpine 3.24 for the updater, as 0.2.0 did; only the updater changed since 0.3.0. Before the
release, the updater from the generated `compose.yaml` ran in a local setup, with GitHub's answers
of 2026-10-17 (releases, the layer's canary runs, issues and comments) saved or made up for each
case, against the web builds of PdfCraft 0.8.0, PhotoCraft 0.9.0, VectorCraft 0.11.0 and 0.12.0,
DesignCraft 0.8.0, WordCraft, GridCraft, DeckCraft and CADCraft 0.7.0, LightCraft 0.8.0, FilmCraft
0.8.0, EffectCraft 0.10.0 and SoundCraft 0.6.1 and 0.7.0, with nextcloud-craftsuite-layer 0.5.1
(also on the way from craftsuite-webapp 0.3.0 with layer 0.4.2 and back). For 0.4.2, which changes
only how an open canary issue holds apps, the same setup ran again with GitHub's answers of
2026-10-18 and nextcloud-craftsuite-layer 0.5.2, from 0.4.1 with layer 0.5.1 and back, against the
web builds of PdfCraft 0.9.0, PhotoCraft 0.10.0, VectorCraft 0.13.1, DesignCraft 0.9.0, WordCraft,
GridCraft and CADCraft 0.8.0, LightCraft 0.9.1, FilmCraft 0.9.0, EffectCraft 0.11.1 and SoundCraft
0.8.0 (DeckCraft stays at 0.7.0: the canary failed for 0.8.0). For 0.5.0 (`auto` for the layer),
the same setup ran with made-up layer releases (newer, lower, drafts, without GitHub's checksum,
with a wrong one, with another protocol version, waiting for or failing its canary run, on a
first installation) and with GitHub's answers of 2026-10-18, where `auto` moved a copy from
layer 0.5.1 to 0.5.2. nginx, oauth2-proxy and their configuration are unchanged from 0.2.0, where
their headers were checked. Opening and saving from Nextcloud is tested by the layer itself, for
the Craft versions its release lists. The Craft apps are not pinned here: the updater follows
their releases, and with `auto` the layer's too.

## Affiliation and trademarks

This project is not affiliated with, endorsed by or sponsored by storytold, the ArtCraft Team or
Nextcloud GmbH. PdfCraft, PhotoCraft, VectorCraft, DesignCraft, WordCraft, GridCraft, DeckCraft,
CADCraft, LightCraft, FilmCraft, EffectCraft, SoundCraft, ArtCraft and Nextcloud are names or
trademarks of their respective owners and are used here only to say what this project works with.
The apps are © the ArtCraft Team and their contributors, licensed MIT OR Apache-2.0; their bundled
fonts, icons and other assets keep their own licences (SIL OFL, ISC, CC BY 3.0 and others), listed
in `ATTRIBUTION.md` or `ASSETS.md` in each app's repository. The licence and notice files of the
web builds stay in every folder that is served. With the Nextcloud integration on, the served
builds carry the layer's translator (EffectCraft also the layer's replacement for its service
worker) and are not official ArtCraft builds.

## Licence

MIT, see [LICENSE](LICENSE). This repository contains neither the Craft apps nor
nextcloud-craftsuite-layer (AGPL-3.0-or-later): the updater downloads them from their releases.

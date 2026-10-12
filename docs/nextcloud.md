# Nextcloud

Nextcloud can play two roles, independently of each other:

1. **The sign-in provider** for the apps, with the Nextcloud app *OIDC Identity Provider*
   (`oidc`). People sign in with their Nextcloud account, second factor included.
2. **The place files are opened from**, with the Nextcloud app `craftsuite_layer` of
   [nextcloud-craftsuite-layer](https://github.com/hozwei/nextcloud-craftsuite-layer): Files gets
   "Open in PdfCraft" and similar entries, the app opens on an editor page inside Nextcloud, and
   saving stores the file back in Nextcloud.

`occ` below stands for the Nextcloud command line, run as the web server user. With the official
Docker image:

```sh
docker exec -u www-data <nextcloud-container> php occ …
```

Take a backup (database and config) before installing apps, as for any change to Nextcloud.

## 1. Sign in with Nextcloud

Tested with the `oidc` app 2.5.2 on Nextcloud 34. Its commands and settings may differ in other
versions; read its [releases](https://github.com/H2CK/oidc/releases) before updating it, and
remember that `occ app:update --all` and every Nextcloud upgrade update it too.

1. Install the app:

   ```sh
   occ app:install oidc
   ```

2. Check the issuer; `CRAFT_OIDC_ISSUER_URL` must be exactly this value (the `tr` removes the
   backslashes that JSON may put before slashes):

   ```sh
   curl -fsSL https://cloud.example.com/.well-known/openid-configuration | grep -o '"issuer":"[^"]*"' | tr -d '\\'
   ```

3. Create a group for the people who may use the apps and add them:

   ```sh
   occ group:add --display-name='Craft apps' craft
   occ group:adduser craft alice
   ```

4. Create the client. The answer shows the `client_secret` once: put it into `.env` as
   `CRAFT_OIDC_CLIENT_SECRET` (and into your password manager), and the `client_id` as
   `CRAFT_OIDC_CLIENT_ID`. The app requires a client ID of 32 to 64 printable characters without
   `:`:

   ```sh
   occ oidc:create craft https://craft.example.com/oauth2/callback --type=confidential --flow=code --algorithm=RS256 --token_type=opaque --allowed_scopes=openid --client_id=craft-example-com-oauth2-proxy-gate
   ```

5. Limit the client to the group; `occ` cannot do this. *Administration settings* → *OpenID
   Connect Provider* → tab *Clients* → click the client → *Group Limitations*: `craft` → *Save*.
   Without it, every Nextcloud account can sign in.
6. On the tab *Settings*, leave *Allow User Settings* at "User cannot edit any settings" (the
   default); otherwise everybody has to give consent at their first sign-in.

Then start the stack. People outside the group get Nextcloud's "Access forbidden" page instead of
the apps. `occ oidc:list` shows every client's secret in plain text: do not paste its output
anywhere.

## 2. Open files from Nextcloud

Requirements: Nextcloud 34 or 35, the apps on a host name of their own under the same
registrable domain as Nextcloud (`craft.example.com` next to `cloud.example.com`), and the same
release of nextcloud-craftsuite-layer on both sides. This page uses 0.4.0.

### On the apps' side

In `.env`:

```sh
CRAFTSUITE_ALLOWED_ORIGINS=https://cloud.example.com
CRAFTSUITE_LAYER_VERSION=0.4.0
CRAFTSUITE_LAYER_SHA256=2d0e8e3c795193d800b8316b28db545e5be24e0ab45e8423114adfd38bc2be1d
```

`CRAFTSUITE_ALLOWED_ORIGINS` is your Nextcloud's address exactly as the browser shows it, without
a path and without a slash at the end (`https://cloud.example.com`, `https://cloud.example.com:8443`).
Several Nextcloud servers: separate them with spaces. Then:

```sh
docker compose up -d
docker compose logs -f update
```

When the run has finished (a line for each app), check:

```sh
docker exec craft-update craft-update --status
```

Every app should show `Nextcloud yes`, and the last line `OK …`. The updater has downloaded the
layer's hosting bundle, checked it against the checksum, and added the translator to the
versions being served.

### On Nextcloud's side

1. Download the app and check it:

   ```sh
   cd "$(mktemp -d)"
   curl -fLO https://github.com/hozwei/nextcloud-craftsuite-layer/releases/download/v0.4.0/craftsuite_layer-0.4.0.tar.gz
   curl -fLO https://github.com/hozwei/nextcloud-craftsuite-layer/releases/download/v0.4.0/SHA256SUMS
   sha256sum -c --ignore-missing SHA256SUMS
   ```

2. Unpack it into Nextcloud's `custom_apps` folder (`/var/www/html/custom_apps` in the official
   image; on the host, wherever that folder is mounted), owned by the web server user (33:33 in the
   official image), and enable it:

   ```sh
   tar -xzf craftsuite_layer-0.4.0.tar.gz -C /path/to/nextcloud/custom_apps
   chown -R 33:33 /path/to/nextcloud/custom_apps/craftsuite_layer
   occ app:enable craftsuite_layer
   ```

   To offer it only to the group that may use the apps, enable it with
   `occ app:enable -g craft craftsuite_layer` instead; check with
   `occ config:app:get craftsuite_layer enabled` (expect `["craft"]`).
3. Set the addresses of the apps you serve, with the slash at the end; the app refuses an address
   with a query (`?…`). An app without an address has no entry in Files:

   ```sh
   occ config:app:set craftsuite_layer pdfcraft_url --value=https://craft.example.com/pdfcraft/
   occ config:app:set craftsuite_layer photocraft_url --value=https://craft.example.com/photocraft/
   occ config:app:set craftsuite_layer vectorcraft_url --value=https://craft.example.com/vectorcraft/
   occ config:app:set craftsuite_layer designcraft_url --value=https://craft.example.com/designcraft/
   occ config:app:set craftsuite_layer wordcraft_url --value=https://craft.example.com/wordcraft/
   occ config:app:set craftsuite_layer gridcraft_url --value=https://craft.example.com/gridcraft/
   occ config:app:set craftsuite_layer deckcraft_url --value=https://craft.example.com/deckcraft/
   occ config:app:set craftsuite_layer cadcraft_url --value=https://craft.example.com/cadcraft/
   occ config:app:set craftsuite_layer lightcraft_url --value=https://craft.example.com/lightcraft/
   occ config:app:set craftsuite_layer filmcraft_url --value=https://craft.example.com/filmcraft/
   occ config:app:set craftsuite_layer effectcraft_url --value=https://craft.example.com/effectcraft/
   occ config:list craftsuite_layer
   ```

4. In *Administration settings* → *Craft apps*, each address must appear without an error message.
   "The Craft app must be hosted on another host name than Nextcloud" means the apps' host name is
   one of Nextcloud's `trusted_domains`: remove it there.

In Files, a PDF now has "Open in PdfCraft" in its menu; PSD and IDML files open in PhotoCraft and
DesignCraft with a click, `.deckcraft` in DeckCraft, camera raw files (`.dng`, `.cr3`, `.nef`, …)
in LightCraft, `.fcproj` in FilmCraft, `.ecproj` in EffectCraft, and `.dxf` in CADCraft (in
VectorCraft if CADCraft has no address). Office files (`.docx`, `.xlsx`, `.pptx`, …) have
WordCraft, GridCraft and DeckCraft in their menu only, so a click on them stays with Nextcloud
Office, ONLYOFFICE or Euro-Office where one is installed; JPEG, PNG, TIFF and WebP pictures have
PhotoCraft and LightCraft in their menu only. A Craft app made the default app (below) takes the
click on all its types. FilmCraft and EffectCraft open and save their project files only: the
media a project uses are not in the file and are missing when it is opened from Nextcloud. The
layer's [Nextcloud app documentation](https://github.com/hozwei/nextcloud-craftsuite-layer/blob/v0.4.0/docs/nextcloud-app.md)
lists every file type, the editor page's messages and what happens on save.

What the Nextcloud app 0.3.0 and 0.4.0 added, in short; the settings and their limits are in the
layer's documentation, under
[Configuring](https://github.com/hozwei/nextcloud-craftsuite-layer/blob/v0.4.0/docs/nextcloud-app.md#configuring)
and [Files](https://github.com/hozwei/nextcloud-craftsuite-layer/blob/v0.4.0/docs/nextcloud-app.md#files):

- **Entries only for the enabled groups.** Enabled with `-g` (step 2), the app shows its entries
  in Files only to the members of those groups; before 0.3.0, everybody saw them.
- **The language each app starts in**, next to its address on the settings page, or
  `occ config:app:set craftsuite_layer <app>_language --value=…`: `user` (the user's Nextcloud
  language) or one of the app's languages, such as `de`; empty, the app decides. It needs
  translator 0.3.0 or later, so `CRAFTSUITE_LAYER_VERSION` 0.3.0 or later here. DesignCraft,
  WordCraft and DeckCraft always start in English.
- **File type icons**: Files shows the apps' icons on the files they open where Nextcloud has only
  a general icon (`.psd`, `.dxf`, camera raws, …). For the extensions Nextcloud does not know, the
  app writes MIME types into `config/mimetypemapping.json` and `config/mimetypealiases.json` when
  it is enabled or updated, so Nextcloud's `config/` folder must be writable for the web server's
  user; if it is not, enabling and updating still work: the app logs a warning, says so in the
  output of `occ`, and the files whose extensions Nextcloud does not know keep Nextcloud's icons.
  The MIME types apply to every account, also outside the enabled groups: `.dxf`, `.svgz`, `.wmf`,
  `.psb` and the camera raws `.cr3`, `.nrw`, `.rwl`, `.srw` then count as images, and `.eps` files
  lose the previews of Nextcloud's Postscript preview provider where it is enabled.
- **A default app**: PdfCraft, PhotoCraft, VectorCraft, WordCraft, GridCraft, DeckCraft and
  LightCraft can take the click on all their file types ("On a click" on the settings page, or
  `<app>_default_app`); the app that had the click before stays in the file's menu.
- **"+ New" entries** in Files for the apps' own formats; WordCraft, GridCraft and PdfCraft get one
  only as the default app.

### Nextcloud's own headers

The editor page adds the apps' origin to its `frame-src` and sends
`Cross-Origin-Opener-Policy: same-origin` itself. If the reverse proxy in front of Nextcloud sets
its own `Content-Security-Policy`, `X-Frame-Options` or `Cross-Origin-Opener-Policy`, it overrides
these: let Nextcloud's headers through, or at least allow the apps' origin in `frame-src`.

### The sign-in cookie and the frame

The editor page frames `https://craft.example.com/<app>/`. The frame needs a valid session at the
gate:

- **Same site**: the gate's cookie is `SameSite=Lax`, and requests of a frame on
  `craft.example.com` inside a page on `cloud.example.com` are same-site, so the cookie is sent in
  every browser. On another registrable domain (`craft.example.org`) it would not be; this setup
  does not support that.
- **Without a session**, the gate redirects the frame to the sign-in. With Nextcloud as the
  provider, that is Nextcloud itself, the same origin as the editor page. When the editor page
  allows frames from Nextcloud (`frame-src 'self'`, which Nextcloud 34 sends while its shipped PDF viewer app is enabled), the
  sign-in runs inside the frame without a prompt, because the person is signed in to Nextcloud
  already, and the app starts a moment later. Otherwise the editor shows, after 15 seconds, a
  hint with a link: open the app in a new tab, sign in there, reload the editor page.

### Updating and turning it off

See [operations.md](operations.md#upgrading-nextcloud-craftsuite-layer) and
[operations.md](operations.md#turning-the-nextcloud-integration-off).

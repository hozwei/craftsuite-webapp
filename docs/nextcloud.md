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
release of nextcloud-craftsuite-layer on both sides. This page uses 0.1.0.

### On the apps' side

In `.env`:

```sh
CRAFTSUITE_ALLOWED_ORIGINS=https://cloud.example.com
CRAFTSUITE_LAYER_VERSION=0.1.0
CRAFTSUITE_LAYER_SHA256=8aafbc59cee7a3bad95b0ab03be6c7dce23f0be178e461142266246988639017
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
   curl -fLO https://github.com/hozwei/nextcloud-craftsuite-layer/releases/download/v0.1.0/craftsuite_layer-0.1.0.tar.gz
   curl -fLO https://github.com/hozwei/nextcloud-craftsuite-layer/releases/download/v0.1.0/SHA256SUMS
   sha256sum -c --ignore-missing SHA256SUMS
   ```

2. Unpack it into Nextcloud's `custom_apps` folder (`/var/www/html/custom_apps` in the official
   image; on the host, wherever that folder is mounted), owned by the web server user (33:33 in the
   official image), and enable it:

   ```sh
   tar -xzf craftsuite_layer-0.1.0.tar.gz -C /path/to/nextcloud/custom_apps
   chown -R 33:33 /path/to/nextcloud/custom_apps/craftsuite_layer
   occ app:enable craftsuite_layer
   ```

   To offer it only to the group that may use the apps, enable it with
   `occ app:enable -g craft craftsuite_layer` instead; check with
   `occ config:app:get craftsuite_layer enabled` (expect `["craft"]`).
3. Set the addresses of the apps, with the slash at the end:

   ```sh
   occ config:app:set craftsuite_layer pdfcraft_url --value=https://craft.example.com/pdfcraft/
   occ config:app:set craftsuite_layer photocraft_url --value=https://craft.example.com/photocraft/
   occ config:app:set craftsuite_layer vectorcraft_url --value=https://craft.example.com/vectorcraft/
   occ config:app:set craftsuite_layer designcraft_url --value=https://craft.example.com/designcraft/
   occ config:list craftsuite_layer
   ```

4. In *Administration settings* → *Craft apps*, each address must appear without an error message.
   "The Craft app must be hosted on another host name than Nextcloud" means the apps' host name is
   one of Nextcloud's `trusted_domains`: remove it there.

In Files, a PDF now has "Open in PdfCraft" in its menu; PSD and IDML files open in PhotoCraft and
DesignCraft with a click. The layer's [Nextcloud app documentation](https://github.com/hozwei/nextcloud-craftsuite-layer/blob/v0.1.0/docs/nextcloud-app.md)
lists every file type, the editor page's messages and what happens on save.

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

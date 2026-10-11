# Changelog

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

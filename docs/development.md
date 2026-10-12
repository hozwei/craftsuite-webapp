# Development

## Where things are

| Path | What it is |
|---|---|
| `compose.yaml` | The file users run. **Generated**: do not edit the two scripts in it by hand. |
| `src/compose.template.yaml` | `compose.yaml` without the scripts: services, settings, health checks. |
| `src/web-start.sh` | Command of `craft-web`: checks `CRAFTSUITE_ALLOWED_ORIGINS`, writes the nginx configuration, starts nginx. |
| `src/update-loop.sh` | Command of `craft-update`: installs `craft-update` into `/tmp/bin`, runs it at start and daily, retries after errors. |
| `src/craft-update.sh` | The updater itself (`--status`, `--rollback`). |
| `tools/build-compose.sh` | Writes `compose.yaml` from `src/`. |
| `tools/render-compose.sh` | Fills `.env` into `compose.yaml` for single-file setups ([truenas.md](truenas.md)). |

## Changing a script

Edit the file in `src/`, then:

```sh
sh tools/build-compose.sh
sh tools/build-compose.sh --check
```

The build doubles every `$` (Compose's escaping) and indents the scripts into the YAML block;
`--check` exits with 1 when `compose.yaml` does not match `src/`. Commit both.

The scripts are POSIX `sh` and run under BusyBox `ash` (Alpine 3.24) with GNU coreutils, `curl`,
`jq`, `unzip` and `gzip`; `craft-web` uses the BusyBox of the nginx image. Avoid bashisms.
When `dockerfile_inline` of the updater changes, raise its image tag.

## Checking a change

- `docker compose config` with a test `.env` validates the file and the interpolation.
- `for f in src/*.sh tools/*.sh; do sh -n "$f" || echo "$f"; done` catches syntax errors;
  ShellCheck (`shellcheck -s sh src/*.sh tools/*.sh`) catches more.
- Run the updater outside Docker against a scratch folder: `CRAFT_BASE=/tmp/craft-test sh
  src/craft-update.sh` with the settings in the environment. Each run makes one request to the
  GitHub API per app in `CRAFT_APPS`, plus two for the canary (its runs and its issues) when the
  integration and the canary check are on: thirteen with the eleven default apps. The API allows
  60 per hour per IP address without authentication.
- For nginx, write the configuration without starting nginx, then test it:

  ```sh
  sed -e "s#/tmp/nginx.conf#$PWD/t.conf#g" -e '/^exec nginx/d' src/web-start.sh | CRAFTSUITE_ALLOWED_ORIGINS=https://cloud.example.com sh
  nginx -t -c "$PWD/t.conf"
  ```

  (Outside the nginx image, `include /etc/nginx/mime.types` and the `/tmp` paths must exist.)

# TrueNAS SCALE

TrueNAS SCALE 24.10 and later run Docker Compose files as *custom apps*. A custom app takes one
YAML file and no `.env`, so the settings are filled into the file before it is pasted.

## Install

1. **A dataset for the data**, for example `tank/craft` (*Datasets* → *Add Dataset*, preset
   *Generic*, ACL type POSIX). TrueNAS apps run as the user `apps` (568), so give it to that user
   in the TrueNAS shell:

   ```sh
   chown -R 568:568 /mnt/tank/craft
   chmod 755 /mnt/tank/craft
   ```

2. **The settings.** On a trusted machine with a copy of this repository (Linux, macOS, Git Bash
   or WSL on Windows, or the TrueNAS shell itself), create `.env` from `.env.example` with
   `chmod 600 .env` and fill it in as in the [README](../README.md#quick-start), with:

   ```sh
   CRAFT_DATA_DIR=/mnt/tank/craft
   CRAFT_USER=568:568
   CRAFT_PORT=30080
   ```

   `CRAFT_PORT` is any free port on the TrueNAS host; your reverse proxy will forward to
   `<truenas-ip>:<CRAFT_PORT>`.
3. **Render the YAML:**

   ```sh
   (umask 077; sh tools/render-compose.sh .env > compose.rendered.yaml)
   ```

   It needs only `sh` and `awk`, and it prints nothing but an error if a required setting is
   missing or malformed.
4. **Install:** *Apps* → *Discover Apps* → the three-dot menu → *Install via YAML*, name `craft`,
   paste the whole content of `compose.rendered.yaml`, *Save*. TrueNAS pulls the images and builds
   the updater. Then delete `compose.rendered.yaml`: it contains your secrets.
5. **Reverse proxy:** point `craft.example.com` at `<truenas-ip>:<CRAFT_PORT>`, as in
   [reverse-proxy.md](reverse-proxy.md) (the *Nginx Proxy Manager* app from the catalogue works).

Right after installing, the app shows *Deploying* until the first update run has finished (a few
minutes).

## Changing settings

TrueNAS keeps no comments and no `.env`. Change `.env`, render again, then *Apps* → `craft` →
*Edit*, select all, paste the new YAML, *Save*. The same goes for a new release of this
repository. Keep `.env` safe: it is the source of the configuration.

## Everyday commands

The `docker exec` and `docker logs` commands from [operations.md](operations.md) run unchanged in
the TrueNAS shell as root (`docker exec craft-update craft-update --status`, …). The `docker
compose` steps there assume a folder with `compose.yaml` and `.env`, which a custom app does not
have. On TrueNAS:

| operations.md says | On TrueNAS |
|---|---|
| change `.env`, then `docker compose up -d` | change `.env`, render, *Edit*, paste, *Save* |
| `docker compose ps` | `docker ps --filter name=craft-` |
| `docker compose logs -f update` | `docker logs -f craft-update` |
| `docker compose stop web` | `docker stop craft-web` (or *Stop* for the whole app) |
| `docker compose up -d` after a stop | *Start* in the Apps list |
| `docker compose pull …` / `build --pull …` | see below |
| rebuilding the data folder | *Stop* the app, `rm -rf /mnt/tank/craft/www /mnt/tank/craft/state /mnt/tank/craft/layer`, *Start* |

**Newer images within the pinned lines** (nginx security fixes, Alpine packages for the updater):
find the file TrueNAS deployed, pull and build with it, then *Stop* and *Start* the app:

```sh
F=$(docker inspect craft-update --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}')
docker compose -p ix-craft -f "$F" pull web gate
docker compose -p ix-craft -f "$F" build --pull --no-cache update
```

`ix-craft` is the Compose project TrueNAS uses for an app named `craft`.

## Replacing an earlier installation

If the dataset held another setup of the Craft apps before, start this one with an empty data
folder: stop the old app, move or delete its files in the dataset, `chown -R 568:568` it. Then
either delete the old app and install as above, or keep it and paste the new YAML with *Edit*: the
name `craft` and the container names `craft-gate`, `craft-web` and `craft-update` can be used only
once. The first run downloads the apps again.

## Notes

- **"Deploying" in the Apps list** although the apps work: `craft-update` is unhealthy, its last
  run had an error. See its log (`docker logs --tail 50 craft-update`).
- The dataset is covered by your periodic snapshots and replication like any other; it holds no
  user data and can be rebuilt.

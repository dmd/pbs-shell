# PBS Snapshot Browser Container

TUI for browsing Proxmox Backup Server snapshots, mounting them read-only,
and then providing a shell for exploration.

Requires Docker. Tested on Linux (amd64) and MacOS (arm64).

[![asciicast](https://asciinema.org/a/aav2JNC8tldJ6jjv.svg)](https://asciinema.org/a/aav2JNC8tldJ6jjv)

## What it does

- Uses `proxmox-backup-client` + `pxar` binaries with architecture-specific source policy:
  - `amd64`: official Proxmox `proxmox-backup-client-static` package from `download.proxmox.com`.
  - `arm64`: fallback to `ayufan/pve-backup-server-dockerfiles` release artifacts (build-time warning emitted).
- Lets you choose:
  - backup group
  - snapshot
  - archive
- Opens a shell inside the mounted filesystem.
- Cleans up mounts and loop mappings on exit.

## Filesystem and LVM behavior

- Image target selection supports both partitions and LVs.
- Should support ext2/3/4 and XFS.

## Image

`./pbs-browse.sh` uses the published image by default:

```bash
ghcr.io/dmd/pbs-shell:latest
```

Override it with `IMAGE=...` if needed.

## Build (optional, for local development)

```bash
docker build -t pbs-snapshot-browser .
```

## Published image

GitHub Actions automatically builds and publishes a multi-arch image
(`linux/amd64`, `linux/arm64`) to GHCR:

```bash
ghcr.io/dmd/pbs-shell:latest
```

Publishing triggers:
- push to `main`
- push tags matching `v*`
- manual `workflow_dispatch`

## Auth file

By default the container reads `auth.env` in the current directory; see `auth.env.dist` for format.
The `PBS_USER` you use must have `DatastoreReader` rights.


## Run

```bash
./pbs-browse.sh
```

By default, `./pbs-browse.sh`:
- reads `./auth.env`
- pulls `ghcr.io/dmd/pbs-shell:latest`
- runs the container with required privileges/devices

Useful overrides:

```bash
AUTH_FILE=/path/to/auth.env IMAGE=ghcr.io/dmd/pbs-shell:v0.1.0 ./pbs-browse.sh
```

```bash
PULL_IMAGE=0 IMAGE=pbs-snapshot-browser ./pbs-browse.sh
```

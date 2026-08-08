# WebKitGTK-DND-Fix-builder

Fedora 44 image with the WebKitGTK build toolchain and the CI entrypoint
baked under `/opt/webkitgtk-dnd-fix/bin/`. Package choices come from
`webkit-dnd-research.md` and `packages.txt`.

## GHCR name

GitHub Container Registry wants lowercase names:

`ghcr.io/<owner>/webkitgtk-dnd-fix-builder:<YYYYMMDD>`

Tags are **UTC date only** (`YYYYMMDD`). No floating `latest` / `fedora44` /
`sha-*` tags on the image. Human title: **WebKitGTK-DND-Fix-builder**.

## What is baked in

- gcc/g++, cmake, ninja, pkg-config, ccache (2G default, compressed)
- mold and lld for faster links
- gtk3-devel, gtk4-devel, and the rest of the WebKit GTK dep list
- `pcre2-devel`, `enchant2-devel`, `perl-bignum`
- `ci-build-and-test.sh` and `print-layer-checklist.sh`

WPE packages are best-effort only. This image is GTK-first.

No full `dnf upgrade` on build. That keeps layer cache hits useful.

## Build on GitHub

Actions → **Build deps container** → Run workflow (manual).

After a successful push, GHCR is pruned to the newest two date-tagged
versions. Actions artifacts are pruned to the newest five.

Before building, the workflow runs `scripts/sync-container-scripts.sh` so
`containers/` matches `scripts/`.

## Build locally

```sh
./scripts/sync-container-scripts.sh
podman build -t webkitgtk-dnd-fix-builder:$(date -u +%Y%m%d) -f containers/Dockerfile containers/
```

## Consumers

`.github/workflows/webkit-gtk-dnd.yml` pulls this image (newest date tag when
the input is empty) and mounts `scripts/` at runtime so entrypoint fixes do
not force an image rebuild.

## Layer caching

- `packages-core.txt` then `packages-webkit.txt` then scripts
- Script-only edits do not re-run dnf
- Build with BuildKit (`DOCKER_BUILDKIT=1`) for dnf cache mounts
- On the self-hosted runner, `docker pull` reuses local layers until the tag digest changes

# CI federation and dual runners

## Self-hosted runner (Vultr VOC-C 16c)

- Runner name: `vultr-voc-c-16c-webkit-dnd` on this private repo only
- Labels: `self-hosted`, `linux`, `x64`, `webkit-dnd`, `vultr`, `fedora-44`
- Host: Fedora 44 Server, Docker CE, mold/ccache on host, runner under `/opt/actions-runner`
- Persistent paths: `/var/cache/webkit-dnd/{ccache,build-gtk,prefix,buildx-cache}`
- Workflows use `runs-on: [self-hosted, linux, x64, webkit-dnd]` - not `ubuntu-latest`
- No GHA-hosted minutes for heavy jobs; no free-disk-space step; no Actions cache upload for ccache/build tree
- ccache max ~40G on local NVMe; `JOBS=$(nproc)` => 16
- SELinux left enforcing where possible; runner lives under `/opt` to avoid home_t exec issues
- Vultr API key stays on admin laptop only; not in repo secrets



### Host performance tuning (Fedora 44 runner)

Fedora is fine for this workload. What matters is profile + I/O + caches, not switching distro.

Applied on the Vultr box:
- `tuned` profile **throughput-performance**
- sysctl: swappiness 5, dirty_ratio 20 / background 5, sched_autogroup_enabled=0, large inotify/file-max, bigger TCP buffers for git/ghcr
- THP **madvise**
- block scheduler **none** on vda (NVMe/virtio)
- docker live-restore, higher nofile ulimits, concurrent pulls
- git: preloadIndex, manyFiles, fetch.parallel, pack.threads=0
- runner systemd drop-in: LimitNOFILE, job hooks, CCACHE_DIR on NVMe
- nightly `webkit-dnd-seed.timer` refreshes git mirrors + AppImage tools

Memory note: `-j16` Release TestWebCore can fill 32G; that is expected. Watch swap; if thrashing, drop to `-j14` without changing machines.

### What we cache on NVMe (`/var/cache/webkit-dnd`)

- `ccache/` (~40G cap)
- `build-gtk/` persistent ninja tree
- `prefix/` WebKitGTK install for GNOME Web
- `mirrors/WebKit.git`, `mirrors/epiphany.git` bare repos
- `tools/` linuxdeploy + appimagetool AppImages
- `buildx-cache/` Dockerfile layer cache
- docker image store: fedora:44 + builder date tags

Do **not** bake WebKit sources into the builder image; mirrors + ccache + build tree beat a stale multi-GB image layer.

### GHCR builder image local cache

- First `docker pull ghcr.io/.../webkitgtk-dnd-fix-builder:YYYYMMDD` stores layers on the runner disk.
- Later jobs with the **same tag digest** reuse local layers (pull is nearly instant).
- Image only changes when we rebuild and push a new date tag (packages/Dockerfile). Script-only edits can still rebuild a tag; prefer not retagging if only scripts change and scripts are bind-mounted from the repo (they are).
- Dockerfile layers: `packages-core.txt` -> `packages-webkit.txt` -> optional soft deps -> scripts last. BuildKit dnf cache mounts keep rebuilds faster when a package layer does change.

### WebKit source mirror on the runner

- Bare mirror: `/var/cache/webkit-dnd/mirrors/WebKit.git` (sirredbeard/WebKit)
- Jobs use `scripts/clone-webkit.sh` with `git clone --reference-if-able` so day-to-day is fetch deltas + checkout, not a full GitHub pack each run
- Prefer mirror + origin fetch over baking WebKit into the container image (image would be huge and stale every commit)
- ccache + persistent `build-gtk` matter more than image-embedded source after the first compile


## Build caching and reuse (2-core private runners)

### What WebKit upstream does (and does not)

- **WebKit/WebKit does not ship public GitHub Actions workflows** for engine builds. Under `.github/` you get CODEOWNERS and a PR template, not `workflows/*.yml`.
- Real CI is **Buildbot EWS** on build.webkit.org / results.webkit.org, with worker glue under `Tools/CISupport/` in-tree. Status can show on GitHub PRs via hooks; the workers are not Actions YAML.
- In-tree compile cache support lives in `Source/cmake/WebKitCCache.cmake`:
 - ccache on by default if installed (`WK_USE_CCACHE=NO` to disable)
 - Linux path is thinner than macOS: macOS generates a launcher with `CCACHE_BASEDIR`, `CCACHE_NOHASHDIR`, `CCACHE_DEPEND`, richer `CCACHE_SLOPPINESS`
 - sccache if `WEBKIT_USE_SCCACHE=1` or cloud backend env vars (Igalia has internal sccache-dist; not for us)
- Unified sources (`ENABLE_UNIFIED_BUILDS`) default ON for GTK - fewer TUs, better for ccache size
- Developer mode prefers fast linkers (lld; mold detected). We force mold when present.

We cannot copy upstream Actions. We **do** copy their ccache ideas and keep our own private validation CI.

### Our cache layers (ranked)

1. **GHCR builder image** (Fedora 44 deps, date tag) - avoid dnf every run
2. **ccache 5G Actions cache** with portable hashes:
 - `CCACHE_BASEDIR=$WEBKIT_DIR`
 - `CCACHE_NOHASHDIR=true` (critical or path drift = 100% miss)
 - `CCACHE_DEPEND=true`
 - sloppiness aligned with WebKit macOS launcher
 - keys `ccache-webkitgtk-f44-v2-<ref>-<sha>` + restore-keys fallbacks
 - shared restore into GNOME Web job from unit-build ccache prefixes
3. **Ninja build-dir snapshot** (TestWebCore tree only), size-gated ~3.5GiB:
 - restore `BUILD_HOST_DIR` bind-mounted at `build-gtk`
 - save only on success when small enough
 - next run: cmake reconfigure in place + ninja rebuilds dirty nodes only
 - if too large: skip snapshot, rely on ccache
4. **WebKitGTK install prefix tarball artifact** `webkitgtk-prefix-<sha>`:
 - produced by `ci-build-webkitgtk-prefix.sh`
 - GNOME Web workflow auto-finds latest matching artifact (or takes `webkit_prefix_artifact_run_id`)
 - `SKIP_WEBKIT_BUILD=1` when prefix has `webkitgtk-6.0.pc`
 - force rebuild via `force_rebuild_prefix`
5. **mold** for link; **no LTO** on CI thin/prefix builds
6. **Separate build vs test steps** so a green compile is not thrown away by a test flake without logs

### What we deliberately do not cache

- Full Debug WebKit trees (~10GB) in Actions cache
- Entire shallow git objects beyond the clone of the moment
- Double-compressing already zstd prefix tarballs on upload

### WebKit prefix → GNOME Web every time

Default path:

1. GNOME Web job tries auto-download newest `webkitgtk-prefix-*` artifact (prefer name containing current short SHA)
2. If missing or `force_rebuild_prefix`: build prefix once, upload `webkitgtk-prefix-${{ github.sha }}` for the next consumer
3. Pack AppImage with `SKIP_WEBKIT_BUILD=1` against that PREFIX

Thin `TestWebCore` trees are **not** install prefixes. Unit job may still warm **ccache** that the prefix job restores.

### Scripts

- `scripts/ccache-env.sh` - shared env
- `scripts/find-latest-webkit-prefix-artifact.sh` - GH API helper
- `scripts/ci-build.sh` / `ci-build-webkitgtk-prefix.sh` / `ci-build-gnome-web-appimage.sh`



## Dual self-hosted runners (Vultr + Azure)

### What we run now

Two machines share the `webkit-dnd` runner label so GitHub can hand a job to whichever is idle.

1. **Vultr** `github_actions` / runner name `vultr-voc-c-16c-webkit-dnd`
 - Public IP `155.138.194.251`
 - Plan class CPU-optimized ~16 vCPU / 32G RAM / ~500G disk
 - Fedora 44 host
 - Labels: `self-hosted`, `linux`, `x64`, `webkit-dnd`, `vultr`, `fedora-44`
 - Instance id `3f9688ab-29c8-440a-a13e-ad6ded14792d`
 - Bills whether idle or busy (Vultr style). Treat as a short burn box.

2. **Azure** `azure-webkit-dnd-d16` / runner name `azure-d16ds-webkit-dnd`
 - Public IP `20.127.61.97` on **static** Standard public IP `pip-webkit-dnd` (reserved, does not change across deallocate/start)
 - SKU `Standard_D16ds_v5` - 16 vCPU / 64 GiB RAM / local temp disk; OS disk 512G **StandardSSD_LRS** (no ZRS tax)
 - Host OS **Ubuntu 24.04 LTS** (marketplace). Fedora cloud VHD path fought the Azure agent; CI still builds inside the **Fedora 44** deps container, so the host distro is just docker + runner plumbing.
 - Labels: `self-hosted`, `linux`, `x64`, `webkit-dnd`, `azure`, `ubuntu-24.04`
 - Resource group `rg-webkit-dnd`, eastus, VS Enterprise sub with ~20 vCPU family/regional quota (16 is the practical max core count)
 - Deallocate when idle: compute stops billing; disk + static IP still cost a little
 - System-assigned managed identity + Virtual Machine Contributor on the RG so the box can deallocate itself when told

### Vultr API allowlist

Azure static IP was added with the user IP whitelist API (POST `/v2/users/{id}/ip-whitelist` with subnet + subnet_size 32), same docs path as the console guide. Current useful entries include the laptop `/32` and `20.127.61.97/32`. Without that, `vultr-cli` on Azure gets blocked even with a valid key.

Vultr API key lives only under `/root/.config/vultr/` and `/etc/webkit-dnd/vultr.env` on Azure (mode 600). Not in the git repo. Not in GitHub Actions secrets (allowlist chicken-egg and no need).

### Five-day Vultr exit hatch (runs on Azure)

systemd timer `webkit-dnd-vultr-snapshot-delete.timer` is active on Azure with `OnActiveSec=5d` from enable time (fires about five days out).

Service runs `/usr/local/sbin/webkit-dnd-vultr-snapshot-delete.sh` which:

1. Confirms API auth and that instance `3f9688ab-29c8-440a-a13e-ad6ded14792d` still exists
2. `vultr-cli snapshot create -i <id> -d webkit-dnd-gha-...`
3. Waits until snapshot status looks complete
4. `vultr-cli instance delete <id>`

API auth from Azure was tested live (`vultr-cli account info` and `instance get` succeeded) before arming the timer. Log: `/var/log/webkit-dnd-vultr-snapshot-delete.log`.

If we finish earlier, run the service manually or delete the timer. Snapshot is the recovery path if we still need that disk later.

### Azure $150/month budget

Consumption budget `webkit-dnd-150` on resource group `rg-webkit-dnd`, amount **150**, timeGrain **Monthly**.

The detail lives in `findings/budget-and-ops.md`. Short version, because the
old text here was wrong and cost us $554.26 in August 2026:

- Warning thresholds at actual 50%, 75%, 90% and forecasted 100% email only,
  through `ag-webkit-dnd-notify`.
- Actual 100% goes to `ag-webkit-dnd-budget`, which runs an Automation runbook
  that deallocates the VM. An alert on its own does not stop compute.
- The on-VM guard `scripts/azure-budget-guard.sh` reads real month-to-date cost
  every 10 minutes and deallocates at 100%. It needed Cost Management Reader at
  subscription scope, which it did not have until September 2026.
- A scheduled runbook `Enforce-WebKitDndBudget` re-checks cost hourly from
  Azure, independent of the VM and of budget alert latency.
- Native daily auto-shutdown at 0300 UTC bounds anything the above misses.

Compute stops at the budget. Storage does not, on purpose. Keeping the ccache
and prefix tarballs is cheaper than recompiling WebKit on a D16.

VS Enterprise credit behavior can also hard-limit the whole sub when credits are gone; treat the $150 budget as the decision alarm for this RG, not magic autoscaler math.

### Host tuning (both)

Same shape as the Fedora host-tune script:

- `tuned` profile `throughput-performance`
- sysctl: low swappiness, higher dirty ratios, big file-max/inotify, sched_autogroup off, large TCP buffers
- block scheduler `none` where available
- docker `daemon.json`: overlay2, live-restore, log cap, high concurrent pulls, nofile ulimit
- runner systemd drop-in: LimitNOFILE, TasksMax, OOMScoreAdjust, CCACHE_DIR/MAXSIZE, GIT_MIRROR_ROOT, job hooks
- jobs use `nproc` for ninja parallelism; Azure’s 64G is the better host when RAM was the wall on 32G Vultr

### Cache layout and peer sync

Shared path on both hosts: `/var/cache/webkit-dnd/{ccache,build-gtk,prefix,mirrors,tools,images,buildx-cache,...}` owned by `gha`.

Seeded on Azure from Vultr over root SSH keys (`id_ed25519_cache` both ways):

- bare git mirrors (WebKit, epiphany, …)
- appimage tools
- ccache tree
- docker image tarballs under `images/*.tar.zst` then `docker load` (GHCR pull from the VM was denied without package token; peer seed avoids that)

Hourly bidirectional rsync: `webkit-dnd-cache-sync.timer` on both ends. Syncs mirrors, tools, images, ccache. Does not sync full `build-gtk` object trees by default (host-specific and huge).

Workflows also try `docker load` from the local tarball seed if the named image is missing before a job.

### Workflow split

Peer sync (`webkit-dnd-peer-sync.sh`) `quick`/`full` now includes **flatpak-webkit handoff**:
`webkitgtk-flatpak-sdk50-last-good.tar.zst`, tip-named sha tarballs, and stamp files under
`/var/cache/webkit-dnd/flatpak-webkit/`. Same winner-by-size pattern as Fedora prefix.
Does **not** rsync `flatpak-builder-state` (live ninja trees). `SYNC_MODE=flatpak` for that alone.

All three workflows take optional `runner_label`: `any` | `azure` | `vultr`.

- `any` → labels `self-hosted,linux,x64,webkit-dnd` (first free host)
- pin adds `azure` or `vultr`

Concurrency groups include the runner_label so unit build and AppImage can run at the same time on different machines without canceling each other. Package + unit + prefix workflows default to **any** so idle peers pick up work. Pin only when you need a specific box (e.g. azure 64G for a cold full prefix).

For package workflow with `any`: Azure wake is **non-blocking** (`wake-azure-pool` parallel job). Build starts immediately on whichever webkit-dnd runner is free; Azure is still woken so it can join the pool. Pin `azure` still blocks on wake.

### Burn plan and ramp-down

Short window: keep both hot for a few days, split heavy jobs, keep mirrors/ccache in sync.

Then:

1. Let Azure timer snapshot+delete Vultr (or do it sooner once Azure has everything)
2. Capture Azure OS disk / image before shrinking SKU
3. Redeploy smaller Azure size aimed around ~$300/mo total willingness later (or ~$150 credit + small out of pocket), deallocate hard when idle
4. Vultr off because idle still costs money there

### Scripts added for this

- `scripts/azure-vm-start.sh` / `scripts/azure-vm-deallocate.sh`
- `scripts/bootstrap-self-hosted-runner.sh`
- `scripts/sync-runner-caches.sh`
- `scripts/seed-runner-mirrors.sh`

Laptop SSH:

- `Host azure-webkit-dnd` → `azureuser@20.127.61.97` key `~/.ssh/azure_webkit_dnd`
- `Host vultr-webkit-dnd` → root key `~/.ssh/vultr_id_rsa`

### Unit build note

Self-hosted unit workflow already went green once on Vultr in about twenty minutes wall time for the TestWebCore/SelectionData path after caches were warm. Next runs should spread across both hosts and keep warming ccache on Azure via sync.


## Azure scale-to-zero and wake-on-workload

Azure compute should not sit hot all day. Pattern:

1. **Idle watchdog on the Azure VM** (`webkit-dnd-idle-watchdog.timer`, every 5 minutes)
 - Tracks `/var/cache/webkit-dnd/out/last-runner-activity` (updated by runner job hooks)
 - If no `Runner.Worker`, no webkit docker job container, and idle ≥ **30 minutes**, stops the runner service and `az vm deallocate` via managed identity
 - Skips when `/etc/webkit-dnd/MAINTENANCE_LOCK` or `HOLD_AWAKE` exists

2. **Wake on workload**
 - GitHub Actions secrets: `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_RG`, `AZURE_VM_NAME`
 - SP `webkit-dnd-gha-runner-control` has Contributor on `rg-webkit-dnd`
 - Heavy workflows start with a github-hosted `wake-azure` job (`azure/login` + `scripts/azure-vm-wake.sh`) unless `runner_label=vultr`
 - Wake waits until runner `azure-d16ds-webkit-dnd` is **online** in the GitHub API
 - `runner_label=any` still wakes Azure so both hosts can share load; if wake fails, job can still land on Vultr

3. **Daily maintain** workflow `azure-runner-lifecycle.yml`
 - Cron once daily: wake → on Azure runner run seed (git mirrors, GHCR image pull/save, peer sync) → clear maintenance lock → idle watchdog shuts it down after 30m if nothing else runs
 - Manual `workflow_dispatch` wake or maintain

4. **Peer sync (bidirectional, quiet)**
 - `/usr/local/sbin/webkit-dnd-peer-sync.sh` on both hosts
 - Tries Azure `20.127.61.97` and Vultr `155.138.194.251`, skips self, **exits 0** if peer unreachable (deallocated Azure or dead Vultr)
 - Hourly timer still fires; job hooks fire **background** sync on start/complete via `systemd-run` so builds are not held
 - Workflows also kick a non-blocking background sync step at the end (`continue-on-error: true`)

5. **Static IP**
 - Azure public IP remains Standard/static `20.127.61.97` across deallocate/start so Vultr API allowlist and SSH config stay valid


## Parallel burn and cross-host resume

WebKit compile does not shard a single ninja graph across two machines without distcc. What does work:

1. **Split lanes** (`ci-parallel-burn.yml`): Azure runs unit `TestWebCore` + SelectionData; Vultr runs AppImage/prefix at the same time. Different concurrency groups so they do not cancel each other.
2. **Portable cache is ccache** (CCACHE_BASEDIR = WebKit source root). `build-gtk` object trees stay host-local.
3. **warm-ccache-from-peer.sh** pulls ccache (and optionally mirrors) with a hard time budget before builds. If Vultr dies mid-build, re-run the same workflow pinned to `azure` and ccache hits skip most recompilation.
4. **After jobs**, peer sync is background only (`systemd-run` / non-blocking step).
5. **Vultr teardown** also scheduled as GitHub Actions (`vultr-teardown.yml`): github-hosted wakes Azure, Azure does final sync then snapshot+delete. Works even if Azure was deallocated and the on-box 5-day timer never fired.

Burn defaults: unit_runner=azure (64G), appimage_runner=vultr. Flip or set skip_* as needed.



## Dual-runner ccache federation (efficient warm / live / handoff)

The ninja graph for one WebKitGTK configure is still monolithic. Federation is lanes plus shared cache, not splitting one compile graph across hosts.

What we want out of the next few days on Vultr + Azure is simple:

- Pay a little wall time up front for ccache so ninja does not go cold.
- Keep ccache moving while a long build runs so the other host can start without waiting for job end.
- Hand off a last-good WebKitGTK prefix tarball so GNOME Web AppImage can pack on one box while a fresh engine unit/prefix build runs on the other.
- Never hard-fail a build because the peer is asleep or the link is flaky.

### Warm (pre-build, short block)

`scripts/warm-ccache-from-peer.sh`

- Probes both peer IPs (Azure static 20.127.61.97, Vultr 155.138.194.251), skips self.
- Picks the peer with the largest ccache tree.
- Default block budget about 300 seconds for ccache only (WARM_TIMEOUT_SEC).
- If local ccache is already competitive with the best peer, budget shrinks to at most 90s for a cheap delta.
- Optional WARM_PREFIX=1 pulls `webkitgtk-prefix-last-good.tar.zst` plus sha side-car files (small handoff), not the whole extracted prefix tree.
- Soft-fail always unless STRICT=1.
- Fast rsync: -aH --partial --inplace, no compression by default (LAN/cross-cloud CPU is not free; payload is already compressed objects).

### Live (mid-build, non-blocking)

`scripts/ccache-live-sync.sh start|stop|once`

- start: systemd-run or nohup loop, default every 180s, push then pull ccache both ways.
- stop: kill loop, one final push/pull.
- Unit/prefix workflows start live-sync just before docker build and stop after.
- Does not gate ninja. If peer is down, ticks are quiet.

### Peer sync modes

`scripts/webkit-dnd-peer-sync.sh` with SYNC_MODE=

- quick: ccache + last-good prefix tarball handoff (default for post-job and timers)
- ccache: ccache only
- prefix: last-good tarball handoff (optional full prefix tree if SYNC_PREFIX_TREE=1)
- full: mirrors, tools, images, ccache, prefix handoff (daily maintain)

### Prefix handoff for AppImage

`scripts/seed-prefix-from-last-good.sh`

AppImage lane order:

1. Warm ccache + pull last-good tarball from peer (bounded).
2. seed-prefix-from-last-good into PREFIX_HOST.
3. Else download GH Actions webkitgtk-prefix-* artifact.
4. Else build prefix in container (with live-sync if rebuilding).
5. Pack GNOME Web AppImage against PREFIX_HOST with SKIP_WEBKIT_BUILD=1.

Prefix lane marks:

- `/var/cache/webkit-dnd/prefix/webkitgtk-prefix-last-good.tar.zst`
- `/var/cache/webkit-dnd/prefix/.webkitgtk-dnd-sha`
- `/var/cache/webkit-dnd/out/last-good-prefix-sha`

and background-pushes with SYNC_MODE=prefix so the other host can pick it up without waiting on artifact CDN.

### Workflow wiring

- webkit-gtk-dnd.yml: checkout scripts first, warm 300s, live-sync around build/test, stop + quick peer push after.
- webkit-gtk-prefix.yml: same warm/live, mark last-good, SYNC_MODE=prefix push.
- gnome-web-dnd-fix-appimage.yml: warm with WARM_PREFIX=1, host seed before GH artifact, AppImage runs if host seed OR artifact OR fresh prefix succeeded.
- ci-parallel-burn.yml:
 - unit lane waits only on Azure pre-warm (default unit_runner=azure)
 - appimage lane waits only on Vultr pre-warm (default appimage_runner=vultr, force_rebuild_prefix=false)
 - so unit compile and AppImage-from-last-good can run at the same time
 - post-job SYNC_MODE=quick on both hosts

### Practical limits

- build-gtk trees stay host-local (not rsynced). Portable state is ccache + prefix tarball + GH artifacts.
- A failed unit build on Vultr can be re-dispatched on Azure after warm; you do not restart from zero objects if ccache already held the objects.
- Live-sync helps the second host more when the first has been compiling for a while; first 3 minutes of a cold peer still lean on the pre-warm block.
- Prefix last-good must be produced once before AppImage can skip engine rebuild. Until then lane B builds prefix (expensive) or waits on artifact.

Scripts installed on both runners under /usr/local/sbin and also live in the private repo so jobs re-install on checkout.



## Free dual allocation (two jobs, either host)

Self-hosted labels: both runners carry `webkit-dnd`. Pin with `azure` or `vultr` when you care which box; `any` means first idle host.

Concurrency groups now include `github.run_id` and `cancel-in-progress: false` on unit, AppImage, and prefix workflows. Two dispatches no longer cancel each other. Parallel burn keeps one burn group per ref without cancel so the short window stays at two heavy lanes (unit + AppImage) rather than stacking multiple burns.

Handoff for resume on the other host:
- ccache (warm block + live mid-build + quick post sync)
- last-good prefix tarball + sha sidecars
- newest builder image seed tar.zst under /var/cache/webkit-dnd/images (warm WARM_IMAGES=1, quick peer-sync)
- GH Actions artifacts as the CDN fallback for prefix

build-gtk trees stay local. Portable truth is ccache + prefix tarball + image + git mirrors.



## Docker on Azure ephemeral (gated)

`/mnt` resource disk is much faster than OS disk for docker graph, but wiped on deallocate.

Implementation (armed, not forced while uptime is short):

- `docker-seed-export.sh` - nice/ionice `docker save|zstd` of builder tags to `/var/cache/webkit-dnd/images` (OS disk), flocked, 30m timer when ephemeral mode on
- `docker-seed-load.sh` - load seeds if tags missing (wake/boot)
- `docker-ephemeral-enable.sh` - moves docker data-root to `/mnt/webkit-dnd/docker` only if:
 - `DOCKER_ON_EPHEMERAL=1`, or auto when uptime >= `AUTO_DOCKER_EPHEMERAL_HOURS` (default 2)
 - and no Runner.Worker / containers (unless FORCE=1)
- disable helper restores OS-disk data-root
- host-tune + wake try auto-enable; idle watchdog exports seeds before deallocate

Until Azure stays up ≥2h continuously, mode stays off so 30m scale-to-zero does not thrash rehydration.




## Build snapshot + tests-only + external validation

- build-tree-snapshot.sh: save/restore/push/pull ninja trees under /var/cache/webkit-dnd/build-snapshots
- webkit-gtk-tests-only.yml: re-run SelectionData + external validation without rebuild
- ci-external-validation.sh: HTML fixtures + all 9 SelectionData gtests must PASS in log
- peer-sync quick/full includes build-snapshots
- last-good-unit.json stamped on green unit




## Mirrors are per-host (no peer sync)

If both runners `git fetch` their own bare mirrors, they do **not** need to sync `mirrors/` with each other. Peer rsync of live git object stores was a corruption footgun and is disabled:

- `webkit-dnd-peer-sync.sh` full mode: tools/images/ccache/build-snapshots only
- `warm-ccache-from-peer.sh`: no WARM_MIRRORS path
- `sync-runner-caches.sh`: SYNC_MIRRORS defaults 0; requires FORCE_MIRROR_RSYNC=1 to override (discouraged)

Still worth peer-syncing: ccache, prefix last-good tarball, docker image seeds, build-snapshots.
Still local-only: `mirrors/*.git` via seed-runner-mirrors + flock + fsck.


## Dual-runner health check (live snapshot)

Hosts checked while both runners were up:

- Azure `azure-d16ds-webkit-dnd` (D16ds_v5, 16c/64G): up, Listener active, nested-virt capable
- Vultr `vultr-voc-c-16c-webkit-dnd` (16c/32G): up, Listener active, no nested virt

### What is syncing

Hourly (and on-job) peer path is `webkit-dnd-cache-sync.timer` -> `webkit-dnd-peer-sync.sh`. Intended payload:

- ccache under `/var/cache/webkit-dnd/ccache`
- builder image tarballs under `images/`
- prefix tarballs / last-good under `prefix/`
- build-tree snapshots under `build-snapshots/`
- tools crumbs as configured

Git mirrors stay **per-host**. Each side `git fetch`es its own `WebKit.git` / `epiphany.git`. Do not rsync live `*.git` object DBs.

Observed sizes roughly matched across hosts when both were warm:

- ccache ~323M directory, ccache tool reporting ~0.2 GiB of 5 GiB max, hit rate high on repeated unit compiles (~78% of cacheable calls)
- images ~710M (fedora-44 seed + builder date tag)
- build-snapshots ~388M with several `build-gtk-unit-*.tar.zst` and a `latest` symlink
- mirrors ~13G each (good - separate complete-ish bare repos)
- prefix last-good still ~48M - too small to be a full WebKitGTK install; treat as stale or partial until a real prefix job lands on tip

### What is not at full potential yet

1. **ccache depth** - 0.2 GiB used of 5 GiB. Unit jobs target TestWebCore only, so the cache never fills like a full WebKitGTK prefix build would. Dual runners help resume unit work; they will help prefix more once a green prefix exists on tip.
2. **Peer reachability flaps** - Azure cache-sync log lines showed `peer unreachable 20.127.61.97` then still `sync 155.138.194.251 mode=quick`. Quick syncs finishing in ~10-12s are suspicious for real ccache bulk transfer. Need to confirm rsync actually moves bytes (log byte counts, or `rsync --stats`) and that each host's peer list is the **other** host only, never itself.
3. **Prefix reuse** - AppImage set `SKIP_WEBKIT_BUILD=1` because it saw webkitgtk-6.0 in PREFIX, but that prefix is the old 48M last-good, not a tip build of our branch. Product validation is lying until prefix is rebuilt on `gtk-dnd-file-access-reenable` tip.
4. **Concurrency** - We can pin unit to Azure and AppImage/prefix to Vultr (or the reverse) with `runner_label`. That is the right dual-burn shape. Running two full WebKitGTK prefix compiles at once on 32G Vultr is a bad idea; Azure 64G is the prefix machine. Unit TestWebCore fits either host.
5. **Build snapshots** - Failure snapshots are landing (`build-gtk-unit-*.tar.zst`). Good for tests-only resume. Confirm restore path runs on the peer host after warm_from_peer, not only same-host.
6. **Ephemeral docker on Azure** - timer armed (`webkit-dnd-ephemeral-arm`); only enable when uptime policy says so and no migrate conflict. Nested GUI later wants the same Azure host.

### Resiliency checklist (keep honest)

- Wake Azure on job; idle deallocate ~30m; budget guard; Vultr 5-day snapshot+delete from Azure
- Fail closed on wrong WebKit HEAD and empty SelectionData gtest logs
- Clone: `--reference` without `--shared`, dissociate, WebCore check only for WebKit URLs
- Mirror seed: flock + fetch + fsck on each host
- actionlint before workflow commits; `scripts/lint-local.sh` before engine/CI pushes
- Do not cancel in-flight runs unless asked

### Gaps to close next

- Verify peer-sync stats (bytes moved, exclude self IP)
- Force a real prefix build on current engine tip; replace 48M last-good
- After tip prefix exists, AppImage should consume it without rebuilding engine
- Optional: ccache live sync during long compiles (script exists; confirm it is armed when dual-burn runs)
- iso-codes (and any other GNOME Web meson deps) must be in the builder image before AppImage can pass meson


## Peer-sync self-skip fix

`PEER_HOSTS` defaults to both public IPs. `hostname -I` is private-only on Azure, so self-skip failed and logs showed `peer unreachable 20.127.61.97` (self) before syncing Vultr. Fix: `SELF_IPS` + public IP probe + per-host systemd override (`PEER_HOSTS` = the other machine only). Quick sync should log a single `sync <peer>` line without self unreachable noise. Still verify rsync byte counts on a cold ccache pull.


## Dual-runner health after PASS/parser burn

What is working:

- Unit on Azure + AppImage/prefix on Vultr in parallel (separate concurrency groups).
- Peer cache-sync timer hourly; SELF_IPS / PEER_HOSTS override on Vultr; Azure skips self via public IP probe (`skip self 20.127.61.97`).
- warm-ccache-from-peer pulled ~333M and showed rsync stats (`speedup is 856.25`).
- ccache hit rate ~82% on unit-shaped work. Mirrors 13G each, independent.
- build-snapshots present both sides (~300-700M).
- Unit last-good on tip 17647b after green run.

What is not full potential:

- Prefix last-good still points at main `d5bec83` and 48M tarball. Vultr prefix tree grew (~233M partial lib64) mid force-rebuild but is not a stamped tip last-good yet.
- ccache only ~0.3G of 40G - needs full prefix compiles to deepen.
- systemd unit is `webkit-dnd-cache-sync` → historically a 70-byte wrapper `exec`ing `webkit-dnd-peer-sync.sh`. Jobs only installed the peer-sync name. Now both sbin names get the full script on install. Log path: `/var/log/webkit-dnd-cache-sync.log`.
- Quick sync finishes in ~6-16s when trees already match; expected after warm. Cold warm-ccache showed real rsync bytes (~333M, speedup 856).
- Azure override: SELF_IPS=20.127.61.97 PEER_HOSTS=155.138.194.251. Vultr reverse. Self-skip logs clean.


## Stale last-good vs tip prefix (postmortem)

last-good is not "newest file on disk." It was a sticky 48M d5bec artifact while tip tarballs sat beside it. Seed always took last-good. Peer sync was blind bidirectional, so the bad handoff could bounce between Vultr and Azure.

Fix direction: pin every seed and pack step to `EXPECTED_WEBKIT_SHA` / WebKit HEAD. Prefer tip-named tarballs. Keep DEST tarballs when reseeding the tree. Peer pull only if remote last-good is larger or local missing. After a green tip pack, last-good must be rewritten from that tip tarball only.

## GUI automation and dual-runner lessons (summary)

Full narrative: findings/gui-automation-and-ci.md.

Worked: on-box ccache + prefix last-good with tip pin, peer ccache warm, Azure wake/deallocate, Vultr allowlist from Azure static IP, stamp-cached nested golden, AppRun-only smoke.

Did not work: rsync of bare git mirrors between peers, last-good without tip pin, zombie runner trusted via systemctl only, bare epiphany smoke, bwrap-as-AppRun, sed -i ELF reloc in pack container.

Note: `reboot-runners-when-idle.yml` removed; idle reboot handled by attached runner watchdog/lifecycle, not a GitHub workflow cron.

## Rebuild only if stale (overnight rule)

Do not burn the remaining days on full rebuilds when tip artifacts already exist.

- Flatpak in-SDK WebKit: last-good `webkitgtk-flatpak-sdk50-<sha>.tar.zst`. Rebuild
  only on tip change, force flag, or real compile failure.
- Flatpak package export: packaging-only when wrapper/manifest/finish-args change
  and WebKit seed hits.
- AppImage: needs tip prefix. Rebuild packer only when prefix tip or AppRun/packer
  changes. Never re-upload a leftover OUT AppImage from a Flatpak-only job.
- Units: prefer build snapshot + ccache restore.

## What peers should sync

Reasonable between Azure and Vultr:

- ccache
- prefix last-good + tip-named tarballs
- flatpak-webkit last-good + tip-named tarballs
- builder image seeds / snapshots the scripts already know
- nested golden qcow stamp metadata if small and safe

Not reasonable:

- live git mirrors mid-fetch
- flatpak-builder-state (huge, host-locked)
- docker root / ephemeral graphs
- nested overlay disks or guest RAM dumps

quick peer-sync mode should cover the useful set without waking a full state copy.

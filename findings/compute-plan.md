# Compute plan for the upstream push

Written 2026-09-02. Companion to `upstream-strategy.md`. This file is about how
we buy compute for phase 1 and phase 2, and how we stay inside the $150 Azure
budget while doing it.

## What we actually need to build now

The work changed shape, so the machine should too.

Phase 1 was written here as `beginDragWithFiles` for GTK in WebKitTestRunner
plus unskipping `fast/events/drop-with-file-paths.html`. `upstream-strategy.md`
corrected that the same day: the seam is a GLib API test driving `DropTarget`,
and `TestDragAndDrop` now exists on the fork. The build needs are the same
either way:

- A GTK build of WebKit with `ENABLE_API_TESTS=ON` and developer mode.
- `Tools/Scripts/run-webkit-tests --gtk` for the layout test.
- `TestWebCore` with `SelectionData.*` and `DropTargetState.*`.
- `Tools/Scripts/check-webkit-style` on the touch set.

It does not need an AppImage, a Flatpak, a nested KVM guest, a compositor, or a
GUI session. That is the whole point of driving `DropTarget`'s page seam instead
of faking GDK events. The test runs headless like any other layout test.

So the demand profile is: one large burst to build WebKit from cold, then many
small incremental rebuilds against a warm ccache and a warm build tree.

## Prices, measured not guessed

Pulled from the Azure retail prices API on 2026-09-02 for eastus, Linux,
consumption:

- `Standard_D16ds_v5` on demand: $0.9040 per hour
- `Standard_D16ds_v5` spot: $0.1810 per hour
- `Standard_D48ds_v5` on demand: $2.7120, spot $0.5725
- `Standard_D64ds_v5` on demand: $3.6160, spot $0.7633
- `Standard_F32s_v2` on demand: $1.3530, spot $0.2977

Spot is consistently about a fifth of on demand. That is the single biggest
lever available to us and we were not using it. The August D16 that ran for 24
days was on demand.

### Quota reality

`az vm list-usage -l eastus` on 2026-09-02:

- Total Regional vCPUs: 16 used of 20
- Total Regional Low-priority vCPUs: 0 used of 20
- Standard DDSv5 Family vCPUs: 16 used of 20

Two things follow. Spot capacity is available and completely unused. And we are
capped at 20 cores in the region, so D16 is effectively the largest thing we can
run without a quota increase. Do not design around a D48 or D64 until a quota
request is approved.

### Budget math

September month to date is $11.68 of $150. Remaining is $138.32.

- On demand D16: 152 hours remaining.
- Spot D16: 764 hours remaining.

764 hours is more than the month contains. Spot converts the budget from a real
constraint into a non-issue, provided we still deallocate when idle. The
enforcement layers from the August postmortem stay exactly as they are; cheaper
compute is not a reason to leave a machine running.

## Decision: spot D16, on demand only as fallback

Use `--priority Spot --eviction-policy Deallocate --max-price -1`.

`Deallocate` rather than `Delete` matters. On eviction the disk survives, so the
ccache and the build tree under `/var/cache/webkit-dnd` survive, and the next
wake resumes instead of restarting. `--max-price -1` means pay up to the on
demand rate, so we are never evicted for price, only for capacity.

Eviction is survivable for this workload and we should stop treating it as a
risk. A WebKit build is a long ninja run with a persistent ccache. Losing the
machine mid build costs the compile units in flight, not the build. The idle
watchdog already handles the deallocated state.

The one thing eviction is bad for is an interactive debugging session. If we are
mid investigation and want stability, wake on demand deliberately and say so.

## What to stop paying for

The AppImage and Flatpak lanes are demoted to supplemental. They are why the
machine had to be large and why runs took hours. Not building them is worth more
than any VM sizing choice:

- No Epiphany build, no linuxdeploy, no appimagetool, no 504 MB AppImage.
- No in-SDK WebKit rebuild inside a Flatpak SDK, which was a second full engine
  compile.
- No nested KVM guest, which required the D16 specifically for nested
  virtualization support.

If we ever want a package again, the prefix tarball path in
`ci-build-webkitgtk-prefix.sh` still exists and the findings still describe it.

## Standing storage cost

Deallocating stops compute billing and keeps the managed disks, the static IP,
and `/var/cache/webkit-dnd`. That standing cost is about $35 a month.

That is deliberate and it is allowed to exceed the compute policy. A cold WebKit
build on a D16 is hours; a warm ccache build is minutes. Paying $35 to avoid
repeatedly paying for cold builds is correct. Storage is exempt from the halt.

## Vultr

Up to $200 is available and `vultr-cli` is installed on the operator host with
the key at the usual path. The WebKit instance there is deleted. Snapshot
`webkit-dnd-gha-final`, id `a6af62c4-7552-465e-8770-8523fea18506`, taken
2026-08-13, 500 GB raw and 47.9 GB compressed, status complete, is the restore
path.

Hold Vultr in reserve. Reasons:

- Azure spot at $0.181 an hour is cheaper than any comparable Vultr instance,
  and the Azure credit is use it or lose it each month while the Vultr $200 is
  a finite pool.
- Spending Azure credit first is strictly correct when both can do the job.
- Restore Vultr from the snapshot only if Azure spot capacity in eastus is
  unavailable when we need it, or if we want a second builder for a parallel
  bisect.

## GitHub Actions

The repo is private, so Actions minutes are metered against the plan rather than
free. Self hosted runners do not consume them. Keep heavy work on
`[self-hosted, linux, x64, webkit-dnd]` as the existing rules already require.

All prior workflow runs were deleted on 2026-09-01, so the Actions history is
empty. The validation GitHub Releases survived and remain the receipts.

## Sequence for the next work session

1. Provision or convert the builder to spot with
   `scripts/azure-vm-provision-spot.sh`. Reuse the existing OS disk so the
   ccache and mirrors survive.
2. Wake with a reason, per the existing gate:
   `WAKE_REASON="phase1 beginDragWithFiles" scripts/azure-vm-wake.sh`.
3. Build GTK developer mode once from the warm cache.
4. Iterate on the WebKitTestRunner change with incremental ninja.
5. Run `run-webkit-tests --gtk fast/events/drop-with-file-paths.html` and the
   new security test.
6. Run `check-webkit-style` on the touch set.
7. Deallocate. The watchdog will do it anyway after 20 minutes idle, and the
   hourly runbook is the backstop.

Expect the cold build to be the only expensive step. At spot rates a four hour
cold build is about $0.72.

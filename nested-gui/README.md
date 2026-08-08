# Nested GUI DnD validation (Azure only, optional)

Optional human-assisted + automated path. Does **not** gate unit/prefix/AppImage CI.

## Goal

On the Azure runner (nested KVM available), boot a **Fedora 44 Workstation** guest under qemu-kvm, install our **GNOME Web AppImage** built from the DnD-fix WebKitGTK, drive the `html/layer*.html` drag-and-drop scenarios, and capture stack evidence that:

- we do what the design claims (trusted external files vs untrusted URI-list, no silent filename promotion)
- we are not leaking local file paths/contents across the untrusted boundary

Manual host verification remains first-class. This guest is for repeatable automation and deep debug packs.

## When to run

Only after:

1. WebKitGTK unit lane green (`SelectionData.*` + external validation)
2. AppImage lane green (artifact uploaded)

Trigger: `workflow_dispatch` on `nested-gui-dnd.yml` (future), pin `azure` only.

## Host prerequisites (Azure)

- `/dev/kvm` + nested VT-x (confirmed on azure-d16ds-webkit-dnd)
- ~8c/16G for guest on a 16c/64G host
- Golden image on OS disk; ephemeral overlay on `/mnt` during run

## Layout

```
nested-gui/
  README.md
  host/build-golden-image.sh   # rare: create qcow2
  host/run-guest-suite.sh      # boot overlay, run suite, collect out/
  guest/cloud-init.yaml
  guest/run-dnd-suite.sh
  guest/leak-watch.sh
  guest/canary-setup.sh
  qemu/domain.xml.in
```

See comments inside the host/guest scripts for the full sequence.

## Scenarios

| ID | Action | Expect |
|----|--------|--------|
| L1 | Drop text/uri-list only | files.length === 0 |
| L2 | Drop real file from Nautilus | files.length >= 1 |
| L4 | Page-sourced drag / file URI without trust | no grant / stripped |
| NEG | Canary file never appears in page or logs | leak-report clean |

## Instrumentation

WebKit/GTK DnD debug channels, portal journal, doc-portal dir diff, fd/lsof snapshots, canary token scrub, optional short strace, cores on crash.

## Non-goals v1

Nested on Vultr; blocking compile lanes; replacing SelectionData gtests.

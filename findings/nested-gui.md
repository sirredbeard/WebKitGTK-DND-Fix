# Nested GUI validation

## Nested virtualization on CI VMs

Checked live:

- Azure D16ds_v5 (ubuntu host): typically runs under Hyper-V; nested virt requires VM size + portal "Nested virtualization" / Security profile support. See probe results in session notes.
- Vultr: depends on plan; many VPS expose vmx/svm to guest for nested KVM, not all.

Not required for WebKitGTK container CI (docker/podman is enough). Only matters if we wanted full VM guests (GNOME boxes, nested Fedora) for interactive DnD.


## GUI validation plan (human + automated nested)

Two tracks, not either/or:

1. **Human-in-the-loop host verification** - run the AppImage (or prefix-linked Epiphany) on a real desktop against html/layer1 - 4. Checklist stays the source of truth for portal/Nautilus/file-manager edge cases. Manual remains required for sign-off before any upstream pitch.

2. **Automated GUI on Azure nested KVM** - feasible because D16ds_v5 exposes nested VT-x + /dev/kvm. Vultr cannot host this. Direction:
 - Golden Fedora Workstation (or Silverblue) guest image on Azure resource disk / managed disk
 - workflow_dispatch only, pin runner_label=azure, HOLD_AWAKE for the job
 - Boot guest headless (libvirt + qemu-kvm), install/run our Epiphany AppImage + serve html/
 - Drive AT-SPI / ydotool where possible; screenshot + junit-ish JSON artifacts
 - Focus first on in-page and same-app drops; cross-app Nautilus last
 - Never block compile/unit/prefix lanes on nested GUI

Nested is phase-2 after unit + prefix + AppImage are reliably green. Human verification can start as soon as AppImage artifact exists.




## Nested GUI sketch (checked in)

See `nested-gui/README.md` and stubs under `nested-gui/{host,guest,qemu}/`.
Azure-only optional lane after unit+AppImage green. Human-in-the-loop remains required for sign-off.
Instrumentation plan: canary file, portal/doc grants, fd snapshots, WebKit/GTK DnD logs, screenshots.




GNOME Web AppImage validation {{PRETTY_UTC}} (UTC).

Built on Fedora 44 against patched WebKitGTK. Private validation only.
Not an upstream GNOME or WebKit release. Not for Flathub.

### Runtime requirements

- Arch: x86_64
- Builder OS: Fedora 44 (latest stable at pack time)
- Minimum glibc: {{GLIBC_VER}} (from the Fedora 44 builder)
- Cross-distro note: AppImage portability is usually limited by glibc,
  not by missing shared libs. Hosts with glibc older than {{GLIBC_VER}}
  will fail at startup (GLIBC_x.y not found). Fedora 44+ and other
  distros with glibc >= {{GLIBC_VER}} are the intended targets.
- Needs a working GUI session (Wayland or X11) for real DnD QA.
- CLI check: ./GNOME_Web-WebKitGTK-DnD-x86_64.AppImage --version
  prints Web <epiphany-shortrev>. That alone does not prove the migrator
  or GUI path; open the app once for a real smoke.

### Build pins

- workflow run: {{RUN_URL}}
- image: {{IMAGE}}
- webkit: {{WEBKIT_REPO}} @ {{WEBKIT_REF}} ({{WEBKIT_SHA}})
- gnome-web ref: {{GNOME_WEB_REF}} ({{GNOME_SHA}})
- builder glibc: {{GLIBC_VER}}

### Manual QA

1. chmod +x the AppImage and run it (GUI).
2. Confirm profile migrator does not abort (no /opt/webkitgtk-dnd path errors).
3. Open the HTML harness from this release (or bundled under share/webkitgtk-dnd-fix/html).
4. External file drop from Files into layer2 / an upload UI: files should populate.
5. Layer1 web uri-list attack page: no file contents.
6. Layer4 local drag/export: no surprise file grant.
7. File picker still works.

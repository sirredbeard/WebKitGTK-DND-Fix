# Manual interactive QA (AppImage)

This is the human E2E gate Opus called out. Unit tests can pass while browser DnD stays dead. You prove product + security on a real desktop.

## What you need

- Tip AppImage: `~/Downloads/GNOME_Web-WebKitGTK-DnD-x86_64.AppImage`
  - Must embed WebKit tip (today: `17647b75dff4…`). CI smoke already checked that.
- HTML kit: `~/Downloads/webkit-dnd-qa/html/` (or repo `html/`)
- Fedora 44+ recommended (AppImage glibc floor is F44 / 2.43)
- GNOME Files (Nautilus) for real external drops

Stage kit anytime:

```bash
./scripts/stage-manual-qa-kit.sh
```

## Launch

```bash
chmod +x ~/Downloads/GNOME_Web-WebKitGTK-DnD-x86_64.AppImage
# optional local server so file:// quirks do not confuse drops
cd ~/Downloads/webkit-dnd-qa/html
python3 -m http.server 8765
# other terminal:
~/Downloads/GNOME_Web-WebKitGTK-DnD-x86_64.AppImage --private-instance http://127.0.0.1:8765/
```

If the AppImage aborts on migrator, stop and report. That was a packaging bug; tip builds should not.

`--version` alone is a weak check (`Web <epiphany-shortrev>`). Use the cases below.

## Security and function cases

Mark each pass/fail. Security fails block any “DnD restored” claim.

### S1 - Web attack (Layer 1) - MUST PASS

Open `layer1-web-uri-list-no-files.html`.

1. Drag yellow box into blue box.
2. Page sets `text/uri-list` to `file:///etc/passwd` on dragstart.

Pass: log shows `files.length: 0` and green PASS. No name/size for passwd.  
Fail: any File object. Treat as CVE-class regression. Stop.

### S2 - Local / IsSource (Layer 4A) - MUST PASS

Open `layer4-local-drag-and-export.html`.

1. Drag red box into blue box on the same page.

Pass: `files.length === 0`.  
Fail: local drag grants files.

### S3 - Export sanitize (Layer 4B) - MUST PASS

Still on layer4.

1. Drag red box to Nautilus/Files window.
2. Pass: no new file created from `/etc/passwd`. Drag should not look like a real file offer.
3. Optional: drag a normal https link from another tab/page; non-file URL export can still work.

### F1 - Trusted external drop (Layer 2) - MUST PASS for product

Open `layer2-external-drop-files.html`.

1. Create `~/Downloads/webkit-dnd-qa/sample-drop.txt` with a known string.
2. From Files, drag that file onto the green box.

Pass: `files.length >= 1`, name matches, size > 0. Optionally read blob text in console.  
Fail: empty files on tip AppImage means IPC/filenames path still broken in the product (Opus hard case).

### F2 - Multi-file drop (optional)

Drop two small files at once. Expect `files.length >= 2`.

### F3 - Directory drop (document only)

Drop a folder. Record actual behavior. Do not expand scope if directories are ignored.

### N1 - Non-regression file picker

On any page with `<input type=file>`, click and pick a file. Must still work.

### N2 - Non-file in-page drag

Drag plain text or an image within a page. Must still work.

### P1 - Portal notes (Layer 3, optional)

Read `layer3-portal-notes.html`. On sandboxed GTK4, portal path should own filenames when present. Manual portal session only if you have a flatpak-like portal setup.

## Negative / leak sanity

- Canary: create `~/dnd-canary/canary.txt` with a random token. After S1-S3 and F1, search page logs and journal for that token. Must not appear in the page.
- Do not open or paste the canary into the browser yourself.

## What “good enough for private burn” means

All MUST PASS cases green on tip AppImage. Record:

- AppImage path and size
- Embedded engine sha if you have it (CI stamp or `strings` on squashfs)
- Host Fedora version
- Pass/fail per case
- Anything surprising (portal prompts, empty multi-drop, Wayland vs X11)

## What is still not proved by this kit alone

- Full `run-webkit-tests --gtk` garden
- WPE file-drop parity
- Clipboard paste Files (intentionally off)
- Nested KVM automation (separate path under `nested-gui/`)

## After you finish

Drop results into `findings/testing-plan.md` or a short note in the tracking issue. Do not claim upstream-ready until S1/S2/S3/F1 are green.

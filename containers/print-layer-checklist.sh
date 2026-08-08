#!/usr/bin/env bash
cat <<'CHK'
WebKitGTK DnD fix layer checklist
=================================
[ ] Layer 1 unit: SelectionData.SetURIListDoesNotPromoteFilenames
[ ] Layer 1 unit: SelectionData.TrustedSetFilenamesFromURIList
[ ] Layer 1 manual: html/layer1-web-uri-list-no-files.html -> files.length 0
[ ] Layer 2 manual: html/layer2-external-drop-files.html -> files.length >= 1
[ ] Layer 3 code review: DropTargetGtk4 portal path sets m_portalFilenames
[ ] Layer 3 manual (optional portal session): drop still grants files
[ ] Layer 4 unit: SelectionData.DragDataIsSourceDeniesFilenameAccess
[ ] Layer 4 unit: SelectionData.URIListWithoutFilenamesStripsFileURLs
[ ] Layer 4 manual: local drag no files; export to Nautilus not a passwd file
[ ] Non-regression: input type=file click still works
[ ] Cocoa untouched (no PLATFORM(COCOA) edits in the series)
CHK

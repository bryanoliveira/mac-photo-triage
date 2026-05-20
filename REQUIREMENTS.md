# Photo Triage — Requirements

## Overview

Native macOS app for organizing DSLR photos. Three primary views: **Gallery** (default, grid browse), **Preview** (view/edit single image), and **Triage** (compare similar images side-by-side, decide what to keep).

## Views

### Gallery View (Default)

- Resizable grid of thumbnails (pinch/scroll to resize grid density)
- Clicking a photo opens a **detail panel** (sidebar or popover):
  - Editable metadata (title, tags, rating)
  - EXIF summary (read-only): focal length, aperture, shutter, ISO, timestamp, camera body, lens
  - Buttons: "Open in Preview", "Start Triage from here"
  - Favorite toggle (⭐)
- Multi-select support (⌘-click, shift-click)
- Filter/sort: by date, by triage state (unreviewed / kept / trashed / favorite)
- Drag to reorder (optional, stretch goal)

### Preview Mode

- Display a single image at full resolution (fit-to-window, zoom with scroll/pinch)
- **Clipping warnings**: Toggle button (W) flashes red over blown highlights (channels ≥ 252/255) and blue over crushed shadows (channels ≤ 3/255). Helps catch exposure problems before deciding to keep or trash.
- **Rotate**: 90° step buttons (toolbar) + **Level panel** (level icon) with a −45°/+45° slider and ±0.5° nudge buttons for horizon correction
- **Crop**: Free-form crop + presets:
  - 1:1, 4:3, 3:2, 16:9, 5:4, 2:3, 9:16
  - Custom ratio input
- Apply/cancel crop with configurable keys (default: Enter / Escape)
- **Trash**: Send current image to trash and advance to next (Delete key or toolbar button)
- Navigation: forward/backward through image list
- Favorite toggle
- Keyboard shortcut to return to Gallery or Triage

### Triage Mode

- **Clipping warnings**: Same toggle (W) applies to both anchor and candidate panes simultaneously — flashing red/blue overlays make blown highlights and crushed shadows immediately visible for direct comparison.
- **Layout**: Two images side-by-side (50/50 split, resizable divider)
- **Left image** = anchor (current selection)
- **Right image** = most similar image to anchor (sorted by content similarity + time distance; always shows something — no threshold)
- **Actions**:
  - Keep left → mark anchor kept, trash candidate, load next candidate for same anchor
  - Keep right → mark candidate kept, trash anchor, candidate becomes new anchor with fresh candidates
  - Keep both → mark both kept, load next unreviewed candidate for same anchor
  - Keep none → trash both, advance anchor to next unreviewed image
  - When no candidates remain for the current anchor, advancing moves to the next anchor automatically
- **Auto-keep on forward navigation**: Moving to the next anchor (forward) automatically places `.keep` on the current anchor (signals "done with this one")
- **Navigation**:
  - Next/Previous anchor (configurable, default: ← / →)
  - Next/Previous candidate on right (configurable, default: ↑ / ↓)
- **Preview access**: Open Preview mode on left or right image
- **Zoom**: Independent zoom/pan on each side
- Metadata overlay toggle: EXIF summary
- Favorite toggle on either image

## Favorites

- Available from any view (Gallery, Preview, Triage)
- Stored as `.favorite` sentinel file
- Favorites filter available in Gallery view
- Visual indicator (star badge) on thumbnails and preview

## Image Similarity

Strategy (no ML, fast, offline):

1. **Perceptual hash (dHash)**: 16×16 difference hash per image, computed on import/scan
2. **Timestamp distance**: EXIF capture time difference as secondary signal
3. **Ranking**: Sort candidates by weighted combination of dHash Hamming distance + time proximity. No threshold — always show the best available candidate, even if distant (user may photograph same subject at different times/angles/weather).
4. **Cache**: Store hashes in a sidecar SQLite DB (`.photo-triage.db` in folder root)

## RAW + JPEG Pairing

- **Matching**: Same filename stem (e.g., `IMG_1234.CR3` ↔ `IMG_1234.JPG`)
- **Display priority**: Always show JPEG when pair exists; show RAW only if no JPEG
- **Edits**: Applied to JPEG only; RAW kept pristine
- **Trash**: Moving one member trashes the entire pair (JPEG + RAW)
- **Supported RAW**: CR2, CR3, NEF, ARW, DNG, RAF, ORF, RW2

## State Management (Sentinel Files)

All state stored as filesystem artifacts — portable, inspectable, no lock-in.

| File | Meaning |
|------|---------|
| `.keep` | Image explicitly marked "keep" (or auto-marked on forward triage navigation) |
| `.trash` | Image marked for trash (not yet deleted) |
| `.reviewed` | Image has been triaged (regardless of decision) |
| `.favorite` | Marked as favorite |
| `.photo-triage.db` | SQLite: perceptual hashes, timestamps, pair mappings, progress state |

Sentinel files live next to the image: `IMG_1234.JPG.keep`, `IMG_1234.JPG.trash`, etc.

**Trash execution**: "Empty trash" action physically moves `.trash`-marked files (+ paired RAW) to macOS Trash (via `NSWorkspace.shared.recycle`).

## Progress Tracking

The app remembers where you left off:
- Current anchor index in triage
- Last viewed image in gallery/preview
- Stored in `.photo-triage.db` (per-folder session state)
- On reopen, offers to resume from last position

## Keyboard Shortcuts

All shortcuts are **configurable** via Preferences. Defaults:

| Default Key | Action | Mode |
|-------------|--------|------|
| ← / → | Navigate images | Preview, Triage (anchor) |
| ↑ / ↓ | Next/prev candidate (right side) | Triage |
| L | Keep left | Triage |
| R | Keep right | Triage |
| B | Keep both | Triage |
| N | Keep none (trash both) | Triage |
| ⌘← / ⌘→ | Rotate 90° CCW/CW | Preview |
| Enter | Apply crop | Preview |
| Escape | Cancel crop / Return to previous view | Preview |
| Space | Toggle zoom-to-fit vs 100% | Preview, Triage |
| I | Toggle EXIF overlay | All |
| W | Toggle clipping warnings | Preview, Triage |
| T | Switch to Triage mode | Gallery, Preview |
| G | Switch to Gallery | Preview, Triage |
| F | Toggle favorite | All |
| P | Open left in Preview | Triage |
| ⇧P | Open right in Preview | Triage |
| ⌘Z | Undo last action | All |
| ⌘⇧Z | Redo | All |
| ⌘O | Open folder | All |
| ⌫ | Trash current image | Preview |
| ⌘⌫ | Empty trash (execute pending deletes) | All |
| +/- | Resize gallery grid | Gallery |

## Non-Functional

- **Platform**: macOS 14+ (Sonoma), native SwiftUI + AppKit where needed
- **Performance**: Handle folders of 1000+ images; lazy-load thumbnails; background hash computation
- **No network**: Fully offline, no telemetry, no cloud
- **Undo**: Full undo stack for triage decisions (marks are just sentinel files, easily reversible)
- **Window management**: Resizable, supports full-screen, remembers window position
- **Build**: `build.sh` for binary-only build; `make-app.sh` to build and assemble a signed `.app` bundle
- **Tests**: Unit + UI tests, runnable via `test.sh`

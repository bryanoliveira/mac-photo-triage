# Photo Triage — Requirements

## Overview

Native macOS app for organizing DSLR photos. Three primary views: **Gallery** (default, grid browse), **Preview** (view/edit single image), and **Triage** (compare similar images side-by-side, decide what to keep).

## Views

### Gallery View (Default)

- Resizable thumbnail grid; keyboard +/- changes column density
- Clicking a photo selects it and opens a **detail panel** (right sidebar):
  - Thumbnail preview of selected image
  - File info: filename, type (JPEG / RAW / RAW+JPEG), dimensions, file size
  - EXIF summary (read-only): camera body, lens, focal length, aperture, shutter speed, ISO, capture timestamp (includes seconds)
  - State indicator: current triage state and file type
  - Actions:
    - Favorite toggle (⭐)
    - "Open in Preview" — switches to Preview mode
    - "Start Triage from here" — switches to Triage mode anchored on this image
    - "Keep" / "Trash" / "Clear State" — direct triage decisions
    - **"Restore Original"** — appears only when the image has been cropped or rotated; replaces the current file with the backed-up original and refreshes the thumbnail immediately
  - Detail panel visibility toggled via toolbar button
- Filter bar: All / Kept / Trashed / Favorites (segmented control)
- Sort picker: Date Ascending / Date Descending (and other sort options)
- Statistics summary (count of reviewed, kept, trashed, favorites)
- **Empty Trash** button in toolbar: shows count of `.trash`-marked images; confirmation dialog before executing macOS Trash move (also ⌘⌫)
- **Scroll preservation**: when returning to Gallery from Preview or Triage, the gallery scrolls to and highlights the last-viewed image

### Preview Mode

- Display a single image at full resolution (fit-to-window by default; zoom with pinch/scroll, double-tap toggles 100%)
- **Space** resets zoom to fit-to-window regardless of current zoom state
- **Clipping warnings** (W): flashes red pixels over blown highlights (any channel ≥ 252) and blue pixels over crushed shadows (any channel ≤ 3). Helps catch exposure problems before deciding to keep or trash.
- **Guiding grid** (H): rule-of-thirds grid (4 lines, semi-transparent white) + center crosshair (thinner lines). Always visible in crop mode.

#### 90° Rotation

- Toolbar buttons (Cmd+Left / Cmd+Right) rotate 90° CCW / CW
- **Baked to file immediately**: the rotation is applied to the JPEG on disk (using a CGContext with swapped dimensions), not just a display transform
- The original is backed up to `.photo-triage-originals/` on first edit; subsequent rotations on the same file do not overwrite the backup
- Rotation is undoable (Cmd+Z restores from backup; Cmd+Shift+Z reapplies)
- Disabled while crop mode is active

#### Crop + Horizon Adjust

- **Entering crop mode**: clicking the Crop toolbar button checks for a backup (original) file
  - If no backup exists: loads the current file and initializes the crop rect to fill the image
  - If a backup exists (previously edited): loads the original backup file for display, and initializes the crop rect centered to the current (cropped) image's pixel dimensions — allowing the user to select an area larger than the current file
- **Crop overlay**:
  - Draggable corner handles resize the crop rect
  - Dragging inside the crop rect moves it
  - The selected area is shown at full brightness; the rest of the image (including letterbox areas) is dimmed by 50%
  - Rule-of-thirds grid drawn inside the crop rect
  - The guiding grid is always visible in crop mode
- **Horizon adjust strip** (shown below the image in crop mode):
  - Slider: ±15° range, 0.1° steps
  - ±0.5° nudge buttons; Reset button
  - Current angle displayed as text
  - The crop rect is clamped to the **safe zone**: the largest axis-aligned rectangle fully inside the rotated image that contains no black-corner pixels. Formula: `safeW = (W·cos θ − H·sin θ) / cos(2θ)`, `safeH = (H·cos θ − W·sin θ) / cos(2θ)`. The corners of the safe zone always touch the rotated image boundary.
- **Aspect ratio presets**: Free, 1:1, 4:3, 3:2, 16:9, 5:4, 2:3, 9:16 (segmented picker in toolbar while cropping)
- **Apply** (Enter or toolbar button): rotation is baked in first, then crop is applied — both in a single CGContext pass. The original is backed up first (no-op if already backed up). If recropping from original, the crop is applied to the original file rather than the current one.
- **Cancel** (Escape or toolbar button): discards crop rect and rotation adjustment, restores crop button to normal

#### Restore Original

- Appears in toolbar when the current image has been edited (backup exists)
- Replaces the current file with the original backup (does not delete the backup)
- Immediately refreshes the full-resolution view and the thumbnail in the gallery grid

#### Other Preview Features

- Trash current image (Delete): marks image for trash, advances to next image
- Navigation: ← → through current filter-sorted image list
- Favorite toggle (F): toggles `.favorite` sentinel
- EXIF overlay (I): shows camera/lens/settings badge overlaid on image
- Undo / Redo (Cmd+Z / Cmd+Shift+Z): reverses triage marks and file edits
- G: return to Gallery (scroll preserved); T: switch to Triage mode

### Triage Mode

- **Layout**: two images side-by-side with a resizable divider (50/50 default)
- **Left image** = anchor (current selection from gallery/navigation)
- **Right image** = most similar candidate (chosen by three-component weighted score; always shows a candidate — no threshold applied)
- **Candidate filter** (toolbar picker): controls which images can appear as candidates based on their similarity score
  - All: any non-trashed image is a candidate
  - Loose (≤ 0.65): excludes clearly unrelated photos
  - Moderate (≤ 0.45): requires same-scene visual similarity
  - Strict (≤ 0.25): near-duplicates only
- **Actions** (keyboard and toolbar buttons):
  - **Keep Left** (L): mark anchor kept, trash candidate, load next candidate for same anchor
  - **Keep Right** (R): mark candidate kept, trash anchor, candidate becomes new anchor with fresh candidates
  - **Keep Both** (B): mark both kept, load next candidate for same anchor
  - **Keep None** (N): trash both, advance anchor to next unreviewed image
  - **Swap** (S): swap anchor and candidate for visual comparison without making a decision
- **Auto-keep on forward navigation**: moving to next anchor (←/→) automatically places `.keep` on the current anchor
- **Navigation**:
  - ← / →: previous/next anchor
  - ↑ / ↓: previous/next candidate on right
- **Open in Preview**: P opens left image in Preview; Shift+P opens right
- **Independent zoom/pan** per pane; Space resets both panes to fit-to-window
- **Clipping warnings** (W): red/blue clipping overlay on both panes simultaneously
- **Guiding grid** (H): rule-of-thirds + crosshair on both panes simultaneously
- **EXIF overlay** (I): toggle metadata badge on both panes
- **Favorite toggle** (F): favorites the currently focused pane's image

## Favorites

- Available from any view (Gallery, Preview, Triage)
- Stored as `.favorite` sentinel file alongside the image
- Favorites filter available in Gallery view
- Visual star badge on thumbnails and in preview

## Image Similarity

Strategy: no ML, fully offline, fast.

1. **Perceptual hash (dHash)**: 16×16 difference hash — resize to 17×16 grayscale, compare adjacent horizontal pixels (left > right = 1, else 0) → 256-bit hash. Hamming distance measures structural similarity.
2. **Color histogram**: 16-bucket × 3-channel (RGB) normalized histogram computed from a 64px CGImageSource thumbnail. Captures dominant color distribution — crucial for distinguishing landscape vs. sky-heavy shots, green vs. brown terrain, etc. L1 distance: `Σ|a_i − b_i| / (2 × 3 channels)` → [0, 1].
3. **Timestamp distance**: EXIF capture time difference in seconds, capped at 1 hour.
4. **Aspect ratio / orientation**: image pixel dimensions compared to penalize portrait-vs-landscape mismatches.
5. **Ranking**: three-component weighted score (lower = more similar, range 0–1):
   - **Content 60%**: `(dHashDistance + histogramDistance) / 2` — each normalized to [0, 1]; falls back to dHash-only if histogram not available
   - **Time proximity 30%**: `min(secondsBetween / 3600.0, 1.0)` — shots within ~1 hour score best; unknown time treated as 1.0
   - **Aspect ratio 10%**: `abs(arA − arB) / max(arA, arB)` — 0 for identical ratio; 0 if either dimension unknown
6. **Cache**: hashes, histograms, and pixel dimensions stored in `.photo-triage.db` (SQLite via GRDB). Old records without histograms are backfilled automatically on next scan.
7. **No minimum threshold**: always return the best available candidate.

## RAW + JPEG Pairing

- **Matching**: same filename stem (e.g., `IMG_1234.CR3` ↔ `IMG_1234.JPG`)
- **Display priority**: always show JPEG when pair exists; show RAW only if no JPEG
- **Edits**: applied to JPEG only; RAW kept pristine (CropService enforces this)
- **Trash**: moving one member trashes the entire pair (JPEG + RAW sentinels created)
- **Supported RAW extensions**: CR2, CR3, NEF, ARW, DNG, RAF, ORF, RW2

## State Management (Sentinel Files)

All triage state is stored as filesystem artifacts — portable, inspectable, no lock-in.

| File | Meaning |
|------|---------|
| `.keep` | Image explicitly marked "keep" |
| `.trash` | Image marked for trash (not yet deleted) |
| `.reviewed` | Image has been triaged (regardless of outcome) |
| `.favorite` | Marked as favorite |
| `.photo-triage.db` | SQLite: perceptual hashes, histograms, pixel dimensions, progress state |

Sentinel files live next to the image file: `IMG_1234.JPG.keep`, `IMG_1234.JPG.trash`, etc. For RAW+JPEG pairs, sentinels on the JPEG are mirrored to the RAW automatically.

**Trash execution**: "Empty Trash" physically moves `.trash`-marked files (+ paired RAW) to macOS Trash via `NSWorkspace.shared.recycle`.

## Original Backup System

When a JPEG is edited for the first time (crop, rotation, or both):

- A backup directory `.photo-triage-originals/` is created next to the image file
- The original JPEG is copied there (e.g., `.photo-triage-originals/IMG_1234.JPG`)
- Subsequent edits do NOT overwrite this backup — it always represents the true original
- The backup enables:
  - **Undo**: restoring from backup reverts the file to its original state
  - **Restore Original**: explicit button in Preview toolbar and Gallery detail panel
  - **Recrop from original**: entering crop mode on an edited image loads the original for display and allows selecting an area larger than the current (cropped) image

Only JPEG files are edited; RAW files are never modified.

## Progress Tracking

The app remembers where you left off per folder:
- Last view (gallery / preview / triage)
- Last triage anchor index
- Last preview index
- Stored in `.photo-triage.db`
- On reopen, offers "Resume from last position?" or "Start Fresh"

## Keyboard Shortcuts

All shortcuts are **configurable** via Preferences (⌘,). Defaults:

| Default Key | Action | Mode |
|-------------|--------|------|
| ← / → | Navigate images | Preview; navigate anchor in Triage |
| ↑ / ↓ | Next/prev candidate (right pane) | Triage |
| L | Keep left | Triage |
| R | Keep right | Triage |
| B | Keep both | Triage |
| N | Keep none (trash both) | Triage |
| ⌘← / ⌘→ | Rotate 90° CCW/CW (baked to file) | Preview |
| Enter | Apply crop | Preview |
| Escape | Cancel crop / return to previous view | Preview |
| Space | Reset zoom to fit-to-window | Preview, Triage |
| I | Toggle EXIF overlay | All |
| W | Toggle clipping warnings | Preview, Triage |
| H | Toggle guiding grid | Preview, Triage |
| S | Swap anchor and candidate | Triage |
| T | Switch to Triage mode | Gallery, Preview |
| G | Switch to Gallery | Preview, Triage |
| F | Toggle favorite | All |
| P | Open left pane in Preview | Triage |
| ⇧P | Open right pane in Preview | Triage |
| ⌘Z | Undo last action | All |
| ⌘⇧Z | Redo | All |
| ⌘O | Open folder | All |
| ⌫ | Trash current image | Preview |
| ⌘⌫ | Empty trash (execute pending deletes) | All |
| +/- | Resize gallery grid (more/fewer columns) | Gallery |

## Non-Functional Requirements

- **Platform**: macOS 14+ (Sonoma), native SwiftUI + AppKit interop
- **Performance**: handle folders of 1000+ images; lazy-load thumbnails; background hash computation; thumbnail reload is targeted to individual assets (not full-grid reload)
- **No network**: fully offline, no telemetry, no cloud
- **Undo**: full undo stack for triage decisions and file edits; file edits (crop, rotation) undo by restoring from backup
- **Window management**: resizable, supports full-screen
- **Build**: `build.sh` for binary-only build; `make-app.sh` to build and assemble a signed `.app` bundle
- **Tests**: unit tests runnable via `swift test` / `test.sh`

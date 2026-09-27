# Photo Triage — Requirements

## Overview

Native macOS app for organizing DSLR photos. Three primary views: **Gallery** (default, grid browse), **Preview** (view/edit single image), and **Triage** (compare similar images side-by-side, decide what to keep).

## Views

### Gallery View (Default)

- Resizable thumbnail grid; keyboard +/- (or the size slider in the status bar) changes column density; the column count and detail-panel visibility persist across launches
- Thumbnails show the decision at a glance: green check badge = kept, red trash badge = marked for trash (trashed thumbnails are also dimmed and desaturated), star = favorite, purple RAW tag = RAW+JPEG pair. Each badge has its own corner so they never collide, even at 12 columns
- Single click selects immediately; double-click opens Preview; right-click opens a context menu (Open in Preview, Start Triage Here, Keep, Mark for Trash, Clear Decision, Favorite, Show in Finder)
- **Keyboard culling**: ←/→ move the selection, ↑/↓ move by a row, Return/Space open Preview, K keeps, ⌫ marks for trash, U clears the decision (K/⌫ advance to the next photo), F favorites, T triages from the selection, I toggles the detail panel
- Clicking a photo selects it and opens a **detail panel** (right sidebar):
  - Thumbnail preview of selected image
  - File info: filename, type (JPEG / RAW / RAW+JPEG), dimensions, file size
  - EXIF summary (read-only): camera body, lens, focal length, aperture, shutter speed, ISO, capture timestamp (includes seconds)
  - Status pill (Kept / Trashed / Unreviewed) plus a Keep · Undecided · Trash segmented control that changes it (undoable)
  - Actions:
    - Favorite toggle (⭐)
    - "Open in Preview" — switches to Preview mode
    - "Start Triage Here" — switches to Triage mode anchored on this image
    - **"Restore Original"** — appears only when the image has been edited; replaces the current file with the backed-up original (undoable) and refreshes the thumbnail immediately
    - "Show in Finder"
  - Detail panel visibility toggled via toolbar button or I
- **Toolbar** (never overlaps): folder button, filter (All / Unreviewed / Kept / Trashed / Favorites), sort menu, Empty Trash, detail-panel toggle. On narrow windows it falls back first to icon buttons, then to a filter pop-up menu, instead of squeezing controls on top of each other
- Sort menu: Date (oldest/newest first), Name (A–Z / Z–A); ties in capture time are broken by filename so the order is stable
- **Status bar** (bottom): review progress bar + "N of M reviewed (x%)", kept / trash / favorite counts, background similarity-analysis progress, thumbnail size slider
- **Empty Trash** (toolbar, File menu, ⌘⌫ — in every view): shows the count of `.trash`-marked photos and always asks for confirmation before moving them to the macOS Trash
- Empty states: no folder (with "Reopen <last folder>"), folder without photos, and filter with no matches (with a hint and "Show All Photos")
- **Scroll preservation**: when returning to Gallery from Preview or Triage, the gallery scrolls to and highlights the last-viewed image

### Preview Mode

- Display a single image fit-to-window; images are decoded off the main thread and the neighbours are prefetched, so ←/→ is instant. Native resolution is loaded only when zooming past screen resolution
- **Zoom**: double-click toggles fit ↔ 100% (actual pixels) around the click point; pinch or mouse wheel zooms around the pointer; drag or two-finger scroll pans (panning is clamped to the image). **Space** fits, **Z** toggles 100%, **+/−** zoom in/out. The bottom bar shows the zoom level (percentage of actual pixels) with a Fit / 100% menu
- **Decision status is always visible**: a pill at the top-left of the photo reads KEPT (green), TRASHED (red) or UNREVIEWED, and the bottom bar has a Keep · Undecided · Trash control reflecting and changing the decision
- **Arrow keys keep**: pressing ← or → marks the photo being left as **kept** if it has no decision yet (a trashed photo stays trashed). This also applies at the first/last photo. Each auto-keep is undoable, and undo navigates back to that photo
- Under a filter such as "Unreviewed", navigation resolves the next photo *before* the current one leaves the list, so no photo is skipped
- **Clipping warnings** (W): flashes red pixels over blown highlights (**any** channel ≥ 252 — a single blown channel already loses detail) and blue pixels over crushed shadows (**all** channels ≤ 3). Helps catch exposure problems before deciding to keep or trash.
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
- **Aspect ratio presets**: Free, 1:1, 4:3, 3:2, 16:9, 5:4, 2:3, 9:16 (pop-up in the edit sidebar)
- While editing, navigation / decision / rotation keys are disabled (a message says "Apply or cancel the edit first") so an unsaved edit is never discarded by accident
- **Apply** (Enter or toolbar button): rotation is baked in first, then crop is applied — both in a single CGContext pass. The original is backed up first (no-op if already backed up). If recropping from original, the crop is applied to the original file rather than the current one.
- **Cancel** (Escape or toolbar button): discards crop rect and rotation adjustment, restores crop button to normal

#### Tone & Color Adjustments (Edit sidebar)

- **Histogram** (RGB + luminance) of the adjusted preview at the top of the sidebar, with shadow / highlight clipping indicators showing the clipped percentage. With W on, the red/blue clipping overlay is drawn on the *adjusted* preview
- Sliders show −100…+100 (Exposure in EV, −3…+3); every slider follows Lightroom's direction (right = brighter / more). Double-click a slider's name to reset it; each section (Light, Color) has its own Reset; "Reset All" resets tone, colour and straighten; hold "Preview Original" or \` to compare
- **Exposure**: gain of 2^EV in linear light; for +EV a smooth highlight shoulder maps the new white back to 1.0, so bright areas roll off instead of clipping (the previous `CIExposureAdjust` clipped everything above 1/2^EV)
- **Highlights** (−100 recovers bright areas, +100 brightens them) and **Shadows** (+100 opens dark areas, −100 deepens them): smooth curves on perceptual luminance concentrated in the bright / dark end and fading to zero through the midtones. The luminance change is applied as an RGB ratio, so colours are preserved (lifted shadows stay colourful instead of greying out). The curves are monotonic for every value — no tonal inversions or halos. Pure white and pure black stay fixed
- **Whites / Blacks**: white and black points (levels). **Brightness**: midtone gamma with black and white fixed. **Contrast**: smooth S-curve around mid-grey that never clips
- **Temperature / Tint**: luminance-neutral white-balance gains. **Vibrance**: saturation boost weighted towards muted colours. **Saturation**: uniform (−100 = monochrome)
- All adjustments are sampled into one 3D LUT and applied in a single CoreImage pass (32³ for the live preview, 64³ for the saved file), in the photo's own RGB colour space so Adobe RGB / Display P3 files are not clipped to sRGB
- Sidecars written by earlier versions (v1 slider scale) are migrated automatically when re-entering Edit mode

#### Metadata preservation on edit

- All edits (crop, rotation, tone adjustments) carry the original photo's EXIF/TIFF/GPS metadata (camera, lens, exposure, capture date, GPS) into the saved JPEG, copied from the pristine backup so it survives even repeated edits.
- The EXIF capture timestamp (`DateTimeOriginal`) is left unchanged; only the TIFF modify time (`DateTime`) is bumped to the edit time.
- Orientation is reset to upright (the edited pixels are already display-correct), and the editor stamps `Software` = "Photo Triage" plus a `UserComment` describing the edit.

#### Restore Original

- Appears in toolbar when the current image has been edited (backup exists)
- Replaces the current file with the original backup (does not delete the backup); undoable like any edit
- Immediately refreshes the full-resolution view, the thumbnail in the gallery grid and cached clipping masks

#### Other Preview Features

- Trash current image (⌫): marks image for trash, advances to next image
- Keep current image (K): marks it kept, advances to next image
- Clear decision (U): back to unreviewed, stays on the image
- Navigation: ← → through current filter-sorted image list (auto-keeps undecided photos, see above)
- Favorite toggle (F): toggles `.favorite` sentinel
- EXIF overlay (I): shows camera/lens/settings badge overlaid on image
- Undo / Redo (Cmd+Z / Cmd+Shift+Z): reverses triage marks and file edits; the Edit menu and button tooltips name the action ("Undo Keep")
- G or Esc: return to Gallery (scroll preserved); T: switch to Triage mode; Return: enter Edit mode
- Toolbar collapses to icons on narrow windows

### Triage Mode

- **Layout**: two images side-by-side with a resizable divider (50/50 default)
- **Left image** = anchor (current selection from gallery/navigation)
- **Right image** = most similar candidate (chosen by three-component weighted score; always shows a candidate — no threshold applied). Photos marked for trash are not offered as candidates; kept photos are
- **Reviewed photos are shown too**: anchor navigation walks through **every** photo in the gallery's sort order — kept and trashed ones included — so earlier decisions can be revisited. Entering Triage without an explicit photo starts from the Preview photo / gallery selection (even if reviewed), else the previous anchor, else the first unreviewed photo
- Each pane shows its role (Anchor / Candidate), a status pill (Kept / Trashed / Unreviewed), the candidate's **match %** (tooltip: visual difference and time between shots), filename and capture time
- The toolbar shows the anchor position ("12 / 340") and candidate position ("Candidate 2 / 15"); it collapses to icons on narrow windows
- **Candidate filter** (toolbar picker): controls which images can appear as candidates based on their similarity score
  - All: any non-trashed image is a candidate
  - Loose (≤ 0.65): excludes clearly unrelated photos
  - Moderate (≤ 0.45): requires same-scene visual similarity
  - Strict (≤ 0.25): near-duplicates only
- **Actions** (keyboard and toolbar buttons):
  - **Keep Left** (L): mark anchor kept, trash candidate, load next candidate for same anchor
  - **Keep Right** (R): mark candidate kept, trash anchor, candidate becomes new anchor with fresh candidates
  - **Keep Both** (B): mark both kept and stay on the same pair (swap or ↓ to continue)
  - **Keep None** (N): trash both, advance anchor to next unreviewed image
  - **Swap** (S): swap anchor and candidate for visual comparison without making a decision
- **Auto-keep on forward navigation**: moving to the next anchor (→) places `.keep` on the current anchor if it has no decision (trashed anchors stay trashed)
- **Completion screen**: → past the last photo shows a summary card (reviewed / kept / trash / favorite counts) with Start Over, Back to Gallery and Empty Trash…; ← or Esc dismisses it
- **Undo** restores the exact previous states of both photos (a previously kept candidate goes back to kept) and brings the pair back on screen
- **Navigation**:
  - ← / →: previous/next anchor
  - ↑ / ↓: previous/next candidate on right
- **Open in Preview**: P opens left image in Preview; Shift+P opens right
- **Synced zoom** (link toggle, on by default and persisted): both panes zoom and pan together for comparing focus; turn it off for independent zoom. Space fits both panes, Z toggles 100%, +/− zoom
- Divider: drag to resize (20–80%), double-click to reset to 50/50
- **Clipping warnings** (W): red/blue clipping overlay on both panes simultaneously
- **Guiding grid** (H): rule-of-thirds + crosshair on both panes simultaneously
- **EXIF overlay** (I): toggle metadata badge on both panes
- **Favorite toggle** (F): favorites the currently focused pane's image

## Feedback

- A short toast confirms decisions and undo/redo ("Kept · IMG_0102.JPG", "Undo Keep Left", "Last photo")
- Errors appear in a banner that dismisses itself after 8 seconds (or on click)

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
- On reopen, offers "Resume from last position?" or "Start Fresh"; resume locates the photo by path first (robust to files added/removed since), then by index
- The last opened folder is reopened automatically at launch

## Keyboard Shortcuts

All shortcuts are **configurable** via Preferences (⌘,). Defaults:

| Default Key | Action | Mode |
|-------------|--------|------|
| ← / → | Previous / next photo (Preview: keeps the photo being left if undecided) | Gallery, Preview; anchor in Triage |
| ↑ / ↓ | Previous / next candidate; row up / down in Gallery | Triage, Gallery |
| L | Keep left | Triage |
| R | Keep right | Triage |
| B | Keep both | Triage |
| N | Keep none (trash both) | Triage |
| K | Keep photo (and advance) | Gallery, Preview |
| ⌫ | Mark photo for trash (and advance) | Gallery, Preview |
| U | Clear keep/trash decision | Gallery, Preview |
| ⌘← / ⌘→ | Rotate 90° CCW/CW (baked to file) | Preview |
| Return | Open Preview (Gallery) · enter Edit / apply edit (Preview) | Gallery, Preview |
| Escape | Cancel edit / return to Gallery | Preview, Triage |
| Space | Fit to window (Preview/Triage) · open Preview (Gallery) | All |
| Z | Toggle 100% zoom | Preview, Triage |
| + / − | Zoom in / out (Preview, Triage) · larger / smaller thumbnails (Gallery). "+" works with or without Shift | All |
| I | Toggle EXIF overlay (Preview, Triage) · detail panel (Gallery) | All |
| W | Toggle clipping warnings | Preview (incl. Edit), Triage |
| H | Toggle guiding grid | Preview, Triage |
| S | Swap anchor and candidate | Triage |
| T | Switch to Triage mode | Gallery, Preview |
| G | Switch to Gallery | Preview, Triage |
| F | Toggle favorite | All |
| P | Open left pane in Preview | Triage |
| ⇧P | Open right pane in Preview | Triage |
| \` (hold) | Compare with original | Edit |
| ⌘Z | Undo last action | All |
| ⌘⇧Z | Redo | All |
| ⌘O | Open folder | All |
| ⌘⌫ | Empty trash (with confirmation) | All |

Shortcuts only act on the main window — typing in Settings never triggers photo actions.

## Non-Functional Requirements

- **Platform**: macOS 14+ (Sonoma), native SwiftUI + AppKit interop
- **Performance**: handle folders of 1000+ images; lazy-load thumbnails; background hash computation; thumbnail reload is targeted to individual assets (not full-grid reload); decoded thumbnails and screen-size images are cached in memory and neighbours are prefetched; images are never decoded on the main thread
- **No network**: fully offline, no telemetry, no cloud
- **Undo**: full undo stack for triage decisions and file edits. Decisions restore the exact previous state. File edits (crop, straighten, tone, 90° rotation, restore original) are undone by restoring a snapshot taken just before the edit, so undo returns to the *previous* version (not all the way to the original); undoing a photo's first edit also removes its backup
- **Window management**: resizable, supports full-screen
- **Build**: `build.sh` for binary-only build; `make-app.sh` to build and assemble a signed `.app` bundle
- **Tests**: unit tests runnable via `swift test` / `test.sh`

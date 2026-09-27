# Photo Triage

A native macOS app for fast, offline triage of DSLR photo folders. Browse a gallery, review images side-by-side against their closest match, and cull duplicates/near-duplicates — all backed by plain files on disk, with no cloud, database lock-in, or ML models.

- **Gallery** — resizable thumbnail grid with filters, sort, keyboard culling and a detail sidebar
- **Preview** — single-photo view that always shows whether the photo is kept or trashed; arrow keys keep as you go; true 100% zoom; crop, straightening, tone/colour adjustments (with a live histogram) and 90° rotation baked to disk
- **Triage** — side-by-side comparison against the most similar image, with one-key keep/trash decisions; walks every photo, including ones you've already reviewed

State (`.keep` / `.trash` / `.favorite` / `.reviewed`) is stored as zero-byte sentinel files next to each photo, so it's inspectable and portable without opening the app. See [REQUIREMENTS.md](REQUIREMENTS.md) for the full feature spec and [ARCHITECTURE.md](ARCHITECTURE.md) for how it's implemented.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ / Swift 5.9+ command line tools

## Getting Started

```bash
# Clone and enter the repo
git clone git@github.com:bryanoliveira/mac-photo-triage.git
cd mac-photo-triage

# Build a release binary
./build.sh
.build/release/PhotoTriage

# Or build a double-clickable, ad-hoc signed .app bundle
./make-app.sh
open PhotoTriage.app
```

Run the test suite with `./test.sh` (or `./test.sh <TestName>` to filter). There is no `.xcodeproj` — everything goes through Swift Package Manager.

On first launch, open a folder (⌘O) containing JPEGs and/or RAW files. The app pairs RAW+JPEG files that share a filename stem (e.g. `IMG_1234.CR3` + `IMG_1234.JPG`), computes perceptual hashes in the background, and drops you into the Gallery.

## Usage

### Gallery

The default view. Click a thumbnail to select it and open the detail sidebar (decision control, file info, EXIF summary, favorite toggle, and **Restore Original** for edited images). Badges show each photo's decision; trashed photos are dimmed. Cull straight from the grid with `K` (keep), `⌫` (trash) and `U` (clear) — the selection advances — or right-click for more. Use the filter (All / Unreviewed / Kept / Trashed / Favorites) and sort menu to navigate large folders, and `+`/`-` (or the status-bar slider) to resize the grid.

### Preview

Opens a single photo. A pill on the photo and the Keep · Undecided · Trash control in the bottom bar show its decision. Stepping with `←`/`→` marks the photo you leave as **kept** unless you already decided (`K` keep, `⌫` trash, `U` clear). Double-click or `Z` for true 100% zoom, scroll or pinch to zoom around the pointer, `Space` to fit.

Rotate 90° (⌘←/⌘→ — baked to the JPEG immediately) or press **Edit** (Return) to crop, straighten (±15°) and adjust Exposure, Contrast, Highlights, Shadows, Whites, Blacks, Brightness, Temperature, Tint, Vibrance and Saturation while watching a live histogram. Exposure rolls highlights off instead of clipping, and Shadows/Highlights preserve colour. Clipping warnings (`W`) flash blown highlights/crushed shadows (on the adjusted image while editing); the guiding grid (`H`) overlays rule-of-thirds. All edits back up the original to `.photo-triage-originals/` on first touch; undo (⌘Z) steps back one edit at a time and **Restore Original** is always available.

### Triage

Shows your current image (anchor, left) next to its best-matching candidate (right, with a match %), ranked by a weighted score of perceptual hash, color histogram, capture time, and aspect ratio. Decide with `L` (keep left) / `R` (keep right) / `B` (keep both) / `N` (trash both) / `S` (swap for comparison only). `←`/`→` step through **every** photo, including ones already kept or trashed, and each pane shows its status. Zoom is synced between panes by default (link button) for comparing focus. The candidate filter picker (All/Loose/Moderate/Strict) controls how similar a candidate must be to surface.

### Keyboard Shortcuts

All shortcuts are rebindable in Preferences (⌘,). See [REQUIREMENTS.md § Keyboard Shortcuts](REQUIREMENTS.md#keyboard-shortcuts) for the full default table.

### Trash

Trash is soft: triage decisions and `Delete` in Preview only mark files with a `.trash` sentinel — nothing touches disk yet. Nothing is actually deleted until you run **Empty Trash** (⌘⌫, always confirmed), which moves marked files (and their RAW/JPEG partner) to the macOS Trash via `NSWorkspace`, so they're always recoverable from Trash afterward.

## Project Layout

```
Sources/PhotoTriage/
├── App/         entry point, global AppState, KeyBindings
├── Models/      ImageAsset, ImageFolder, SimilarityEngine, HashCache, ProgressStore, SentinelState
├── Views/       Gallery/ Preview/ Triage/ Shared/ Settings/
├── Services/    CropService, EditHistory, ImagePipeline, ClippingAnalyzer, TrashService
└── Utilities/   DHash, ColorHistogram, Histogram, EXIFReader, FileExtensions
Tests/
├── PhotoTriageTests/     unit tests (swift test)
└── PhotoTriageUITests/   XCUITest stubs (not yet exercised — need fixture images)
```

For the full breakdown of every file's responsibility, data flow between views, and the internals of crop/rotation/similarity, see **[ARCHITECTURE.md](ARCHITECTURE.md)**.

## Extending the App

A few common extension points and where to make them:

### Add a keyboard shortcut

1. Add a case to `KeyAction` in `Sources/PhotoTriage/App/KeyBindings.swift`, plus its `displayName` and default binding.
2. Handle the new `KeyAction` in the relevant view's `focusedKeyboardHandler { action in ... }` closure (`GalleryView`, `PreviewView`, or `TriageView`).
3. It automatically appears in the rebindable shortcuts table in Settings — no extra UI work needed.

### Add a new sentinel (triage state)

1. Add a case to `SentinelState` in `Sources/PhotoTriage/Models/SentinelState.swift` and its file extension.
2. Add read/write/clear logic to `ImageAsset` (mirroring the RAW partner if the state should apply to pairs, following the pattern of `markKept()`/`toggleFavorite()`).
3. Wire up UI: a toolbar/detail-panel action to set it, and (optionally) a `CandidateFilter`-style gallery filter to query it.

### Add a tone or colour slider

Add a field to `ImageAdjustments` (plus its `CodingKeys` and `encode`), implement it inside `ToneMapper.map` (a pure function — add a test in `ToneMapperTests`), and add an `AdjustmentRow` to `EditSidebarPanel` in `CropOverlay.swift`. The LUT picks it up automatically for both the live preview and the saved file.

### Adjust or extend the similarity score

The scoring logic lives entirely in `Sources/PhotoTriage/Models/SimilarityEngine.swift`, with the weighted formula documented in `ARCHITECTURE.md § Similarity Engine`. To add a new signal (e.g. a face-count or sharpness score):

1. Compute and cache the new value in `HashCache.swift` (add a column; `HashCache.init` already has a pattern for additive, backfilled migrations).
2. Fold it into the weighted score in `SimilarityEngine`, adjusting the existing weights so they still sum to 1.0.
3. Add a test in `Tests/PhotoTriageTests/SimilarityEngineTests.swift` covering the new term in isolation.

### Add a new file edit (beyond crop/rotate)

All destructive JPEG edits go through `Sources/PhotoTriage/Services/CropService.swift`, which owns the `.photo-triage-originals/` backup contract and the metadata-preserving `writeJPEG` path. New edit operations should:

1. Call `backupURL(for:)` / rely on the existing backup-on-first-edit behavior — never write to a file that hasn't been backed up.
2. Funnel the pixel output through `writeJPEG(_:to:metadataFrom:editNote:)` so EXIF/TIFF/GPS metadata and the creation-date fix-up are preserved automatically.
3. Expose it from `AppState` through `performFileEdit(on:label:_:)` (see `rotate`/`applyEdit`/`restoreOriginal`) — that snapshots the file before and after for exact undo/redo and refreshes every cache and view of the photo.

### Add a new view/mode

Follow the existing `Gallery`/`Preview`/`Triage` pattern: a folder under `Views/`, a case in `AppState.AppView`, and a transition method on `AppState` (see `showGallery()`) that syncs shared state (`selectedAsset`, etc.) before switching `currentView`.

Before submitting changes, run `./test.sh` and update `TODO.md`/`ARCHITECTURE.md` if you've changed behavior they document.

## Documentation Map

| Document | Contents |
|----------|----------|
| [README.md](README.md) | This file — quick start, usage, extension points |
| [REQUIREMENTS.md](REQUIREMENTS.md) | Full feature spec from the user's perspective |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Technical design: file responsibilities, data flow, algorithms |
| [TODO.md](TODO.md) | Implementation status and known gaps |

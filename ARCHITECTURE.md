# Photo Triage — Architecture

## Technology Stack

- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI (primary) + AppKit interop for image manipulation and event handling
- **Image handling**: ImageIO (decode, thumbnail generation, pixel dimensions), CGImage / CGContext (crop, rotation, clipping analysis), CoreImage (`CIColorCubeWithColorSpace` for tone/colour adjustments), NSImage (display)
- **Hashing**: vImage (resize for dHash) + custom dHash implementation; CoreGraphics for color histogram
- **Database**: SQLite via GRDB.swift (hash cache + progress state)
- **File operations**: FileManager + NSWorkspace (macOS Trash)
- **Minimum deployment**: macOS 14.0 (Sonoma)
- **Build system**: Swift Package Manager (`build.sh`, `test.sh`, `make-app.sh`)
- **Testing**: XCTest (unit, 150 tests); XCUITest stubs present (not yet exercised)

## Project Structure

```
photo-triage/
├── build.sh                          # swift build -c release
├── make-app.sh                       # Build + assemble signed .app bundle
├── test.sh                           # swift test
├── Package.swift                     # SPM manifest (depends on GRDB.swift 6.24+)
├── Sources/PhotoTriage/
│   ├── App/
│   │   ├── PhotoTriageApp.swift      # Entry point, WindowGroup, menus, ContentView (toast, error banner, Empty Trash alert)
│   │   ├── AppState.swift            # Global @MainActor ObservableObject: navigation, decisions, file edits, undo/redo
│   │   └── KeyBindings.swift         # Configurable keyboard shortcut definitions + UserDefaults persistence
│   ├── Models/
│   │   ├── ImageAsset.swift          # Single image or JPEG+RAW pair; manages sentinel state (setTriageState)
│   │   ├── ImageFolder.swift         # Scans folder (reads EXIF up front), pairs RAW+JPEG, filter/sort, statistics
│   │   ├── ImageAdjustments.swift    # Tone/colour slider values (Codable, v1 migration) + ToneMapper pixel math + LUT
│   │   ├── SentinelState.swift       # TriageState enum; read/write zero-byte sentinel files (.keep, .trash, .favorite, .reviewed)
│   │   ├── SimilarityEngine.swift    # dHash + color histogram + timestamp + aspect ranking
│   │   ├── HashCache.swift           # SQLite persistence for hashes, histograms, pixel dimensions
│   │   └── ProgressStore.swift       # Per-folder resume position (last view, anchor, preview index, image path)
│   ├── Views/
│   │   ├── Gallery/
│   │   │   ├── GalleryView.swift     # Grid, adaptive toolbar (ViewThatFits), status bar, context menu, keyboard culling
│   │   │   ├── GalleryThumbnail.swift # Thumbnail cell (decision badges, trashed dimming) + AsyncThumbnail, via ImagePipeline
│   │   │   └── DetailPanel.swift     # Sidebar: decision control, file info, EXIF, actions, Restore Original
│   │   ├── Preview/
│   │   │   ├── PreviewView.swift     # Single photo: status pill, DecisionControl, ZoomControls, adaptive toolbar, edit entry
│   │   │   └── CropOverlay.swift     # Edit mode: crop handles, straighten, safe zone, tone sidebar, histogram, live clipping
│   │   ├── Triage/
│   │   │   ├── TriageView.swift      # Side-by-side panes, synced zoom, completion overlay, adaptive toolbar, divider
│   │   │   ├── ComparisonPane.swift  # One pane: image + role/status/match% overlays
│   │   │   └── TriageControls.swift  # Keep L/R/Both/None buttons, stats, TriageCompleteView
│   │   ├── Shared/
│   │   │   ├── ZoomableImageView.swift    # ZoomableImageCore (fit/100%/wheel/pinch/pan, full-res on demand) + ScrollWheelMonitor
│   │   │   ├── DecisionBadge.swift        # Kept/Trashed/Unreviewed badge (icon + pill styles), ToastView
│   │   │   ├── ClippingOverlay.swift      # Flashing red/blue overlay driven by ClippingAnalyzer
│   │   │   ├── GuidingGridOverlay.swift   # Rule-of-thirds grid + center crosshair
│   │   │   ├── EXIFOverlay.swift          # Metadata badge overlay with position control
│   │   │   ├── FavoriteButton.swift       # Star toggle, thumbnail badges (one per corner), RAW badge
│   │   │   └── KeyboardHandler.swift      # NSEvent local monitor → KeyAction dispatch; KeyEventMatcher (pure)
│   │   └── Settings/
│   │       └── ShortcutSettings.swift    # Preferences: rebind keys table, reset to defaults
│   ├── Services/
│   │   ├── CropService.swift         # Apply crop/rotation/tone to JPEG, backups in .photo-triage-originals/, CIContext.shared
│   │   ├── EditHistory.swift         # EditSnapshot capture/restore — exact undo/redo for file edits
│   │   ├── ImagePipeline.swift       # Off-main decoding, thumbnail/screen/full tiers, NSCache, prefetch, invalidation
│   │   ├── ClippingAnalyzer.swift    # Actor: red/blue clipping masks from a URL (cached) or an in-memory CGImage
│   │   └── TrashService.swift        # Move files to macOS Trash via NSWorkspace.shared.recycle
│   └── Utilities/
│       ├── DHash.swift               # Perceptual hash: 17×16 grayscale → 256-bit, Hamming distance
│       ├── ColorHistogram.swift      # 16-bucket RGB signature from 64px thumbnail (similarity); L1 distance
│       ├── Histogram.swift           # 256-bin RGB + luminance histogram + clip fractions (Edit sidebar)
│       ├── EXIFReader.swift          # Extract EXIF metadata via ImageIO → EXIFMetadata struct
│       └── FileExtensions.swift      # RAW/JPEG extension sets, URL helpers, EXIF orientation helpers
├── Tests/PhotoTriageTests/
│   ├── AppStateTests.swift           # Preview auto-keep, filtered navigation, triage order, undo, file-edit undo
│   ├── ToneMapperTests.swift         # Every adjustment curve, monotonicity, LUT layout, CI render, Codable migration
│   ├── EditHistoryTests.swift        # Snapshot undo/redo incl. backup removal/recreation
│   ├── ImagingUtilitiesTests.swift   # Histogram, clipping masks, ImagePipeline, TriageState sentinels
│   ├── KeyEventMatcherTests.swift    # Shortcut matching ("+" with/without Shift), default binding collisions
│   ├── TestSupport.swift             # Real-JPEG fixture helpers
│   ├── DHashTests.swift, ColorHistogramTests.swift, CropServiceTests.swift, SentinelStateTests.swift,
│   ├── ImageFolderTests.swift, KeyBindingsTests.swift, FileExtensionsTests.swift,
│   └── SimilarityEngineTests.swift, ProgressStoreTests.swift
└── Tests/PhotoTriageUITests/        # XCUITest stubs (XCTSkip — no fixture images / UI test target yet)
```

## Data Flow

```
Folder Scan
    │
    ▼
ImageFolder   — enumerates files, pairs RAW+JPEG by stem, reads sentinels
    │
    ▼
SimilarityEngine — computes/loads dHash + color histogram, ranks candidates
    │
    ▼
AppState (@MainActor ObservableObject)
    │   published: folder, currentView, selectedAsset, triageAnchor/Candidate,
    │              previewAsset, cropVersion, candidateFilter, show* toggles, …
    │
    ├──▶ GalleryView
    │       LazyVGrid inside ScrollViewReader — scrolls to selectedAsset on appear
    │       and on .onChange(of: currentView) when returning from Preview/Triage
    │
    ├──▶ PreviewView
    │       ZoomableImageView (reloadToken: cropVersion, request: ZoomRequest)
    │       CropOverlay (url: cropSourceURL ?? displayURL, initialCropHint, showClippingWarnings)
    │
    └──▶ TriageView
            ControlledZoomableImageView per pane (one shared ZoomState binding when synced)
            TriageControls + candidateFilter picker

ImagePipeline (shared) ◀── every image view decodes through it; AppState prefetches neighbours
```

## AppState

`AppState` is the single source of truth. Key published properties:

| Property | Type | Purpose |
|----------|------|---------|
| `folder` | `ImageFolder?` | Currently open folder |
| `currentView` | `AppView` | `.gallery`, `.preview`, or `.triage` |
| `selectedAsset` | `ImageAsset?` | Selected item in gallery |
| `previewAsset` | `ImageAsset?` | Image being previewed |
| `triageAnchor` / `triageCandidate` | `ImageAsset?` | Left / right pane in triage |
| `triageFinished` | `Bool` | → ran past the last photo; shows the completion overlay |
| `candidateFilter` | `CandidateFilter` | Triage candidate score threshold (persisted) |
| `cropVersion` | `Int` | Incremented on every file edit; `ZoomableImageView` uses as `reloadToken` |
| `showEXIFOverlay` / `showClippingWarnings` / `showGuidingGrid` | `Bool` | Global overlay toggles |
| `showDetailPanel`, `galleryColumns`, `syncTriageZoom` | | Layout preferences (persisted in UserDefaults) |
| `toast` | `String?` | Short confirmation message, auto-cleared after 1.6 s |
| `showEmptyTrashConfirmation` | `Bool` | Drives the single Empty Trash alert in `ContentView` |
| `canUndo` / `canRedo` | `Bool` | Published so buttons and menus update; `undoLabel` / `redoLabel` name the action |

### Decisions

All keep/trash/clear changes go through `AppState` so they are undoable and produce a toast:

- `setState(_:on:label:context:)` — any asset, any `TriageState` (detail panel, context menu)
- `decideSelected(_:)` — gallery selection, then advances the selection
- `keepPreviewImage()` / `trashPreviewImage()` / `clearPreviewImage()` — Preview; keep/trash advance
- `nextPreviewImage()` / `previousPreviewImage()` — **auto-keep** the photo being left if it has no decision, then move. The target is resolved from the filtered list *before* the state change, because under "Unreviewed" the kept photo leaves the list
- `AppState.neighbor(of:in:)` — next item, else previous (used after a photo leaves the filtered list)

### Undo stack

`[UndoAction]` with a matching redo stack:

```swift
struct StateChange { let asset: ImageAsset; let from: TriageState; let to: TriageState }
enum UndoContext { case none, preview(ImageAsset), triage(anchor:, candidate:) }

enum UndoAction {
    case stateChange([StateChange], label: String, context: UndoContext)  // decisions, auto-keep, triage pairs
    case toggleFavorite(ImageAsset)
    case fileEdit(ImageAsset, before: EditSnapshot, after: EditSnapshot, label: String)
}
```

- **State changes** record each asset's *previous* `TriageState`, so undo restores it exactly (a previously kept triage candidate returns to kept, not to unreviewed). Undo also restores the `context`: Preview jumps back to the photo, Triage restores the anchor/candidate pair.
- **File edits** (crop + straighten + tone, 90° rotation, restore original) all run through `performFileEdit`: capture an `EditSnapshot` → run the `CropService` operation → capture another snapshot → push `.fileEdit`. Undo restores `before`, redo restores `after` (see **EditHistory**). Every edit, undo and redo calls `didModifyFile`, which invalidates `ImagePipeline` and `ClippingAnalyzer` caches, bumps `cropVersion` and `asset.thumbnailVersion`, and re-reads EXIF/dimensions.
- Opening a folder or emptying the trash clears both stacks (entries would point at other or deleted files).

**`showGallery()`**: before switching to `.gallery`, syncs `selectedAsset` from `previewAsset` or `triageAnchor` so the gallery always scrolls to the last-viewed image.

## ImageAsset

```swift
final class ImageAsset: Identifiable, ObservableObject, Equatable, Hashable {
    let id: UUID
    let displayURL: URL          // JPEG if pair exists, otherwise RAW
    let jpegURL: URL?
    let rawURL: URL?
    let stem: String             // Filename without extension
    let folderURL: URL

    @Published var exifMetadata: EXIFMetadata?
    @Published var dHash: Data?
    @Published var colorHistogram: Data?
    @Published var imageSize: CGSize?
    @Published var sentinelState: SentinelState
    @Published var thumbnailVersion: Int = 0  // Increment to force thumbnail reload

    var triageState: TriageState               // .unreviewed / .reviewed / .kept / .trashed
    func setTriageState(_ state: TriageState)  // writes sentinels, mirrors to the RAW partner
}
```

`thumbnailVersion` is incremented by `AppState` after every file edit (crop, rotation, undo, redo, restore). `GalleryThumbnail` uses `.task(id: asset.thumbnailVersion)` so only the affected image's thumbnail reloads — not the entire grid. `AsyncThumbnail` in `DetailPanel` accepts `reloadToken: asset.thumbnailVersion` for the same reason.

## EditHistory

`EditSnapshot` = a copy of the image file, a copy of its edit sidecar (if any), and whether the pristine backup existed. Snapshots live in a per-process temp directory (`$TMPDIR/PhotoTriage-Undo-<pid>`).

- `capture(url)` — copy the current state
- `restore(snapshot, to: url, originalIfMissing:)` — put the file and sidecar back; if the snapshot had **no** backup, the backup is deleted (undoing a photo's first edit makes "Restore Original" disappear again); if it expects a backup that is missing, the backup is recreated from `originalIfMissing` (redo of a first edit passes the `before` snapshot, which *is* the original)

This replaces the old "undo = restore original / redo = re-run the crop" approach, which lost earlier edits (undoing a rotation after a crop dropped the crop) and re-ran crops without their tone adjustments.

## ImagePipeline

Singleton `ImagePipeline.shared`; all decoding happens in detached tasks with `kCGImageSourceShouldCacheImmediately`, never on the main thread (`NSImage(contentsOf:)` decoded lazily at first draw on the main thread, stalling every navigation).

| Tier | Max pixel size | Used by |
|------|----------------|---------|
| `.thumbnail` | 512 | Gallery cells, detail panel, instant placeholder in Preview |
| `.screen` | longest screen edge × backing scale, clamped 2048–5120 | Fit-to-window display, prefetch |
| `.full` | native | Loaded only when zoomed past screen resolution |

- Two `NSCache`s (thumbnails 256 MB, large 900 MB, cost = w×h×4); concurrent requests for the same key share one decode
- `invalidate(url)` bumps a per-URL version that is part of every cache key, so edited files never show stale pixels
- `prefetch(urls)` — Preview warms ±1/+2 neighbours; Triage warms the next candidate and the next anchor
- `pixelSize(for:)` / `orientedPixelSize(url:)` — EXIF-orientation-aware dimensions from metadata only

## ZoomableImageCore

Shared by `ZoomableImageView` (Preview, owns its `ZoomState`) and `ControlledZoomableImageView` (Triage, binding — both panes get the same binding when zoom is synced).

- `ZoomState { scale, offset }`, `scale` relative to fit (1 = fit, max 16). The image view is framed to the fitted size, then `scaleEffect` + `offset`
- **100%** = `pixelWidth / (fittedWidth × displayScale)` — true actual pixels (the old "100%" was scale 1.0, i.e. identical to fit)
- `setScale(_:around:)` keeps the image point under the pointer fixed: `offset' = t − (t − offset)/scale × scale'`; offsets are clamped so the image can't be dragged off-screen
- Input: double-click (fit ↔ 100% at the click point), `MagnifyGesture` (around its start location), drag to pan, `ScrollWheelMonitor` (mouse wheel zooms around the pointer; trackpad two-finger scroll pans when zoomed; ⌘-scroll zooms), `ZoomRequest` commands (`.fit`, `.actualSize`, `.zoomIn`, `.zoomOut`) from keys and buttons
- Reports the zoom percentage back to the Preview bottom bar

## Tone mapping (ImageAdjustments / ToneMapper)

`ImageAdjustments` holds slider values (all −1…+1 except exposure in EV). `ToneMapper` is the pure per-pixel implementation, operating on gamma-encoded RGB:

1. decode sRGB → linear; white balance gains (temperature/tint, normalised to keep grey luminance)
2. **exposure**: `y = x·2^EV`; for +EV a rational shoulder above knee k = 0.5: `y' = k + t/(1 + a·t)`, `t = y − k`, `a = (W−1)/((1−k)(W−k))`, `W = 2^EV` — C¹-continuous, maps W → 1, so nothing hard-clips
3. **shadows / highlights** on perceptual luminance `L = encode(Y)`: `s(L) = L + a·L·(1 − L/e)³` for L < e = 0.7 (peak at e/4). Boost strength a = 3·amount, cut strength a = 0.9·amount; the slope stays positive (monotonic) for all values. Highlights use the same curve mirrored around white. The result is applied as the ratio `Y'/Y` to all three linear channels → hue and saturation preserved
4. encode; per channel: levels (white point `1 − 0.30·whites`, black point `−0.15·blacks`), brightness gamma `p^(2^−amount)`, contrast S-curve pivoting at 0.5 with slope `2^amount`
5. vibrance / saturation around Rec.709 luma

`cubeData(dimension:)` samples `map` into an RGBA Float32 cube; `applyingCI(to:colorSpace:cubeDimension:)` applies it with `CIColorCubeWithColorSpace` in the photo's own RGB space. Export (`CropService.applyCrop`) uses 64³ and renders with `CIContext.shared` into the source colour space; the Edit preview uses 32³ on the ≤1500 px preview image.

**Sidecar format**: `ImageAdjustments` encodes `version: 2`. Version-1 sidecars (CIColorControls-style values: contrast/saturation as multipliers, whites/blacks as raw level points) are converted on decode.

## CropService (actor)

Handles all JPEG file modifications. Only JPEG is ever written; RAW is always kept pristine.

```
.photo-triage-originals/
    IMG_1234.JPG    ← copy of file before first edit (never overwritten)
    IMG_9999.JPG
```

**Key methods:**

`applyRotation(to url: URL, clockwise: Bool) async throws -> URL`
- Backs up original (no-op if already backed up)
- Loads JPEG via CGImageSource at native pixel dimensions, then bakes the EXIF orientation in (`applyingExifOrientation`) so camera files that store rotation as a tag rotate from their *displayed* orientation, not the raw sensor orientation
- Rotates using CGContext with swapped W/H canvas:
  - CW: `translateBy(0, w)` then `rotate(-.pi/2)`
  - CCW: `translateBy(h, 0)` then `rotate(.pi/2)`
- Saves back as JPEG at 0.9 compression, preserving original metadata (see **Metadata preservation** below)

`applyCrop(to url: URL, cropRect: CropRect, rotation: Double = 0, sourceURL: URL? = nil) async throws -> URL`
- Backs up `url` (no-op if already backed up)
- Loads pixels from `sourceURL` if provided (used when recropping from the original), otherwise from `url`
- Applies fine rotation (if |rotation| > 0.001°) via `rotateImage(_:byDegrees:)` — keeps original canvas dimensions, small black corners are covered by the subsequent crop
- Crops using `cgImage.cropping(to: cropRect.cgRect)` — CGImage uses upper-left origin matching JPEG file storage order; no Y-flip needed
- **DPI safety**: always loads via CGImageSource (native pixel dimensions). `NSImage.size` is DPI-scaled and would misplace crops on high-DPI images.
- Saves back as JPEG at 0.9 compression, preserving original metadata (see **Metadata preservation** below)

### Metadata preservation

Both edit paths funnel through `writeJPEG(_:to:metadataFrom:editNote:)`, which writes via ImageIO's `CGImageDestination` rather than re-encoding through `NSBitmapImageRep` (the old path silently dropped all EXIF/TIFF/GPS data). The full property set is copied from the **pristine backup** (`.photo-triage-originals/<filename>`), so camera, lens, exposure, capture date, and GPS survive every edit — even after repeated crops/rotations, since the backup is never overwritten. On write:

- **Orientation** is reset to `1` (Up) at both the top level and in the TIFF dict — the edit bakes display-upright, cropped/rotated pixels, so keeping the original tag would make viewers double-apply the rotation.
- **Dimensions** (`PixelWidth`/`PixelHeight` and EXIF `PixelXDimension`/`PixelYDimension`) are updated to the new image.
- **Modify time** (TIFF `DateTime`) is set to now; the capture timestamps (EXIF `DateTimeOriginal`/`DateTimeDigitized`) are left untouched.
- **Edit-process metadata** is stamped: TIFF `Software` = `"Photo Triage"` and EXIF `UserComment` describes the operation (e.g. `"Edited with Photo Triage: cropped to 300×200, tone adjustments applied"`).
- **Filesystem creation date** is restored from the backup after the file is written. Rewriting in place would otherwise stamp the file with today, which is what Finder's "Created" column and photo importers surface — independent of the embedded EXIF capture date. The **modification date** is left at "now", since the file really was edited (the edit itself is recorded in TIFF `Software` / EXIF `UserComment`).

`restoreOriginal(for url: URL) throws`
- Copies backup file back to `url`, replacing the current file

`nonisolated func backupURL(for url: URL) -> URL`
- Synchronous, no await needed — safe to call from view action handlers
- Returns `.photo-triage-originals/<filename>` adjacent to `url`

`hasBackup(for url: URL) -> Bool`
- Checks if backup file exists (used to show/hide Restore Original button)

## CropOverlay

### Live preview

The ≤1500 px base `CGImage` is kept alongside the displayed `NSImage`. A `.task(id: PreviewRenderKey(adjustments, clipping, hasImage))` debounces for 12 ms, then renders in a detached task: tone LUT (32³) → `Histogram.compute` → `ClippingAnalyzer.buildMasks(from:)` when W is on. Because the task is keyed on the adjustments, a newer slider value cancels the older render, so a slow render can never overwrite a newer one (the previous implementation spawned an unkeyed task per change and round-tripped through TIFF with a fresh `CIContext` each time).

While editing, `PreviewView` only accepts edit keys (Return, Esc, W); navigation/decision keys show a toast instead of silently discarding the edit.

### Visual Structure

```
VStack {
    GeometryReader {
        ZStack {
            Color.black                          // fills entire container incl. letterbox
            Image (full brightness, rotated)     // base layer
            Canvas (dim overlay, even-odd fill)  // dims everything except crop rect
            Image (full brightness, rotated)     // crop window — masked to crop rect only
              .mask { Canvas { crop rect } }     //   mask uses image-view-local coordinates
            Rectangle (crop border)
            ruleOfThirdsGrid (inside crop rect)
            cropHandles (corner circles)
            GuidingGridOverlay
        }
        .clipped()  // ← prevents rotated image from bleeding into toolbar or rotation strip
    }
    rotationStrip (slider + nudge buttons)
}
```

### Dim Overlay

A full-container `Canvas` fills every pixel with 50% black, except the crop rect (even-odd fill rule creates the hole):

```swift
Canvas { ctx, size in
    var combined = Path(CGRect(origin: .zero, size: size))  // outer rect
    combined.addRect(displayCrop)                            // crop rect (hole)
    ctx.fill(combined, with: .color(Color.black.opacity(0.5)),
             style: FillStyle(eoFill: true))
}
```

### Mask Coordinate Space

The crop-window `Image` uses `.resizable().aspectRatio(contentMode: .fit)`, so its layout frame equals the letterboxed image dimensions (e.g., 800×450 inside a 1000×700 container). The `.mask { Canvas { ... } }` draw closure is in that image view's local space (origin at the image's top-left, not the container's). The letterbox offset `(r.minX, r.minY)` must be subtracted:

```swift
ctx.fill(Path(CGRect(x: displayCrop.minX - r.minX,
                     y: displayCrop.minY - r.minY,
                     width: displayCrop.width,
                     height: displayCrop.height)), with: .color(.white))
```

### Safe Zone Formula

The largest axis-aligned rectangle inscribed in a W×H image rotated by θ, whose corners touch the rotated boundary (no black pixels included):

```
safeW = (W·cos θ − H·sin θ) / cos(2θ)
safeH = (H·cos θ − W·sin θ) / cos(2θ)
```

Derivation: solve the two binding constraints simultaneously (the top-right corner `(a,b)` touches the right edge, and the top-left corner `(-a,b)` touches the top edge):
```
a·cos θ + b·sin θ = W/2   [right edge]
a·sin θ + b·cos θ = H/2   [top edge]
```
Solving gives `a = (W·c − H·s) / (2·cos 2θ)` and `b = (H·c − W·s) / (2·cos 2θ)`, so `safeW = 2a`, `safeH = 2b`.

Guard `cos(2θ) > 0.001` to avoid division by zero near 45°; fall back to full image bounds.

### Entering Crop Mode from a Previously-Edited Image

When `PreviewView.enterCropMode()` detects a backup (`CropService().backupURL(for: displayURL)` exists):
1. `cropSourceURL` is set to the backup URL
2. `cropSizeHint` is set to the current image's pixel dimensions (read via `CGImageSourceCopyPropertiesAtIndex` — fast metadata-only, no full decode)
3. `CropOverlay` receives `url: cropSourceURL` (loads and displays the original) and `initialCropSizeHint: cropSizeHint`
4. After `loadImage()`, the initial `cropRect` is centered to `cropSizeHint` within the original's dimensions
5. On Apply, `CropService.applyCrop(to: displayURL, ..., sourceURL: cropSourceURL)` loads pixels from the original backup, crops, and writes to `displayURL`

## GalleryThumbnail / AsyncThumbnail

Both load through `ImagePipeline` (`.thumbnail` tier), so scrolling back through the grid reuses decoded thumbnails. Trashed photos render desaturated at 40% opacity; `ThumbnailBadges` places the decision icon top-left, favorite star top-right and RAW tag bottom-right.

`GalleryThumbnail` uses `.task(id: asset.thumbnailVersion)` — re-fires whenever `thumbnailVersion` changes, which `AppState` increments on every file write to that specific asset. This ensures only the edited image reloads, not all thumbnails.

`AsyncThumbnail` (used in `DetailPanel`) accepts `var reloadToken: Int = 0` and uses `.task(id: reloadToken)`. `DetailPanel` passes `asset.thumbnailVersion`.

## Gallery Scroll Preservation

`GalleryView.gridView(for:)` wraps the `LazyVGrid` in a `ScrollViewReader`. Each thumbnail has `.id(asset.id)`.

`scrollToSelected(proxy:anchor:)` calls `proxy.scrollTo(id, anchor:)` on the main queue with a 0.2 s ease-in-out animation.

Scroll fires on:
- `.onAppear` — initial load or returning to gallery view (centered)
- `.onChange(of: appState.currentView)` — triggers when switching back from Preview or Triage (centered)
- `.onChange(of: appState.selectedAsset?.id)` — keyboard navigation (anchor `nil` = minimal scroll)

### Adaptive toolbars

Gallery, Preview and Triage toolbars wrap several variants of the same row in `ViewThatFits(in: .horizontal)` (labels → icons → compact filter menu) and mark every control `.fixedSize()`. SwiftUI picks the first variant that fits, so controls are never compressed on top of each other (the old gallery toolbar gave pickers fixed frames narrower than their content, which overlapped neighbours, and let the statistics text wrap into a five-line column). Statistics moved to a bottom status bar.

`AppState.showGallery()` sets `selectedAsset` from `previewAsset` or `triageAnchor` before changing `currentView`, so `selectedAsset` is always correct when the gallery fires the scroll.

## Similarity Engine

Three-component score (lower = more similar, range 0–1):

```
score = contentScore × 0.60 + timeScore × 0.30 + aspectScore × 0.10

contentScore    = (dHashDistance + histogramDistance) / 2
                  (falls back to dHash-only if histogram absent)
dHashDistance   = hammingDistance(a.dHash, b.dHash) / 256.0
histogramDist   = Σ|a_i − b_i| / (2 × 3 channels)    → [0, 1]
timeScore       = min(secondsBetween / 3600.0, 1.0)   (unknown = 1.0)
aspectScore     = |arA − arB| / max(arA, arB)          (unknown = 0.0)
```

**No threshold**: always return sorted candidates; the right pane always shows the best candidate.

**`CandidateFilter`** (stored in UserDefaults, applied in `AppState.updateCandidates()`):
- `.all` — no score threshold
- `.loose` — score ≤ 0.65 (excludes clearly unrelated images)
- `.moderate` — score ≤ 0.45 (same-scene similarity required)
- `.strict` — score ≤ 0.25 (near-duplicates only)

**DB schema** (`.photo-triage.db`, table `image_hashes`):
- `path TEXT PRIMARY KEY`
- `dHash BLOB` (32 bytes = 256 bits)
- `colorHistogram BLOB` (192 bytes: 16 buckets × 3 channels × Float32, normalized)
- `imageWidth INTEGER`, `imageHeight INTEGER` (from `kCGImagePropertyPixelWidth/Height`)
- `captureDate TEXT`

**DB migration**: `HashCache.init` adds `colorHistogram`, `imageWidth`, `imageHeight` columns if absent. Old rows missing the histogram are backfilled during the next `computeHashes` pass.

## Sentinel File Design

Zero-byte files. Naming: `<original_filename>.<sentinel_type>`.

```
IMG_1234.JPG
IMG_1234.JPG.keep       ← marked keep
IMG_1234.JPG.favorite   ← favorited
IMG_1234.CR3            ← RAW partner
IMG_1234.CR3.keep       ← mirrored automatically
.photo-triage-originals/
    IMG_1234.JPG        ← backup of first pre-edit state
```

JPEG sentinel is source of truth for a pair. RAW sentinels are mirrored automatically in `ImageAsset.markKept()`, `markTrashed()`, `toggleFavorite()`, and `clearTriageState()`.

**Triage auto-keep**: navigating forward from an anchor automatically places `.keep` + `.reviewed` on that anchor.

## Clipping Warnings

`ClippingAnalyzer` (actor, singleton `ClippingAnalyzer.shared`):
1. `CGImageSourceCreateThumbnailAtIndex` at ≤1024px — avoids decoding full-res RAW
2. `buildMasks(from: CGImage)` (also used directly by the Edit preview) renders into an RGBA CGContext
3. Pixel walk: **any** channel ≥ 252 → highlight (red mask); **all** channels ≤ 3 → shadow (blue mask)
4. Returns two `NSImage` masks
5. Results cached by URL; `AppState.didModifyFile` calls `invalidate(url:)` after every edit, undo and redo

`ClippingOverlay` (SwiftUI view):
- Displays red + blue masks at `.opacity(0.9)`
- Flashes at ~1.4 Hz (700ms on / 700ms off) using animated `.opacity` transitions
- `allowsHitTesting(false)` — gestures pass through to image layer
- Layered inside `ZoomableImageView` / `ControlledZoomableImageView` so it tracks zoom/pan

Both triage panes share `AppState.showClippingWarnings`, so the toggle affects both simultaneously.

## Keyboard Handling

Key events are intercepted via `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` installed by a `NSViewRepresentable` inside a `.background` modifier. Local monitors fire before the responder chain — returning `nil` consumes the event (no system beep).

The monitor is installed when the view enters a window and removed when it leaves. Only the active view (gallery / preview / triage) handles keys at any time.

`focusedKeyboardHandler { action in Bool }` is a `ViewModifier` that translates raw `NSEvent` into typed `KeyAction` values using the user's `KeyBindings`. The monitor ignores events for other windows (Settings) and while a text field is first responder.

Matching lives in the pure `KeyEventMatcher.matches(_:key:keyCode:modifiers:)`: special keys match by key code; single-symbol bindings without an explicit Shift ignore Shift, and "+" also accepts "=" (so the zoom/grid shortcut works on layouts where "+" needs Shift — previously it never fired). Views reuse actions by context: e.g. `.applyCrop` (Return) opens Preview in the gallery, `.gridIncrease` (+) zooms in Preview/Triage.

## Triage Decision Flow

Triage walks `folder.sortedImages` — **every** photo in the gallery's sort order, ignoring the gallery filter, including kept and trashed photos.

```
keepLeft()  → anchor .kept, candidate .trash → advanceToNextCandidate()
keepBoth()  → anchor .kept, candidate .kept  → stay on the same pair
keepRight() → candidate .kept, anchor .trash → candidate becomes anchor, updateCandidates()
keepNone()  → both .trash                    → nextTriageAnchor()
(each is one undoable .stateChange with both assets' previous states + the pair as context)

advanceToNextCandidate(skipping: id):
  1. Rebuild candidate list from current anchor (excludes trashed; applies candidateFilter)
  2. Pick the first candidate ≠ skipped id (kept/reviewed candidates stay eligible)
  3. If none → nextTriageAnchor()

nextTriageAnchor():
  1. Auto-keep current anchor if it has no decision
  2. Move to the next photo in sortedImages (any state)
  3. Past the last photo → triageFinished = true (completion overlay; ← dismisses it)

showTriage(from: nil): Preview photo / gallery selection → previous anchor → first unreviewed → first photo
```

## Progress Tracking

Stored in `.photo-triage.db` table `progress`:

```sql
CREATE TABLE progress (
    folder_path       TEXT PRIMARY KEY,
    last_triage_index INTEGER,
    last_preview_index INTEGER,
    last_view         TEXT,    -- 'gallery' | 'preview' | 'triage'
    updated_at        TEXT
);
```

On app launch with a known folder → offer "Resume from last position?" or "Start Fresh".

## Configurable Shortcuts

`KeyBindings` maps `KeyAction` cases to `(KeyEquivalent, EventModifiers)` pairs, stored in UserDefaults as JSON. `ShortcutSettings` shows an editable table with reset-to-defaults.

## Build & Test

```bash
# Release binary
swift build -c release     # → .build/release/PhotoTriage

# .app bundle (ad-hoc signed, double-clickable)
./make-app.sh              # → PhotoTriage.app

# Unit tests (150 tests as of current build)
swift test
```

All builds use Swift Package Manager. There is no `.xcodeproj`.

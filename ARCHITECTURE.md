# Photo Triage — Architecture

## Technology Stack

- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI (primary) + AppKit interop for image manipulation and event handling
- **Image handling**: ImageIO (decode, thumbnail generation, pixel dimensions), CGImage / CGContext (crop, rotation, clipping analysis), NSImage (display)
- **Hashing**: vImage (resize for dHash) + custom dHash implementation; CoreGraphics for color histogram
- **Database**: SQLite via GRDB.swift (hash cache + progress state)
- **File operations**: FileManager + NSWorkspace (macOS Trash)
- **Minimum deployment**: macOS 14.0 (Sonoma)
- **Build system**: Swift Package Manager (`build.sh`, `test.sh`, `make-app.sh`)
- **Testing**: XCTest (unit); XCUITest stubs present (not yet exercised)

## Project Structure

```
photo-triage/
├── build.sh                          # swift build -c release
├── make-app.sh                       # Build + assemble signed .app bundle
├── test.sh                           # swift test
├── Package.swift                     # SPM manifest (depends on GRDB.swift 6.24+)
├── Sources/PhotoTriage/
│   ├── App/
│   │   ├── PhotoTriageApp.swift      # Entry point, WindowGroup, menu commands
│   │   ├── AppState.swift            # Global @MainActor ObservableObject (all published state + undo stack)
│   │   └── KeyBindings.swift         # Configurable keyboard shortcut definitions + UserDefaults persistence
│   ├── Models/
│   │   ├── ImageAsset.swift          # Single image or JPEG+RAW pair; manages sentinel state
│   │   ├── ImageFolder.swift         # Scans folder, pairs RAW+JPEG by stem, computes statistics
│   │   ├── SentinelState.swift       # Read/write zero-byte sentinel files (.keep, .trash, .favorite, .reviewed)
│   │   ├── SimilarityEngine.swift    # dHash + color histogram + timestamp + aspect ranking
│   │   ├── HashCache.swift           # SQLite persistence for hashes, histograms, pixel dimensions
│   │   └── ProgressStore.swift       # Per-folder resume position (last view, anchor, preview index)
│   ├── Views/
│   │   ├── Gallery/
│   │   │   ├── GalleryView.swift     # Thumbnail grid (LazyVGrid in ScrollViewReader), toolbar, filter/sort
│   │   │   ├── GalleryThumbnail.swift # Thumbnail cell + AsyncThumbnail; uses asset.thumbnailVersion as task id
│   │   │   └── DetailPanel.swift     # Sidebar: file info, EXIF, actions, Restore Original button
│   │   ├── Preview/
│   │   │   ├── PreviewView.swift     # Single-image view; crop entry logic, rotation, restore, zoom reset
│   │   │   ├── CropOverlay.swift     # Crop UI: handles, rotation strip, safe zone, dim canvas, mask
│   │   │   └── RotationControls.swift # Legacy stub — not used in current UI
│   │   ├── Triage/
│   │   │   ├── TriageView.swift      # Side-by-side layout with resizable HSplitView
│   │   │   ├── ComparisonPane.swift  # Single pane: ControlledZoomableImageView + overlays + badges
│   │   │   └── TriageControls.swift  # Action buttons (L/R/Both/None/Swap) + candidate filter picker
│   │   ├── Shared/
│   │   │   ├── ZoomableImageView.swift    # Self-contained pan/zoom (reloadToken, resetZoomToken); ControlledZoomableImageView for triage
│   │   │   ├── ClippingOverlay.swift      # Flashing red/blue overlay driven by ClippingAnalyzer
│   │   │   ├── GuidingGridOverlay.swift   # Rule-of-thirds grid + center crosshair (Canvas, allowsHitTesting false)
│   │   │   ├── EXIFOverlay.swift          # Metadata badge overlay with position control
│   │   │   ├── FavoriteButton.swift       # Star toggle in multiple sizes, used in all views
│   │   │   ├── KeyboardHandler.swift      # NSEvent local monitor → KeyAction dispatch via ViewModifier
│   │   │   └── ImageRenderer.swift        # NSImage display helper (minimal; most rendering uses SwiftUI Image)
│   │   └── Settings/
│   │       └── ShortcutSettings.swift    # Preferences: rebind keys table, reset to defaults
│   ├── Services/
│   │   ├── CropService.swift         # Apply crop/rotation to JPEG, manage .photo-triage-originals/ backups
│   │   ├── ClippingAnalyzer.swift    # Actor: builds red/blue clipping masks at ≤1024px; cached by URL
│   │   ├── TrashService.swift        # Move files to macOS Trash via NSWorkspace.shared.recycle
│   │   ├── ImageLoader.swift         # Thumbnail + full-res cache service (exists; not wired to current UI)
│   │   ├── RAWDecoder.swift          # CoreImage RAW decode helper (exists; not wired to current UI)
│   │   └── UndoService.swift         # Generic UndoableAction protocol (exists; undo is implemented in AppState)
│   └── Utilities/
│       ├── DHash.swift               # Perceptual hash: 17×16 grayscale → 256-bit, Hamming distance
│       ├── ColorHistogram.swift      # 16-bucket RGB histogram from 64px thumbnail; L1 distance
│       ├── EXIFReader.swift          # Extract EXIF metadata via ImageIO → EXIFMetadata struct
│       └── FileExtensions.swift      # RAW/JPEG extension sets, URL helpers (.isJPEG, .stem, etc.)
├── Tests/PhotoTriageTests/
│   ├── DHashTests.swift
│   ├── ColorHistogramTests.swift
│   ├── CropServiceTests.swift
│   ├── SentinelStateTests.swift
│   ├── ImageFolderTests.swift
│   ├── KeyBindingsTests.swift
│   ├── FileExtensionsTests.swift
│   ├── SimilarityEngineTests.swift
│   └── ProgressStoreTests.swift
└── Tests/PhotoTriageUITests/
    ├── GalleryUITests.swift          # Stub (XCTSkip — no fixture images yet)
    ├── TriageUITests.swift           # Stub
    └── PreviewUITests.swift          # Stub
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
    │       ZoomableImageView (reloadToken: cropVersion, resetZoomToken: zoomResetToken)
    │       CropOverlay (url: cropSourceURL ?? displayURL, initialCropSizeHint: cropSizeHint)
    │
    └──▶ TriageView
            ControlledZoomableImageView per pane (shared scale/offset bindings)
            TriageControls + candidateFilter picker
```

## AppState

`AppState` is the single source of truth. Key published properties:

| Property | Type | Purpose |
|----------|------|---------|
| `folder` | `ImageFolder?` | Currently open folder |
| `currentView` | `AppView` | `.gallery`, `.preview`, or `.triage` |
| `selectedAsset` | `ImageAsset?` | Selected item in gallery |
| `previewAsset` | `ImageAsset?` | Image being previewed |
| `triageAnchor` | `ImageAsset?` | Left pane in triage |
| `triageCandidate` | `ImageAsset?` | Right pane in triage |
| `candidateFilter` | `CandidateFilter` | Triage candidate score threshold |
| `cropVersion` | `Int` | Incremented on every file edit; `ZoomableImageView` uses as `reloadToken` |
| `showEXIFOverlay` | `Bool` | Global EXIF badge toggle |
| `showClippingWarnings` | `Bool` | Global clipping warning toggle |
| `showGuidingGrid` | `Bool` | Global guiding grid toggle |
| `showDetailPanel` | `Bool` | Gallery sidebar toggle |
| `galleryColumns` | `Int` | Grid column count (2–12) |

**Undo stack**: `[UndoAction]` with a matching redoStack. `UndoAction` cases:
- `.markKept(ImageAsset)`, `.markTrashed(ImageAsset)`, `.toggleFavorite(ImageAsset)` — synchronous, reverse by clearing/toggling sentinel
- `.triageDecision(anchor:candidate:anchorAction:candidateAction:)` — synchronous, reverses both
- `.cropApplied(ImageAsset, CropRect, Double)` — async undo/redo via `CropService.restoreOriginal` / `applyCrop`
- `.rotationApplied(ImageAsset, Bool)` — async undo/redo via `CropService.restoreOriginal` / `applyRotation`

On every file-modifying operation, `cropVersion += 1` and `asset.thumbnailVersion += 1` are both incremented.

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
}
```

`thumbnailVersion` is incremented by `AppState` after every file edit (crop, rotation, undo, redo, restore). `GalleryThumbnail` uses `.task(id: asset.thumbnailVersion)` so only the affected image's thumbnail reloads — not the entire grid. `AsyncThumbnail` in `DetailPanel` accepts `reloadToken: asset.thumbnailVersion` for the same reason.

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
- Loads JPEG via CGImageSource at native pixel dimensions
- Rotates using CGContext with swapped W/H canvas:
  - CW: `translateBy(0, w)` then `rotate(-.pi/2)`
  - CCW: `translateBy(h, 0)` then `rotate(.pi/2)`
- Saves back as JPEG at 0.9 compression

`applyCrop(to url: URL, cropRect: CropRect, rotation: Double = 0, sourceURL: URL? = nil) async throws -> URL`
- Backs up `url` (no-op if already backed up)
- Loads pixels from `sourceURL` if provided (used when recropping from the original), otherwise from `url`
- Applies fine rotation (if |rotation| > 0.001°) via `rotateImage(_:byDegrees:)` — keeps original canvas dimensions, small black corners are covered by the subsequent crop
- Crops using `cgImage.cropping(to: cropRect.cgRect)` — CGImage uses upper-left origin matching JPEG file storage order; no Y-flip needed
- **DPI safety**: always loads via CGImageSource (native pixel dimensions). `NSImage.size` is DPI-scaled and would misplace crops on high-DPI images.
- Saves back as JPEG at 0.9 compression

`restoreOriginal(for url: URL) throws`
- Copies backup file back to `url`, replacing the current file

`nonisolated func backupURL(for url: URL) -> URL`
- Synchronous, no await needed — safe to call from view action handlers
- Returns `.photo-triage-originals/<filename>` adjacent to `url`

`hasBackup(for url: URL) -> Bool`
- Checks if backup file exists (used to show/hide Restore Original button)

## CropOverlay

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

Both use `CGImageSourceCreateThumbnailAtIndex` directly (not `ImageLoader`).

`GalleryThumbnail` uses `.task(id: asset.thumbnailVersion)` — re-fires whenever `thumbnailVersion` changes, which `AppState` increments on every file write to that specific asset. This ensures only the edited image reloads, not all thumbnails.

`AsyncThumbnail` (used in `DetailPanel`) accepts `var reloadToken: Int = 0` and uses `.task(id: reloadToken)`. `DetailPanel` passes `asset.thumbnailVersion`.

## Gallery Scroll Preservation

`GalleryView.gridView(for:)` wraps the `LazyVGrid` in a `ScrollViewReader`. Each thumbnail has `.id(asset.id)`.

`scrollToSelected(proxy:)` calls `proxy.scrollTo(id, anchor: .center)` on the main queue with a 0.25s ease-in-out animation.

Scroll fires on:
- `.onAppear` — initial load or returning to gallery view
- `.onChange(of: appState.currentView)` — triggers when switching back from Preview or Triage

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
2. Renders into RGBA CGContext (premultiplied)
3. Pixel walk: channels ≥ 252 → highlight (red mask), channels ≤ 3 → shadow (blue mask)
4. Returns two `NSImage` masks
5. Results cached by URL; `invalidate(url:)` clears on file edit

`ClippingOverlay` (SwiftUI view):
- Displays red + blue masks at `.opacity(0.9)`
- Flashes at ~1.4 Hz (700ms on / 700ms off) using animated `.opacity` transitions
- `allowsHitTesting(false)` — gestures pass through to image layer
- Layered inside `ZoomableImageView` / `ControlledZoomableImageView` so it tracks zoom/pan

Both triage panes share `AppState.showClippingWarnings`, so the toggle affects both simultaneously.

## Keyboard Handling

Key events are intercepted via `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` installed by a `NSViewRepresentable` inside a `.background` modifier. Local monitors fire before the responder chain — returning `nil` consumes the event (no system beep).

The monitor is installed when the view enters a window and removed when it leaves. Only the active view (gallery / preview / triage) handles keys at any time.

`focusedKeyboardHandler { action in Bool }` is a `ViewModifier` that translates raw `NSEvent` into typed `KeyAction` values using the user's `KeyBindings`.

## Triage Decision Flow

```
keepLeft()  → anchor .kept, candidate .trash → advanceToNextCandidate()
keepBoth()  → anchor .kept, candidate .kept  → advanceToNextCandidate()
keepRight() → candidate .kept, anchor .trash → candidate becomes anchor, updateCandidates()
keepNone()  → both .trash                    → nextTriageAnchor()

advanceToNextCandidate(skipping: id):
  1. Rebuild candidate list from current anchor (excludes trashed; applies candidateFilter)
  2. Find first candidate ≠ skipped id that isn't yet reviewed
  3. If found → show it, anchor unchanged
  4. If none  → nextTriageAnchor()

nextTriageAnchor():
  1. Auto-keep current anchor if not yet reviewed
  2. Walk forward in folder.images to find next non-trashed, non-reviewed image
  3. Set as new anchor, updateCandidates()
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

# Unit tests (84 tests as of current build)
swift test
```

All builds use Swift Package Manager. There is no `.xcodeproj`.

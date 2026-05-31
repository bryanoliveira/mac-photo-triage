# Photo Triage — Architecture

## Technology Stack

- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI (primary) + AppKit interop for image manipulation
- **Image handling**: CoreImage (filters, rotation, crop), ImageIO (RAW decode), CGImage
- **Hashing**: vImage (resize for dHash) + custom dHash implementation + CoreGraphics for color histogram
- **Database**: SQLite via GRDB.swift for hash cache + progress state
- **File operations**: FileManager + NSWorkspace (trash)
- **Minimum deployment**: macOS 14.0 (Sonoma)
- **Build system**: Xcode + xcodebuild via `build.sh`
- **Testing**: XCTest (unit) + XCUITest (UI), via `test.sh`

## Project Structure

```
PhotoTriage/
├── build.sh                              # SPM release build
├── make-app.sh                           # Build + assemble signed .app bundle
├── test.sh                               # SPM test runner
├── PhotoTriage/
│   ├── App/
│   │   ├── PhotoTriageApp.swift          # Entry point
│   │   ├── AppState.swift                # Global app state (ObservableObject)
│   │   └── KeyBindings.swift             # Configurable keyboard shortcuts
│   ├── Models/
│   │   ├── ImageAsset.swift              # Single image (or JPEG+RAW pair)
│   │   ├── ImageFolder.swift             # Loaded folder state
│   │   ├── SentinelState.swift           # Read/write sentinel files (.keep, .trash, .favorite, .reviewed)
│   │   ├── SimilarityEngine.swift        # dHash + timestamp ranking
│   │   ├── HashCache.swift               # SQLite hash persistence
│   │   └── ProgressStore.swift           # Resume position tracking
│   ├── Views/
│   │   ├── Gallery/
│   │   │   ├── GalleryView.swift         # Resizable grid of thumbnails
│   │   │   ├── GalleryThumbnail.swift    # Single cell with badges
│   │   │   └── DetailPanel.swift         # Sidebar: metadata, actions, favorites
│   │   ├── Preview/
│   │   │   ├── PreviewView.swift         # Single image preview + trash action
│   │   │   ├── CropOverlay.swift         # Crop rectangle + handles + presets
│   │   │   └── RotationControls.swift    # 90° steps + level panel (−45°/+45° slider, ±0.5° nudge)
│   │   ├── Triage/
│   │   │   ├── TriageView.swift          # Side-by-side layout
│   │   │   ├── ComparisonPane.swift      # Single pane (left or right)
│   │   │   └── TriageControls.swift      # Action buttons bar
│   │   ├── Shared/
│   │   │   ├── ImageRenderer.swift       # CIImage → NSImage display
│   │   │   ├── EXIFOverlay.swift         # Metadata badge
│   │   │   ├── ZoomableImageView.swift   # Pan + zoom container
│   │   │   ├── ClippingOverlay.swift     # Flashing highlight/shadow clipping overlay
│   │   │   ├── FavoriteButton.swift      # Star toggle (used everywhere)
│   │   │   └── KeyboardHandler.swift     # Global key event routing (reads KeyBindings)
│   │   └── Settings/
│   │       └── ShortcutSettings.swift    # Preferences: rebind keys
│   ├── Services/
│   │   ├── ImageLoader.swift             # Async image loading + thumbnail caching
│   │   ├── RAWDecoder.swift              # RAW → displayable pipeline
│   │   ├── CropService.swift             # Apply crop to JPEG (backup original)
│   │   ├── TrashService.swift            # Move to macOS Trash
│   │   ├── UndoService.swift             # Undo/redo stack
│   │   └── ClippingAnalyzer.swift        # Background pixel analysis for highlight/shadow masks
│   └── Utilities/
│       ├── DHash.swift                   # Perceptual hash algorithm
│       ├── ColorHistogram.swift          # 16-bucket RGB histogram + L1 distance
│       ├── EXIFReader.swift              # Extract EXIF metadata
│       └── FileExtensions.swift          # RAW/JPEG extension sets
├── PhotoTriageTests/
│   ├── DHashTests.swift
│   ├── ColorHistogramTests.swift
│   ├── SentinelStateTests.swift
│   ├── ImageFolderTests.swift
│   ├── SimilarityEngineTests.swift
│   └── ProgressStoreTests.swift
├── PhotoTriageUITests/
│   ├── GalleryUITests.swift
│   ├── TriageUITests.swift
│   └── PreviewUITests.swift
└── README.md
```

## Data Flow

```
Folder Scan
    │
    ▼
ImageFolder (pairs RAW+JPEG, reads sentinels, loads progress)
    │
    ▼
SimilarityEngine (computes/loads dHash, ranks by similarity + time)
    │
    ▼
AppState (current view, anchor, candidate queue, undo stack)
    │
    ├──▶ GalleryView (thumbnail grid + detail panel)
    │
    ├──▶ TriageView (anchor + candidate queue; keep-left/both advance candidate, keep-right swaps anchor)
    │
    └──▶ PreviewView (single image for edit)
```

## Similarity Engine Detail

Three-component score (lower = more similar, range 0–1):

```
score = contentScore × 0.60 + timeScore × 0.30 + aspectScore × 0.10

contentScore = (dHashDistance + histogramDistance) / 2   # each 0..1; falls back to dHash-only if no histogram
dHashDistance  = hammingDistance(a.dHash, b.dHash) / 256.0
histogramDistance = l1Distance(a.histogram, b.histogram) / (2 × 3 channels)  # normalized 0..1
timeScore = min(secondsBetweenCaptures / 3600.0, 1.0)    # 1 hr cap; unknown time = 1.0
aspectScore = abs(arA - arB) / max(arA, arB)              # 0 for identical ratio; 0 if either unknown
```

**Data stored per image in `.photo-triage.db`:**
- `dHash` — 256-bit perceptual hash (`Data`, 32 bytes)
- `colorHistogram` — 192 bytes: 16 buckets × 3 channels × Float32, normalized to [0,1]
- `imageWidth`, `imageHeight` — pixel dimensions from ImageIO (no full decode)
- `captureDate` — from EXIF

**dHash algorithm**:
1. Resize image to 17×16 grayscale
2. Compare adjacent horizontal pixels (left > right = 1, else 0)
3. Produces 256-bit hash; Hamming distance = number of differing bits

**Color histogram (`ColorHistogram.analyze`)**:
- Uses a 64×64 CGImageSource thumbnail — very fast, no full RAW decode
- 16 evenly-spaced buckets per channel (R, G, B); each channel normalized to sum = 1.0
- L1 distance: `Σ|a_i - b_i| / (2 × channels)` → [0, 1]

**No threshold**: Always return sorted candidates. Right pane always shows the top candidate.

**DB migration**: `HashCache.init` adds `colorHistogram`, `imageWidth`, `imageHeight` columns if absent. Old records missing the histogram are backfilled during the next `computeHashes` pass.

## Sentinel File Design

Sentinels are zero-byte files. Naming: `<original_filename>.<sentinel_type>`

```
IMG_1234.JPG
IMG_1234.JPG.keep       ← marked keep
IMG_1234.JPG.favorite   ← favorited
IMG_1234.CR3            ← RAW partner (sentinels mirrored from JPEG)
```

JPEG sentinel is source of truth for a pair. RAW sentinels mirrored automatically.

**Triage auto-keep**: When user navigates forward from an anchor, `.keep` + `.reviewed` are placed automatically on the current anchor (they decided it's good enough to move on).

## Progress Tracking

Stored in `.photo-triage.db` table `progress`:

```sql
CREATE TABLE progress (
    folder_path TEXT PRIMARY KEY,
    last_triage_index INTEGER,
    last_preview_index INTEGER,
    last_gallery_scroll REAL,
    last_view TEXT,  -- 'gallery' | 'preview' | 'triage'
    updated_at TEXT
);
```

On app launch with a known folder → offer "Resume from image X?" or start fresh.

## Configurable Shortcuts

Stored in UserDefaults (or a plist). `KeyBindings` model maps action IDs to key combos:

```swift
struct KeyBinding: Codable {
    let action: String       // e.g. "triage.keepLeft"
    var key: KeyEquivalent
    var modifiers: EventModifiers
}
```

Settings UI shows a table of actions with editable key fields. Reset-to-defaults button.

## Clipping Warnings

Toggled via `AppState.showClippingWarnings` (key: W). When active, `ClippingOverlay` is layered inside `ZoomableImageView` / `ControlledZoomableImageView` as an inner `ZStack` sibling of the image, so the overlay automatically tracks zoom and pan.

**`ClippingAnalyzer`** (actor, singleton):
1. Uses `CGImageSourceCreateThumbnailAtIndex` at ≤1024px — avoids decoding full-res RAW into memory
2. Renders the thumbnail into a `CGContext` (RGBA premultiplied)
3. Walks every pixel: channels ≥ 252 → highlight (solid red in mask), channels ≤ 3 → shadow (solid blue in mask)
4. Creates two transparent `NSImage` masks — one per clipping type
5. Caches results by URL so repeated toggling or navigation is instant

**`ClippingOverlay`** (SwiftUI view):
- Displays red mask + blue mask with `.opacity(0.9)` so the original image texture remains faintly visible
- A `.task` loop flashes the overlay at ~1.4 Hz (700 ms on / 700 ms off) using animated `.opacity` transitions — same visual idiom used by dedicated cameras
- `allowsHitTesting(false)` so gestures pass through to the image layer

Both panes in Triage mode share the same `showClippingWarnings` flag, making highlight/shadow comparison across two images instant.

## Performance Strategy

- **Thumbnail cache**: 256px thumbnails in `.photo-triage-thumbs/`
- **Lazy full-res load**: Only when displayed; prefetch ±1
- **Background hashing**: Concurrent async queue, ~50ms per image on M1
- **Progressive scan**: UI available immediately; similarity updates as hashes complete
- **Memory ceiling**: Max 4 full-res images in memory

## Keyboard Handling

Key events are intercepted via `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` installed by `KeyMonitorView` (an `NSViewRepresentable` placed in `.background`). Local monitors fire **before** the responder chain — returning `nil` consumes the event (no system beep), returning the original event passes it through. The monitor is installed when the view enters a window and removed when it leaves, so only the currently active view (gallery / preview / triage) handles keys at any time.

`FocusedKeyboardHandler` is a `ViewModifier` that wraps this mechanism and translates raw `NSEvent`s into typed `KeyAction` values using the user's current `KeyBindings`.

## Triage Decision Flow

```
keepLeft()  → mark anchor .kept, candidate .trash  → advanceToNextCandidate()
keepBoth()  → mark anchor .kept, candidate .kept   → advanceToNextCandidate()
keepRight() → mark candidate .kept, anchor .trash  → candidate becomes new anchor, updateCandidates()
keepNone()  → mark both .trash                     → nextTriageAnchor()

advanceToNextCandidate(skipping: id):
  1. Rebuild candidate list (excludes trashed images)
  2. Find first candidate that isn't `id` and isn't already reviewed
  3. If found → show it (anchor unchanged)
  4. If none  → nextTriageAnchor()
```

## Build & Test

All builds use Swift Package Manager (no `.xcodeproj`).

**build.sh** — release binary only:
```bash
swift build -c release
# output: .build/release/PhotoTriage
```

**make-app.sh** — release binary + `.app` bundle + ad-hoc codesign:
```bash
./make-app.sh
# output: PhotoTriage.app  (double-clickable, Dock-compatible)
```

**test.sh** — unit test suite:
```bash
swift test
```

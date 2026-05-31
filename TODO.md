# Photo Triage — TODO

## Phase 1: Foundation
- [x] 1. Set up Swift Package Manager project, targets macOS 14+, add GRDB dependency
- [x] 2. Implement `ImageAsset` model (JPEG+RAW pairing, extension detection)
- [x] 3. Implement `ImageFolder` scanner (enumerate files, pair RAW/JPEG by stem)
- [x] 4. Implement sentinel file read/write (`SentinelState`: .keep, .trash, .favorite, .reviewed)
- [x] 5. Implement `ProgressStore` (SQLite: last position per folder, last view)
- [x] 6. Configurable `KeyBindings` model + UserDefaults persistence
- [x] 7. `build.sh` + `test.sh` scripts; `make-app.sh` for signed `.app` bundle

## Phase 2: Gallery View (Default)
- [x] 8. Resizable thumbnail grid (`GalleryView` with `LazyVGrid`)
- [x] 9. Thumbnail generation via `CGImageSourceCreateThumbnailAtIndex` (async, per-cell)
- [x] 10. Detail panel on selection (file info, EXIF, action buttons, favorite toggle)
- [x] 11. Favorite toggle from gallery (star badge on thumbnails)
- [x] 12. Filter/sort controls (by date, by state: all/kept/trashed/favorites)
- [x] 13. Navigation to Preview and Triage from detail panel
- [x] 14. Gallery scroll preservation: when returning from Preview or Triage, scroll to and highlight the last-viewed image using `ScrollViewReader`
- [x] 15. Detail panel: "Restore Original" button appears when backup exists; immediately refreshes thumbnail via `asset.thumbnailVersion`
- [x] 16. Targeted thumbnail reload: `ImageAsset.thumbnailVersion` incremented on every file edit; `GalleryThumbnail` uses it as `.task(id:)` so only the edited image reloads

## Phase 3: Preview Mode
- [x] 17. `ZoomableImageView` — pan, zoom (scroll/pinch), fit-to-window; `reloadToken` + `resetZoomToken` parameters
- [x] 18. Image navigation (← →)
- [x] 19. 90° rotation baked to file immediately (`CropService.applyRotation`); original backed up first; undoable
- [x] 20. Crop overlay: free-form drag handles, aspect ratio presets, inside-crop rule-of-thirds grid
- [x] 21. Horizon adjust strip inside crop mode: ±15° slider, ±0.5° nudge, reset; shown below image area
- [x] 22. Crop safe zone: crop rect constrained to the largest axis-aligned inscribed rectangle in the rotated image (formula: `safeW = (W·c − H·s) / cos(2θ)`) — no black pixels ever included
- [x] 23. Crop dim overlay covers full container (letterbox areas + rotated image content) using Canvas with even-odd fill; `.clipped()` prevents rotation from bleeding into toolbar
- [x] 24. Apply crop: rotation baked first, then crop applied — single CGContext pass; original backed up; bakes to JPEG at 0.9 compression
- [x] 25. Recrop from original: when backup exists, entering crop mode loads the original file and initializes crop rect centered to current image dimensions; `CropService.applyCrop(sourceURL:)` reads from original
- [x] 26. EXIF overlay toggle (I)
- [x] 27. Favorite toggle from preview (F)
- [x] 28. Trash current image from preview (Delete key + toolbar button)
- [x] 29. Clipping warnings overlay (W) — red highlights, blue shadows, flashing at ~1.4 Hz
- [x] 30. Space key resets zoom to fit-to-window (increments `zoomResetToken`)
- [x] 31. Restore Original button in preview toolbar; refreshes `ZoomableImageView` via `cropVersion`

## Phase 4: Similarity Engine
- [x] 32. dHash implementation (17×16 grayscale → 256-bit, Hamming distance)
- [x] 33. SQLite hash cache (`.photo-triage.db`) via GRDB
- [x] 34. Timestamp extraction from EXIF; capture date stored per asset
- [x] 35. Three-component weighted score: 60% content (dHash + histogram), 30% time proximity, 10% aspect ratio
- [x] 36. Background hash computation with progress indicator
- [x] 37. Color histogram: 16-bucket RGB, computed from 64px CGImageSource thumbnail; L1 distance
- [x] 38. Image pixel dimensions stored per asset (from `kCGImagePropertyPixelWidth/Height`); used for aspect ratio scoring
- [x] 39. DB migration: adds `colorHistogram`, `imageWidth`, `imageHeight` columns if absent; backfills old rows

## Phase 5: Triage Mode
- [x] 40. Side-by-side layout with resizable divider (`HSplitView`)
- [x] 41. Independent zoom/pan per pane (`ControlledZoomableImageView` with shared bindings)
- [x] 42. Action buttons + keyboard: Keep L / R / Both / None
- [x] 43. Keep-left/keep-both advance candidate (not anchor); keep-right swaps anchor; keep-none advances anchor
- [x] 44. Auto-keep on forward navigation (anchor gets `.keep` when advancing)
- [x] 45. Candidate navigation (↑ ↓)
- [x] 46. Open Preview from either pane (P / ⇧P)
- [x] 47. Favorite toggle on either image (F)
- [x] 48. Undo/redo stack for triage decisions
- [x] 49. Clipping warnings in both panes simultaneously (W)
- [x] 50. Guiding grid in both panes simultaneously (H)
- [x] 51. Swap anchor ↔ candidate (S key + toolbar button)
- [x] 52. Candidate filter picker in triage toolbar (All / Loose / Moderate / Strict); threshold applied in `updateCandidates()`; persisted in UserDefaults
- [x] 53. Space resets zoom in both panes simultaneously

## Phase 6: Polish & Integration
- [x] 54. Trash execution (⌘⌫ → move `.trash` files to macOS Trash via `NSWorkspace.shared.recycle`)
- [x] 55. Empty Trash button in gallery toolbar with item count and confirmation dialog
- [x] 56. Settings panel (configurable shortcuts, ⌘,); reset-to-defaults button
- [x] 57. Resume from last position on folder reopen (offer resume dialog)
- [x] 58. Progress statistics: reviewed/total, kept/trashed/favorites shown in toolbar
- [x] 59. Unit tests: DHash, ColorHistogram, CropService, SentinelState, ImageFolder, SimilarityEngine, ProgressStore, KeyBindings (84 tests total)
- [x] 60. EXIF/detail panel timestamps include seconds (`.timeStyle = .medium`)
- [x] 61. Undo/redo for file edits (crop, 90° rotation): undo restores from `.photo-triage-originals/` backup; redo reapplies operation

## Remaining / Not Yet Implemented
- [ ] Window state persistence (size, position, last-opened folder path)
- [ ] Handle edge cases: empty folder, all images reviewed, single image, RAW-only folder with no JPEGs (display gracefully)
- [ ] Performance testing with 1000+ image folders
- [ ] App icon + menu bar polish
- [ ] UI tests — currently stubbed with XCTSkip; need test image fixture set
- [ ] Keyboard handler: verify arrow key focus without requiring a prior click (local event monitor is in place; needs hardware testing)
- [ ] `ImageLoader.swift` / `RAWDecoder.swift` / `UndoService.swift` / `RotationControls.swift` — currently unreferenced stubs; wire up or delete
- [ ] Thumbnail disk cache (`ImageLoader` already has the `.photo-triage-thumbs/` logic; not yet used by UI)
- [ ] Crop custom ratio input (free-form text entry; presets implemented, custom entry is not)
- [ ] Multi-select in gallery (⌘-click, shift-click)

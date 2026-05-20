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
- [x] 8. Resizable thumbnail grid (`GalleryView`)
- [x] 9. Thumbnail generation + async loading
- [x] 10. Detail panel on selection (metadata, EXIF, actions)
- [x] 11. Favorite toggle from gallery (star badge on thumbnails)
- [x] 12. Filter/sort controls (date, state, favorites)
- [x] 13. Navigation to Preview and Triage from detail panel

## Phase 3: Preview Mode
- [x] 14. `ZoomableImageView` — pan, zoom (scroll/pinch), fit-to-window
- [x] 15. Image navigation (← →)
- [x] 16. Rotation: 90° steps (toolbar) + level panel (−45°/+45° slider, ±0.5° nudge)
- [x] 17. Crop overlay: free-form drag + aspect ratio presets
- [x] 18. Apply crop (saves to JPEG, backs up original)
- [x] 19. EXIF overlay toggle (I)
- [x] 20. Favorite toggle from preview (F)
- [x] 21. Trash current image from preview (Delete key + toolbar button)
- [x] 22. Clipping warnings overlay (W) — red highlights, blue shadows, flashing

## Phase 4: Similarity Engine
- [x] 23. dHash implementation (17×16 grayscale → 256-bit)
- [x] 24. SQLite hash cache (`.photo-triage.db`)
- [x] 25. Timestamp extraction from EXIF
- [x] 26. Candidate ranking (weighted: 70% dHash distance + 30% time proximity)
- [x] 27. Background hash computation with progress indicator

## Phase 5: Triage Mode
- [x] 28. Side-by-side layout with resizable divider
- [x] 29. Independent zoom/pan per pane
- [x] 30. Action buttons + keyboard: Keep L/R/Both/None
- [x] 31. Keep-left/keep-both advance candidate (not anchor); keep-right swaps anchor; keep-none advances anchor
- [x] 32. Auto-keep on forward navigation (anchor gets .keep when advancing)
- [x] 33. Candidate navigation (↑ ↓)
- [x] 34. Open Preview from either pane (P / ⇧P)
- [x] 35. Favorite toggle on either image (F)
- [x] 36. Undo/redo stack for triage decisions
- [x] 37. Clipping warnings in both panes simultaneously (W)

## Phase 6: Polish & Integration
- [x] 38. Trash execution (⌘⌫ → move .trash files to macOS Trash via NSWorkspace)
- [x] 39. Settings panel (configurable shortcuts, ⌘,)
- [ ] 40. Window state persistence (position, size, last folder)
- [x] 41. Resume from last position on folder reopen
- [x] 42. Progress stats: reviewed/total, kept/trashed/favorites
- [ ] 43. Handle edge cases: empty folder, all reviewed, single image, no JPEG (RAW-only)
- [ ] 44. Performance testing with 1000+ image folders
- [ ] 45. App icon + menu bar polish
- [x] 46. Unit tests (DHash, SentinelState, ImageFolder, SimilarityEngine, ProgressStore, KeyBindings)
- [ ] 47. UI tests — currently stubbed with XCTSkip; need test image fixture set
- [ ] 48. Keyboard handler: fix focus so arrow keys work without clicking first (local event monitor in place, verify on real hardware)

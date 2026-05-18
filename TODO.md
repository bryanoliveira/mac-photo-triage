# Photo Triage — TODO

## Phase 1: Foundation
- [ ] 1. Set up Xcode project with SwiftUI, targets macOS 14+, add GRDB dependency
- [ ] 2. Implement `ImageAsset` model (JPEG+RAW pairing, extension detection)
- [ ] 3. Implement `ImageFolder` scanner (enumerate files, pair RAW/JPEG by stem)
- [ ] 4. Implement sentinel file read/write (`SentinelState`: .keep, .trash, .favorite, .reviewed)
- [ ] 5. Implement `ProgressStore` (SQLite: last position per folder, last view)
- [ ] 6. Configurable `KeyBindings` model + UserDefaults persistence
- [ ] 7. build.sh + test.sh scripts

## Phase 2: Gallery View (Default)
- [ ] 8. Resizable thumbnail grid (`GalleryView`)
- [ ] 9. Thumbnail generation + caching (`.photo-triage-thumbs/`)
- [ ] 10. Detail panel on selection (metadata, EXIF, actions)
- [ ] 11. Favorite toggle from gallery (star badge on thumbnails)
- [ ] 12. Filter/sort controls (date, state, favorites)
- [ ] 13. Navigation to Preview and Triage from detail panel

## Phase 3: Preview Mode
- [ ] 14. `ZoomableImageView` — pan, zoom (scroll/pinch), fit-to-window
- [ ] 15. Image navigation (← →) with prefetch
- [ ] 16. Rotation: 90° steps + free rotation
- [ ] 17. Crop overlay: free-form drag + aspect ratio presets
- [ ] 18. Apply crop (saves to JPEG, backs up original)
- [ ] 19. EXIF overlay toggle
- [ ] 20. Favorite toggle from preview

## Phase 4: Similarity Engine
- [ ] 21. dHash implementation (17×16 grayscale → 256-bit)
- [ ] 22. SQLite hash cache (`.photo-triage.db`)
- [ ] 23. Timestamp extraction from EXIF
- [ ] 24. Candidate ranking (weighted: 70% dHash distance + 30% time proximity)
- [ ] 25. Background hash computation with progress indicator

## Phase 5: Triage Mode
- [ ] 26. Side-by-side layout with resizable divider
- [ ] 27. Independent zoom/pan per pane
- [ ] 28. Action buttons + keyboard: Keep L/R/Both/None
- [ ] 29. Auto-keep on forward navigation (anchor gets .keep when advancing)
- [ ] 30. Candidate navigation (↑ ↓)
- [ ] 31. Anchor advancement logic after decisions
- [ ] 32. Open Preview from either pane
- [ ] 33. Favorite toggle on either image
- [ ] 34. Undo/redo stack for triage decisions

## Phase 6: Polish & Integration
- [ ] 35. Trash execution (⌘⌫ → move .trash files to macOS Trash via NSWorkspace)
- [ ] 36. Settings panel (configurable shortcuts)
- [ ] 37. Window state persistence (position, size, last folder)
- [ ] 38. Resume from last position on folder reopen
- [ ] 39. Progress stats: "X reviewed, Y kept, Z trashed, W favorites"
- [ ] 40. Handle edge cases: empty folder, all reviewed, single image, no JPEG (RAW-only)
- [ ] 41. Performance testing with 1000+ image folders
- [ ] 42. App icon + menu bar polish
- [ ] 43. Unit tests (DHash, SentinelState, ImageFolder, SimilarityEngine, ProgressStore)
- [ ] 44. UI tests (Gallery navigation, Triage workflow, Preview crop)

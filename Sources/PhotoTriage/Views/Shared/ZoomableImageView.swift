import SwiftUI
import AppKit

/// Zoom/pan state. `scale` is relative to fit-to-window (1 = fit).
struct ZoomState: Equatable {
    var scale: CGFloat = 1
    var offset: CGSize = .zero

    var isFit: Bool { scale <= 1.0001 }

    static let fit = ZoomState()
}

/// A one-shot zoom instruction sent from a toolbar button or keyboard shortcut.
/// Each `send` bumps `id`, so repeating the same command still triggers `onChange`.
struct ZoomRequest: Equatable {
    enum Command: Equatable {
        case fit, actualSize, zoomIn, zoomOut
    }

    private(set) var id = 0
    private(set) var command: Command = .fit

    mutating func send(_ command: Command) {
        id += 1
        self.command = command
    }
}

/// Self-contained pan/zoom image (Preview mode). Owns its zoom state.
struct ZoomableImageView: View {
    let url: URL
    var showClippingWarnings: Bool = false
    /// Increment to force a reload from disk (e.g. after an edit or undo)
    var reloadToken: Int = 0
    /// Fit / 100% / zoom in / zoom out commands
    var request: ZoomRequest = ZoomRequest()
    /// Receives the zoom level as a percentage of actual pixels (nil while unknown)
    var onZoomPercentChange: ((Int?) -> Void)? = nil

    @State private var zoom = ZoomState.fit

    var body: some View {
        ZoomableImageCore(url: url, reloadToken: reloadToken, showClippingWarnings: showClippingWarnings,
                          zoom: $zoom, request: request, onZoomPercentChange: onZoomPercentChange)
    }
}

/// Zoomable image driven by an external zoom binding (Triage, where both panes can share one).
struct ControlledZoomableImageView: View {
    let url: URL
    @Binding var zoom: ZoomState
    var request: ZoomRequest = ZoomRequest()
    var showClippingWarnings: Bool = false

    var body: some View {
        ZoomableImageCore(url: url, reloadToken: 0, showClippingWarnings: showClippingWarnings,
                          zoom: $zoom, request: request, onZoomPercentChange: nil)
    }
}

/// Shared implementation:
/// - decodes through `ImagePipeline` (cached, off the main thread; a cached thumbnail is shown
///   instantly while the screen-size image loads)
/// - loads native resolution only once the user zooms past screen resolution
/// - double-click toggles fit ↔ 100% (actual pixels) around the click point
/// - pinch or mouse wheel zooms around the pointer; drag or two-finger scroll pans
struct ZoomableImageCore: View {
    let url: URL
    let reloadToken: Int
    let showClippingWarnings: Bool
    @Binding var zoom: ZoomState
    let request: ZoomRequest
    let onZoomPercentChange: ((Int?) -> Void)?

    @Environment(\.displayScale) private var displayScale

    @State private var image: NSImage?
    @State private var isFullRes = false
    @State private var pixelSize: CGSize?
    @State private var loadFailed = false
    @State private var containerSize: CGSize = .zero
    @State private var gestureStart: ZoomState?

    private let maxScale: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            let fitted = fittedSize(in: geometry.size)
            ZStack {
                if let image {
                    ZStack {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                        if showClippingWarnings {
                            ClippingOverlay(url: url)
                        }
                    }
                    .frame(width: fitted.width, height: fitted.height)
                    .scaleEffect(zoom.scale)
                    .offset(zoom.offset)
                } else if loadFailed {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                        Text("Can't display this image")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.black)
            .contentShape(Rectangle())
            .clipped()
            .gesture(panGesture)
            .simultaneousGesture(magnifyGesture(container: geometry.size))
            .onTapGesture(count: 2, coordinateSpace: .local) { location in
                withAnimation(.easeInOut(duration: 0.2)) {
                    toggleZoom(around: location, container: geometry.size)
                }
            }
            .background(
                ScrollWheelMonitor { event, location in
                    handleScroll(event, at: location, container: geometry.size)
                }
            )
            .onAppear { containerSize = geometry.size }
            .onChange(of: geometry.size) { _, size in
                containerSize = size
                zoom.offset = clamped(zoom.offset, scale: zoom.scale, container: size)
            }
        }
        .task(id: "\(url.path)#\(reloadToken)") {
            await loadImage()
        }
        .task(id: needsFullResolution) {
            if needsFullResolution { await loadFullResolution() }
        }
        .onChange(of: request) { _, request in
            withAnimation(.easeInOut(duration: 0.2)) { apply(request.command) }
        }
        .onChange(of: zoomPercent) { _, percent in onZoomPercentChange?(percent) }
        .onAppear { onZoomPercentChange?(zoomPercent) }
    }

    // MARK: - Geometry

    private func fittedSize(in container: CGSize) -> CGSize {
        let source = pixelSize ?? image?.size ?? .zero
        guard source.width > 0, source.height > 0, container.width > 0, container.height > 0 else { return container }
        let s = min(container.width / source.width, container.height / source.height)
        return CGSize(width: source.width * s, height: source.height * s)
    }

    /// Fit-relative scale at which one image pixel maps to one screen pixel.
    private func actualSizeScale(in container: CGSize) -> CGFloat? {
        guard let px = pixelSize, px.width > 0 else { return nil }
        let fitted = fittedSize(in: container)
        guard fitted.width > 0 else { return nil }
        return px.width / (fitted.width * displayScale)
    }

    /// Zoom as a percentage of actual pixels (e.g. 100 = 1:1)
    private var zoomPercent: Int? {
        guard let actual = actualSizeScale(in: containerSize), actual > 0 else { return nil }
        return Int((zoom.scale / actual * 100).rounded())
    }

    /// True when the displayed (screen-tier) image has fewer pixels than the screen shows.
    private var needsFullResolution: Bool {
        guard !isFullRes, !zoom.isFit, let image, let px = pixelSize, px.width > image.size.width + 1 else { return false }
        let shownPixels = fittedSize(in: containerSize).width * zoom.scale * displayScale
        return shownPixels > image.size.width * 1.02
    }

    private func clamped(_ offset: CGSize, scale: CGFloat, container: CGSize) -> CGSize {
        let fitted = fittedSize(in: container)
        let maxX = max(0, (fitted.width * scale - container.width) / 2)
        let maxY = max(0, (fitted.height * scale - container.height) / 2)
        return CGSize(width: min(max(offset.width, -maxX), maxX),
                      height: min(max(offset.height, -maxY), maxY))
    }

    /// Change scale while keeping the image point under `point` (container coordinates) fixed.
    private func setScale(_ newScale: CGFloat, around point: CGPoint, container: CGSize, from start: ZoomState? = nil) {
        let base = start ?? zoom
        let s = min(max(newScale, 1), maxScale)
        let t = CGPoint(x: point.x - container.width / 2, y: point.y - container.height / 2)
        // Image point (in fitted coordinates, relative to centre) currently under t
        let px = (t.x - base.offset.width) / base.scale
        let py = (t.y - base.offset.height) / base.scale
        let offset = CGSize(width: t.x - px * s, height: t.y - py * s)
        zoom = ZoomState(scale: s, offset: s <= 1.0001 ? .zero : clamped(offset, scale: s, container: container))
    }

    private func center(_ container: CGSize) -> CGPoint {
        CGPoint(x: container.width / 2, y: container.height / 2)
    }

    // MARK: - Commands

    private func apply(_ command: ZoomRequest.Command) {
        let c = containerSize
        switch command {
        case .fit:
            zoom = .fit
        case .actualSize:
            setScale(max(actualSizeScale(in: c) ?? 1, 1), around: center(c), container: c)
        case .zoomIn:
            setScale(zoom.scale * 1.5, around: center(c), container: c)
        case .zoomOut:
            setScale(zoom.scale / 1.5, around: center(c), container: c)
        }
    }

    private func toggleZoom(around location: CGPoint, container: CGSize) {
        if zoom.isFit {
            let actual = actualSizeScale(in: container) ?? 2
            setScale(actual > 1.05 ? actual : 2, around: location, container: container)
        } else {
            zoom = .fit
        }
    }

    // MARK: - Gestures

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard !zoom.isFit else { return }
                if gestureStart == nil { gestureStart = zoom }
                guard let start = gestureStart else { return }
                let proposed = CGSize(width: start.offset.width + value.translation.width,
                                      height: start.offset.height + value.translation.height)
                zoom.offset = clamped(proposed, scale: zoom.scale, container: containerSize)
            }
            .onEnded { _ in gestureStart = nil }
    }

    private func magnifyGesture(container: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if gestureStart == nil { gestureStart = zoom }
                guard let start = gestureStart else { return }
                setScale(start.scale * value.magnification, around: value.startLocation,
                         container: container, from: start)
            }
            .onEnded { _ in gestureStart = nil }
    }

    /// Mouse wheel (or ⌘ + trackpad scroll) zooms around the pointer; plain trackpad scrolling
    /// pans while zoomed in. Returns true when the event was consumed.
    private func handleScroll(_ event: NSEvent, at location: CGPoint, container: CGSize) -> Bool {
        let isTrackpad = event.hasPreciseScrollingDeltas
        if isTrackpad && !event.modifierFlags.contains(.command) {
            guard !zoom.isFit else { return false }
            let proposed = CGSize(width: zoom.offset.width + event.scrollingDeltaX,
                                  height: zoom.offset.height + event.scrollingDeltaY)
            zoom.offset = clamped(proposed, scale: zoom.scale, container: container)
            return true
        }
        let delta = event.scrollingDeltaY
        guard delta != 0 else { return false }
        let factor = pow(isTrackpad ? 1.01 : 1.15, delta)
        setScale(zoom.scale * factor, around: location, container: container)
        return true
    }

    // MARK: - Loading

    private func loadImage() async {
        loadFailed = false
        isFullRes = false
        let pipeline = ImagePipeline.shared

        if let cached = pipeline.cachedImage(for: url, tier: .screen) {
            image = cached
        } else {
            // Instant placeholder from the gallery's thumbnail cache, if we have it
            image = pipeline.cachedImage(for: url, tier: .thumbnail)
        }

        let target = url
        pixelSize = await Task.detached { pipeline.pixelSize(for: target) }.value

        if let screen = await pipeline.image(for: url, tier: .screen) {
            guard !Task.isCancelled else { return }
            image = screen
        } else if image == nil {
            loadFailed = true
        }
        zoom.offset = clamped(zoom.offset, scale: zoom.scale, container: containerSize)
    }

    private func loadFullResolution() async {
        let target = url
        guard let full = await ImagePipeline.shared.image(for: target, tier: .full),
              !Task.isCancelled, target == url else { return }
        image = full
        isFullRes = true
    }
}

// MARK: - Scroll wheel monitor

/// Zero-size background view that forwards scroll-wheel events landing inside its bounds.
/// `handler` receives the event and its location in SwiftUI (top-left origin) coordinates,
/// and returns true to consume it.
struct ScrollWheelMonitor: NSViewRepresentable {
    let handler: (NSEvent, CGPoint) -> Bool

    func makeNSView(context: Context) -> MonitorView {
        let v = MonitorView()
        v.handler = handler
        return v
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.handler = handler
    }

    final class MonitorView: NSView {
        var handler: ((NSEvent, CGPoint) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { install() } else { remove() }
        }

        private func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let p = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(p) else { return event }
                let swiftUIPoint = CGPoint(x: p.x, y: self.isFlipped ? p.y : self.bounds.height - p.y)
                return (self.handler?(event, swiftUIPoint) == true) ? nil : event
            }
        }

        private func remove() {
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        }

        deinit { remove() }
    }
}

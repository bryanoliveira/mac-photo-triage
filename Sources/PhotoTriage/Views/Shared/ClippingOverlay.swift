import SwiftUI

/// Flashing red/blue overlay that marks blown highlights and crushed shadows.
/// Must be placed inside the same ZStack as the image it annotates, with both
/// using .resizable().aspectRatio(contentMode: .fit) so they align automatically.
struct ClippingOverlay: View {
    let url: URL

    @State private var highlights: NSImage? = nil
    @State private var shadows: NSImage? = nil
    @State private var visible = true

    var body: some View {
        ZStack {
            if let h = highlights {
                Image(nsImage: h)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .opacity(visible ? 0.9 : 0)
            }
            if let s = shadows {
                Image(nsImage: s)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .opacity(visible ? 0.9 : 0)
            }
        }
        .allowsHitTesting(false)
        .task(id: url) {
            highlights = nil
            shadows = nil
            let masks = await ClippingAnalyzer.shared.masks(for: url)
            highlights = masks?.highlights
            shadows = masks?.shadows
        }
        .task {
            // Flash at ~1.4 Hz (700ms period)
            do {
                while true {
                    try await Task.sleep(nanoseconds: 700_000_000)
                    withAnimation(.easeInOut(duration: 0.15)) {
                        visible.toggle()
                    }
                }
            } catch {}
        }
    }
}

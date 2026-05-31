import SwiftUI

/// Overlay displaying EXIF metadata
struct EXIFOverlay: View {
    let metadata: EXIFMetadata?
    let position: OverlayPosition

    enum OverlayPosition {
        case topLeading
        case topTrailing
        case bottomLeading
        case bottomTrailing
    }

    var body: some View {
        if let metadata = metadata, !metadata.summaryString.isEmpty {
            VStack(alignment: alignment, spacing: 4) {
                if let camera = metadata.cameraString {
                    Text(camera)
                        .font(.caption.bold())
                }

                Text(metadata.summaryString)
                    .font(.caption)

                if let lens = metadata.lensString {
                    Text(lens)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if let date = metadata.captureDate {
                    Text(dateFormatter.string(from: date))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(12)
        }
    }

    private var alignment: HorizontalAlignment {
        switch position {
        case .topLeading, .bottomLeading:
            return .leading
        case .topTrailing, .bottomTrailing:
            return .trailing
        }
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium  // includes seconds
        return formatter
    }
}

/// Compact EXIF badge for thumbnails
struct EXIFBadge: View {
    let metadata: EXIFMetadata?

    var body: some View {
        if let metadata = metadata, !metadata.summaryString.isEmpty {
            Text(compactSummary)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.6))
                .cornerRadius(3)
        }
    }

    private var compactSummary: String {
        var parts: [String] = []
        if let focal = metadata?.focalLengthString { parts.append(focal) }
        if let ap = metadata?.apertureString { parts.append(ap) }
        return parts.joined(separator: " ")
    }
}

/// View modifier for adding EXIF overlay
struct EXIFOverlayModifier: ViewModifier {
    let metadata: EXIFMetadata?
    let isVisible: Bool
    let position: EXIFOverlay.OverlayPosition

    func body(content: Content) -> some View {
        content.overlay(alignment: overlayAlignment) {
            if isVisible {
                EXIFOverlay(metadata: metadata, position: position)
            }
        }
    }

    private var overlayAlignment: Alignment {
        switch position {
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        }
    }
}

extension View {
    func exifOverlay(
        _ metadata: EXIFMetadata?,
        isVisible: Bool,
        position: EXIFOverlay.OverlayPosition = .bottomLeading
    ) -> some View {
        modifier(EXIFOverlayModifier(metadata: metadata, isVisible: isVisible, position: position))
    }
}

import SwiftUI

// MARK: - Full overlay

/// Structured EXIF panel shown over the image in Preview mode.
struct EXIFOverlay: View {
    let metadata: EXIFMetadata?
    let position: OverlayPosition

    enum OverlayPosition {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
    }

    var body: some View {
        if let m = metadata, m.hasAnyData {
            VStack(alignment: .leading, spacing: 0) {
                // Camera
                if let camera = m.cameraString {
                    Text(camera)
                        .font(.caption.bold())
                        .padding(.bottom, 6)
                }

                // Exposure summary chips
                if !m.summaryString.isEmpty {
                    Text(m.summaryString)
                        .font(.caption.monospacedDigit())
                        .padding(.bottom, 6)
                }

                if m.lensString != nil || m.focalLength35mmString != nil
                    || m.exposureCompensationString != nil || m.flash != nil {
                    Divider().padding(.bottom, 6)
                    if let lens = m.lensString {
                        EXIFInfoRow(label: "Lens", value: lens)
                    }
                    if let f35 = m.focalLength35mmString {
                        EXIFInfoRow(label: "35mm", value: f35)
                    }
                    if let ev = m.exposureCompensationString {
                        EXIFInfoRow(label: "EV", value: ev)
                    }
                    if let fl = m.flashString {
                        EXIFInfoRow(label: "Flash", value: fl)
                    }
                }

                if m.resolutionString != nil || m.fileSize != nil {
                    Divider().padding(.vertical, 6)
                    if let res = m.resolutionString {
                        EXIFInfoRow(label: "Size", value: res)
                    }
                    if let name = m.filename, let sz = m.fileSizeString {
                        EXIFInfoRow(label: "File", value: "\(name)  ·  \(sz)")
                    } else if let name = m.filename {
                        EXIFInfoRow(label: "File", value: name)
                    } else if let sz = m.fileSizeString {
                        EXIFInfoRow(label: "File", value: sz)
                    }
                }

                if let date = m.captureDate {
                    Divider().padding(.vertical, 6)
                    Text(dateFormatter.string(from: date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: 300, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(12)
        }
    }

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }
}

private struct EXIFInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
            Text(value)
                .font(.caption2)
                .textSelection(.enabled)
        }
        .padding(.bottom, 2)
    }
}

// MARK: - Compact badge (thumbnails)

struct EXIFBadge: View {
    let metadata: EXIFMetadata?

    var body: some View {
        if let m = metadata, !m.summaryString.isEmpty {
            Text(compactSummary(m))
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.6))
                .cornerRadius(3)
        }
    }

    private func compactSummary(_ m: EXIFMetadata) -> String {
        [m.focalLengthString, m.apertureString].compactMap { $0 }.joined(separator: " ")
    }
}

// MARK: - View modifier

struct EXIFOverlayModifier: ViewModifier {
    let metadata: EXIFMetadata?
    let isVisible: Bool
    let position: EXIFOverlay.OverlayPosition

    func body(content: Content) -> some View {
        content.overlay(alignment: alignment) {
            if isVisible {
                EXIFOverlay(metadata: metadata, position: position)
            }
        }
    }

    private var alignment: Alignment {
        switch position {
        case .topLeading:     return .topLeading
        case .topTrailing:    return .topTrailing
        case .bottomLeading:  return .bottomLeading
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

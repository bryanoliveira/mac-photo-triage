import SwiftUI

extension TriageState {
    var color: Color {
        switch self {
        case .kept: return .green
        case .trashed: return .red
        case .reviewed: return .blue
        case .unreviewed: return .gray
        }
    }

    var systemImage: String {
        switch self {
        case .kept: return "checkmark.circle.fill"
        case .trashed: return "trash.circle.fill"
        case .reviewed: return "eye.circle.fill"
        case .unreviewed: return "circle.dashed"
        }
    }
}

/// Keep / trash status of an image, used consistently across Gallery, Preview and Triage.
struct DecisionBadge: View {
    @ObservedObject var asset: ImageAsset
    var style: Style = .pill
    /// Whether to show a badge for images without a decision
    var showUnreviewed = false

    enum Style {
        /// Icon only, for thumbnails
        case icon
        /// Coloured capsule with icon + label, for image overlays
        case pill
    }

    var body: some View {
        let state = asset.triageState
        if state != .unreviewed || showUnreviewed {
            switch style {
            case .icon:
                Image(systemName: state.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, state.color)
                    .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1)
                    .help(state.label)
            case .pill:
                Label(state.label.uppercased(), systemImage: state.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(state == .unreviewed ? AnyShapeStyle(.black.opacity(0.45)) : AnyShapeStyle(state.color.opacity(0.9)),
                                in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    .accessibilityLabel("Status: \(state.label)")
            }
        }
    }
}

/// Floating confirmation message shown after keep/trash/undo actions
struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
    }
}

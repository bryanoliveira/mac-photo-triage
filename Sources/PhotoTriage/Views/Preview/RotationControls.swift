import SwiftUI

/// Rotation controls for preview mode
struct RotationControls: View {
    @Binding var rotation: Angle
    let onApply: () -> Void

    @State private var freeRotation: Double = 0

    var body: some View {
        VStack(spacing: 16) {
            // Quick rotation buttons
            HStack(spacing: 20) {
                Button(action: { rotate(by: -90) }) {
                    VStack {
                        Image(systemName: "rotate.left")
                            .font(.title2)
                        Text("90° CCW")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)

                Button(action: { rotation = .zero; freeRotation = 0 }) {
                    VStack {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.title2)
                        Text("Reset")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)

                Button(action: { rotate(by: 90) }) {
                    VStack {
                        Image(systemName: "rotate.right")
                            .font(.title2)
                        Text("90° CW")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
            }

            Divider()

            // Free rotation slider
            VStack(spacing: 8) {
                Text("Horizon adjust: \(String(format: "%+.1f", freeRotation))°")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Slider(value: $freeRotation, in: -45...45, step: 0.5) { _ in
                    updateRotation()
                }
                .frame(maxWidth: 300)

                HStack {
                    Button("-0.5°") { adjustFreeRotation(by: -0.5) }
                    Spacer()
                    Button("+0.5°") { adjustFreeRotation(by: 0.5) }
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func rotate(by degrees: Double) {
        rotation += .degrees(degrees)
        freeRotation = 0
    }

    private func adjustFreeRotation(by degrees: Double) {
        freeRotation += degrees
        freeRotation = max(-45, min(45, freeRotation))
        updateRotation()
    }

    private func updateRotation() {
        // Combine step rotation with free rotation
        let stepDegrees = rotation.degrees.truncatingRemainder(dividingBy: 360)
        let nearestStep = (stepDegrees / 90).rounded() * 90
        rotation = .degrees(nearestStep + freeRotation)
    }
}

/// Compact rotation button for toolbar
struct RotationButton: View {
    let direction: RotationDirection
    let action: () -> Void

    enum RotationDirection {
        case clockwise
        case counterclockwise

        var systemImage: String {
            switch self {
            case .clockwise: return "rotate.right"
            case .counterclockwise: return "rotate.left"
            }
        }

        var label: String {
            switch self {
            case .clockwise: return "Rotate CW"
            case .counterclockwise: return "Rotate CCW"
            }
        }
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: direction.systemImage)
        }
        .help(direction.label)
    }
}

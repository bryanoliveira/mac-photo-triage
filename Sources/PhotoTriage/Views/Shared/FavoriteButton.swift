import SwiftUI

/// Toggle button for favorite state
struct FavoriteButton: View {
    @ObservedObject var asset: ImageAsset
    let size: ButtonSize
    let action: () -> Void

    enum ButtonSize {
        case small
        case medium
        case large

        var iconSize: CGFloat {
            switch self {
            case .small: return 12
            case .medium: return 16
            case .large: return 24
            }
        }

        var padding: CGFloat {
            switch self {
            case .small: return 4
            case .medium: return 8
            case .large: return 12
            }
        }
    }

    init(asset: ImageAsset, size: ButtonSize = .medium, action: @escaping () -> Void = {}) {
        self.asset = asset
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: {
            action()
        }) {
            Image(systemName: asset.isFavorite ? "star.fill" : "star")
                .font(.system(size: size.iconSize))
                .foregroundColor(asset.isFavorite ? .yellow : .gray)
        }
        .buttonStyle(.plain)
        .padding(size.padding)
        .contentShape(Rectangle())
    }
}

/// Star badge overlay for thumbnails
struct FavoriteBadge: View {
    let isFavorite: Bool

    var body: some View {
        if isFavorite {
            Image(systemName: "star.fill")
                .font(.system(size: 10))
                .foregroundColor(.yellow)
                .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                .padding(4)
        }
    }
}

/// State badge for thumbnails (keep/trash)
struct StateBadge: View {
    let asset: ImageAsset

    var body: some View {
        if asset.isTrashed {
            Badge(text: "Trash", color: .red)
        } else if asset.isKept {
            Badge(text: "Keep", color: .green)
        }
    }

    private struct Badge: View {
        let text: String
        let color: Color

        var body: some View {
            Text(text)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(color.opacity(0.9))
                .cornerRadius(3)
        }
    }
}

/// Combined badges overlay for thumbnails
struct ThumbnailBadges: View {
    @ObservedObject var asset: ImageAsset

    var body: some View {
        VStack {
            HStack {
                Spacer()
                FavoriteBadge(isFavorite: asset.isFavorite)
            }
            Spacer()
            HStack {
                StateBadge(asset: asset)
                Spacer()
                if asset.isPair {
                    PairBadge()
                }
            }
        }
        .padding(4)
    }
}

/// Badge indicating RAW+JPEG pair
struct PairBadge: View {
    var body: some View {
        Text("RAW")
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(Color.purple.opacity(0.8))
            .cornerRadius(2)
    }
}

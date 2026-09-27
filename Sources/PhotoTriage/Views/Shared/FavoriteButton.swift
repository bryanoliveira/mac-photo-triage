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
            case .large: return 20
            }
        }

        var padding: CGFloat {
            switch self {
            case .small: return 4
            case .medium: return 8
            case .large: return 10
            }
        }
    }

    init(asset: ImageAsset, size: ButtonSize = .medium, action: @escaping () -> Void = {}) {
        self.asset = asset
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: asset.isFavorite ? "star.fill" : "star")
                .font(.system(size: size.iconSize, weight: .medium))
                .foregroundColor(asset.isFavorite ? .yellow : .secondary)
                .padding(size.padding)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(asset.isFavorite ? "Remove from favorites (F)" : "Add to favorites (F)")
    }
}

/// Star badge overlay for thumbnails
struct FavoriteBadge: View {
    let isFavorite: Bool

    var body: some View {
        if isFavorite {
            Image(systemName: "star.fill")
                .font(.system(size: 12))
                .foregroundColor(.yellow)
                .shadow(color: .black.opacity(0.6), radius: 1.5, x: 0, y: 1)
        }
    }
}

/// Combined badges overlay for thumbnails. Each corner holds one small icon so badges never
/// collide, even at the densest grid setting.
struct ThumbnailBadges: View {
    @ObservedObject var asset: ImageAsset

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                DecisionBadge(asset: asset, style: .icon)
                Spacer(minLength: 0)
                FavoriteBadge(isFavorite: asset.isFavorite)
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                if asset.isPair {
                    PairBadge()
                }
            }
        }
        .padding(5)
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
            .background(Color.purple.opacity(0.85))
            .cornerRadius(2)
    }
}

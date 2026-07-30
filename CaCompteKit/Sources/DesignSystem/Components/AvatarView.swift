import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Doc 08 : tailles nommées — `.small` en liste, `.medium` en tableau, `.large` en fiche.
public enum AvatarSize: Sendable {
    case small, medium, large

    public var diameter: CGFloat {
        switch self {
        case .small: 28
        case .medium: 44
        case .large: 96
        }
    }
}

/// Doc 08 « Avatars » — rend les trois sources (symbole, emoji, photo) derrière une seule vue,
/// pour qu'aucun écran n'ait à distinguer les cas.
public struct AvatarView: View {
    private let avatar: Avatar
    private let size: AvatarSize

    public init(avatar: Avatar, size: AvatarSize) {
        self.avatar = avatar
        self.size = size
    }

    public var body: some View {
        content
            .frame(width: size.diameter, height: size.diameter)
            .clipShape(Circle())
            .overlay {
                if case .photo = avatar.kind {
                    Circle().strokeBorder(avatar.palette.color, lineWidth: 2)
                }
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch avatar.kind {
        case .symbol(let name):
            ZStack {
                Circle().fill(avatar.palette.color)
                Image(systemName: name)
                    .font(.system(size: size.diameter * 0.5))
                    .foregroundStyle(.white)
            }
        case .emoji(let character):
            ZStack {
                Circle().fill(avatar.palette.color)
                Text(character)
                    .font(.system(size: size.diameter * 0.6))
            }
        case .photo(let data):
            photoContent(data)
        }
    }

    @ViewBuilder
    private func photoContent(_ data: Data) -> some View {
        #if canImport(UIKit)
        if let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            Circle().fill(.neutralFill)
        }
        #else
        Circle().fill(.neutralFill)
        #endif
    }
}

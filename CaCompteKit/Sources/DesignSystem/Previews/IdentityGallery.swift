import SwiftUI

#Preview("Joueurs & logo — clair") {
    IdentityGallery()
}

#Preview("Joueurs & logo — sombre") {
    IdentityGallery()
        .preferredColorScheme(.dark)
}

private struct IdentityGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Palette joueurs").font(.h6).foregroundStyle(.textSecondary)
                    HStack(spacing: Space.sm) {
                        ForEach(1...10, id: \.self) { index in
                            Circle()
                                .fill(PlayerPalette(index: index).color)
                                .frame(width: 28, height: 28)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Avatars").font(.h6).foregroundStyle(.textSecondary)
                    HStack(spacing: Space.md) {
                        AvatarView(avatar: .generated(for: "Alice"), size: .small)
                        AvatarView(avatar: .generated(for: "Bob"), size: .medium)
                        AvatarView(avatar: .generated(for: "Chloé"), size: .large)
                        AvatarView(avatar: Avatar(kind: .emoji("🦊"), palette: PlayerPalette(index: 2)), size: .medium)
                    }
                }

                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Logo").font(.h6).foregroundStyle(.textSecondary)
                    LogoMarkView()
                        .frame(width: 96, height: 96)
                        .background(.neutralSurface, in: .rect(cornerRadius: Radius.md))
                    LogoLockupHorizontal(height: 40)
                        .background(.neutralSurface, in: .rect(cornerRadius: Radius.md))
                    LogoLockupVertical(height: 40)
                        .background(.neutralSurface, in: .rect(cornerRadius: Radius.md))
                }
            }
            .padding(Space.lg)
        }
        .background(.neutralBg)
    }
}

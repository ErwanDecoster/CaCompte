import DesignSystem
import Domain
import Store
import SwiftUI

/// Doc 06 : image 1080×1350 (4:5), mode clair uniquement — « elle finit dans une conversation
/// dont on ne connaît pas le thème » (charte §8).
struct ResultsShareCard: View {
    let gameName: String
    let standings: [Standing]
    let recordByID: [Participant.ID: ParticipantRecord]

    private let pointSize = CGSize(width: 360, height: 450)

    var body: some View {
        VStack(spacing: Space.xl) {
            Text(gameName)
                .font(.h2)
                .foregroundStyle(.textPrimary)

            VStack(spacing: Space.md) {
                ForEach(standings.prefix(3), id: \.participantID) { standing in
                    if let record = recordByID[standing.participantID] {
                        HStack(spacing: Space.md) {
                            Text("\(standing.rank)")
                                .font(.h4)
                                .foregroundStyle(standing.rank == 1 ? .brandBrass : .textSecondary)
                            AvatarView(avatar: record.avatar, size: .medium)
                            Text(record.nicknameSnapshot).font(.h5).foregroundStyle(.textPrimary)
                            Spacer()
                            Text(standing.score.formatted()).font(.scoreL).foregroundStyle(.textSecondary)
                        }
                    }
                }
            }

            Spacer()

            LogoLockupHorizontal(height: 28)
        }
        .padding(Space.xl)
        .frame(width: pointSize.width, height: pointSize.height)
        .background(.neutralSurface)
        .environment(\.colorScheme, .light)
    }
}

extension View {
    /// Rendu résolu au moment de l'appel — acceptable pour un écran de résultats statique
    /// (pas de re-rendu à chaque frame).
    @MainActor
    func renderedImage(scale: CGFloat = 3) -> Image {
        let renderer = ImageRenderer(content: self)
        renderer.scale = scale
        if let uiImage = renderer.uiImage {
            return Image(uiImage: uiImage)
        }
        return Image(systemName: "photo")
    }
}

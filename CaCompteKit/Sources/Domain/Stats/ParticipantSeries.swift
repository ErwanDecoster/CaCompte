/// Doc 06 « Courbe d'évolution » — une série par joueur, cumul en ordonnée, manches en abscisse.
public struct ParticipantSeries: Sendable, Identifiable, Equatable {
    public struct Point: Sendable, Equatable {
        public let round: Int
        public let total: Int

        public init(round: Int, total: Int) {
            self.round = round
            self.total = total
        }
    }

    public let id: Participant.ID
    public let name: String
    public let points: [Point]

    public init(id: Participant.ID, name: String, points: [Point]) {
        self.id = id
        self.name = name
        self.points = points
    }
}

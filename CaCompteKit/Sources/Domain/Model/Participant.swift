import Foundation

public struct Participant: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    public let displayName: String
    public let seatIndex: Int
    /// Doc 05 « Belote » — `nil` pour tous les jeux individuels. Deux participants partagent
    /// une équipe s'ils portent le même `teamID` ; la valeur elle-même (ex. "A"/"B") n'a pas de
    /// sens en dehors de cette égalité.
    public let teamID: String?

    public init(id: UUID = UUID(), displayName: String, seatIndex: Int, teamID: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.seatIndex = seatIndex
        self.teamID = teamID
    }
}

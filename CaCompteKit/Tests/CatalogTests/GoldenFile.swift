import Domain
import Foundation
import Testing

/// Décodage de `spec/golden/*.json` — format documenté dans `spec/README.md`. Les identifiants
/// de participants ("p1", "p2"…) sont des jetons de test lisibles, pas des `UUID` : le test les
/// convertit à la volée.
struct GoldenFile: Decodable, Sendable {
    struct Participant: Decodable, Sendable {
        let id: String
        let name: String
        let seatIndex: Int
        /// Doc 05 « Belote » — `nil` pour tous les jeux individuels.
        let teamID: String?
    }

    struct Input: Decodable, Sendable {
        let participant: String
        let rawValue: Int
        let modifiers: [String]
        /// Payload de `ScoreDetail`, générique dans ce format (`spec/` ignore Catalog) — la
        /// traduction vers un type concret (ex. `YamsCategoryDetail`) se fait dans le test,
        /// pas ici.
        let detail: [String: String]?
    }

    struct RoundInput: Decodable, Sendable {
        let index: Int
        let inputs: [Input]
    }

    struct RoundResult: Decodable, Sendable {
        let index: Int
        let computed: [String: Int]
        let cumulative: [String: Int]
        let doubled: [String]
        let status: String
    }

    struct StandingResult: Decodable, Sendable {
        let participant: String
        let rank: Int
        let score: Int
        let sharedWith: [String]?
    }

    struct FinalResult: Decodable, Sendable {
        let status: String
        let reason: String?
        let standings: [StandingResult]
    }

    struct InsightExpectation: Decodable, Sendable {
        let id: String
        let participant: String?
        let value: Double?
        let round: Int?
        let values: [String: Double]?
    }

    struct Expected: Decodable, Sendable {
        let roundResults: [RoundResult]
        let final: FinalResult
        let insights: [InsightExpectation]
    }

    let goldenId: String
    let gameId: String
    let rulesVersion: Int
    let variants: VariantSelection
    let participants: [Participant]
    let rounds: [RoundInput]
    let expected: Expected

    static let all: [GoldenFile] = {
        let urls = (Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "GoldenResources") ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let decoder = JSONDecoder()
        return urls.map { url in
            let data = try! Data(contentsOf: url)
            return try! decoder.decode(GoldenFile.self, from: data)
        }
    }()
}

extension GoldenFile: CustomTestStringConvertible {
    var testDescription: String { goldenId }
}

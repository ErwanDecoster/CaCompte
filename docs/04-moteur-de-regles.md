# 04 — Moteur de règles

C'est le cœur de l'application. Tout le reste est de l'habillage.

## Le problème à résoudre

Les jeux de société se répartissent en deux familles très inégales :

- **~80 % sont triviaux** : on saisit un nombre par joueur et par manche, on cumule, on
  s'arrête à un seuil ou après N manches. Rami, Scrabble, Triominos, 6 qui prend, Uno…
- **~20 % ont une arithmétique propre** : le doublement de Skyjo, le bonus de 35 du Yams, la
  formule du Tarot, l'annonce du Wizard, le retour à 25 du Mölkky.

Écrire une classe par jeu pour les 80 % serait 16 fois le même code. Tout décrire en JSON
échouerait sur les 20 % — un moteur de règles générique suffisamment expressif pour encoder le
Tarot devient un langage de programmation mal conçu.

**Solution retenue : deux couches.**

```
┌────────────────────────────────────────────────────────────────┐
│  Couche déclarative — spec/games/*.json                        │
│  identité, joueurs, sens du score, contraintes de saisie,      │
│  conditions de fin, départages, variantes                      │
│  ▸ partagée mot pour mot avec Android                          │
│  ▸ suffisante seule pour 11 des 16 jeux du catalogue           │
└──────────────────────────┬─────────────────────────────────────┘
                           │  "engine": "skyjo.v1"
                           ▼
┌────────────────────────────────────────────────────────────────┐
│  Couche impérative — GameRules (Swift) / GameRules (Kotlin)    │
│  uniquement le calcul non exprimable en données                │
│  ▸ ré-implémentée par plateforme                               │
│  ▸ verrouillée par les golden files                            │
└────────────────────────────────────────────────────────────────┘
```

Les jeux simples pointent tous vers `"engine": "generic.sum.v1"` : une seule implémentation
impérative les sert tous.

---

## Types du domaine

Tout est `struct`, `Sendable`, `Codable`, `Equatable`.

```swift
// ─── Identité ────────────────────────────────────────────────────────────
public struct Participant: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    public let displayName: String
    public let seatIndex: Int
}

// ─── Saisie ──────────────────────────────────────────────────────────────
/// Ce que l'utilisateur a saisi pour un joueur, avant toute règle.
public struct ScoreInput: Sendable, Codable, Equatable {
    public let participantID: Participant.ID
    public let rawValue: Int
    public let detail: ScoreDetail?      // Yams, Tarot… payload structuré
    public let modifiers: Set<ModifierID> // ["closedRound"], ["capot"]…
}

public struct RoundDraft: Sendable, Codable, Equatable {
    public let index: Int
    public let inputs: [ScoreInput]      // un par participant, ordre libre
    public let note: String?
}

// ─── Résultat ────────────────────────────────────────────────────────────
public struct ScoreEntry: Sendable, Codable, Equatable {
    public let participantID: Participant.ID
    public let rawValue: Int
    public let computedValue: Int        // après règles
    public let explanation: String?      // « doublé : n'a pas le score le plus bas »
    public let detail: ScoreDetail?
    public let modifiers: Set<ModifierID>
}

public struct Round: Sendable, Codable, Equatable {
    public let index: Int
    public let entries: [ScoreEntry]
    public let committedAt: Date
    public let note: String?
}

// ─── État ────────────────────────────────────────────────────────────────
public struct MatchState: Sendable, Codable, Equatable {
    public let matchID: UUID
    public let gameID: String
    public let rulesVersion: Int
    public let variants: VariantSelection
    public let participants: [Participant]
    public private(set) var rounds: [Round]
    public private(set) var status: MatchStatus
    public private(set) var endReason: EndReason?

    /// Cumul par joueur, recalculé, jamais stocké.
    public func totals() -> [Participant.ID: Int]
    public func total(for id: Participant.ID) -> Int
}

public enum MatchStatus: String, Sendable, Codable {
    case inProgress
    case finalRound      // le seuil est franchi, on termine le tour de table
    case ended
    case abandoned
}
```

`MatchState` n'a **pas** de setter public. Il ne se modifie que par `MatchEngine.reduce`.

## Le protocole `GameRules`

```swift
public protocol GameRules: Sendable {
    /// Identifiant du moteur, tel qu'écrit dans le JSON : "skyjo.v1".
    static var engineID: String { get }

    /// Contrôle de la saisie, avant validation. Bloquant.
    func validate(_ draft: RoundDraft,
                  in state: MatchState,
                  definition: GameDefinition) -> ValidationResult

    /// Transforme la saisie brute en scores effectifs.
    /// C'est ici que vit le doublement Skyjo, le bonus Yams, la formule Tarot.
    func score(_ draft: RoundDraft,
               in state: MatchState,
               definition: GameDefinition) -> [ScoreEntry]

    /// La partie doit-elle s'arrêter ? Appelé après chaque manche validée.
    func endCheck(_ state: MatchState,
                  definition: GameDefinition) -> EndCheck

    /// Classement final, gestion des ex æquo et des départages.
    func standings(_ state: MatchState,
                   definition: GameDefinition) -> [Standing]
}
```

Quatre méthodes, aucune n'a d'effet de bord, aucune ne prend de dépendance. Une implémentation
tient en 40 à 120 lignes. Les valeurs par défaut de l'extension de protocole couvrent
entièrement `generic.sum.v1` : un jeu simple n'implémente rien du tout.

### `EndCheck` — le point subtil

La quasi-totalité des jeux à seuil ne s'arrêtent **pas** au moment où le seuil est franchi :
on termine le tour de table pour que chacun ait joué le même nombre de manches. Modéliser
cela explicitement évite le bug classique du joueur lésé parce qu'il était assis en dernier.

```swift
public enum EndCheck: Sendable, Equatable {
    case `continue`
    case finalRound(triggeredBy: Participant.ID, reason: EndReason)
    case ended(reason: EndReason)
}

public enum EndReason: String, Sendable, Codable {
    case scoreThreshold      // un joueur a atteint le seuil
    case roundLimit          // nombre de manches fixé atteint
    case targetReached       // objectif atteint exactement (Mölkky)
    case allSheetsComplete   // toutes les grilles remplies (Yams)
    case elimination         // un seul joueur reste en lice
    case manualStop          // arrêt décidé par l'utilisateur
}
```

L'UI réagit aux trois cas : bandeau neutre, bandeau « Dernière manche » orangé, écran de
résultats.

### `ValidationResult`

```swift
public enum ValidationResult: Sendable, Equatable {
    case valid
    case warning([String])          // affiché, n'empêche pas de valider
    case invalid([ValidationError]) // bloque, ancré sur le champ fautif
}
```

Distinction volontaire entre *warning* et *invalid*. Un score de 137 au Skyjo est
mathématiquement possible mais très improbable : on avertit, on n'interdit pas. Deux joueurs
déclarés « a fermé la manche » sont impossibles : on bloque. Une app qui refuse une saisie
légitime en pleine soirée est pire qu'une app permissive.

---

## Event sourcing

`MatchState` ne se construit jamais par mutation, mais par repli d'un journal d'événements.

```swift
public enum MatchEvent: Sendable, Codable, Equatable {
    case matchCreated(gameID: String, rulesVersion: Int,
                      variants: VariantSelection, participants: [Participant])
    case roundCommitted(RoundDraft)
    case roundAmended(index: Int, draft: RoundDraft)
    case roundRemoved(index: Int)
    case matchAbandoned(at: Date)
    case noteAdded(roundIndex: Int, text: String)
}

public struct StampedEvent: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public let lamport: UInt64      // horloge logique
    public let deviceID: String     // départage les égalités de lamport
    public let occurredAt: Date     // affichage uniquement, jamais pour trier
    public let event: MatchEvent
}

public struct MatchEngine: Sendable {
    public func reduce(_ state: MatchState, _ event: MatchEvent,
                       rules: any GameRules,
                       definition: GameDefinition) -> MatchState
    public func replay(_ log: [StampedEvent],
                       catalog: GameCatalog) throws -> MatchState
}
```

`replay` trie par `(lamport, deviceID)` puis replie. Quatre propriétés en découlent
directement, sans code supplémentaire :

| Besoin | Comment il est satisfait |
|---|---|
| **Annuler / corriger** | on ajoute `roundRemoved` ou `roundAmended`, on rejoue. Pas de logique inverse à écrire. |
| **Partie partagée** | deux appareils échangent leurs événements et rejouent. |
| **Conflit iCloud** | fusion de journaux : dédoublonnage par `id`, tri, rejeu. Commutatif et idempotent. |
| **Test** | un golden file *est* un journal + un état attendu. |

Le coût : rejouer 40 manches à 6 joueurs prend moins d'une milliseconde. Aucune optimisation
n'est prévue ; si elle devenait nécessaire, un instantané tous les 50 événements suffirait.

**`occurredAt` ne sert jamais à ordonner.** Les horloges murales de deux téléphones divergent
et un utilisateur peut changer la sienne. Seul `(lamport, deviceID)` fait foi.

---

## Le cas Skyjo, en détail

Skyjo est le jeu de référence du projet : il illustre exactement pourquoi la couche impérative
existe.

**Règles retenues** (édition officielle) :

1. La manche s'arrête quand un joueur a retourné ses 12 cartes ; les autres jouent un dernier
   tour.
2. Chacun additionne ses cartes visibles (valeurs de −2 à 12 ; une colonne de trois cartes
   identiques est retirée et compte 0).
3. **Si le joueur qui a fermé la manche n'a pas le score strictement le plus bas, son score est
   doublé.** L'égalité ne le protège pas. Le doublement ne s'applique que si son score est
   strictement positif — doubler −4 récompenserait la faute.
4. La partie s'arrête à la fin de la manche où un joueur atteint **100 points ou plus**.
5. Le score **le plus bas** gagne.

```swift
struct SkyjoRulesV1: GameRules {
    static let engineID = "skyjo.v1"

    func validate(_ draft: RoundDraft, in state: MatchState,
                  definition: GameDefinition) -> ValidationResult {
        let closers = draft.inputs.filter { $0.modifiers.contains(.closedRound) }
        guard closers.count == 1 else {
            return .invalid([.init(field: .modifier(.closedRound),
                                   message: "Un seul joueur ferme la manche.")])
        }
        let extremes = draft.inputs.filter { $0.rawValue < -24 || $0.rawValue > 156 }
        return extremes.isEmpty ? .valid
                                : .warning(["Score inhabituel, à vérifier."])
    }

    func score(_ draft: RoundDraft, in state: MatchState,
               definition: GameDefinition) -> [ScoreEntry] {
        let doublingEnabled = state.variants.bool("doublePenalty", default: true)
        let lowest = draft.inputs.map(\.rawValue).min() ?? 0

        return draft.inputs.map { input in
            let closed  = input.modifiers.contains(.closedRound)
            let isStrictlyLowest = input.rawValue == lowest
                && draft.inputs.filter { $0.rawValue == lowest }.count == 1
            let penalised = doublingEnabled && closed
                && !isStrictlyLowest && input.rawValue > 0

            return ScoreEntry(
                participantID: input.participantID,
                rawValue: input.rawValue,
                computedValue: penalised ? input.rawValue * 2 : input.rawValue,
                explanation: penalised
                    ? "Score doublé : a fermé la manche sans le score le plus bas."
                    : nil,
                detail: nil,
                modifiers: input.modifiers
            )
        }
    }

    func endCheck(_ state: MatchState, definition: GameDefinition) -> EndCheck {
        let threshold = state.variants.int("threshold", default: 100)
        let totals = state.totals()
        guard let (id, _) = totals.first(where: { $0.value >= threshold }) else {
            return .continue
        }
        // Le seuil est constaté en fin de manche : tout le monde a déjà joué.
        return .ended(reason: .scoreThreshold)
    }

    func standings(_ state: MatchState, definition: GameDefinition) -> [Standing] {
        // Score le plus bas gagne ; départage : meilleure manche, puis ex æquo.
        …
    }
}
```

Ce qui n'est **pas** dans le code : le retrait des colonnes de trois cartes identiques. C'est
une règle de table, pas de comptage — l'utilisateur saisit son total final. Une option
« saisie assistée » (grille 3×4 tapée carte par carte) est envisagée en v2 et calculerait les
colonnes elle-même ; elle produirait exactement le même `rawValue`, sans toucher au moteur.

Golden file correspondant : [`spec/golden/skyjo-01-doublement.json`](../spec/golden/skyjo-01-doublement.json).

---

## Catalogue et chargement

```swift
public struct GameCatalog: Sendable {
    public func definition(for gameID: String, version: Int) throws -> GameDefinition
    public func rules(for gameID: String, version: Int) throws -> any GameRules
    public var allGames: [GameDefinition] { get }
}
```

Les définitions sont décodées **au lancement** depuis les JSON embarqués, jamais téléchargées.
Le mapping `engineID -> GameRules` est une table statique, exhaustive, vérifiée par un test qui
échoue si un JSON du catalogue référence un moteur inexistant.

Le versionnage suit deux axes distincts :

- `specVersion` — version du **format** de `GameDefinition`. Change rarement.
- `rulesVersion` — version des **règles d'un jeu donné**. Incrémentée dès qu'un calcul change.
  Les anciennes implémentations sont conservées (`SkyjoRulesV1` reste indéfiniment) afin que
  l'historique reste exact.

## Filet de sécurité : le jeu libre

Un jeu spécial `"freeform"` est présent dès la v1 : nom saisi par l'utilisateur, sens du score
au choix, condition de fin au choix (seuil, nombre de manches, ou arrêt manuel). Il utilise
`generic.sum.v1`.

Il coûte presque rien et garantit que l'app est utilisable pour un jeu absent du catalogue —
c'est le meilleur remède au risque « le jeu de ce soir n'y est pas » identifié dans la
[vision produit](01-vision-produit.md).

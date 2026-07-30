# 02 — Architecture

## Principe directeur

> Le calcul des scores ne connaît ni SwiftUI, ni SwiftData, ni le réseau.

Tout ce qui décide d'un score, d'un classement ou d'une fin de partie vit dans un module de
**fonctions pures sur des structures `Sendable`**. Ce module n'importe rien d'autre que
`Foundation`. Il en découle trois bénéfices directs :

- il se teste sans simulateur, sans base, sans horloge, en quelques millisecondes ;
- il se rejoue à l'identique à partir d'un fichier golden ;
- il se transpose mécaniquement en Kotlin, parce qu'il n'utilise aucun concept propre à Apple.

Tout le reste — persistance, réseau, interface — est un **adaptateur** autour de ce noyau.

## Modules

Un unique package Swift local, `CaCompteKit`, contenant plusieurs cibles. Un package plutôt
qu'un projet monolithique parce que les dépendances entre cibles deviennent alors vérifiées à
la compilation : `Domain` ne *peut pas* importer SwiftUI, le compilateur le refuse.

```
                        ┌──────────────────┐
                        │   CaCompte.app   │  cible Xcode
                        │  features + DI   │
                        └────────┬─────────┘
             ┌───────────────┬───┴────┬───────────────┐
             ▼               ▼        ▼               ▼
      ┌────────────┐  ┌───────────┐ ┌──────┐  ┌──────────────┐
      │   Store    │  │  Catalog  │ │ Sync │  │ DesignSystem │
      │ SwiftData  │  │  6 jeux   │ │Wi/BLE│  │   SwiftUI    │
      └──────┬─────┘  └─────┬─────┘ └──┬───┘  └──────────────┘
             └──────────────┼──────────┘
                            ▼
                    ┌───────────────┐
                    │    Domain     │   Foundation uniquement
                    │ types + moteur│   100 % pur, 100 % Sendable
                    └───────────────┘
```

| Cible | Dépend de | Contient | Ne contient jamais |
|---|---|---|---|
| **Domain** | `Foundation` | Types du domaine, protocole `GameRules`, `MatchEngine`, `StatsEngine`, chargement des définitions JSON | Aucune I/O, aucun `Date()` implicite, aucun singleton |
| **Catalog** | Domain | Une implémentation `GameRules` par jeu + les JSON embarqués en ressource | Persistance, UI |
| **Store** | Domain | Modèles `@Model`, `ModelContainer`, repositories, mapping domaine ↔ persistance | Règles de jeu |
| **Sync** | Domain | `LiveSession`, protocole `Transport` (implémentations `WifiTransport`/`BLETransport`), `WireMessage`, horloge de Lamport | UI, persistance |
| **DesignSystem** | `SwiftUI` | Tokens, composants réutilisables, avatars, pavé de saisie | Domain (délibérément — composants agnostiques) |
| **CaCompte.app** | tout | Écrans, navigation, `@Observable` de flux, composition des dépendances | Logique de calcul |

`DesignSystem` ne dépend pas de `Domain` volontairement : ses composants prennent des valeurs
brutes en entrée. Cela évite qu'un bouton finisse par embarquer une règle de jeu, et rend les
previews Xcode instantanées.

## Pattern d'interface : MV, pas MVVM

SwiftUI + `@Observable` rendent la couche ViewModel systématique inutile. La règle retenue :

- **Listes et lectures simples** → `@Query` SwiftData directement dans la vue. Pas
  d'intermédiaire pour afficher l'historique des parties.
- **Flux avec état** → un objet `@Observable` `@MainActor` qui porte l'état et les intentions.
  Il y en a peu : `LiveMatchModel`, `MatchSetupModel`, `PlayerEditorModel`. Ce ne sont pas des
  ViewModels par écran mais **par flux métier**, partagés entre plusieurs vues.
- **Aucun état métier dans `@State` de vue**. `@State` ne porte que du transitoire d'UI
  (feuille présentée, champ focalisé, animation en cours).

```swift
@MainActor @Observable
final class LiveMatchModel {
    private(set) var state: MatchState          // Domain, valeur pure
    private(set) var pendingRound: RoundDraft   // saisie en cours, non validée
    private let engine: MatchEngine             // Domain
    private let store: MatchStore               // Store
    private let session: LiveSession?           // Sync, nil en solo

    func setScore(_ value: Int, for participant: Participant.ID) { … }
    func commitRound() async throws { … }       // valide → persiste → diffuse
    func undoLastRound() async throws { … }
}
```

## Concurrence Swift 6

Le projet est en **mode langage Swift 6, concurrence stricte activée**, sans exception.

- Tous les types de `Domain` sont des `struct` immuables et `Sendable`. Aucune classe, aucun
  état partagé, donc aucune donnée à isoler.
- Les moteurs (`MatchEngine`, `StatsEngine`) sont des `struct` sans état : `nonisolated`
  par nature, appelables depuis n'importe quel contexte.
- L'UI et les modèles `@Observable` sont `@MainActor`.
- Les écritures SwiftData volumineuses (import, recalcul d'agrégats) passent par un
  `@ModelActor` dédié. Les écritures interactives restent sur le `mainContext` : elles portent
  sur quelques objets, la latence est nulle, et cela évite tout aller-retour d'identifiants.
- `Sync` expose ses événements entrants par un `AsyncStream<MatchEvent>` consommé dans une
  `.task` de la vue de partie. Aucun callback, aucun delegate remonté jusqu'à l'UI.

## Arborescence cible

```
CaCompte/
├── docs/                      ce plan
├── spec/                      source de vérité inter-plateformes (JSON)
├── CaCompteKit/               package Swift local
│   ├── Package.swift
│   ├── Sources/
│   │   ├── Domain/
│   │   │   ├── Model/         Player, Participant, MatchState, Round, ScoreEntry…
│   │   │   ├── Rules/         GameDefinition, GameRules, EndCheck, Standing
│   │   │   ├── Engine/        MatchEngine, EventLog, LamportClock
│   │   │   └── Stats/         StatsEngine, Insight, Badge
│   │   ├── Catalog/
│   │   │   ├── Games/         SkyjoRules.swift, YamsRules.swift, TarotRules.swift…
│   │   │   ├── GenericRules/  SumRules, TrickPredictionRules, FreeFormRules
│   │   │   └── Resources/     copie synchronisée de spec/games/*.json
│   │   ├── Store/
│   │   ├── Sync/
│   │   └── DesignSystem/
│   └── Tests/
│       ├── DomainTests/
│       ├── CatalogTests/       ← rejoue spec/golden/*.json
│       └── StoreTests/
├── App/
│   ├── CaCompte.xcodeproj
│   ├── CaCompteApp.swift
│   ├── Features/
│   │   ├── Home/  Players/  MatchSetup/  LiveMatch/  Results/  History/  Profile/
│   │   └── Settings/
│   ├── Resources/             Assets, Localizable.xcstrings, Info.plist
│   └── CaCompteUITests/
└── .github/ ou ci_scripts/    Xcode Cloud
```

Les JSON de `Catalog/Resources/` sont une copie de `spec/games/`. Un script de build
(Phase 0) copie et vérifie l'égalité : si les deux divergent, la compilation échoue. `spec/`
reste la source, jamais l'inverse.

## Flux de données d'une manche validée

```
 Vue de saisie
     │ setScore(12, for: alice)
     ▼
 LiveMatchModel.pendingRound        (brouillon, rien n'est encore acté)
     │ commitRound()
     ▼
 GameRules.validate(draft, in: state)          ─ refus possible, message affiché
     │ ok
     ▼
 MatchEvent.roundCommitted(...)     événement horodaté (Lamport), signé du deviceID
     │
     ├──▶ EventLog.append          → MatchEngine.reduce(state, event) → nouvel état
     │                               │
     │                               ├─▶ GameRules.endCheck(state)
     │                               │     .continue / .finalRound / .ended
     │                               └─▶ UI mise à jour
     │
     ├──▶ MatchStore.persist(event, state)      SwiftData, immédiat
     │
     └──▶ LiveSession.propose(event)            transport actif (Wi-Fi ou BLE), si partagée —
                                                 diffusion immédiate si hôte, sinon proposition
                                                 à l'hôte (doc 09)
```

Un point important : `reduce` est une fonction pure `(MatchState, MatchEvent) -> MatchState`.
C'est elle qui rend l'annulation triviale (on retire l'événement et on rejoue), la
synchronisation possible (on fusionne deux journaux et on rejoue), et le test exhaustif
(un golden file *est* une liste d'événements et un état final attendu).

Voir [04 — Moteur de règles](04-moteur-de-regles.md) pour le détail des types.

## Injection de dépendances

Pas de conteneur DI, pas de framework. Les dépendances sont passées à l'initialisation depuis
`CaCompteApp`, et exposées aux vues profondes par `@Environment` avec des clés typées :

```swift
extension EnvironmentValues {
    @Entry var gameCatalog: GameCatalog = .live
    @Entry var matchStore: MatchStore = .live
}
```

`@Entry` (Swift 5.10+) évite le boilerplate `EnvironmentKey`. Chaque dépendance a une valeur
`.live` et une valeur `.preview` déterministe, ce qui rend toutes les previews Xcode
fonctionnelles sans base de données.

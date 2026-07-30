# 09 — Tests & qualité

## Ce qu'on cherche à empêcher

Un seul défaut est réellement grave : **un score faux**. Une animation ratée se corrige la
semaine suivante ; un total erroné détruit la confiance dans l'app définitivement, et personne
ne la rouvre. La stratégie de test est donc déséquilibrée volontairement : l'essentiel de
l'effort porte sur le domaine, très peu sur l'interface.

## Pyramide

```
        ╱  XCUITest — 3 parcours     ╲       lents, fragiles, indispensables
       ╱     création joueur          ╲      quand même
      ╱      partie Skyjo complète     ╲
     ╱       reprise après relance      ╲
    ╱─────────────────────────────────────╲
   ╱  Intégration — Store, Sync            ╲   base en mémoire,
  ╱     mapping, migrations, convergence     ╲  transport simulé
 ╱───────────────────────────────────────────╲
╱  Unitaires — Domain, Catalog, Stats         ╲  ~80 % de l'effort
│  ▸ golden files rejoués                      │ < 1 s au total
│  ▸ invariants, propriétés                    │
└───────────────────────────────────────────────┘
```

**Swift Testing**, pas XCTest — sauf pour XCUITest, qui reste sur XCTest.

## Les golden files

C'est la pièce maîtresse, et le pivot de la stratégie Android.

Un golden file décrit une partie complète et ses résultats attendus, en JSON, sans une ligne de
Swift ni de Kotlin. Les deux plateformes le chargent, le rejouent, et comparent.

```swift
@Suite("Golden files")
struct GoldenTests {
    @Test(arguments: GoldenFile.all)      // découverte automatique du dossier
    func replay(_ golden: GoldenFile) throws {
        let catalog = GameCatalog.embedded
        let rules = try catalog.rules(for: golden.gameID, version: golden.rulesVersion)
        let definition = try catalog.definition(for: golden.gameID, version: golden.rulesVersion)

        var state = MatchState(from: golden)
        for round in golden.rounds {
            state = MatchEngine().reduce(state, .roundCommitted(round.draft),
                                         rules: rules, definition: definition)
            let expected = golden.expected.roundResults[round.index]
            #expect(state.totals() == expected.cumulative)
            #expect(state.status == expected.status)
        }

        #expect(state.endReason == golden.expected.final.reason)
        #expect(rules.standings(state, definition: definition) == golden.expected.final.standings)

        let stats = StatsEngine().insights(for: state, definition: definition)
        #expect(stats.matches(golden.expected.insights))
    }
}
```

Un test paramétré : ajouter un golden au dossier ajoute un cas, sans toucher au code de test.
Un échec nomme le fichier fautif.

**Couverture exigée par jeu** : au minimum deux golden files —

1. une partie nominale, du début à la fin ;
2. le cas limite qui fait la particularité du jeu (doublement Skyjo, bonus de 63 au Yams,
   chute du preneur au Tarot, dépassement de 50 au Mölkky, ex æquo au sommet).

Un jeu sans golden ne sort pas.

## Invariants et tests de propriété

Certaines vérités doivent tenir pour *toute* partie, pas seulement pour les cas écrits à la
main. Swift Testing permet de les exprimer sur des entrées générées.

| Invariant | Portée |
|---|---|
| Somme des scores d'une donne = 0 | Tarot — attrape immédiatement toute erreur de formule ou de répartition |
| `replay(L) == replay(σ(L))` pour toute permutation σ | journal d'événements — fondement de la sync |
| `replay(L + L) == replay(L)` | idempotence — doublons réseau |
| `standings()` est un ordre total, ex æquo compris | tous les jeux |
| `total(joueur) == Σ computedValue` de ses entrées | tous les jeux |
| `endCheck` ne repasse jamais de `.ended` à `.continue` | monotonie — évite une partie qui « redémarre » |
| Un `MatchState` encodé puis décodé est identique | `Codable`, transport réseau |

Ces sept lignes attrapent en pratique plus de bugs que cinquante tests d'exemple.

## Tests d'intégration

**Store** — `ModelConfiguration(isStoredInMemoryOnly: true)` : aller-retour domaine ↔
persistance, préservation de l'ordre des manches (le piège SwiftData), suppression en cascade,
comportement d'une fiche joueur supprimée alors qu'elle apparaît dans l'historique.

**Migrations** — un magasin de test figé par version publiée, ouvert par la version courante.
Ajouté dès qu'une V2 du schéma existe ; le test échoue si une migration perd une donnée.

**Sync** — deux `LiveSession` reliées par un `Transport` en mémoire, sans Wi-Fi ni Bluetooth réels.
Convergence, reconnexion, rejet d'une proposition invalide, ordre d'arrivée inversé.

## Tests d'interface

Trois parcours seulement, sur le chemin critique :

1. Créer un joueur avec un avatar, le retrouver dans la liste.
2. Partie de Skyjo à 3 joueurs, jusqu'à la fin, vérifier le vainqueur à l'écran de résultats.
3. Démarrer une partie, tuer l'app, la relancer, vérifier que la partie est proposée en reprise.

Le troisième est le plus important : il couvre le scénario « soirée perdue », identifié comme
rédhibitoire dans la [vision produit](01-vision-produit.md).

## Ce qui n'est pas testé automatiquement

Assumé explicitement, pour ne pas dépenser l'effort au mauvais endroit :

- L'apparence. Pas de tests de capture d'écran : Liquid Glass et Dynamic Type les rendraient
  instables à chaque version d'iOS pour un bénéfice faible. Les previews Xcode, déclinées en
  clair/sombre, en AX5 **et dans les deux rendus iOS 18-25 / iOS 26+** pour tout composant
  concerné par l'amélioration progressive Liquid Glass ([ADR-0015](13-decisions-adr.md)), jouent
  ce rôle en revue.
- Transport Wi-Fi et BLE sur appareils réels, y compris entre iPhone et Android — check-list de
  recette manuelle, Phase 7.
- La sync CloudKit — nécessite deux appareils et un compte réel ; check-list manuelle,
  Phase 5.

## Qualité de code

- **Mode langage Swift 6, concurrence stricte**, sur toutes les cibles. Aucune exception,
  aucun `@unchecked Sendable`, aucun `@preconcurrency import`. Ces trois interdits sont
  vérifiés par une règle de revue, pas par un outil.
- **Avertissements = erreurs** (`SWIFT_TREAT_WARNINGS_AS_ERRORS`) sur le package.
- **swift-format** avec la configuration par défaut d'Apple, appliqué à la validation.
- Aucune dépendance tierce. Toute proposition d'en ajouter une passe par un ADR.

## Intégration continue — Xcode Cloud

Choisi par cohérence avec la contrainte « outils Apple » : intégration native à Xcode et à
App Store Connect, aucune infrastructure à maintenir, signature de code gérée.

| Déclencheur | Actions |
|---|---|
| Chaque push sur une branche | build package + tests unitaires et d'intégration |
| Pull request vers `main` | idem + XCUITest sur simulateur iPhone et iPad |
| Tag `v*` | build d'archive, TestFlight interne |

Objectif : **moins de 5 minutes** sur un push de branche. Les tests unitaires du domaine se
comptant en millisecondes, le temps est presque entièrement celui de la compilation — d'où
l'intérêt d'un `Domain` sans dépendance.

## Définition de « terminé »

Un écran ou une fonctionnalité n'est terminé que si :

- [ ] les tests unitaires du domaine concerné passent, golden files inclus ;
- [ ] la fonctionnalité est traversable **entièrement à VoiceOver**, sans regarder l'écran ;
- [ ] elle est lisible en Dynamic Type AX5 sans troncature ni chevauchement ;
- [ ] elle est correcte en mode clair et en mode sombre ;
- [ ] elle est correcte sur iPhone SE et sur iPad en Split View ;
- [ ] toutes les chaînes sont dans le catalogue, français et anglais ;
- [ ] aucun nouvel avertissement de compilation ;
- [ ] le parcours a été fait une fois sur un appareil réel, pas seulement en simulateur.

Les deux derniers points sont ceux qu'on saute quand on est pressé, et ceux qui coûtent le plus
cher plus tard.

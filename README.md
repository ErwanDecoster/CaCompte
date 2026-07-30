# Ça Compte

Application de suivi de scores pour jeux de société, tour par tour, **100 % hors-ligne** et
**sans serveur**.

Apple d'abord (iPhone + iPad, SwiftUI + SwiftData), Android ensuite (Kotlin + Compose + Room),
avec une **spécification de règles partagée** qui garantit que les deux plateformes calculent
exactement les mêmes scores.

> Sobre et précis pendant la partie, ludique au moment du résultat.

---

## Le plan en une page

| Quoi | Décision |
|---|---|
| **Plateformes v1** | iPhone + iPad, une cible SwiftUI adaptative, iOS 18 minimum |
| **UI** | SwiftUI, pattern MV avec `@Observable`, Liquid Glass en amélioration progressive iOS 26+ (repli Material iOS 18-25), HIG natives |
| **Persistance** | SwiftData, modèle compatible CloudKit dès le départ |
| **Sync** | CloudKit privé (entre les appareils du propriétaire) + transport hybride Wi-Fi/BLE (partie partagée autour de la table, sans Internet, interopérable Apple/Android) |
| **Cœur métier** | Swift pur, `Sendable`, zéro dépendance framework, fonctions pures |
| **Règles de jeu** | Définition déclarative JSON + moteurs impératifs nommés pour les jeux à calcul non trivial |
| **Identité** | Tokens uniques bi-plateformes, contrastes WCAG AA vérifiés par calcul |
| **Typographie** | SF Pro / Roboto système ; police display réservée au logo, vectorisée |
| **Android** | Ré-implémentation 100 % native, pilotée par `spec/` et validée par les mêmes golden files |
| **Tests** | Swift Testing, golden files rejoués sur les deux plateformes, XCUITest sur le parcours critique |
| **Dépendances** | Zéro côté Apple. Une seule côté Android (Vico, graphiques) |
| **CI** | Xcode Cloud |

---

## Documents

| # | Document | Contenu |
|---|---|---|
| 01 | [Vision produit](docs/01-vision-produit.md) | Problème, personas, parcours, périmètre v1, ce qui ferait échouer le produit |
| 02 | [Architecture](docs/02-architecture.md) | Modules, dépendances, concurrence Swift 6, flux de données |
| 03 | [Modèle de données](docs/03-modele-de-donnees.md) | Entités SwiftData, contraintes CloudKit, conflits, migrations |
| 04 | [Moteur de règles](docs/04-moteur-de-regles.md) | Le cœur : types du domaine, `GameRules`, event sourcing, cas Skyjo |
| 05 | [Catalogue de jeux](docs/05-catalogue-jeux.md) | 16 jeux, conditions de fin, formules, priorisation en 3 vagues |
| 06 | [Statistiques](docs/06-statistiques.md) | Indicateurs, score d'intérêt, badges, profils joueur |
| 07 | **[Charte graphique](docs/07-charte-graphique.md)** | **Source unique des tokens** — couleurs, typo, grille, icônes, composants, mouvement, logo, microcopy |
| 08 | [Design system Apple](docs/08-design-system.md) | Implémentation SwiftUI des tokens, Liquid Glass, écran de saisie, accessibilité |
| 09 | [Partie partagée](docs/09-partie-partagee.md) | Transport hybride Wi-Fi/BLE interopérable Apple/Android, hôte autoritaire, protocole, horloge de Lamport |
| 10 | [Tests & qualité](docs/10-tests-et-qualite.md) | Pyramide, golden files, invariants, CI, définition de « terminé » |
| 11 | [Portage Android](docs/11-portage-android.md) | Équivalences, charte côté Material 3, discipline Swift, plan en 7 étapes |
| 12 | [Roadmap](docs/12-roadmap.md) | 10 phases, 3 jalons, estimations, risques |
| 13 | [Décisions (ADR)](docs/13-decisions-adr.md) | 15 décisions, alternatives écartées et pourquoi |

**Règle de cohérence** : le doc 07 définit toute valeur ; les docs 08 et 11 décrivent seulement
comment elle s'implémente sur chaque plateforme. Aucune valeur n'est définie deux fois.

## Spécification partagée

`spec/` est la **source de vérité inter-plateformes**. Ni Swift ni Kotlin n'y sont autorisés :
uniquement du JSON, lu et rejoué par les deux bases de code.

```
spec/
├── README.md                              contrat, versionnage, procédure d'ajout d'un jeu
├── schema/game-definition.schema.json     JSON Schema 2020-12 des définitions
├── games/skyjo.json                       définition déclarative de Skyjo
├── games/yams.json                        définition déclarative du Yams
├── golden/skyjo-01-doublement.json        partie de 5 manches, les 2 cas de doublement
└── golden/skyjo-02-egalite-finale.json    égalité parfaite, chaîne de départage jusqu'au rang partagé
```

Règle d'or : **une modification de règle commence toujours par `spec/`**, jamais par le code.

## État de vérification

Ce qui a été contrôlé par exécution, pas seulement rédigé :

| Contrôle | Résultat |
|---|---|
| Contrastes WCAG de la charte — 68 paires texte/fond, marque, sémantique, joueurs | **0 échec** (après correction de `text/tertiary` et des bordures de contrôles) |
| Golden files rejoués contre `skyjo.v1` (implémentation Swift réelle, `SkyjoRulesV1`) | **2/2 conformes** — scores, cumuls, doublements, statuts, classement, ex æquo partagé |
| Définitions de jeu validées contre le JSON Schema | **2/2 conformes** |
| JSON bien formé sur tout `spec/` | **5/5** |
| Liens croisés entre les 13 documents | **tous résolus** |
| `swift build` / `swift test` sur `CaCompteKit`, avertissements en erreurs | **OK** |
| `xcodebuild` sur simulateur iOS 26 (iPhone 17e) | **build + lancement OK**, écran blanc conforme au critère de fin de Phase 0 |
| `xcodebuild test -scheme CaCompteKit-Package` sur simulateur — Domain/Catalog/Store/DesignSystem | **OK**, dont les 39 paires de contraste WCAG rejouées sur le vrai catalogue d'assets |
| Icône d'app (claire/sombre/teintée) générée depuis `LogoMark` et intégrée à `App/` | **build OK** sur simulateur avec les 3 variantes |
| Wordmark « Ça Compte » (Outfit SemiBold, Google Fonts, licence SIL OFL dans `Licenses/Outfit-OFL.txt`) vectorisé en SVG, lockups horizontal/vertical | **build + rendu vérifiés par capture d'écran** sur simulateur |
| Phase 2 — `PlayerRecord`/`PlayerRepository`, écrans Joueurs (liste, création, édition, avatars, palette, archivage, réordonnancement) | **build OK**, persistance vérifiée par test (10 joueurs, réouverture du magasin) et par capture d'écran (créés → relancés → toujours là) |
| Phase 3 — `MatchEngine` (reduce/replay/Lamport), `GameCatalog`, `generic.sum.v1`, `SkyjoRulesV1` | **build OK sur simulateur**, 2/2 golden files conformes |
| Invariants de propriété (doc 09) — total = Σ entrées, classement = ordre total, monotonie de fin de partie, Codable round-trip, `replay` indépendant de l'ordre et idempotent aux doublons | **7 propriétés, 20 tirages aléatoires chacune (générateur reproductible par seed) — 0 échec** |
| Phase 4 — `MatchRecord`/`ParticipantRecord`/`MatchRepository`, configuration de partie, écran de partie en direct (pavé numérique, validation, annulation, fin de partie) | **build OK sur simulateur** ; partie complète testée (`MatchRepositoryTests` : classement final écrit, survit à la réouverture du magasin) ; rendu réel vérifié par capture d'écran — reprise après relance opérationnelle, doublement Skyjo affiché correctement à l'écran |
| Phase 5 — `StatsEngine` (insights, séries, badges), écran de résultats (podium, faits marquants, badges, courbe Swift Charts, image partageable) | **8 indicateurs vérifiés par golden file** (dont l'écart-type exact `10.14`) — étendu aux deux golden files existants ; rendu réel vérifié par capture d'écran : podium, faits marquants, courbe à axe inversé avec ligne de seuil, bouton de partage (rendu `ImageRenderer` sans crash) |
| Phase 6 — Historique (filtres jeu/joueur, détail manche par manche), fiches de profil (`ProfileRepository`, statistiques agrégées), réglage de consentement iCloud, container CloudKit câblé | **`ProfileRepositoryTests` : 4 tests** (agrégats multi-parties, némésis, sens du jeu sur meilleur/pire score, activité mensuelle zero-fillée) — **19 tests / 8 suites sur `CaCompteKit-Package`, 0 échec** ; rendu réel vérifié par capture d'écran : liste Historique avec filtres, détail d'une partie passée, fiche de profil complète |
| Correctif crash iCloud — inverse de relation manquant + tableaux CloudKit non optionnels (schéma), dossier `Resources` renommé (bug `codesign` de l'environnement) | **`CloudKitSchemaTests`** : échouait avant le correctif, passe maintenant — **build signé** (vrai Team ID, sans contourner la signature) + scénario réel rejoué sur simulateur (iCloud activé, app fermée/rouverte) : **plus de crash** |
| Phase 7 — Catalogue élargi : Rami, 6 qui prend, Jeu libre (`generic.sum.v1`), Yams (`yams.v1`, grille structurée), Belote (`belote.v1`, premier jeu par équipes), fin manuelle (`manualStop`), sélecteur de jeu générique | **22 tests / 8 suites sur `CaCompteKit-Package`, 0 échec** (dont départage Yams, capot Belote, fin manuelle, isolés en tests unitaires) ; build **signé** OK ; rendu réel vérifié par capture d'écran : sélecteur à 6 jeux, mise en place Belote avec équipes, saisie Belote, grille Yams |
| Phase 8 (socle protocolaire) — cible `Sync` : `WireMessage`, protocole `Transport`/`TransportSession` (ADR-0014, transport hybride Wi-Fi/BLE, indépendant de l'implémentation), `LiveSession` (hôte autoritaire — arbitrage, diffusion, appairage/chiffrement AES-GCM dérivé par HKDF) | **10 tests / 3 suites** sur un transport en mémoire (`SyncTests`) : convergence d'une proposition acceptée (même id événement des deux côtés, horloge de l'hôte), rejet transmis au contributeur, observateur bloqué en écriture, chiffrement round-trip et dérivation de clé — **34 tests / 13 suites sur `CaCompteKit-Package`, 0 échec** ; `WifiTransport`/`BLETransport` (implémentations réelles Network.framework/CoreBluetooth) et l'interface d'invitation restent à écrire |
| Plancher abaissé à iOS 18 ([ADR-0015](docs/13-decisions-adr.md)) — `IPHONEOS_DEPLOYMENT_TARGET` (les deux configs Debug/Release du target `CaCompte`) et `Package.swift` (`.iOS(.v18)`) | **build + lancement réels OK** sur simulateur iOS 18.6 (iPhone 16, créé pour l'occasion), écran Joueurs vérifié par capture d'écran — aucune API iOS 26 n'était encore utilisée dans le code (`glassEffect`/`concentric` restaient à l'état de plan dans les docs 07/08, jamais codés), donc aucun `#available` à ajouter dans l'immédiat ; Liquid Glass et les coins concentriques deviennent une amélioration progressive iOS 26+ pour la suite du design system |
| Phase 8 — `WifiTransport` réel (`NetService`/`NetServiceBrowser` + `NWListener`/`NWConnection`), `ShareSessionView`/`JoinMatchView`/`SharedMatchModel`/`SharedMatchView`, `DeviceIdentity`, `MatchRepository.appendRemoteEvent` | **Vérifié sur appareils réels (iPhone + iPad)** par l'auteur du projet : partie partagée créée, rejointe en observateur et en contributeur, tableau des scores synchronisé en direct. Deux bugs trouvés en recette et corrigés (pair fantôme après déconnexion, erreur explicite si code erroné/hôte injoignable) — voir doc 09. `WifiTransport` vérifié isolément par un exécutable macOS autonome (hors bac à sable `.xctest`, qui n'a pas les entitlements réseau local d'une vraie app) — découverte + échange de messages tramés dans les deux sens, succès. **34 tests / 13 suites sur `CaCompteKit-Package`, 0 échec.** |

## Actions manuelles en attente

Ne peuvent pas être faites en CLI — à traiter quand tu as la main :

| Action | Pourquoi | Bloque |
|---|---|---|
| ~~Team ID Apple Developer + capability iCloud/CloudKit~~ **fait** (Team ID `U79ZYL8WF3`, container `iCloud.com.cacompte.app`) | Signing réel sur appareil, container CloudKit | — |
| **Remote git** (GitHub ou autre) | Xcode Cloud a besoin d'un repo distant lié à App Store Connect | Xcode Cloud |
| **Configurer le workflow Xcode Cloud** (Product → Xcode Cloud dans Xcode) | Pas d'API/CLI publique pour ça, uniquement l'UI Xcode/App Store Connect | CI automatique sur push |
| **Premier commit git** | En attente de ta validation avant de committer | — |
| **Valeurs *High Contrast* des tokens couleur** | La charte §14 ne donne que Clair/Sombre ; aucune valeur « contraste augmenté » n'est spécifiée | Rendu en mode contraste augmenté (dégrade proprement sur Any/Dark en attendant) |
| **Symboles de courbe joueurs #6 et #9** | `BasicChartSymbolShape` (Swift Charts) n'a que 8 formes natives, la charte en demande 10 (étoile, hexagone) — substitués par astérisque et carré dans `PlayerPalette.swift` | Distinction visuelle au-delà de 6 joueurs simultanés sur la courbe (Phase 5) |
| ~~**Liste curatée d'emoji**~~ **fait** — 60 emoji dans `Avatar.curatedEmoji` (dérivation déterministe du pseudo), la cible ~60 de la charte (§10) est atteinte ; 6 ajoutés sur retour explicite (🤖 🧙 🥷 👾 🏎️ 🌸), écartés parmi les 36 proposés : redondants avec l'existant (🦝🐲 déjà couverts par 🐻🐼🐨🦄, 👻🎃🍄 saisonniers/moins « sûrs », ⚡ proche de 🔥, 🏄 proche de 🏎️/⚽/🏀, 🌷 proche de 🌸) et les 4 cœurs (♥️💚💙🩷), redondants entre eux | — |
| **Palette joueurs v2 (vive) — daltonisme non revérifié** | Recolorée le 29/07 pour plus d'impact visuel (avatars, courbe) ; le contraste WCAG 3:1 est revérifié par test, mais la distinguabilité en deutéranopie/protanopie des 6 premières teintes ne l'a pas été depuis ce changement (charte §1.5) | À confirmer par simulation dédiée avant un usage graphique dense (courbe à 6+ joueurs) |
| **Tests `CaCompteKit` non câblés dans le schéma `CaCompte`** | Xcode → Edit Scheme → Test → `+` → ajouter Domain/Catalog/Store/DesignSystemTests (30 secondes en UI, non fiabilisable en pbxproj à la main) | Xcode Cloud doit tester via ce schéma ; en attendant, `xcodebuild test -scheme CaCompteKit-Package` valide tout |
| **Proportion icône/wordmark dans les déclinaisons** | Le ratio exact entre la hauteur de l'icône et la casse du wordmark n'est pas chiffré dans la charte (§11.2 donne l'espacement, pas la proportion) — hauteurs égales choisies par défaut | Ajustement visuel possible en revue de design, pas un blocage technique |
| **XCUITest « création joueur »** (doc 10, parcours n°1) | Pas encore écrit — la persistance est validée par `PlayerRepositoryTests` (10 joueurs, réouverture du magasin) et par capture d'écran manuelle sur simulateur, mais pas par un test UI automatisé | Couverture du parcours critique en CI (peut attendre que `CaCompteUITests` soit créé) |
| **Règles de départage génériques incomplètes** | `mostRoundsWon`, `lowerSecondaryScore`, `higherSecondaryScore`, `headToHead` ne sont pas résolues par le classement générique (`GameRules.standings()`) faute de données modélisées — ignorées silencieusement, passage à la règle suivante | Un futur jeu déclarant l'une d'elles dans son `tieBreak` ne serait pas départagé dessus tant qu'elle n'est pas implémentée |
| **Taps du pavé numérique non vérifiés par automatisation** | Le simulateur iOS n'expose pas les vues SwiftUI internes à l'accessibilité macOS (testé directement) — seul un vrai XCUITest peut simuler des taps. Vérifié à la place : rendu réel par capture d'écran (le tableau, le focus, le doublement s'affichent juste) + logique de `LiveMatchModel`/`MatchRepository` couverte par tests | Confiance moindre sur le fil `draftText` → `setScore` (simple concaténation de chaînes), spécifiquement en attente d'un XCUITest |
| **Sélection narrative des insights (score d'intérêt)** | La charte §06 décrit le principe (écart à la normale, unicité, rareté, diversité) sans formule exacte — l'implémentation dans `StatsEngine.select` est une heuristique de première passe, non vérifiée par golden (seuls les *candidats* le sont) | Le choix des 4 à 6 faits affichés peut être retravaillé sans casser les tests |
| **Ordre de rareté des badges** | Doc 06 dit « le plus rare l'emporte » sans lister l'ordre — `photoFinish > comeback > rollercoaster > metronome > unshakeable > kamikaze > winner` est mon choix, pas une valeur de la charte | Ajustable en revue de design |
| **Badge Chirurgien non implémenté** | Propre à Wizard/Mölkky (doc 06), aucun des deux n'existe encore dans le catalogue | Sans effet avant leur arrivée (Phase 7) |
| **Photo d'avatar absente des snapshots de partie** | `ParticipantRecord` (doc 03) ne stocke que `avatarKindSnapshot`/`avatarValueSnapshot` en `String`, pas de photo — un joueur en avatar photo retombe sur un symbole générique dans les résultats/l'historique | Repli visuel, pas une perte de données côté `PlayerRecord` lui-même |
| **Partage d'image non vérifié par interaction réelle** | Le bouton "Partager le résumé" s'affiche et `ImageRenderer` produit une image sans crash (vérifié), mais la feuille de partage elle-même n'a pas été ouverte (même limite d'automatisation que les taps du pavé) | Confiance moindre sur le rendu final de `ResultsShareCard` en dehors du bouton |
| **Recette CloudKit sur deux appareils** (doc 12, critère de fin de Phase 6 : « une partie créée sur iPhone apparaît sur iPad sans rien faire ») | Nécessite un second appareil physique (ou un second compte iCloud de test) — pas simulable en CLI | Confirmation qu'une partie/un joueur créé localement se synchronise réellement, au-delà de la vérification statique de la configuration `ModelConfiguration`/entitlements |
| **Complice (doc 06, statistiques de profil)** | « Coéquipier avec le meilleur taux de victoire » — Belote existe désormais (Phase 7, `Participant.teamID`), mais ce bloc n'a pas été ajouté à `ProfileStats`/`ProfileRepository`, contrairement à Némésis qui ne le nécessite pas | Bloc absent de la fiche de profil ; l'ajouter est maintenant possible mais reste à faire |
| **Contrat Belote simplifié** (validé explicitement, voir rapport de Phase 7) | « Belote classique » sans annonce chiffrée : succès au-delà de 81 points, chute → défense à 162 à plat — la coinche (contrat annoncé, ×2/×4) est, comme documenté, une variante de la v1.2, pas implémentée | Score correct pour la Belote « classique » ; pas encore de coinche/contrée |
| **`six-qui-prend` : fin alternative non implémentée** | Doc 05 mentionne une variante « nombre de manches fixé » en plus du seuil à 66 — seul le seuil est implémenté (changer de *type* de condition de fin, pas seulement sa valeur, n'est pas modélisable par une simple variante) | Le mode « nombre de manches fixé » n'est pas proposé au réglage de partie |
| **Yams : « Yams supplémentaire » (+100) non implémenté** | Règle du joker officiel (une seconde grille « Yams » obtenue après la première) incompatible avec le modèle actuel (une catégorie ne se remplit qu'une fois par joueur) sans remaniement plus large — retiré du JSON plutôt que déclaré sans effet | Bonus rare absent ; sans incidence sur le reste du calcul |

## Prérequis

Vérifiés sur cette machine le 29/07/2026 :

- macOS 26.5.2 · Xcode 26.6 (build 17F113) · Swift 6.3.3

Aucune dépendance tierce n'est prévue côté Apple.

## Étape suivante

**Phase 0 terminée** : `git init`, package `CaCompteKit` (cibles Domain/Catalog/Store/Sync/
DesignSystem + tests), `App/CaCompte.xcodeproj`, script de synchronisation `spec/` ↔
`Catalog/Resources/`, hook `ci_scripts/` pour Xcode Cloud. Vérifié par exécution : voir
« État de vérification » ci-dessus.

**Phase 1 terminée** : tokens (`Space`, `Radius`, `Motion`, tailles, `Color`, `Font`), catalogue
de couleurs (28 tokens Any/Dark), composants (boutons, `ScoreField`, `Card`, `Chip`, `Banner`,
`EmptyState`, `AvatarView`), `PlayerPalette`, logo complet (marque, icône d'app, wordmark
vectorisé, lockups), galerie de previews, contraste WCAG en test unitaire.

**Phase 2 terminée** : `PlayerRecord` + `PlayerRepository` (Store), écrans Joueurs — liste,
création/édition (pseudo, avatar symbole/emoji/photo, palette de couleur), archivage,
réordonnancement. Persistance vérifiée par test et par capture d'écran (voir ci-dessus).

**Phase 3 terminée — ◆ Jalon 1 : le calcul est juste.** Types du domaine (`Participant`,
`MatchState`, `ScoreEntry`…), protocole `GameRules` avec ses défauts génériques (`endCheck`,
classement, départage), `MatchEngine` (`reduce`/`replay`, horloge de Lamport), `GameCatalog`,
`generic.sum.v1`, `SkyjoRulesV1`. Aucune interface, comme prévu par la roadmap. 2/2 golden
files conformes, 7 invariants de propriété vérifiés sur entrées aléatoires (voir ci-dessus).

**Phase 4 terminée — ◆ Jalon 2 : première partie réelle.** `MatchRecord`/`ParticipantRecord`/
`MatchRepository` (Store, `eventLogData` = source de vérité), `MatchSetupView` (choix des
joueurs, variantes), `LiveMatchView` (`NumericKeypad`, tableau des scores, validation,
annulation de la dernière manche), reprise automatique d'une partie en cours au lancement.
Vérifié par test (partie complète, classement final, survit à la réouverture du magasin) et
par capture d'écran réelle sur simulateur.

**Phase 5 terminée.** `StatsEngine` (insights, séries, badges), écran de résultats — podium,
faits marquants sélectionnés par intérêt narratif, badges, courbe d'évolution Swift Charts
(axe inversé, ligne de seuil), image de résumé partageable (`ImageRenderer` + `ShareLink`).
8 indicateurs vérifiés par golden file (voir ci-dessus), rendu vérifié par capture d'écran.

**Phase 6 terminée — ◆ Jalon 3 : utilisable au quotidien.** `MatchRepository.finishedMatches()`,
écran Historique (filtres par jeu et par joueur, `HistoryListModel`), détail d'une partie passée
en lecture seule (`HistoryDetailView` — rejoue le journal d'événements puis réutilise
`ResultsView` telle quelle, y compris son nouveau tableau « manche par manche »). Fiche de
profil (`ProfileRepository`/`ProfileStats`, doc 06 : parties jouées, victoires, taux de victoire,
rang moyen et rang moyen normalisé, détail par jeu avec meilleur/pire score, némésis, séries de
victoires, activité sur 12 mois — calcul à la demande, aucun agrégat persisté). `AppSettings`
(consentement iCloud, `UserDefaults` — délibérément *hors* du schéma CloudKit qu'il conditionne,
voir le commentaire dans `AppSettings.swift`) et écran Réglages ; le container CloudKit privé
(`iCloud.com.cacompte.app`) est câblé dans `ModelConfiguration` (`CaCompteApp.swift`), activé ou
non selon ce consentement — le changement s'applique au prochain lancement plutôt qu'un
remplacement à chaud du `ModelContainer` en cours de session (source de crashs de durée de vie
plus subtils que ce qu'un simple réglage justifie). Racine de l'app passée en `TabView`
(Joueurs/Historique) ; la ligne d'un joueur ouvre désormais sa fiche de profil, l'édition se
fait depuis le bouton « Modifier » de cette fiche. Vérifié par test (`ProfileRepositoryTests`,
4 tests — agrégats multi-parties, sens du jeu, activité mensuelle) et par capture d'écran réelle
sur simulateur (Historique, détail de partie, fiche de profil).

**Correctif post-Phase 6 — crash à l'activation d'iCloud.** Deux bugs distincts dans le schéma
SwiftData, tous deux invisibles en local et révélés uniquement une fois CloudKit actif :

1. `ParticipantRecord.player` n'avait pas de relation inverse déclarée côté `PlayerRecord`
   (violation de la contrainte CloudKit doc03 §3) — corrigé par `PlayerRecord.participations`.
2. CloudKit exige en plus que les relations vers plusieurs soient elles-mêmes de type optionnel
   (`[T]?`), pas seulement dotées d'une valeur par défaut — `MatchRecord.participants` et le
   `participations` ajouté au point 1 violaient tous les deux cette règle. Corrigé par un
   stockage optionnel privé exposé via une propriété calculée non optionnelle (même principe que
   `statusRaw`/`status`), sans changement pour le code appelant.

Régression verrouillée par `CloudKitSchemaTests` (ouvre le vrai schéma avec un container
CloudKit actif) — échouait avant le correctif, passe maintenant.

En vérifiant sur simulateur, build **signé** (Team ID, pas de contournement de signature) : un
deuxième problème, sans rapport avec le code de l'app, bloquait tout build signé — `codesign`
plante sur un dossier de ressources nommé exactement `Resources` copié tel quel dans un bundle
(reproduit hors projet avec un bundle minimal fait à la main : un dossier `Resources`, même vide,
suffit à déclencher *"bundle format unrecognized, invalid, or unsuitable"* sur ce macOS/Xcode).
Corrigé en renommant `CaCompteKit/Sources/Catalog/Resources/` en `.../GameDefinitions/` (voir
`Package.swift`, `GameCatalog+Embedded.swift`, `Scripts/check-spec-sync.sh`) — aucun autre dossier
du projet ne porte ce nom. Scénario complet revérifié sur simulateur avec un build signé :
réglage iCloud activé, app fermée puis rouverte, plus de crash.

**Phase 7 terminée.** Les cinq jeux restants de la vague 1 :

- **Rami**, **6 qui prend** (`six-qui-prend` — l'identifiant doit commencer par une lettre, le
  schéma l'exige), **Jeu libre** : purement déclaratifs (`generic.sum.v1`), aucun code.
- **Jeu libre** a nécessité un vrai ajout d'architecture malgré tout : sa fin est `manualStop`
  (« c'est toi qui décides »), qu'`endCheck` ne peut par nature jamais détecter tout seul.
  Nouvel événement `MatchEvent.matchEndedManually` + `MatchRepository.endMatchManually` (statut
  `.ended` normal, classement écrit, compté dans les statistiques de profil — contrairement à
  `matchAbandoned`) ; bouton « Terminer la partie » dans `LiveMatchView`, avec confirmation.
  Réutilisable tel quel par Scrabble/Qwirkle (vague 1.2).
- **Yams** (`yams.v1`) : sorti de `spec/games/.pending/`. Une « manche » y est le tour d'un seul
  joueur sur une seule catégorie (pas un tour de table homogène) — `ScoreDetail` porte le
  `categoryID` choisi. Bonus de section haute (+35) ajouté à l'entrée qui fait franchir le seuil
  plutôt qu'une entrée synthétique séparée. Départage par section basse (`higherSecondaryScore`,
  non résolu par le classement générique) surchargé intégralement dans `YamsRulesV1.standings`.
  Écran dédié (`YamsSheetView`) : grille 13 catégories × joueurs, saisie contextuelle par
  catégorie (dés/somme/obtenu-raté) dans une feuille.
- **Belote** (`belote.v1`), premier jeu par équipes : `Participant.teamID` ajouté au domaine
  (optionnel, `nil` partout ailleurs) avec sa plomberie de persistance (`ParticipantRecord`,
  `MatchRepository.ParticipantSeed`). Astuce d'implémentation : chaque coéquipier reçoit une
  entrée **identique** par donne (le score de l'équipe) plutôt qu'une entrée par équipe — ainsi
  `endCheck`/`standings` de l'extension par défaut de `GameRules` gèrent déjà correctement le
  seuil et le partage de rang entre coéquipiers, sans rien surcharger (seuls `validate`/`score`
  sont propres à Belote, comme `SkyjoRulesV1`). **Simplification assumée, validée explicitement**
  avec l'auteur du projet : « Belote classique » sans contrat chiffré — le preneur réussit
  au-delà de 81 points, sinon la défense encaisse 162 à plat ; la coinche (annonces + ×2/×4)
  reste, comme documenté, une variante de la v1.2. Écran dédié (`BeloteRoundView`) : équipe
  preneuse, points, capot, belote-rebelote.
- **`MatchSetupView` généricisé** : elle ne connaissait que les variantes de Skyjo (`threshold`,
  `doublePenalty`) codées en dur. Rendu désormais généré dynamiquement depuis
  `definition.variants` (bool/integerChoice/integerRange/option), plus une section d'assignation
  d'équipe quand `definition.players.teams` existe. `GamePickerView` (nouveau) précède la
  sélection des joueurs : choisir un jeu n'est plus figé sur Skyjo.
- `MatchPlayView` (nouveau) aiguille entre `LiveMatchView` (pavé numérique), `YamsSheetView`
  (grille) et `BeloteRoundView` (saisie par équipe) selon `scoring.entry.kind` — un point unique
  à étendre pour un futur jeu `structured`/`rank`.

Vérifié par golden files (2 par jeu à moteur propre — nominal + cas limite — sauf Rami/6 qui
prend/Jeu libre qui n'en ont qu'un, sans calcul spécifique à couvrir), tests unitaires ciblés
pour les branches non atteignables par un golden (départage Yams, capot Belote, fin manuelle),
et rendu réel vérifié par capture d'écran sur simulateur (sélecteur de jeu à 6 entrées, mise en
place Belote avec équipes auto-réparties, saisie Belote, grille Yams). **22 tests / 8 suites sur
`CaCompteKit-Package`, 0 échec**, build **signé** réussi.

**Retouche post-Phase 7 — onglet Jeux.** Démarrer une partie ne se fait plus depuis l'onglet
Joueurs (bouton « Nouvelle partie » retiré) : un troisième onglet **Jeux** (`GamesTabView`)
porte désormais le catalogue avec recherche (`.searchable`), la mise en place d'une partie et la
reprise d'une partie en cours. `PlayerListView` redevient purement la gestion du répertoire de
joueurs. `GameDefinition` est maintenant `Identifiable` (son `id` existait déjà) — nécessaire
pour la présenter en feuille (`.sheet(item:)`) depuis la liste recherchable, plutôt qu'un
`NavigationLink` qui aurait imbriqué la `NavigationStack` propre à `MatchSetupView`. Vérifié par
capture d'écran réelle sur simulateur (recherche, liste des 6 jeux) sur un build signé ; suite de
tests inchangée (22/22).

**Phase 8 — socle protocolaire.** Avant même d'écrire un transport réel, le choix de mécanique a
changé : MultipeerConnectivity (Apple seul) et Nearby Connections (Android seul) ne
s'interopèrent structurellement pas, ce qui aurait interdit un groupe mixte iPhone + Android.
Remplacés par un transport hybride Wi-Fi (mDNS/DNS-SD + socket) puis Bluetooth LE en secours,
construit sur des standards que les deux OS parlent nativement — [doc 09](docs/09-partie-partagee.md),
[ADR-0014](docs/13-decisions-adr.md). Livré dans cette passe, sur `Transport` en mémoire
uniquement (`WifiTransport`/`BLETransport` restent à écrire) :

- `WireMessage` (protocole applicatif versionné, identique quel que soit le transport),
  `Transport`/`TransportSession` (le seam que `WifiTransport` et `BLETransport` implémenteront)
- `LiveSession` (acteur) : hôte autoritaire qui arbitre les propositions des contributeurs
  (`GameRules.validate` + `MatchEngine.reduce`), rediffuse ce qui est accepté, relaie pour les
  pairs non-hôtes — un seul point d'entrée `propose(_:)` quel que soit le rôle local
- Appairage par code à 6 chiffres → clé de session dérivée par HKDF, chiffrement AES-GCM de
  chaque message (`CryptoKit`, aucune dépendance tierce, ADR-0012 préservé)

Vérifié par 10 tests (`SyncTests`, transport en mémoire `InMemoryTransport`/`InMemoryChannel`) :
convergence d'une proposition acceptée (l'événement confirmé porte le même id que la proposition
optimiste, mais l'horloge de l'hôte), rejet transmis au contributeur, observateur bloqué en
écriture, chiffrement round-trip, dérivation de clé déterministe et salée par `matchID`.

**Phase 8 — Wi-Fi bout en bout.** `WifiTransport` écrit et branché : `NetService`/
`NetServiceBrowser` pour la découverte (`NWBrowser` ne remontait pas les enregistrements TXT
dans cet environnement — diagnostiqué avec un harnais macOS autonome, `dns-sd` au niveau
système confirmant que le problème était dans l'API Swift, pas le réseau), `NWListener`/
`NWConnection` tramés par un préfixe de longueur pour le transport. Câblé dans l'app :
`ShareSessionView` (hôte — code d'appairage, liste des pairs connectés) et `JoinMatchView` +
`SharedMatchModel`/`SharedMatchView` (pair — découverte, appairage, tableau en direct,
proposition de manche si contributeur), `DeviceIdentity` (UUID stable en `UserDefaults`) et
extension de `MatchRepository` (`currentLog`/`appendRemoteEvent`) pour que l'hôte persiste ce
qu'un contributeur distant propose. `Info.plist` : `NSLocalNetworkUsageDescription` +
`NSBonjourServices`.

**Recette réelle sur iPhone + iPad**, menée par l'auteur du projet — deux problèmes trouvés et
corrigés dans la foulée :
- un pair qui quittait restait listé comme connecté chez l'hôte : rien ne fermait jamais le
  socket sous-jacent. Corrigé par `LiveSession.leave()`/`stopHosting()`, qui ferment réellement
  la connexion des deux côtés plutôt que d'oublier seulement la référence locale.
- un code d'appairage erroné ou un hôte injoignable ne produisait aucune erreur claire (l'écran
  restait sur « Connexion à la partie… » indéfiniment). Corrigé par un délai explicite de 8 s
  dans `attachToHost` (`SessionError.noResponseFromHost`), distingué de
  `WifiTransportError.hostNotFound` dans le message affiché.
- suggestion de recette également traitée : bouton clavier « Suivant »/« Envoyer » ajouté à
  `SharedMatchView` (l'hôte l'avait déjà, l'écran pair en avait été privé par oubli).

**Deuxième passage de recette**, deux problèmes supplémentaires trouvés et corrigés :
- une manche proposée par un contributeur et rejetée par l'hôte restait affichée comme validée :
  l'application optimiste locale n'était jamais annulée sur `rejection`, seul un message
  d'erreur s'affichait à côté. Donnait l'impression qu'aucune validation n'avait lieu, alors
  qu'elle avait bien lieu côté hôte — seul l'écran du contributeur ne le reflétait pas. Corrigé
  dans `SharedMatchModel` (l'événement rejeté est retiré du journal local par son id, puis on
  rejoue).
- terminer la partie n'arrêtait jamais le partage : l'hôte continuait d'annoncer une partie
  finie sur le réseau, toujours rejoignable depuis un autre appareil. Corrigé : `LiveMatchModel`
  arrête le partage automatiquement dès qu'une écriture locale conclut la partie, juste après
  avoir diffusé l'état final aux pairs connectés.
- retouche d'interface : la feuille de saisie du code d'appairage répétait le nom de l'appareil
  (déjà dans le titre de navigation) et portait le bouton « Rejoindre » comme une simple ligne de
  formulaire ; le nom répété a été retiré et le bouton déplacé en action de confirmation de la
  barre de navigation, cohérent avec `MatchSetupView`.

`WifiTransport` lui-même n'est pas testable depuis `SyncTests` : un bundle `.xctest` n'a pas les
entitlements réseau local d'une vraie app, `NWListener`/`NetService` y échouent silencieusement.
Vérifié à la place par un exécutable macOS autonome (hors bac à sable), qui découvre, connecte
et échange des messages tramés dans les deux sens avec succès. **34 tests / 13 suites sur
`CaCompteKit-Package` toujours au vert.**

**`BLETransport` (secours GATT) — écrit, non vérifié par exécution.** Mêmes rôles que
`WifiTransport` (hôte = périphérique `CBPeripheralManager`, pair = central `CBCentralManager`),
mais découverte en deux temps (une annonce BLE ne peut pas porter `gameID`/`participantCount`
comme un TXT record mDNS — seulement l'UUID de service ; chaque périphérique trouvé est connecté
brièvement pour lire une caractéristique d'info JSON, puis déconnecté si non sélectionné) et
cadrage par morceaux de 180 octets (`BLEFraming`, même principe de préfixe de longueur que
`WifiTransportSession`, adapté à des écritures de caractéristique plutôt qu'un flux continu).
Limite de plateforme actée dans le code et la doc 09 : `CBPeripheralManager` ne peut pas fermer
la connexion d'un central précis, seul le central le peut lui-même.

Contrairement à `WifiTransport`, pas de harnais d'auto-vérification possible : un harnais
macOS calqué sur le même principe (périphérique et central dans un seul process) a bien démarré
des deux côtés (`CBCentralManager.authorization`/`CBPeripheralManager.authorization` retournent
`.allowed`), mais la découverte locale n'a jamais abouti — limite du framework en
self-communication, pas un bug identifié dans le code. Le simulateur iOS n'a de toute façon
aucun support Bluetooth. **Recette prévue sur deux appareils physiques par l'auteur du projet.**
Pas encore branché dans `ShareSessionView`/`JoinMatchView` : l'orchestration Wi-Fi-puis-BLE
reste à écrire une fois validé. `Info.plist` : `NSBluetoothAlwaysUsageDescription` ajoutée par
anticipation. Build vérifié (App + `CaCompteKit-Package`, 34 tests toujours au vert).

**Troisième passage de recette**, trois problèmes trouvés et corrigés :
- **crash au retour au premier plan** après avoir rejoint une partie et mis l'app en arrière-plan
  (sans la tuer). Cause : `stateUpdateHandler` de `NWListener`/`NWConnection` reste branché
  après sa première résolution et retente de résoudre la même `CheckedContinuation` à la
  transition d'état suivante (typiquement `.failed` au retour au premier plan) — une continuation
  déjà résolue ne tolère pas d'être résolue une seconde fois, ce qui crashe à coup sûr. Corrigé
  aux deux endroits concernés (`WifiTransport.advertise`, `WifiTransportSession.waitUntilReady`) :
  le handler se retire lui-même dès la première résolution.
- **la feuille « Rejoindre une partie » se fermait par balayage**, contournant
  `SharedMatchModel.stop()` et laissant la connexion ouverte sans que l'hôte ne le sache jamais —
  même bug de pair fantôme que celui déjà corrigé pour le bouton, par un chemin différent.
  Corrigé par `.interactiveDismissDisabled(true)` : seul le bouton « Quitter » peut fermer cet
  écran.
- **Wi-Fi coupé, recherche silencieuse** : rejoindre ou partager avec le Wi-Fi désactivé
  affichait indéfiniment « recherche… » sans jamais dire pourquoi. Ajout de `WiFiAvailability`
  (`NWPathMonitor(requiredInterfaceType: .wifi)`, ignore la cellulaire) : un message explicite
  invite à activer le Wi-Fi, des deux côtés (rejoindre et partager).

Build vérifié, 34 tests toujours au vert.

**Notification de l'activité distante + appairage par QR**, sur retour utilisateur :
- l'hôte ne voyait jamais qu'une manche venait d'un contributeur distant — les totaux changeaient
  sans explication. `WireMessage.Kind.hello` porte désormais `deviceID` (le même qui horodate les
  `StampedEvent`), ce qui permet à `LiveMatchModel` de nommer l'appareil et d'afficher un bandeau
  (`Banner`, DesignSystem) accompagné d'un retour haptique (`.sensoryFeedback(.success, …)`) ; les
  totaux eux-mêmes s'animent (`.contentTransition(.numericText())`) plutôt que de sauter d'un coup.
- appairage par QR en plus de la saisie manuelle : `QRCodeView` (génère le code via
  `CIFilter.qrCodeGenerator()`, système) côté hôte ; côté pair, un scanner intégré
  (`QRScannerView`, `AVCaptureMetadataOutput`) ou l'appareil photo système via le schéma d'URL
  personnalisé `cacompte://join?matchID=…&code=…` (`JoinLink`, `DeepLinkRouter` + `.onOpenURL`
  dans `CaCompteApp`). Schéma personnalisé plutôt qu'un lien universel `https://` : ce dernier
  demanderait un nom de domaine possédé et une vérification hébergée (Associated Domains/App
  Links), hors de portée pour l'instant — arbitrage discuté avec l'auteur du projet avant
  d'implémenter. `Info.plist` : `NSCameraUsageDescription`, `CFBundleURLTypes` (`cacompte`).

Build vérifié, 34 tests toujours au vert.

Étape suivante : recette `BLETransport` sur deux appareils physiques (l'auteur du projet s'en
charge), puis l'orchestration Wi-Fi-puis-BLE dans l'app, le portage Android et le golden du
protocole (`spec/wire/`).

Reste en attente (voir « Actions manuelles en attente ») : câblage des tests `CaCompteKit` dans
le schéma Xcode, XCUITest « création joueur » et « partie complète », recette CloudKit sur deux
appareils (nécessite un second appareil physique ou un second compte iCloud de test).

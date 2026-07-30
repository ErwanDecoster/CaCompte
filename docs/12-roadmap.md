# 12 — Roadmap

Estimations pour **une personne à temps plein**. Elles supposent la maîtrise de SwiftUI ;
ajouter 30 à 40 % en phase d'apprentissage.

## Vue d'ensemble

```
  Apple v1                                                    ~17 semaines
  ├─ P0  Fondations ...................... 1 sem   ██
  ├─ P1  Identité & design system ........ 1 sem   ██
  ├─ P2  Joueurs ......................... 1 sem   ██
  ├─ P3  Moteur + Skyjo .................. 1,5 sem ███          ◆ jalon 1
  ├─ P4  Partie en direct ................ 2 sem   ████         ◆ jalon 2
  ├─ P5  Résultats & statistiques ........ 1,5 sem ███
  ├─ P6  Historique & iCloud ............. 1,5 sem ███          ◆ jalon 3
  ├─ P7  Catalogue élargi ................ 2 sem   ████
  ├─ P8  Partie partagée ................. 3 sem   ██████
  └─ P9  Finitions & TestFlight .......... 2,5 sem █████        ◆ v1.0

  Android v1 ............................ ~12,5 sem █████████████████████████
```

Le **chemin critique** est P3 → P4 → P5 : le moteur, la saisie, les résultats. Tout le reste
peut glisser sans bloquer une mise en main. P7 et P8 sont ré-ordonnançables selon l'envie.

---

## P0 — Fondations · 1 semaine

- `git init`, structure de dossiers, `.gitignore` Swift
- Package `CaCompteKit` : cibles `Domain`, `Catalog`, `Store`, `Sync`, `DesignSystem`
- Projet Xcode, cible iOS 18 minimum (Liquid Glass en amélioration progressive iOS 26+, voir
  [ADR-0015](13-decisions-adr.md)), iPhone + iPad, identifiant de bundle et container CloudKit
- Mode langage Swift 6 + concurrence stricte + avertissements en erreurs, **dès la première
  ligne** — l'activer plus tard coûte des jours de reprise
- Script de build qui vérifie l'égalité entre `spec/games/` et `Catalog/Resources/`
- Xcode Cloud : workflow de test sur push

**Fini quand** : le package compile à vide, un test bidon passe en CI, l'app se lance sur un
écran blanc.

## P1 — Identité & design system · 1 semaine

- Logo : marque, déclinaisons horizontale / verticale / icône, icône d'app (claire, sombre,
  teintée)
- Catalogue d'assets : tous les tokens couleur de la [charte §14](07-charte-graphique.md), avec
  variantes *Dark* et *High Contrast*
- Cible `DesignSystem` : `Space`, `Radius`, `Motion`, extensions `Font` et `Color`
- Composants : `PrimaryButton`, `SecondaryButton`, `ScoreField`, `Card`, `Chip`, `Banner`,
  `AvatarView`, `EmptyState` — **tous les états** de la charte §5
- **Le script de vérification de contraste devient un test unitaire** et tourne en CI

**Fini quand** : une galerie de previews montre chaque composant dans tous ses états, en clair,
en sombre, en contraste augmenté et en AX5.

> Placer cette phase avant tout écran réel est délibéré : reprendre 15 écrans pour aligner des
> couleurs coûte bien plus qu'une semaine passée en amont.

## P2 — Joueurs · 1 semaine

- Modèle `PlayerRecord`, `ModelContainer`, repository
- Liste, création, édition, archivage, réordonnancement
- Trois sources d'avatar (symbole, emoji, photo) + génération déterministe
- Attribution automatique de couleur

**Fini quand** : on crée dix joueurs, on relance l'app, ils sont là.

## P3 — Moteur + Skyjo · 1,5 semaine ◆ **Jalon 1 : le calcul est juste**

- Types du domaine complets ([04](04-moteur-de-regles.md))
- `MatchEngine` : `reduce`, `replay`, journal d'événements, horloge de Lamport
- `GameCatalog`, chargement et validation des JSON
- `generic.sum.v1` et `skyjo.v1`
- `spec/games/skyjo.json` + 2 golden files
- Tests d'invariants et de propriété

**Fini quand** : les golden files passent et les invariants tiennent sur des entrées générées.
**Aucune interface à ce stade** — c'est le seul jalon purement métier, et le plus important.

## P4 — Partie en direct · 2 semaines ◆ **Jalon 2 : première partie réelle**

- Configuration : choix du jeu, des joueurs, des variantes
- `LiveMatchModel`, écran de partie, tableau des scores
- **Pavé numérique** et son enchaînement de saisie (charte §5.4, doc [08](08-design-system.md))
- Validation, correction, annulation d'une manche
- Bandeau « dernière manche », détection de fin
- Persistance à chaque manche validée + reprise après relance

**Fini quand** : une vraie partie de Skyjo est jouée de bout en bout sur un appareil réel, et
survit à un arrêt forcé de l'app.

Mesurer ici l'objectif produit : **5 scores saisis en moins de 15 secondes**. S'il n'est pas
atteint, corriger avant d'avancer — c'est la métrique numéro un de la
[vision produit](01-vision-produit.md).

## P5 — Résultats & statistiques · 1,5 semaine

- `StatsEngine` : indicateurs universels, score d'intérêt, sélection
- Écran de résultats : podium, faits marquants, badges
- Courbe d'évolution (Swift Charts), axe inversé selon le sens du jeu
- Image de résumé partageable (`ImageRenderer` + `ShareLink`)

**Fini quand** : l'écran de résultats donne envie d'être regardé jusqu'en bas.

## P6 — Historique & iCloud · 1,5 semaine ◆ **Jalon 3 : utilisable au quotidien**

- Historique, filtres par jeu et par joueur, détail manche par manche
- Fiches de profil et statistiques agrégées
- CloudKit : activation, réglage de consentement, recette sur deux appareils
- `VersionedSchema` et plan de migration

**Fini quand** : une partie créée sur iPhone apparaît sur iPad sans rien faire.

À ce stade, l'app est **utilisable en vrai**. C'est le bon moment pour la faire tester par le
groupe de joueurs cible, avant d'élargir le catalogue.

## P7 — Catalogue élargi · 2 semaines

Les cinq jeux restants de la vague 1 : Yams, Belote, Rami, 6 qui prend, Jeu libre — plus la
saisie structurée (grille Yams) et la notion d'équipe (Belote), qui touchent le domaine.

Pour chacun : JSON, golden files, moteur si nécessaire, écran de saisie adapté, traductions.

**Fini quand** : les six jeux de la v1 passent leurs golden files et se jouent réellement.

## P8 — Partie partagée · 3 semaines

- ✅ Protocole `Transport` + `WifiTransport` (`NetService`/`NetServiceBrowser` pour la
  découverte, `NWListener`/`NWConnection` pour le socket tramé), protocole `WireMessage`, rôles
  hôte / contributeur / observateur
- ✅ Appairage par code (dérivation HKDF, chiffrement AES-GCM des deux côtés), avec délai
  explicite (`SessionError.noResponseFromHost`) si l'hôte ne répond jamais — code erroné ou hôte
  injoignable, distingué de `WifiTransportError.hostNotFound`
- ✅ Interface d'invitation (`ShareSessionView`, hôte) et de découverte/appariement
  (`JoinMatchView`, pair), branchées dans `LiveMatchView`/`GamesTabView`
- ✅ Départ propre des deux côtés (`LiveSession.leave()`/`stopHosting()` ferment réellement la
  connexion, pas seulement la référence locale — un bug de pair fantôme trouvé et corrigé en
  recette sur appareils réels)
- ✅ Recette manuelle iPhone + iPad concluante (hôte, observateur, contributeur)
- ✅ Deux bugs supplémentaires trouvés en recette et corrigés : rejet d'une manche non répercuté
  visuellement (`SharedMatchModel` gardait l'événement optimiste), partage jamais arrêté à la fin
  de partie (l'hôte restait annoncé et rejoignable une fois la partie terminée)
- 🔶 `BLETransport` (secours GATT) — **écrit, pas encore vérifié ni branché dans l'app**. Ne se
  prête pas à l'auto-test comme le Wi-Fi (essayé : la self-communication BLE sur une seule
  machine n'aboutit jamais, autorisation système pourtant accordée des deux côtés) ; la
  vérification se fera sur deux appareils physiques. L'orchestration Wi-Fi-puis-BLE dans
  `ShareSessionView`/`JoinMatchView` reste à écrire une fois validé.
- ⏳ Portage Android, recette Apple + Android mélangés, golden du protocole (`spec/wire/`)

**Fini quand** : un iPhone, un iPad et un Android suivent la même partie — sur Wi-Fi puis sur
Bluetooth seul — et l'un d'eux se met en veille et revient sans perdre l'état. **Wi-Fi
iPhone ↔ iPad atteint ; BLE écrit mais pas vérifié ni branché ; Android reste à faire.** Voir
[09 — Partie partagée](09-partie-partagee.md) et [ADR-0014](13-decisions-adr.md).

## P9 — Finitions & TestFlight · 2,5 semaines

- Widget, App Intents / Siri, Live Activity, Handoff
- Passe d'accessibilité complète : VoiceOver, AX5, Reduce Motion, contraste augmenté
- Localisation anglaise complète et relecture
- Fiche App Store, captures, confidentialité (« aucune donnée collectée »)
- TestFlight interne, puis externe, correction des retours

**Fini quand** : la check-list « définition de terminé » de [10](10-tests-et-qualite.md) passe
sur tous les écrans.

## Android · ~11 semaines

Détail en [11 — Portage Android](11-portage-android.md). À démarrer **après** la v1.0 Apple :
`spec/` doit être stabilisé, sinon le portage suit une cible mouvante.

---

## Après la v1

Par valeur décroissante, sans engagement de calendrier :

| | Sujet |
|---|---|
| 1 | **Vagues 1.1 et 1.2 du catalogue** — 10 jeux de plus ([05](05-catalogue-jeux.md)) |
| 2 | **Mode week-end** — classement cumulé sur plusieurs parties, demandé explicitement par le persona « groupe du week-end » |
| 3 | **Saisie assistée** — grille Skyjo 3×4, dés du Yams, calcul du Tarot pas à pas |
| 4 | **Statistiques de groupe** — face-à-face, évolution sur l'année, records collectifs |
| 5 | **Apple Watch** — saisie au poignet, WatchConnectivity |
| 6 | **Export/import `.cacompte`** — anticipé pour Android, utile aussi entre utilisateurs Apple |
| 7 | **macOS** — la cible SwiftUI existe déjà, coût faible, valeur faible |

## Risques

| Risque | Impact | Parade |
|---|---|---|
| **La saisie reste trop lente** | Produit inutilisable | Mesuré dès P4, avant d'écrire d'autres écrans. Si l'objectif n'est pas atteint, on retravaille le pavé plutôt que d'avancer. |
| **Règles de jeu mal comprises** | Scores faux, perte de confiance | Golden files écrits **avant** l'implémentation, validés contre les règles officielles ; invariants (somme nulle au Tarot) |
| **Contraintes CloudKit découvertes tard** | Migration douloureuse | Traitées comme invariants de schéma dès P2, pas comme un ajustement en P6 |
| **Dérive du catalogue** | P7 déborde | Le « jeu libre » est livré en P7 : même si un jeu manque, l'app reste utilisable |
| **`spec/` diverge du code** | Le portage Android casse | Vérification d'égalité au build dès P0 ; `spec/` est la seule source |
| **Sur-ingénierie du moteur** | Retard sur P3 | Deux couches seulement (déclaratif + impératif). Toute troisième abstraction passe par un ADR. |
| **Rôle périphérique BLE inégal sur Android** | Le secours Bluetooth du partage cross-plateforme ne marche pas sur certains appareils | Validé tôt à l'étape F du portage (doc 11), avant d'y engager les 3 semaines complètes ; le Wi-Fi reste le chemin principal, le BLE n'est qu'un secours |

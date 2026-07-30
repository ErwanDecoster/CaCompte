# 03 — Modèle de données

Deux modèles coexistent, délibérément :

| | Domaine (`Domain`) | Persistance (`Store`) |
|---|---|---|
| Nature | `struct` immuables, `Sendable` | `final class @Model` SwiftData |
| Rôle | calcul, règles, transport réseau | stockage disque + sync iCloud |
| Durée de vie | le temps d'un calcul | des années |
| Testé par | golden files | tests de mapping et de migration |

Le mapping entre les deux est explicite (`MatchRecord.toDomain()` / `init(from:)`). C'est une
centaine de lignes de code ennuyeux, et c'est le prix à payer pour que les règles de jeu ne
dépendent jamais du schéma disque — donc pour qu'une migration SwiftData ne casse jamais un
calcul de score, et pour que le portage Android n'ait pas à reproduire SwiftData.

---

## Modèle de persistance (SwiftData)

### PlayerRecord

La fiche joueur, réutilisée d'une partie à l'autre.

| Champ | Type | Notes |
|---|---|---|
| `id` | `UUID` | stable, généré à la création, jamais réattribué |
| `nickname` | `String` | pseudo affiché, 1–24 caractères |
| `avatarKind` | `String` | `"symbol"` \| `"emoji"` \| `"photo"` |
| `avatarValue` | `String` | nom SF Symbol, ou emoji, ou `""` si photo |
| `avatarPhoto` | `Data?` | `@Attribute(.externalStorage)`, JPEG 512 px max |
| `paletteID` | `String` | identifiant de palette, voir [charte §1.5](07-charte-graphique.md#15-palette-des-joueurs) |
| `createdAt` | `Date` | |
| `isArchived` | `Bool` | masqué des sélections, conservé dans l'historique |
| `sortIndex` | `Int` | ordre manuel dans la liste des joueurs |

Pas de contrainte d'unicité sur `nickname` : deux Alice sont autorisées, la couleur et
l'avatar les distinguent. Le formulaire prévient d'un doublon sans l'interdire.

### MatchRecord

Une partie, du premier tap à l'archivage.

| Champ | Type | Notes |
|---|---|---|
| `id` | `UUID` | |
| `gameID` | `String` | ex. `"skyjo"`, référence le catalogue |
| `rulesVersion` | `Int` | version des règles au moment de la partie — **ne jamais recalculer une vieille partie avec des règles récentes** |
| `variantsJSON` | `Data` | options choisies, encodées `Codable` |
| `startedAt` / `endedAt` | `Date` / `Date?` | |
| `status` | `String` | `"inProgress"` \| `"finalRound"` \| `"ended"` \| `"abandoned"` |
| `endReasonRaw` | `String?` | condition de fin déclenchée |
| `deviceOrigin` | `String` | identifiant d'appareil créateur, utile en sync |
| `eventLogData` | `Data` | journal d'événements compressé — **la source de vérité** |
| `participants` | `[ParticipantRecord]` | cascade |
| `rounds` | `[RoundRecord]` | cascade — projection matérialisée du journal |

`eventLogData` contient la vérité ; `rounds` en est une projection dénormalisée, présente pour
que l'historique s'affiche sans rejouer le journal. En cas de divergence détectée à
l'ouverture, le journal gagne et la projection est reconstruite.

### ParticipantRecord

Un joueur **dans une partie donnée**.

| Champ | Type | Notes |
|---|---|---|
| `id` | `UUID` | |
| `player` | `PlayerRecord?` | relation, `nil` pour un invité ponctuel |
| `nicknameSnapshot` | `String` | figé à la création de la partie |
| `avatarKindSnapshot` / `avatarValueSnapshot` / `paletteIDSnapshot` | `String` | figés |
| `seatIndex` | `Int` | ordre de jeu |
| `finalRank` | `Int?` | rempli à la fin, rangs ex æquo partagés |
| `finalScore` | `Int?` | |

Le *snapshot* est essentiel : si Marion renomme « Théo » en « Théo-le-tricheur » en 2027, la
partie de 2026 doit continuer d'afficher « Théo ». Et si la fiche est supprimée, l'historique
reste lisible — d'où `player` optionnel avec règle de suppression `.nullify`.

### RoundRecord / ScoreEntryRecord

| `RoundRecord` | Type |
|---|---|
| `id` | `UUID` |
| `index` | `Int` — 0-based, source de l'ordre |
| `committedAt` | `Date` |
| `note` | `String?` — annotation libre |
| `entries` | `[ScoreEntryRecord]` cascade |

| `ScoreEntryRecord` | Type |
|---|---|
| `id` | `UUID` |
| `participantID` | `UUID` — non pas une relation, un identifiant nu |
| `rawValue` | `Int` — ce que l'utilisateur a saisi |
| `computedValue` | `Int` — après application des règles (doublement Skyjo, bonus…) |
| `detailJSON` | `Data?` — payload structuré (catégories de Yams, contrat de Tarot…) |
| `modifiersJSON` | `Data?` — drapeaux (`closedRound`, `capot`…) |

Conserver **`rawValue` et `computedValue` séparément** est ce qui permet d'afficher « 12 → 24
(doublé) » dans l'historique et de corriger une saisie sans perdre l'intention initiale.

### AppSettings

Un unique enregistrement : langue de saisie préférée, retour haptique, palette par défaut,
consentement à la sync iCloud, dernier jeu utilisé.

---

## Contraintes CloudKit — à respecter dès la première ligne

SwiftData + CloudKit impose des règles au schéma. Les violer se découvre au *runtime*, en
production, avec un container qui refuse silencieusement de synchroniser. Elles sont donc
traitées ici comme des invariants de conception, pas comme un ajustement ultérieur.

1. **Aucun `@Attribute(.unique)`.** CloudKit ne connaît pas les contraintes d'unicité.
   L'unicité de `id` est garantie par la génération d'`UUID`, pas par le schéma.
2. **Toute propriété a une valeur par défaut, ou est optionnelle.** Sans exception, y compris
   les `Bool` et les `Int`.
3. **Toute relation est optionnelle** et possède une **relation inverse déclarée**. Une
   relation sans inverse ne synchronise pas.
4. **Pas de règle de suppression `.deny`.** Seules `.cascade` et `.nullify` sont supportées.
5. **Pas d'ordre implicite dans les collections.** SwiftData ne préserve pas l'ordre d'un
   `[RoundRecord]`. D'où les champs `index` / `seatIndex` explicites, et un tri systématique à
   la lecture. C'est la source de bug la plus fréquente sur ce type d'app.
6. **Les `enum` sont stockés en `String`** (`status`, `avatarKind`), jamais en `Int` brut :
   une valeur inconnue arrivant d'une version plus récente doit dégrader proprement, pas
   planter.

Configuration :

```swift
let schema = Schema([PlayerRecord.self, MatchRecord.self,
                     ParticipantRecord.self, RoundRecord.self,
                     ScoreEntryRecord.self, AppSettings.self])

let config = ModelConfiguration(
    schema: schema,
    isStoredInMemoryOnly: false,
    cloudKitDatabase: settings.iCloudEnabled
        ? .private("iCloud.fr.cacompte.app")   // ⚠ à remplacer par l'identifiant réel
        : .none
)
```

La sync est **désactivable** : un utilisateur qui refuse iCloud garde une app pleinement
fonctionnelle. Le basculement recrée le `ModelContainer` ; ce n'est pas une migration.

## Résolution de conflits

Deux appareils peuvent modifier la même partie hors ligne. CloudKit applique un
« dernier écrivain gagne » par enregistrement, ce qui produirait des scores incohérents si on
s'y fiait pour les manches.

C'est précisément pourquoi la vérité est le **journal d'événements** :

- fusionner deux parties = concaténer deux journaux, dédoublonner par `eventID`, trier par
  `(lamportClock, deviceID)`, rejouer ;
- l'opération est associative, commutative et idempotente — donc sûre quel que soit l'ordre
  d'arrivée ;
- `eventLogData` est un `Data` opaque pour CloudKit, mais la fusion est faite par
  l'application à l'ouverture de la partie, pas par CloudKit.

Détail du protocole dans [09 — Partie partagée](09-partie-partagee.md).

## Migrations

`VersionedSchema` + `SchemaMigrationPlan` dès la v1, même avec une seule version. Créer le
plan de migration après coup coûte bien plus cher que de le poser vide au départ.

```swift
enum CaCompteSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [ … ] }
}

enum CaCompteMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [CaCompteSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
```

Règle : **une migration légère par version publiée au maximum**. Si un changement exige une
migration lourde, ajouter un champ optionnel et le remplir paresseusement plutôt que réécrire
le magasin.

`rulesVersion` sur `MatchRecord` joue le même rôle côté métier : les parties anciennes sont
rejouées avec le moteur de leur époque, conservé dans le catalogue (`SkyjoRulesV1`,
`SkyjoRulesV2`…). Un score enregistré ne change jamais rétroactivement.

## Volumétrie

Un usage intensif — 200 parties par an, 6 joueurs, 20 manches — représente environ
24 000 `ScoreEntryRecord`, soit quelques mégaoctets. Aucune contrainte de performance :
pas d'index à ajouter, pas de pagination nécessaire avant plusieurs années. Les seules photos
d'avatar justifient `.externalStorage`.

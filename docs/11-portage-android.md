# 11 — Portage Android

## Stratégie

**Ré-implémentation 100 % native, pilotée par une spécification partagée.**

Aucune couche de partage de code : pas de Kotlin Multiplatform, pas de Swift compilé pour
Android, pas de moteur JavaScript. Les deux applications sont pleinement idiomatiques sur leur
plateforme. Ce qu'elles partagent n'est pas du code, c'est **`spec/`** — du JSON, lu et rejoué
par les deux.

```
                    spec/                   source de vérité
        ┌──────────────┴──────────────┐
        │  games/*.json               │     définitions déclaratives
        │  golden/*.json              │     parties + résultats attendus
        │  schema/*.schema.json       │     contrat de format
        └──────────────┬──────────────┘
          ┌────────────┴────────────┐
          ▼                         ▼
   ┌─────────────┐          ┌──────────────┐
   │  Swift 6    │          │  Kotlin      │
   │  SwiftUI    │          │  Compose     │
   │  SwiftData  │          │  Room        │
   └─────────────┘          └──────────────┘
     rejoue golden/           rejoue golden/
```

**Le coût** : le moteur de règles s'écrit deux fois, soit environ 2 000 lignes dupliquées.
**Le bénéfice** : zéro compromis d'idiome, zéro outillage croisé (pas de Gradle dans le build
iOS), et deux apps qui ressemblent chacune à leur plateforme. Sur une application dont
l'interface représente 80 % du code et dont le moteur est de l'arithmétique pure et stable,
c'est le bon arbitrage. Décision et alternatives : [ADR-0004](13-decisions-adr.md).

**Le garde-fou** : les golden files. Une divergence de calcul entre les deux plateformes est
impossible à ignorer — elle fait échouer la suite de tests Android.

---

## Équivalences techniques

| Apple | Android | Note |
|---|---|---|
| Swift 6 (concurrence stricte) | Kotlin 2.x + coroutines | `Sendable` → immuabilité + `data class` |
| SwiftUI | Jetpack Compose | Modèle déclaratif équivalent |
| `@Observable` | `StateFlow` dans un `ViewModel` | Compose n'a pas d'équivalent d'observation implicite |
| `@MainActor` | `Dispatchers.Main` | |
| `struct` / valeur | `data class` (immuable) | Le domaine reste sans mutation |
| SwiftData | Room + KSP | Voir « Persistance » |
| CloudKit privé | *(aucun équivalent)* | Voir « Synchronisation » |
| `NWListener` / `NWBrowser` (Wi-Fi) | `NsdManager` + `Socket`/`ServerSocket` | Transport **partagé et interopérable**, voir [09](09-partie-partagee.md) |
| `CBPeripheralManager` / `CBCentralManager` (BLE, secours) | `BluetoothGattServer` / `BluetoothGatt` | Idem — même `WireMessage`, même protocole |
| Swift Testing | JUnit 5 + Kotest | Tests paramétrés des deux côtés |
| Swift Charts | Vico | Bibliothèque tierce assumée — Compose n'a pas de graphiques natifs |
| SF Symbols | Material Symbols Rounded | Voir charte §4 |
| `ImageRenderer` | `GraphicsLayer.toImageBitmap()` | Image de résultats partagée |
| WidgetKit | Glance | |
| App Intents | App Actions + `ShortcutService` | |
| Live Activity | Notification persistante + `MediaStyle` | Équivalent partiel |
| Xcode Cloud | GitHub Actions | |
| `Localizable.xcstrings` | `strings.xml` + `plurals` | |

**Une seule dépendance tierce sur Android** (Vico, pour les graphiques), contre zéro côté
Apple. C'est l'écart d'écosystème le plus concret du projet, et il est accepté explicitement :
réécrire un moteur de rendu de courbes coûterait bien plus que d'assumer cette dépendance.

## Persistance

Room remplace SwiftData, avec deux différences à anticiper :

- **Pas de synchronisation intégrée.** SwiftData+CloudKit fait gratuitement ce que Room ne fait
  pas du tout.
- **Les relations sont explicites.** Room impose `@Relation` et des requêtes ; SwiftData les
  résout seul. En pratique cela avantage Android : l'ordre des collections y est déterministe
  par `ORDER BY`, alors que SwiftData impose les champs `index` explicites décrits en
  [03](03-modele-de-donnees.md).

Les entités sont transposées une pour une (`PlayerRecord` → `PlayerEntity`, etc.), avec le même
mapping vers le domaine. Le domaine Kotlin est identique au domaine Swift, au vocabulaire près.

## Synchronisation

La partie partagée en direct **n'est plus un point de divergence** ([ADR-0014](13-decisions-adr.md)) : Apple et Android parlent le même protocole (`WireMessage`) sur les mêmes standards de
transport (mDNS/DNS-SD + socket TCP, puis BLE en secours). Un iPhone et un Android rejoignent
la même partie. Le seul vrai point de divergence fonctionnel reste la synchronisation entre les
appareils **du même propriétaire**, hors partie en direct :

| Fonction | Apple | Android |
|---|---|---|
| **Partie partagée en direct** | Wi-Fi (mDNS+socket) puis BLE — protocole commun | idem, interopérable avec Apple |
| **Sync entre appareils du propriétaire** | CloudKit privé, transparent | **Absent en v1** |
| **Sauvegarde** | iCloud | Android Auto Backup (quota 25 Mo, suffisant) |
| **Export / import** | fichier `.cacompte` | fichier `.cacompte` |

Il n'existe pas d'équivalent Android à CloudKit : pas de stockage privé, gratuit, lié au compte
système et synchronisé sans serveur. Les options seraient Google Drive App Data (API lourde,
nécessite OAuth) ou un backend maison (contredit « sans serveur »).

**Décision** : la v1 Android n'a pas de synchronisation multi-appareils. Elle propose à la
place un **export/import de fichier**, qui existe aussi côté Apple et sert de pont entre les
deux écosystèmes. Le format `.cacompte` est simplement le journal d'événements sérialisé — donc
déjà spécifié, déjà testé, et fusionnable par la même fonction de rejeu.

## Charte graphique sur Android

La [charte](07-charte-graphique.md) est écrite pour être bi-plateforme : chaque token y porte
déjà sa colonne Android. Les points d'attention au portage :

| Sujet | Règle |
|---|---|
| **Couleurs** | Valeurs hexadécimales **identiques**, injectées dans un `ColorScheme` Material 3 custom. On n'utilise **pas** `dynamicColor` (Material You) : il écraserait la palette de marque et casserait les contrastes vérifiés. |
| **Typographie** | Échelle **Material 3**, pas les tailles iOS. La hiérarchie est partagée, la mesure ne l'est pas — voir charte §2.2. `letterSpacing` doit être posé explicitement, contrairement à iOS. |
| **Espacements et rayons** | Valeurs identiques, en `dp`. 1 pt iOS ≈ 1 dp Android. |
| **Élévation** | Rendu Material (tonal + ombre), pas de verre. C'est l'inverse exact d'iOS et c'est voulu — [ADR-0010](13-decisions-adr.md). |
| **Icônes** | Material Symbols Rounded, `weight 400`, `grade 0`, `optical size 24`, `fill 0/1`. |
| **Zone tactile** | **48 dp** (Android), pas 44 pt. Le pavé numérique reste à 56 dp. |
| **Navigation** | `NavigationBar` Material en bas, pas la tab bar flottante iOS. Bouton retour système géré par `BackHandler`. |
| **Toasts** | `Snackbar` Material en bas, pas de bandeau en haut. |
| **Mouvement** | Mêmes durées, courbes Material (`emphasizedDecelerate` / `emphasizedAccelerate`). |

Le **logo** est identique : même SVG, mêmes déclinaisons, mêmes zones de protection. L'icône
d'application, elle, doit être fournie en **icône adaptative** (couche de fond + couche de
premier plan, zone sûre de 66 dp sur 108) — le masque Android est plus agressif que celui
d'iOS et rogne les angles de la marque si elle est fournie à plat.

## Règles de discipline côté Swift

Pour que le portage reste mécanique, le code Swift respecte quelques contraintes dès
maintenant. Elles ne coûtent rien à l'écriture et évitent une réécriture plus tard.

1. **Le domaine n'utilise que des types transposables** : `Int`, `String`, `Bool`, `UUID`,
   `Date`, tableaux, dictionnaires, `enum`, `struct`. Pas de `Measurement`, pas de
   `NSAttributedString`, pas de `KeyPath` dans une signature publique.
2. **Aucune date implicite.** Le domaine ne fait jamais `Date()` : l'instant est toujours passé
   en paramètre. Cela rend les tests déterministes et supprime la question des fuseaux au
   portage.
3. **Pas d'arithmétique de dates dans le domaine.** Les calculs de calendrier restent dans la
   couche présentation.
4. **Les noms sont partagés.** `MatchState`, `RoundDraft`, `EndCheck`, `Standing` s'appellent
   pareil en Kotlin. Une relecture croisée doit être possible sans table de correspondance.
5. **Le JSON est la seule frontière.** Le domaine encode et décode exactement les structures
   de `spec/schema/`. Aucun format de sérialisation propriétaire, aucun `NSKeyedArchiver`.
6. **Pas de `Foundation` au-delà du strict nécessaire** dans `Domain` : `UUID`, `Date`, `Data`
   et `Codable`. Rien d'autre.

## Plan de portage

| Étape | Contenu | Estimation |
|---|---|---|
| **A** | Projet Compose, thème Material 3 issu de la charte, composants de base | 1,5 sem |
| **B** | Domaine Kotlin — types, `MatchEngine`, `GameRules` génériques | 1,5 sem |
| **C** | **Golden files verts** — tous les jeux du catalogue | 1 sem |
| **D** | Room, repositories, mapping | 1 sem |
| **E** | Écrans : joueurs, configuration, partie, résultats, historique | 3 sem |
| **F** | Transport partagé — `NsdManager`+`Socket`, `BluetoothGatt*`, appairage/chiffrement, export/import | 3 sem |
| **G** | Accessibilité (TalkBack, échelle de police), localisation, recette | 1 sem |
| | **Total** | **~12,5 semaines** |

L'étape C est le jalon de vérité : à partir du moment où les golden files passent en Kotlin,
les deux applications calculent **prouvablement** la même chose, et le reste du portage ne
touche plus au métier.

L'étape F est plus coûteuse que le reste ne le laisserait supposer pour un simple portage
d'écrans : contrairement à Nearby Connections (une seule API haut niveau), le transport partagé
demande de construire deux mécanismes (Wi-Fi et BLE), leur appairage et leur chiffrement, sur le
modèle exact du doc [09](09-partie-partagee.md) — c'est le prix de l'interopérabilité réelle
avec Apple plutôt que deux silots qui ne se parlent pas. Le support du rôle périphérique
GATT (`BluetoothGattServer`) est à valider tôt sur le parc d'appareils cible : son comportement
varie selon les fabricants, davantage que côté Apple.

## Ce qui n'est pas partagé, et c'est voulu

- Les composants d'interface. Un bouton SwiftUI et un `Button` Compose n'ont aucune raison de
  se ressembler dans le code, seulement à l'écran.
- La navigation. `NavigationStack` et Navigation Compose ont des modèles différents ; les
  aligner produirait une abstraction inutile des deux côtés.
- Les gestes et les micro-interactions. Chaque plateforme a ses conventions, et l'utilisateur
  attend celles de son téléphone.
- Le rythme des versions. Rien n'oblige les deux apps à sortir la même fonctionnalité le même
  jour, tant que `spec/` reste commun et versionné.

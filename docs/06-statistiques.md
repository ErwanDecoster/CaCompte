# 06 — Statistiques

L'écran de résultats est la récompense de la soirée. Il ne doit pas être un tableau : il doit
**raconter la partie**.

## Principe

Le `StatsEngine` est un ensemble de fonctions pures sur `MatchState`. Rien n'est stocké,
tout est recalculé — une partie de 40 manches à 8 joueurs se traite en microsecondes, et cela
supprime toute classe de bugs de cache invalide.

```swift
public struct StatsEngine: Sendable {
    public func insights(for state: MatchState,
                         definition: GameDefinition) -> [Insight]
    public func series(for state: MatchState) -> [ParticipantSeries]
    public func badges(for state: MatchState,
                       definition: GameDefinition) -> [Badge]
}

public struct Insight: Sendable, Identifiable {
    public let id: InsightID
    public let headline: String          // « Plus gros tour »
    public let detail: String            // « Chloé — 40 points, manche 5 »
    public let participantID: Participant.ID?
    public let symbol: String            // SF Symbol
    public let prominence: Prominence    // .hero, .standard, .minor
}
```

`prominence` permet à l'UI de composer sans logique métier : un `.hero` occupe une grande
carte, les `.standard` une grille de deux colonnes, les `.minor` une liste repliée.

## Sélection : montrer 5 faits, pas 20

Le moteur calcule une vingtaine d'indicateurs, puis n'en retient que **quatre à six** selon
leur *intérêt narratif*. Un indicateur est intéressant s'il est saillant — pas s'il existe.

Score d'intérêt appliqué à chaque candidat :

- **Écart à la normale** — un « plus gros tour » à 40 quand la moyenne est de 18 vaut mieux
  qu'un à 22 quand la moyenne est de 20. Mesuré en écarts-types.
- **Unicité** — un fait qui désigne un seul joueur bat un fait partagé par trois.
- **Rareté** — une remontée de 4 places est plus rare qu'un écart-type faible.
- **Diversité des sujets** — on évite que les six faits parlent tous du vainqueur. Pénalité
  progressive à chaque réapparition d'un même joueur.

Les faits sous un seuil d'intérêt sont écartés. Sur une partie plate et sans relief, l'écran
affiche trois faits, pas six remplis de vide.

## Catalogue d'indicateurs

### Universels

| Indicateur | Définition | Note |
|---|---|---|
| **Podium** | classement final avec écarts | toujours affiché, hors sélection |
| **Plus gros tour** | max de `computedValue` | dans les jeux « le plus bas gagne », c'est le fait le plus drôle |
| **Meilleur tour** | min ou max selon le sens du jeu | |
| **Le plus régulier** | plus faible écart-type des scores de manche | « Le Métronome » |
| **Le plus irrégulier** | plus fort écart-type | « Les montagnes russes » |
| **Écart final** | différence 1ᵉʳ / dernier | signalé s'il est très serré ou très large |
| **Manche décisive** | manche après laquelle le vainqueur prend et garde la tête | |
| **Changements de leader** | nombre de fois où la première place change | 0 → « domination » ; ≥ 4 → « partie disputée » |
| **Plus longue série en tête** | en nombre de manches consécutives | |
| **Remontada** | plus grand gain de places entre le pire rang atteint et le rang final | ≥ 2 places pour être retenu |
| **Effondrement** | symétrique | formulé avec humour, jamais avec mépris |
| **Manche la plus serrée / la plus violente** | amplitude min / max sur une manche | |
| **Moyenne par manche** | par joueur | affiché dans le tableau détaillé |

### Propres à certains jeux

Déclarés par `statsProfiles` dans le JSON du jeu, ce qui évite tout `switch` sur `gameID` dans
le moteur.

| Profil | Indicateurs |
|---|---|
| `skyjo` | manches fermées par joueur · doublements subis · meilleure manche négative · « a fermé et gagné » |
| `yams` | bonus de 63 obtenu · nombre de Yams · cases barrées · meilleure section basse |
| `tarot` | contrats pris / réussis · taux de réussite par contrat · plus gros chelem |
| `wizard` | annonces exactes · joueur le plus optimiste (sur-annonce moyenne) |
| `belote` | capots · dedans infligés · belote-rebelote |
| `molkky` | dépassements de 50 · échecs consécutifs |

## Courbe d'évolution

Swift Charts, une ligne par joueur, cumul en ordonnée, manches en abscisse.

```swift
Chart(series) { s in
    ForEach(s.points) { p in
        LineMark(x: .value("Manche", p.round), y: .value("Total", p.total))
            .foregroundStyle(by: .value("Joueur", s.name))
            .interpolationMethod(.monotone)
    }
    PointMark(...)   // marqueur sur le dernier point uniquement
}
.chartYScale(domain: .automatic(includesZero: false))
```

Détails qui comptent :

- L'axe des ordonnées est **inversé** dans les jeux où le plus bas gagne, pour que « en haut »
  signifie toujours « en train de gagner ».
- Une ligne de seuil (`RuleMark`) matérialise la condition de fin.
- Les couleurs sont celles des joueurs, donc distinguables par les daltoniens (voir
  [charte §1.5](07-charte-graphique.md#15-palette-des-joueurs)) ; un symbole distinct par série double le codage.
- Au-delà de 6 joueurs, la légende passe sous le graphique et les lignes non sélectionnées
  s'atténuent au tap.

## Badges

Décernés en fin de partie, un par joueur au maximum, purement décoratifs. Ils donnent une
raison de regarder l'écran de résultats en entier.

| Badge | Condition |
|---|---|
| 🏆 **Vainqueur** | rang 1 |
| ⏱️ **Le Métronome** | plus faible écart-type, et < 60 % de la moyenne des écarts-types |
| 🎢 **Les montagnes russes** | plus fort écart-type, et > 160 % de la moyenne |
| 🚀 **La remontada** | gain ≥ 3 places depuis le pire rang atteint |
| 💥 **Le kamikaze** | détient le plus gros tour dans un jeu où le plus bas gagne |
| 🎯 **Chirurgien** | Wizard : ≥ 75 % d'annonces exactes ; Mölkky : aucun dépassement |
| 🧊 **Imperturbable** | leader pendant ≥ 80 % des manches |
| 🍀 **Photo finish** | vainqueur avec moins de 3 points d'écart |

Règles d'attribution : un joueur ne reçoit qu'un badge (le plus rare l'emporte) ; un badge dont
la condition n'est remplie par personne n'est pas affiché ; aucun badge n'est décerné avant
la manche 3 — les statistiques sur deux manches n'ont aucun sens.

## Statistiques de profil

Sur la fiche d'un joueur, agrégées sur tout l'historique.

| Bloc | Contenu |
|---|---|
| **En bref** | parties jouées · victoires · taux de victoire · rang moyen |
| **Par jeu** | mêmes chiffres, ventilés ; meilleur et pire score personnel, avec la date |
| **Némésis** | adversaire rencontré au moins 5 fois contre qui le taux de victoire est le plus faible |
| **Complice** | coéquipier avec le meilleur taux de victoire (jeux en équipe) |
| **Séries** | série de victoires en cours et record |
| **Activité** | parties par mois, sur 12 mois |

Le taux de victoire brut est trompeur à nombre de joueurs variable : gagner à 2 n'est pas
gagner à 8. La fiche affiche donc aussi le **rang moyen normalisé**
`(nbJoueurs − rang) / (nbJoueurs − 1)`, dans `[0, 1]`, comparable entre parties.

Pas de classement Elo en v1 : sur des groupes de 4 à 8 personnes qui jouent quelques dizaines
de parties par an, il produirait un chiffre instable et illisible. Réévaluable si le volume
de données le justifie un jour.

## Performance

Les statistiques de profil parcourent tout l'historique. À 200 parties par an, un calcul naïf
reste sous les 50 ms — mais il s'exécuterait à chaque affichage de la fiche.

Stratégie retenue : calcul à la demande dans une `.task`, avec un cache mémoire invalidé à
chaque fin de partie. Aucune pré-agrégation persistée avant d'avoir mesuré un vrai problème :
un agrégat stocké est un agrégat qui finira désynchronisé.

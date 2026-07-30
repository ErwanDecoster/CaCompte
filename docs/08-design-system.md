# 08 — Design system Apple

> **Ce document ne définit aucune valeur.** Couleurs, tailles, espacements, rayons, durées sont
> tous fixés dans la [charte graphique](07-charte-graphique.md), source unique des tokens.
> Ce qui suit décrit **comment ces tokens s'implémentent en SwiftUI**, plancher **iOS 18**, avec
> Liquid Glass et les coins concentriques en amélioration progressive sur iOS 26+
> ([ADR-0001](13-decisions-adr.md), [ADR-0015](13-decisions-adr.md)) — le pendant Android est en
> [11](11-portage-android.md).

## Posture

L'application **suit** les conventions du système, elle ne les réinvente pas. Pas de barre de
navigation maison, pas de composant recodé, aucune police embarquée (la display du logo est
vectorisée). Une app de score se juge à sa vitesse de saisie, pas à son originalité graphique —
et le système fournit gratuitement Dynamic Type, VoiceOver, le mode sombre, les transitions et,
sur iOS 26+, Liquid Glass.

Corollaire assumé : **aucune dépendance UI tierce**, jamais.

## Liquid Glass (amélioration progressive iOS 26+)

iOS 26 généralise le matériau translucide, mais le plancher de l'app est iOS 18
([ADR-0015](13-decisions-adr.md)) : aucune vue ne peut supposer Liquid Glass disponible. La règle
est un repli systématique sur le Material system classique,
déjà celui utilisé partout dans le code actuel :

```swift
@ViewBuilder
func floatingSurface<Content: View>(cornerRadius: CGFloat, @ViewBuilder content: () -> Content) -> some View {
    if #available(iOS 26, *) {
        content().glassEffect(in: .rect(cornerRadius: cornerRadius))
    } else {
        content().background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
    }
}
```

- Les conteneurs flottants — barre d'action de saisie, bandeau « dernière manche », feuille de
  résultats — utilisent ce repli : `.glassEffect()` sur iOS 26+, `.regularMaterial` en dessous.
  Le contenu défilant, lui, reste opaque dans les deux cas : du texte chiffré sur un fond
  translucide devient illisible dès qu'une couleur passe dessous.
- Sur iOS 26+, les effets voisins sont regroupés dans un `GlassEffectContainer` pour qu'ils
  fusionnent au lieu de se superposer ; ce regroupement n'a pas d'équivalent à répliquer sur
  iOS 18-25, où les surfaces `regularMaterial` se superposent simplement (comportement déjà
  correct par défaut).
- `.buttonStyle(.glass)`/`.glassProminent` sur iOS 26+ ; `PrimaryButtonStyle`/`SecondaryButtonStyle`
  (déjà codés en Material) en dessous. Une seule action proéminente par écran, quel que soit le
  rendu.
- Le tableau des scores n'est **jamais** en verre, sur aucune version : c'est la donnée, elle
  doit être nette.
- Chaque composant qui se branche ainsi porte les deux rendus dans sa galerie de previews Xcode
  (doc [10](10-tests-et-qualite.md)) — la revue visuelle ne peut pas se contenter du rendu le
  plus récent.

## Traduction des tokens en Swift

Aucune valeur littérale dans les vues. La cible `DesignSystem` transpose mécaniquement le
tableau de synthèse de la [charte §14](07-charte-graphique.md#14-tableau-de-synthèse-des-tokens),
sans en réinterpréter aucune.

```swift
public enum Space {
    public static let xxs: CGFloat = 2,  xs: CGFloat = 4,  sm: CGFloat = 8
    public static let md:  CGFloat = 12, lg: CGFloat = 16, xl: CGFloat = 24
    public static let xxl: CGFloat = 32, xxxl: CGFloat = 48, xxxxl: CGFloat = 64
}

public enum Radius {
    public static let xs: CGFloat = 6,  sm: CGFloat = 10, md: CGFloat = 14
    public static let lg: CGFloat = 20, xl: CGFloat = 28
}

public enum Motion {
    public static let fast = Duration.milliseconds(120)
    public static let micro = Duration.milliseconds(180)
    public static let standard = Duration.milliseconds(280)
    public static let screen = Duration.milliseconds(350)
    public static let celebrate = Duration.milliseconds(650)
}
```

**Couleurs** — jamais littérales en Swift : chaque token de la charte devient une entrée du
catalogue d'assets, avec ses variantes *Any/Dark* et *High Contrast*, exposée par une extension
générée. Cela donne gratuitement la bascule de thème et le contraste augmenté, que du code
Swift devrait sinon gérer à la main.

```swift
extension ShapeStyle where Self == Color {
    static var inkBrand: Color { Color("brand/ink", bundle: .designSystem) }
    static var textTertiary: Color { Color("text/tertiary", bundle: .designSystem) }
    // …une entrée par token de la charte §14
}
```

**Typographie** — chaque token typographique référence le style système correspondant, jamais
une taille en points, afin que Dynamic Type opère sans intervention :

```swift
extension Font {
    static let h1 = Font.largeTitle.weight(.bold)          // type/h1
    static let h5 = Font.headline                          // type/h5
    static let body = Font.body                            // type/body
    static let scoreXL = Font.system(.largeTitle, design: .rounded,
                                     weight: .semibold).monospacedDigit()
    static let scoreL  = Font.system(.title2, design: .rounded,
                                     weight: .semibold).monospacedDigit()
    static let scoreM  = Font.system(.body, design: .rounded,
                                     weight: .medium).monospacedDigit()
}
```

Le tracking n'est jamais posé à la main sur iOS : SF Pro applique le sien. Les valeurs listées
dans la charte §2.2 n'existent que pour qu'Android les reproduise.

**Rayons concentriques** — la charte impose `rayon_parent − padding` pour l'imbrication. Sur
iOS 26+, cela se délègue au système ; en dessous, le calcul manuel reste nécessaire :

```swift
if #available(iOS 26, *) {
    view.clipShape(.rect(corners: .concentric(minimum: .fixed(Radius.sm))))
} else {
    view.clipShape(.rect(cornerRadius: max(parentRadius - padding, Radius.sm)))
}
```

**Élévation** — les cinq niveaux sémantiques de la charte §5.2 se rendent par matériau, jamais
par ombre, avec un repli Material en dessous d'iOS 26 :

| Token | iOS 26+ | iOS 18-25 |
|---|---|---|
| `elev/0` | `.background(.bgNeutral)` | `.background(.bgNeutral)` |
| `elev/1` | `.background(.surfaceNeutral)` — sans ombre | `.background(.surfaceNeutral)` — sans ombre |
| `elev/2` | `.glassEffect(in: .rect(cornerRadius: Radius.lg))` | `.background(.regularMaterial, in: .rect(cornerRadius: Radius.lg))` |
| `elev/3` | `.background(.regularMaterial)` | `.background(.regularMaterial)` |
| `elev/4` | `.presentationBackground(.regularMaterial)` sur la feuille | `.presentationBackground(.regularMaterial)` sur la feuille |

Seul `elev/2` diverge réellement : `elev/0`, `elev/1`, `elev/3` et `elev/4` utilisaient déjà le
Material system avant même la question du plancher iOS 18, et n'ont donc besoin d'aucune
branche `#available`.

Le seul `shadow/floating` de la charte s'applique à la barre d'action du mode table iPad, et
nulle part ailleurs.

## Couleurs des joueurs

Les dix teintes sont définies en [charte §1.5](07-charte-graphique.md#15-palette-des-joueurs).
Côté implémentation, deux garde-fous :

1. **Test de contraste** — le script de vérification de la charte est rejoué en test unitaire
   sur le catalogue d'assets réel, pas sur une copie des valeurs. Une teinte modifiée dans
   Xcode sans revalidation fait échouer la suite.
2. **Redondance obligatoire** — un composant qui affiche une couleur de joueur reçoit toujours
   aussi son symbole de série. `PlayerPalette` expose les deux ensemble, ce qui rend l'oubli
   difficile :

```swift
public struct PlayerPalette: Sendable, Hashable {
    public let index: Int          // 1…10
    public let color: Color
    public let chartSymbol: BasicChartSymbolShape
    public let accessibilityName: LocalizedStringResource   // « Azur »
}
```

L'attribution est automatique à la création (première couleur libre), modifiable manuellement.

## Avatars

Deux sources, toutes hors ligne.

1. **Emoji + couleur, dérivés du pseudo par défaut, modifiables à la main** — un emoji choisi
   dans une sélection curatée d'environ 60 (animaux, objets, expressions) et une teinte parmi
   les dix couleurs joueur (charte §1.5), toutes deux dérivées du hachage stable du pseudo par
   défaut : même pseudo → même emoji et même couleur, sur tout appareil, tant que rien n'a été
   changé à la main. L'éditeur de joueur propose la grille d'emoji et les dix couleurs en
   sélection directe ; un choix manuel désactive la régénération automatique au changement de
   pseudo, jusqu'à un bouton « Réinitialiser l'avatar généré » qui revient à la dérivation par
   hachage. Aucune saisie manuelle de symbole n'est proposée : un ancien avatar « symbole »
   (`Avatar.Kind.symbol`) reste géré en lecture pour compatibilité, mais n'est plus une source
   de création.
2. **Photo** — `PhotosPicker`, recadrée en carré, redimensionnée à 512 px, JPEG qualité 0,8,
   stockée en `@Attribute(.externalStorage)`. Aucune permission d'accès à la photothèque
   n'est requise : `PhotosPicker` fonctionne hors bac à sable.

```swift
public struct Avatar: Sendable, Hashable {
    public enum Kind: Sendable, Hashable { case symbol(String), emoji(String), photo(Data) }
    public let kind: Kind
    public let palette: PlayerPalette

    /// Toujours un `.emoji`, jamais un `.symbol` — `.symbol` ne subsiste que pour la lecture
    /// d'anciennes données.
    public static func generated(for nickname: String) -> Avatar { … }
}
```

Un unique composant `AvatarView(avatar:size:)` rend les trois cas, avec des tailles nommées
(`.small` 28 pt en liste, `.medium` 44 pt en tableau, `.large` 96 pt en fiche). Le disque de
fond porte la couleur du joueur pour `.symbol` **et** `.emoji` — seul `.photo` s'en passe
(la photo occupe tout le disque).

## L'écran critique : la saisie d'une manche

C'est l'écran qui décide du succès du produit. Objectif mesuré : **moins de 15 secondes pour
5 joueurs**, soit environ 2,5 secondes par joueur.

```
┌──────────────────────────────────┐
│  Skyjo · Manche 4      [Annuler] │
├──────────────────────────────────┤
│  🦊 Alice    44          [  12 ]▌│ ← champ actif, mis en avant
│  🐻 Bob      13          [    ]  │
│  🦉 Chloé    24          [    ]  │
│  🐢 David    31          [    ]  │
├──────────────────────────────────┤
│  A fermé la manche :  🦊 Alice ⌄ │ ← modificateur propre au jeu
├──────────────────────────────────┤
│  ⌨︎ clavier système (.numberPad) │
│  [−/+]                Suivant   │ ← barre d'accessoires du clavier
└──────────────────────────────────┘
```

Décisions de conception :

- **Clavier système** (`.numberPad`), pas un pavé maison — voir
  [ADR-0013](13-decisions-adr.md#adr-0013--retour-au-clavier-système-plutôt-que-le-pavé-propriétaire).
  L'enchaînement « joueur suivant » et la bascule de signe (scores négatifs) vivent dans la
  barre d'accessoires du clavier (`.toolbar(placement: .keyboard)`), pas dans des touches
  recodées à la main.
- **Avancement automatique** : « Suivant » valide le champ et passe au joueur suivant. Sur le
  dernier joueur, la touche devient « Valider ». Un tap direct sur un autre champ déplace aussi
  le focus, sans attendre ce bouton.
- **Cumul toujours visible** à gauche de chaque champ : on saisit en contexte, sans changer
  d'écran pour vérifier où on en est.
- **Cibles de 44 pt minimum** partout ailleurs dans l'écran (le clavier système gère ses
  propres cibles tactiles).
- **Haptique** : `.success` à la validation d'une manche, `.impact(weight: .heavy)` à la fin de
  partie. Discret mais confirme sans qu'on quitte la conversation des yeux.
- **Rien n'est écrit tant que la manche n'est pas validée**, et une manche validée reste
  corrigeable par un appui long sur sa ligne dans l'historique.

## Adaptation iPhone / iPad

Une seule cible, deux compositions, pilotées par `horizontalSizeClass`.

- **iPhone (compact)** — `NavigationStack`, tableau en liste verticale, pavé en bas.
- **iPad (regular)** — `NavigationSplitView`. En partie, un « mode table » : tableau en grand,
  colonnes par joueur, pavé sur le côté. L'iPad reste posé au centre et lisible à 60 cm par
  tout le monde, ce qui suppose des scores en `.largeTitle` et pas en `.body`.
- Aucun `UIDevice.current.userInterfaceIdiom` : uniquement des classes de taille, pour rester
  correct en Split View et en Stage Manager.

## Accessibilité

Traitée comme une exigence de départ, pas comme une passe de finition.

- **Dynamic Type jusqu'à AX5.** Les lignes du tableau passent en `ViewThatFits` : au-delà d'une
  certaine taille, l'avatar disparaît et la ligne se réorganise verticalement.
- **VoiceOver** : chaque ligne du tableau est un seul élément accessible, énoncé
  « Alice, deuxième, 44 points, +12 cette manche ». Le clavier système porte déjà ses propres
  libellés VoiceOver.
- **Reduce Motion** : l'animation du podium devient un fondu ; la courbe s'affiche sans tracé
  progressif.
- **Contraste augmenté** : les couleurs de joueur basculent sur leurs variantes renforcées.
- **Contrôle vocal** : chaque champ porte un `accessibilityLabel` correspondant au pseudo, pour
  que « Appuyer sur Alice » fonctionne.

Barrière de qualité : la traversée complète du parcours principal à VoiceOver, sans regarder
l'écran, fait partie de la définition de « terminé » de chaque écran ([10](10-tests-et-qualite.md)).

## Localisation

- `Localizable.xcstrings` (catalogue de chaînes), français et anglais dès la v1.
- Aucune concaténation de chaînes. Les phrases variables passent par
  `AttributedString(localized:)` et les règles de pluriel du catalogue.
- `.formatted()` pour tous les nombres et toutes les dates — jamais de `String(format:)`.
- Le pseudo-langage `--AppleTextDirection` et le double-longueur sont testés en preview pour
  détecter les troncatures.

## Finitions Apple

Prévues en Phase 8, une fois le cœur stable :

- **Widget** (WidgetKit) — dernière partie et vainqueur, sur l'écran d'accueil.
- **App Intents** — « Démarrer une partie de Skyjo » depuis Siri, Raccourcis et Spotlight.
- **Live Activity** — score en cours sur l'écran verrouillé et dans l'île dynamique, très
  pertinent pour une partie longue.
- **Handoff** — reprendre une partie de l'iPhone sur l'iPad.
- **Partage** — `ShareLink` d'une image de résumé générée par `ImageRenderer`.
- **Contrôle** (Control Center, iOS 18+) — « Nouvelle partie » en un geste.

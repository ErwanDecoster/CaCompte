# 07 — Charte graphique

**Source unique des tokens.** Toute couleur, taille, espacement, rayon, durée utilisé dans
l'application est défini ici et nulle part ailleurs. Le doc [08](08-design-system.md) décrit
*comment* ces tokens sont implémentés côté Apple ; le doc [11](11-portage-android.md) fait de
même côté Android. Aucun des deux ne redéfinit une valeur.

---

## 0. Positionnement

**Ça Compte** — application de suivi de scores pour jeux de société, destinée aux groupes
d'amis et aux familles qui jouent régulièrement.

> **Sobre et précis pendant la partie, ludique au moment du résultat.**

C'est la règle qui tranche tous les arbitrages de cette charte. L'écran de partie est un
**instrument** : dense, net, sans décoration, il doit disparaître pour qu'on regarde ses amis
et pas son téléphone. L'écran de résultats est une **récompense** : couleur, mouvement,
avatars, badges.

| | Écran de partie | Écran de résultats |
|---|---|---|
| Couleur | neutres + couleurs joueurs uniquement | accent Laiton, couleurs joueurs saturées |
| Mouvement | 120–180 ms, fonctionnel | jusqu'à 650 ms, ressort |
| Typographie | chiffres tabulaires, hiérarchie plate | grande titraille, échelle contrastée |
| Densité | maximale | aérée |
| Illustration | aucune | podium, badges, courbe |

Trois attributs de marque, dans l'ordre de priorité — en cas de conflit, le premier gagne :

1. **Fiable** — on ne conteste pas un chiffre affiché par Ça Compte.
2. **Rapide** — rien ne se met entre l'utilisateur et la saisie.
3. **Complice** — l'app connaît le groupe, ses joueurs, ses habitudes, et sait s'en amuser.

---

## 1. Couleurs

### 1.1 Méthode

Toutes les valeurs ci-dessous ont été **vérifiées par calcul** (formule WCAG 2.1 sur
luminance relative sRGB), pas estimées à l'œil. 68 paires contrôlées, 0 échec. Le script de
vérification fait partie de la suite de tests ([10](10-tests-et-qualite.md)) : ajouter une
couleur sans la faire passer casse la compilation.

Seuils appliqués :
- **4,5:1** — tout texte de moins de 24 pt (ou 19 pt gras)
- **3:1** — texte large, bordures de contrôles, icônes porteuses de sens, lignes de graphique
- **exempté** — contrôles désactivés uniquement (WCAG 1.4.3, exception « inactive »)

### 1.2 Couleurs de marque

| Token | Rôle | Clair | Sombre | Justification |
|---|---|---|---|---|
| `brand/ink` | **Primaire.** Tint système, actions principales, liens, état sélectionné | `#1F4899` | `#8FB2FF` | Un bleu d'encre, pas un bleu logiciel : il évoque le stylo sur la feuille de score. Assez sombre en clair pour passer 8,59:1 sur blanc, donc utilisable en texte, ce qu'un bleu iOS standard ne permet pas. |
| `brand/inkPressed` | État pressé du primaire | `#173A80` | `#A9C3FF` | Une seule valeur, −12 % de luminance en clair, +12 % en sombre (en sombre, l'appui *éclaircit*). |
| `brand/brass` | **Accent.** Podium, badges, vainqueur, éléments de célébration | `#9A5B00` | `#F0A73F` | Le laiton d'une médaille. Réservé au moment de récompense — c'est ce qui rend la célébration lisible comme une rupture. |
| `brand/teal` | **Secondaire.** Données, graphiques, éléments informatifs neutres | `#0A6A72` | `#4CC7D1` | Complémentaire froid de l'ambre, se distingue du primaire dans une courbe sans entrer en concurrence avec lui. |

> **Règle d'usage stricte** : `brass` n'apparaît **jamais** sur l'écran de partie. Si l'accent
> est présent partout, il n'accentue plus rien.

### 1.3 Neutres

Gris légèrement bleutés (teinte 220°, saturation 12–18 %) plutôt que gris purs : posés à côté
de `ink`, des gris neutres paraissent jaunes.

**Mode clair**

| Token | Hex | Usage |
|---|---|---|
| `neutral/bg` | `#F6F7F9` | Fond d'écran |
| `neutral/surface` | `#FFFFFF` | Cartes, lignes de liste, feuilles |
| `neutral/sunken` | `#ECEEF2` | Zones en creux, fond du pavé numérique |
| `neutral/fill` | `#E3E6EC` | Remplissages, chips, fonds désactivés |
| `neutral/border` | `#D4D9E2` | Séparateurs, bordures décoratives |
| `neutral/borderStrong` | `#7E879A` | **Bordures de contrôles interactifs** (champs, boutons secondaires) — 3,61:1 |
| `text/primary` | `#161B24` | Titres, scores, contenu principal — 17,26:1 |
| `text/secondary` | `#4A5260` | Sous-titres, métadonnées — 7,87:1 |
| `text/tertiary` | `#5A6373` | Légendes, placeholders — 6,06:1 sur `surface`, **4,84:1 sur `fill`** |
| `text/disabled` | `#9AA3B2` | Contrôles inactifs uniquement — exempté |

**Mode sombre**

| Token | Hex | Usage |
|---|---|---|
| `neutral/bg` | `#0B0E14` | Fond d'écran |
| `neutral/surface` | `#131822` | Cartes, lignes de liste |
| `neutral/sunken` | `#090C11` | Zones en creux |
| `neutral/fill` | `#1D2432` | Remplissages, chips |
| `neutral/border` | `#2B3342` | Séparateurs |
| `neutral/borderStrong` | `#69738A` | Bordures de contrôles — 3,74:1 |
| `text/primary` | `#EDF0F5` | 15,56:1 |
| `text/secondary` | `#BAC2D0` | 9,92:1 |
| `text/tertiary` | `#98A2B4` | 6,91:1 |
| `text/disabled` | `#5A6478` | Exempté |

`text/tertiary` a été assombri de `#666F7E` à `#5A6373` en mode clair précisément parce qu'il
échouait (4,06:1) lorsqu'il était posé sur `fill` — le cas du placeholder dans un champ
rempli. C'est le genre de détail invisible en maquette et bloquant en audit.

### 1.4 Couleurs sémantiques

| Token | Clair | Ratio | Sombre | Ratio | Usage |
|---|---|---|---|---|---|
| `semantic/success` | `#0F6B43` | 6,55:1 | `#41CE92` | 8,86:1 | Manche validée, partie sauvegardée, pair connecté |
| `semantic/error` | `#BC2418` | 6,17:1 | `#FF8A7A` | 7,76:1 | Saisie invalide, échec de synchronisation |
| `semantic/warning` | `#8A5300` | 6,33:1 | `#FFC161` | 11,05:1 | Score inhabituel, **dernière manche**, pair déconnecté |
| `semantic/info` | `#1B5FA6` | 6,49:1 | `#79B6F7` | 8,33:1 | Aide contextuelle, rappel de règle |

Ratios mesurés sur `neutral/surface`. Chaque couleur sémantique dispose d'un fond associé à
**8 % d'opacité** en clair et **16 %** en sombre — l'écart compense la perception d'un voile
translucide sur fond noir.

> `warning` et `brass` sont deux ocres distincts et volontairement non interchangeables :
> l'un signale, l'autre célèbre. Le bandeau « Dernière manche » est en `warning`, jamais en
> `brass`.

### 1.5 Palette des joueurs

Dix teintes vives, ordonnées de sorte que les **six premières** — le cas courant — restent
mutuellement distinguables en deutéranopie et en protanopie. Toutes ≥ 3:1 contre `neutral/
surface` (objets graphiques : lignes de courbe, pastilles, bordures d'avatar).

| # | Nom | Clair | Ratio | Sombre | Ratio | Symbole de courbe |
|---|---|---|---|---|---|---|
| 1 | Azur | `#0066FF` | 4,83 | `#5C9CFF` | 6,48 | ● cercle |
| 2 | Ambre | `#D97300` | 3,28 | `#FFA733` | 9,16 | ■ carré |
| 3 | Émeraude | `#00A550` | 3,23 | `#0BFF81` | 13,23 | ▲ triangle |
| 4 | Magenta | `#D6006D` | 5,15 | `#FF5CB8` | 6,33 | ◆ losange |
| 5 | Ardoise | `#254EAF` | 7,53 | `#89A0E6` | 6,97 | ✕ croix |
| 6 | Cyan | `#00A0B4` | 3,14 | `#1CE8FF` | 11,88 | ★ étoile |
| 7 | Vermillon | `#FF2903` | 3,77 | `#FF7A5C` | 6,93 | ▼ triangle inv. |
| 8 | Violet | `#7220FF` | 6,24 | `#B18CFF` | 6,83 | ⬟ pentagone |
| 9 | Olive | `#6E8C00` | 3,88 | `#D5FF24` | 15,37 | ⬢ hexagone |
| 10 | Rose | `#FF165F` | 3,80 | `#FF7BAA` | 7,33 | + plus |

Palette resaturée (v2 puis v3) pour un rendu plus vif sur les avatars et la courbe — priorité
donnée à l'impact visuel plutôt qu'à l'usage en texte. Certaines teintes passent désormais sous
4,5:1 : **la couleur de joueur n'est plus garantie utilisable en texte** (un pseudo coloré dans
un tableau redeviendrait un audit à part entière si on le souhaitait un jour). La v3 corrige un
retour utilisateur (« couleurs trop fades ») : les teintes en clair dont la saturation HSL
n'était pas déjà à 100 % (Ardoise, Vermillon, Violet, Rose) et les variantes sombres restées à
55-80 % de saturation (Émeraude, Ardoise, Cyan, Olive) ont été repoussées vers le plein — teinte
et luminosité inchangées — pour éliminer l'aspect pastel sans jamais retoucher les couleurs déjà
pleinement saturées. Ardoise reste volontairement sous 100 % (65 %) : au-delà elle devient trop
proche d'Azur pour rester distinguable. La distinguabilité en daltonisme n'a pas été revérifiée
par simulation dédiée depuis ce changement — à confirmer avant un usage intensif de la palette
dans des contextes graphiques denses.

**La couleur n'est jamais le seul porteur d'information.** Chaque joueur possède aussi un
avatar, une initiale dans le tableau, et un symbole distinct sur la courbe. Un daltonien total
(achromatopsie) doit pouvoir lire le graphique — d'où la colonne « symbole ».

Attribution : dérivée du pseudo par hachage stable par défaut (même pseudo → même couleur et
même emoji, quel que soit l'appareil), modifiable à la main et réinitialisable — voir doc 08.

---

## 2. Typographie

### 2.1 Familles

| Rôle | iOS | Android | Justification |
|---|---|---|---|
| **Titres et texte** | SF Pro (système) | Roboto (système) | Dynamic Type et l'échelle système fonctionnent sans effort, l'*optical sizing* ajuste le dessin à la taille, les chiffres tabulaires sont natifs, 0 Ko embarqué. Une police custom coûterait les quatre à la fois. |
| **Chiffres de score** | SF Pro **Rounded**, `monospacedDigit()` | Roboto, `FontFeature.tabularFigures` | Voir 2.3. |
| **Logo uniquement** | Outfit SemiBold, **vectorisée** | idem | Licence SIL OFL (usage commercial et logo autorisés). Vectorisée dans le SVG du logo : **la police n'est pas embarquée dans l'app**. Aucun autre écran ne l'utilise. |

### 2.2 Échelle

Les valeurs en points sont celles **à la taille système par défaut** (`Large` sur iOS,
`1.0×` sur Android). Elles sont documentaires : l'implémentation référence le style système,
qui se met à l'échelle jusqu'à AX5 (≈ ×1,6) sans intervention.

| Token | pt | Graisse | Interligne | Tracking | Style iOS | Style Android |
|---|---|---|---|---|---|---|
| `type/h1` | 34 | Bold | 41 | +0,37 | `.largeTitle` | `headlineLarge` (32/40) |
| `type/h2` | 28 | Bold | 34 | +0,36 | `.title` | `headlineMedium` (28/36) |
| `type/h3` | 22 | Bold | 28 | −0,26 | `.title2` | `headlineSmall` (24/32) |
| `type/h4` | 20 | Semibold | 25 | −0,45 | `.title3` | `titleLarge` (22/28) |
| `type/h5` | 17 | Semibold | 22 | −0,43 | `.headline` | `titleMedium` (16/24, +0,15) |
| `type/h6` | 15 | Semibold | 20 | −0,23 | `.subheadline` | `titleSmall` (14/20, +0,10) |
| `type/body` | 17 | Regular | 22 | −0,43 | `.body` | `bodyLarge` (16/24, +0,50) |
| `type/bodySmall` | 16 | Regular | 21 | −0,31 | `.callout` | `bodyMedium` (14/20, +0,25) |
| `type/label` | 13 | Medium | 18 | −0,08 | `.footnote` | `labelMedium` (12/16, +0,50) |
| `type/caption` | 12 | Regular | 16 | 0 | `.caption` | `bodySmall` (12/16, +0,40) |
| `type/caption2` | 11 | Regular | 13 | +0,06 | `.caption2` | `labelSmall` (11/16, +0,50) |
| `type/button` | 17 | Semibold | 22 | −0,43 | `.headline` | `labelLarge` (14/20, +0,10) |

**Le tracking ne se règle pas manuellement sur iOS** : les valeurs indiquées sont celles que
SF Pro applique automatiquement, listées ici pour que l'implémentation Android les reproduise.
Sur Android, `letterSpacing` doit être posé explicitement (colonne Material).

Les tailles Android diffèrent de 1 à 2 pt : c'est l'échelle Material 3 native. **Les aligner
de force sur les valeurs iOS serait une erreur** — chaque plateforme doit ressembler à
elle-même. Ce qui est partagé, c'est la *hiérarchie*, pas la mesure.

### 2.3 Chiffres de score

Le seul écart typographique assumé de la charte.

```
type/scoreXL    34 pt · Rounded Semibold · monospacedDigit   podium, total final
type/scoreL     22 pt · Rounded Semibold · monospacedDigit   cumul en tableau
type/scoreM     17 pt · Rounded Medium   · monospacedDigit   saisie, delta de manche
```

Deux justifications, toutes deux mesurables :

- **Chasse fixe** — sans elle, le tableau tressaute latéralement quand un score passe de 99 à
  100. Sur un écran regardé quarante fois dans la soirée, c'est visible et agaçant.
- **Rounded** — le SF Rounded distingue le chiffre du texte sans changer de famille, et ses
  formes ouvertes se lisent mieux à 60 cm, distance réelle d'un téléphone posé au centre
  d'une table.

### 2.4 Accessibilité typographique

- **Dynamic Type / échelle système obligatoire.** Aucune taille figée dans le code applicatif.
- Support jusqu'à **AX5** (≈ ×1,6). Au-delà de `.accessibility1`, les lignes du tableau
  passent en disposition verticale et l'avatar disparaît.
- **Interligne minimum 1,25×** la taille de police (WCAG 1.4.12).
- Aucun texte en majuscules forcées : la casse en dur casse la lecture et la prononciation
  VoiceOver.
- Longueur de ligne cible : 45 à 75 caractères sur iPad — les blocs de texte sont plafonnés
  à `680 pt` de large.

---

## 3. Grille et espacements

### 3.1 Échelle

Base 8, avec un demi-pas à 4 pour les ajustements optiques serrés.

| Token | pt | Usage typique |
|---|---|---|
| `space/2xs` | 2 | Séparation icône / badge numérique |
| `space/xs` | 4 | Entre une étiquette et sa valeur |
| `space/sm` | 8 | Padding interne d'un chip, gouttière serrée |
| `space/md` | 12 | Padding vertical d'une ligne de liste |
| `space/lg` | 16 | **Marge extérieure d'écran**, padding de carte |
| `space/xl` | 24 | Entre deux blocs d'une même section |
| `space/2xl` | 32 | Entre deux sections |
| `space/3xl` | 48 | Au-dessus d'une action principale isolée |
| `space/4xl` | 64 | Respiration verticale d'un état vide |

### 3.2 Marges et gouttières

| Contexte | Marge latérale | Gouttière |
|---|---|---|
| iPhone (compact) | `space/lg` = 16 | 12 |
| iPad (regular), colonne | `space/xl` = 24 | 16 |
| iPad, mode table plein écran | `space/2xl` = 32 | 24 |

Grille de 4 colonnes en compact, 8 en regular. Les cartes de jeu du catalogue occupent
2 colonnes en compact (2 par ligne), 2 colonnes en regular (4 par ligne).

### 3.3 Paddings internes standards

| Composant | Horizontal | Vertical |
|---|---|---|
| Bouton large | 24 | 16 |
| Bouton moyen | 16 | 12 |
| Chip | 12 | 6 |
| Champ de saisie | 12 | 12 |
| Ligne de liste | 16 | 12 |
| Carte | 16 | 16 |
| Feuille / modale | 20 | 20 |

### 3.4 Zones de sécurité

- **Jamais de valeur codée en dur** pour l'encoche, la Dynamic Island, la barre d'état ou
  l'indicateur d'accueil. iOS : `safeAreaInset`. Android : `WindowInsets`.
- Le pavé numérique s'ancre par `.safeAreaInset(edge: .bottom)` : il remonte automatiquement
  au-dessus de l'indicateur d'accueil, et le tableau des scores se rétracte d'autant.
- `space/sm` = 8 pt de dégagement supplémentaire sous la dernière touche du pavé, au-dessus de
  la safe area — le geste de retour à l'accueil part du bord et intercepte sinon les taps.
- Le contenu défilant passe **sous** les barres translucides (`.contentMargins`), il n'est pas
  coupé net.
- Mode paysage : marges latérales portées à 24 pt minimum sur iPhone, pour dégager les coins
  arrondis de l'écran.

---

## 4. Iconographie

| Règle | Valeur | Justification |
|---|---|---|
| Bibliothèque iOS | **SF Symbols 7** | 6 000+ symboles, alignés sur la ligne de base du texte, échelle avec Dynamic Type, variantes de graisse automatiques. Aucune raison de dessiner. |
| Bibliothèque Android | **Material Symbols Rounded** | Équivalent système, et l'arrondi correspond au SF Rounded des scores. |
| Grille de dessin | **24 × 24 px**, marge optique 2 px | Standard des deux bibliothèques ; toute icône custom (jaquettes de jeu) s'y conforme. |
| Épaisseur de trait | **1,75 px sur la grille 24** | Correspond au poids `Regular` de SF Symbols et au `weight 400` de Material Symbols. Constante à toutes les tailles : on met à l'échelle le tracé, jamais l'épaisseur seule. |
| Style | **Outline par défaut, filled à l'état actif** | L'onglet sélectionné et le badge acquis sont pleins ; tout le reste est en trait. Le contraste plein/vide double le codage de l'état sélectionné, qui n'est donc pas porté par la seule couleur. |
| Angles | Rayon 2 px sur la grille 24 | Cohérent avec `radius/xs`. Ni carré sec, ni arrondi mou. |

**Tailles d'affichage**

| Token | pt | Usage | Zone tactile |
|---|---|---|---|
| `icon/sm` | 16 | Accolée à du texte, chevron de liste | — |
| `icon/md` | 20 | Icône de champ, badge | 44 si interactive |
| `icon/base` | 24 | **Défaut** — barre d'outils, onglet, liste | 44 |
| `icon/lg` | 28 | Action principale, en-tête | 48 |
| `icon/xl` | 32 | État vide, avatar symbole | — |

**Taille minimale lisible : 16 pt.** En dessous, un trait de 1,75 px sur grille 24 tombe sous
le pixel physique en @2x et devient flou. Aucune icône sous 16 pt, sans exception.

Configuration Material Symbols pour l'équivalence exacte : `weight 400`, `grade 0`,
`optical size 24`, `fill 0` (inactif) / `fill 1` (actif).

---

## 5. Composants

### 5.1 Rayons de bordure

| Token | pt | Usage |
|---|---|---|
| `radius/xs` | 6 | Badge numérique, puce |
| `radius/sm` | 10 | Chip, touche de pavé, champ de saisie |
| `radius/md` | 14 | Carte, bouton |
| `radius/lg` | 20 | Feuille, modale, conteneur en verre |
| `radius/xl` | 28 | Carte de podium |
| `radius/full` | 999 | Avatar, pastille de couleur, bouton capsule |

**Règle des coins concentriques** : un élément imbriqué utilise
`rayon_parent − padding`, jamais une valeur fixe. Une carte `radius/md` = 14 avec un padding de
16 contient un champ à `14 − 16 < 0` → donc `radius/sm` = 10, la plus petite valeur cohérente.
Sur iOS 26+, `.rect(corners: .concentric)` le calcule automatiquement et doit être préféré ; le
plancher de l'app étant iOS 18 ([ADR-0001](13-decisions-adr.md)), tout appel passe par
`if #available(iOS 26, *)` avec repli sur le calcul manuel ci-dessus — voir
[ADR-0015](13-decisions-adr.md).

### 5.2 Élévation

Définie **sémantiquement**, parce que les rendus diffèrent : Material 3 (Android) par élévation
tonale et ombre ; sur Apple, Liquid Glass (translucidité et réfraction) sur iOS 26+, retombant
sur le Material system classique (`regularMaterial`/`ultraThinMaterial`, sans ombre) sur
iOS 18-25 — même sémantique, deux rendus Apple en plus du rendu Android. Voir
[ADR-0010](13-decisions-adr.md) et [ADR-0015](13-decisions-adr.md).

| Token | Sens | Rendu iOS 26+ | Rendu iOS 18-25 | Rendu Android |
|---|---|---|---|---|
| `elev/0` | Fond d'écran | `neutral/bg`, opaque | `neutral/bg`, opaque | `surface`, tonal 0 dp |
| `elev/1` | Contenu posé — carte, ligne | `neutral/surface`, opaque, **sans ombre** | `neutral/surface`, opaque, **sans ombre** | `surfaceContainerLow`, tonal 1 dp + ombre L1 |
| `elev/2` | Flottant — barre d'action, pavé | `.glassEffect()` | `.regularMaterial` | `surfaceContainer`, tonal 3 dp + ombre L2 |
| `elev/3` | Superposé — menu, popover | `.regularMaterial` | `.regularMaterial` | `surfaceContainerHigh`, tonal 6 dp + ombre L3 |
| `elev/4` | Modal — feuille, alerte | feuille système | feuille système | `surfaceContainerHighest`, tonal 8 dp + ombre L4 |

**Ombres Android** (Material 3) :

| Niveau | Ombre |
|---|---|
| L1 | `0 1 2 rgba(0,0,0,.30)` + `0 1 3 1 rgba(0,0,0,.15)` |
| L2 | `0 1 2 rgba(0,0,0,.30)` + `0 2 6 2 rgba(0,0,0,.15)` |
| L3 | `0 1 3 rgba(0,0,0,.30)` + `0 4 8 3 rgba(0,0,0,.15)` |
| L4 | `0 2 3 rgba(0,0,0,.30)` + `0 6 10 4 rgba(0,0,0,.15)` |

**Sur iOS, aucune ombre custom**, à une exception près : la barre d'action flottante du mode
table iPad, où le verre seul ne suffit pas à décoller l'élément d'un tableau dense.

```
shadow/floating   clair : 0 4 16 rgba(22,27,36,.10) + 0 1 3 rgba(22,27,36,.08)
                  sombre: 0 4 16 rgba(0,0,0,.40)    + 0 1 3 rgba(0,0,0,.30)
```

Poser des ombres Material sur du Liquid Glass (ou sur son repli `regularMaterial` iOS 18-25)
donne une app qui a l'air d'un portage Android. C'est l'erreur la plus visible qu'on puisse
commettre sur ce projet.

### 5.3 Boutons

Hauteurs : `large` 52 pt · `medium` 44 pt · `small` 32 pt (zone tactile étendue à 44).

| État | Primaire | Secondaire | Tertiaire (texte) |
|---|---|---|---|
| **Normal** | fond `brand/ink`, libellé `#FFFFFF` (8,59:1), `radius/md` | fond transparent, bordure 1,5 pt `neutral/borderStrong`, libellé `brand/ink` | libellé `brand/ink`, sans fond |
| **Pressed** | fond `brand/inkPressed`, échelle 0,97, 120 ms | fond `brand/ink` @ 8 %, bordure `brand/ink` | fond `brand/ink` @ 8 %, `radius/sm` |
| **Disabled** | fond `neutral/fill`, libellé `text/disabled` | bordure `neutral/border`, libellé `text/disabled` | libellé `text/disabled` |
| **Loading** | fond inchangé, libellé remplacé par un indicateur, **largeur figée**, interaction bloquée | idem | idem |

En mode sombre, le libellé du bouton primaire est `neutral/bg` `#0B0E14` sur `brand/ink`
`#8FB2FF` (9,18:1) — pas du blanc, qui vibrerait sur un fond clair.

Deux règles : **une seule action primaire visible par écran** ; la largeur du bouton *loading*
ne change pas, sinon la mise en page saute et l'utilisateur tape à côté.

### 5.4 Champs de formulaire

| État | Fond | Bordure | Texte | Complément |
|---|---|---|---|---|
| **Normal** | `neutral/surface` | 1 pt `neutral/borderStrong` | `text/primary` | placeholder `text/tertiary` |
| **Focus** | `neutral/surface` | 2 pt `brand/ink` | `text/primary` | halo `brand/ink` @ 12 %, 4 pt |
| **Erreur** | `semantic/error` @ 8 % | 2 pt `semantic/error` | `text/primary` | icône + message dessous en `type/label` / `semantic/error` |
| **Disabled** | `neutral/fill` | aucune | `text/disabled` | — |

Le message d'erreur est **toujours textuel**, jamais une bordure rouge seule : la couleur seule
n'est pas un moyen valide de communiquer une erreur (WCAG 1.4.1).

Le champ de score du pavé numérique déroge : fond `neutral/fill`, texte aligné à droite en
`type/scoreM`, bordure absente au repos et 2 pt `brand/ink` en focus. Il n'est jamais vide en
apparence — il affiche `0` en `text/tertiary` tant que rien n'est saisi.

### 5.5 Autres composants

| Composant | Spécification |
|---|---|
| **Carte** | `elev/1`, `radius/md`, padding 16, gouttière 12. Sans bordure en mode clair, bordure 1 pt `neutral/border` en sombre (le fond seul ne détache pas assez). |
| **Ligne de liste** | Hauteur min 56 pt (une ligne) / 72 pt (avec sous-titre). Padding 16/12. Séparateur 0,5 pt `neutral/border`, en retrait de 16 pt à gauche, aligné sur le texte et non sur l'avatar. |
| **Badge numérique** | Hauteur 20 pt, padding H 6, `radius/full`, `type/caption2` Semibold. Fond `semantic/error`, texte blanc. |
| **Chip** | Hauteur 32 pt, padding 12/6, `radius/sm`, `type/label`. Non sélectionné : fond `neutral/fill`, texte `text/secondary`. Sélectionné : fond `brand/ink` @ 12 %, texte `brand/ink`, bordure 1,5 pt `brand/ink`. |
| **Barre de navigation** | Système. Titre `type/h5` inline, `type/h1` en large. Jamais reconstruite à la main. |
| **Tab bar** | 3 onglets : Accueil · Joueurs · Historique. Icône `icon/base`, outline inactif / filled actif, libellé `type/caption2`. `TabView` système : rendu en barre flottante sur iOS 26+, en barre classique ancrée en bas sur iOS 18-25 — automatique selon l'OS de l'appareil, rien à coder ; `NavigationBar` Material 3 sur Android. |
| **Modale / feuille** | `elev/4`, `radius/lg` en haut, poignée système. Détentes `.medium` / `.large`. Toujours refermable par glissement — jamais de modale bloquante hors confirmation de suppression. |
| **Bandeau (toast)** | Hauteur 48 pt, `radius/lg`, `elev/3`, padding 16/12, `type/bodySmall`. Une action maximum. Auto-disparition à 4 s (8 s si une action est proposée). Ancré en haut sur iOS (sous la barre), en bas sur Android (Snackbar Material). |
| **Bandeau « Dernière manche »** | Pleine largeur, fond `semantic/warning` @ 8 %, bordure gauche 3 pt `semantic/warning`, texte `type/h6` en `semantic/warning`, icône `exclamationmark.circle.fill`. |

---

## 6. Accessibilité tactile

| Règle | iOS | Android |
|---|---|---|
| Zone tactile minimale | **44 × 44 pt** | **48 × 48 dp** |
| Espacement minimal entre deux cibles | **8 pt** | **8 dp** |
| Espacement dans le pavé numérique | **12 pt** | **12 dp** |

La zone tactile est **découplée du visuel** : un chevron de 16 pt garde une cible de 44 pt via
`.contentShape(.rect)` (iOS) / `minimumInteractiveComponentSize` (Android). On agrandit la
cible, pas le dessin.

Les touches du pavé numérique sont à **56 × 56 pt**, au-delà du minimum, avec 12 pt d'écart.
Justification : on tape à bout de bras, de travers, autour d'une table, parfois en parlant à
quelqu'un d'autre. C'est le seul endroit de l'app où la précision du geste est mauvaise, et
c'est celui où une erreur coûte le plus cher.

Deux actions destructrices ne sont jamais adjacentes. « Supprimer la partie » est séparé des
autres actions par 24 pt ou placé dans une section distincte.

---

## 7. Responsive et adaptabilité

Piloté par **classes de taille** uniquement. Jamais de test sur le modèle d'appareil : ce
serait faux en Split View, en Stage Manager et sur les futurs formats.

| Contexte | Largeur de référence | Comportement |
|---|---|---|
| **iPhone SE** | 375 pt | Cas le plus contraint. Le tableau abandonne la colonne « delta de manche », l'avatar passe de 44 à 36 pt. Le pavé reste à 56 pt — c'est le contenu qui cède, jamais la cible tactile. |
| **iPhone standard** | 393–440 pt | Disposition de référence. |
| **iPad, colonne** | ≥ 700 pt | `NavigationSplitView`, liste à gauche, détail à droite. Blocs de texte plafonnés à 680 pt. |
| **iPad, mode table** | plein écran | Colonnes par joueur, scores en `type/scoreXL`, pavé ancré sur le côté long. Lisible à 60 cm par toute la table. |

**Portrait / paysage**

- iPhone portrait : pavé en bas, pleine largeur, 4 colonnes de touches.
- iPhone paysage : pavé ancré à droite sur 40 % de la largeur, tableau à gauche. La hauteur
  disponible est trop faible pour empiler.
- iPad : le mode table est disponible dans les deux orientations ; en portrait, le pavé passe
  en bas.
- **L'orientation n'est jamais verrouillée** — un téléphone posé sur une table tourne.

Un seuil de repli supplémentaire : au-delà de **6 joueurs**, le tableau devient scrollable
horizontalement avec la colonne des pseudos épinglée à gauche. Jamais de réduction de la taille
du texte pour faire tenir plus de colonnes.

---

## 8. Mode sombre

Palette **conçue**, pas inversée. Trois principes, tous visibles dans les valeurs de §1.3 :

1. **Les surfaces s'éclaircissent avec l'élévation.** En mode clair, le fond est gris
   (`#F6F7F9`) et les cartes sont blanches ; en sombre, le fond est presque noir (`#0B0E14`)
   et les cartes plus claires (`#131822`). La hiérarchie s'inverse mais reste lisible dans le
   même sens : *plus clair = plus proche*.
2. **Les couleurs de marque s'éclaircissent et se désaturent.** `brand/ink` passe de `#1F4899`
   à `#8FB2FF` : une couleur saturée sombre sur fond noir vibre et fatigue. Une inversion
   automatique aurait donné un bleu illisible.
3. **Jamais de noir pur en fond, jamais de blanc pur en texte.** `#0B0E14` et `#EDF0F5` :
   le contraste maximal (21:1) provoque un halo perceptif sur écran OLED, particulièrement
   gênant dans une pièce peu éclairée — le contexte d'usage typique de cette app.

Autres règles :

- Les opacités des fonds sémantiques passent de 8 % à **16 %** : un voile translucide est
  moins perceptible sur fond sombre.
- Les cartes gagnent une bordure 1 pt `neutral/border` en sombre. Sans elle, `#131822` sur
  `#0B0E14` ne se détache pas assez.
- Les ombres ne sont **pas** renforcées en sombre : c'est le contraste de surface qui porte
  l'élévation. Une ombre noire sur fond noir n'existe pas.
- Le mode sombre n'est **jamais forcé**. L'app suit le réglage système, avec une bascule
  manuelle dans les réglages (clair / sombre / système).
- Les captures d'écran de résultats partagées via `ImageRenderer` sont générées en **mode
  clair uniquement** : elles finissent dans une conversation dont on ne connaît pas le thème.

---

## 9. Animations et transitions

### 9.1 Durées

| Token | ms | Usage |
|---|---|---|
| `motion/instant` | 0 | Changement d'état sans transition (correction de saisie) |
| `motion/fast` | 120 | Retour de pression : opacité, échelle de bouton |
| `motion/micro` | 180 | Micro-interaction : bascule, chip, anneau de focus |
| `motion/standard` | 280 | Composant : apparition de carte, expansion, bandeau |
| `motion/screen` | 350 | Transition d'écran, présentation de feuille |
| `motion/celebrate` | 650 | Podium, badges — **écran de résultats exclusivement** |

Rien entre 350 et 650 ms : l'entre-deux paraît lent sans paraître intentionnel.

### 9.2 Courbes

| Cas | iOS | Android |
|---|---|---|
| Défaut, dans l'écran | `.snappy(duration:)` | `motionScheme.defaultSpatial` |
| Entrée de contenu | `.smooth` | `emphasizedDecelerate` |
| Sortie de contenu | `.easeOut` | `emphasizedAccelerate` |
| Transition d'écran | système | `MaterialSharedAxis` |
| **Célébration** | `.spring(duration: 0.65, bounce: 0.35)` | `spring(dampingRatio = 0.55f, stiffness = 300f)` |

Le rebond (`bounce > 0.2`) est **réservé à l'écran de résultats**. Un bouton qui rebondit à
chaque manche devient insupportable au bout de vingt manches — c'est l'application directe du
positionnement « sobre pendant la partie ».

### 9.3 Règles

- **Toute animation est interruptible.** L'utilisateur qui tape pendant une transition doit
  être pris en compte, pas ignoré. Sur iOS, cela impose des animations sur ressort plutôt que
  sur durée pour tout ce qui est déclenché par un geste.
- **Rien n'anime au-delà de 650 ms.** Aucune exception, y compris le podium.
- **Rien ne clignote entre 3 et 55 Hz** (WCAG 2.3.1, risque photosensible).
- **Reduce Motion** : toutes les durées tombent à `motion/fast`, les mouvements de position et
  d'échelle sont remplacés par des fondus, le podium apparaît d'un coup, la courbe s'affiche
  tracée. Testé systématiquement, au même titre que le mode sombre.
- L'haptique accompagne mais ne remplace jamais : `.selection` sur touche de pavé, `.success`
  à la validation d'une manche, `.impact(.heavy)` à la fin de partie. Rien d'autre.

---

## 10. Imagerie et illustration

**Aucune photographie de banque d'images**, nulle part. Elle daterait l'app en dix-huit mois
et ne dirait rien du groupe qui l'utilise. Les seules photos présentes sont **celles des
utilisateurs**, en avatar.

| Type | Spécification |
|---|---|
| **Avatar photo** | Cadrage 1:1, 512 × 512 px, JPEG qualité 0,8, masque circulaire, **aucun filtre**. Bordure 2 pt de la couleur du joueur. Stockage externe SwiftData. |
| **Avatar symbole** *(défaut)* | SF Symbol `icon/xl` centré sur un disque plein de la couleur du joueur, symbole en blanc ou `neutral/bg` selon le thème. Sélection curatée d'environ 60 symboles : animaux, objets, sports, expressions. |
| **Avatar emoji** | Un caractère, centré sur un disque `neutral/fill`, taille = 60 % du diamètre. |
| **Illustration d'état vide** | Trait 2 px sur grille 24 (cohérent avec §4), monochrome `text/tertiary` + un unique aplat `brand/brass`. Aucun dégradé, aucune perspective. Hauteur max 160 pt. |
| **Vignette de jeu** | Ratio 16:9, `radius/md`, aplat de couleur + symbole `icon/xl` centré. Pas de visuel d'éditeur : les droits ne sont pas acquis et le style resterait hétérogène. |
| **Image de résultats partagée** | 1080 × 1350 px (4:5, format optimal en messagerie et sur les réseaux). Mode clair. Logo horizontal en bas, 8 % de la hauteur. Générée par `ImageRenderer`. |

Traitement commun : coins arrondis sur les tokens `radius/*`, jamais de valeur ad hoc ; aucune
ombre portée sur une image ; aucun texte incrusté dans un visuel (il ne serait ni traduit, ni
lisible par VoiceOver, ni adaptable à Dynamic Type).

---

## 11. Logo

### 11.1 Concept

**La barre de comptage** : quatre traits verticaux barrés d'un cinquième en diagonale — le
geste universel du décompte manuel, et exactement ce que l'app remplace. Lu autrement, c'est
aussi un diagramme en barres ascendant.

```
   │ │ │ │        →   ╱ traversant
   │ │ │ │
   ╲─┼─┼─┼─╲
   │ │ │ │
   │ │ │ │
```

Construction sur une grille de 24 unités :
- épaisseur de trait : **2 u**, identique pour les cinq traits
- hauteur des verticales : **16 u**
- écart entre verticales : **3 u**
- diagonale : **22°**, débordant de 1,5 u de part et d'autre
- extrémités : arrondies, rayon 1 u — cohérent avec l'iconographie et le SF Rounded des scores

### 11.2 Déclinaisons

| Déclinaison | Composition | Taille minimale | Usage |
|---|---|---|---|
| **Icône seule** | Marque dans un carré, 60 % de la largeur | **24 px** écran · 8 mm impression | Icône d'app, favicon, avatar de partage |
| **Horizontale** | Icône + wordmark à droite, séparés de 2× l'épaisseur de trait | **96 px** écran · 25 mm impression | En-tête, écran d'accueil, pied d'image partagée |
| **Verticale** | Icône au-dessus du wordmark, centrés, séparés de 3× l'épaisseur | **72 px** écran · 20 mm impression | Écran de lancement, à-propos |

Wordmark « Ça Compte » en **Outfit SemiBold**, vectorisé. La cédille est le détail critique :
elle doit rester lisible à 96 px de large, ce qui a écarté plusieurs grotesques géométriques
dont la cédille se referme. Tracking −1 %.

### 11.3 Zone de protection

**x = épaisseur d'un trait (2 u).** Marge libre minimale de **2x** sur les quatre côtés.
Aucun élément — texte, image, bordure, autre logo — ne pénètre cette zone.

### 11.4 Fonds

| Autorisé | Interdit |
|---|---|
| `neutral/bg` clair, `neutral/surface` blanc | Photographie |
| `neutral/bg` sombre, `neutral/surface` sombre | Dégradé |
| `brand/ink` (logo en blanc) | Une couleur de joueur |
| Noir, blanc | `brand/brass` — le wordmark s'y dissout |

Règles absolues : ne jamais **déformer** (l'échelle reste proportionnelle), ne jamais
**recolorer** hors des variantes fournies, ne jamais **ajouter d'effet** (ombre, contour,
biseau, reflet), ne jamais **recomposer** les déclinaisons soi-même.

### 11.5 Icône d'application

- Pleine bleed, **aucune transparence**, **aucun coin arrondi manuel** — le masque est appliqué
  par le système, et un arrondi en dur produit un liseré visible.
- Fond `brand/ink`, marque en `#FFFFFF`, occupant 58 % de la largeur, optiquement centrée
  (la diagonale décale le centre de gravité de ~2 % vers la droite : la compenser).
- **Aucun texte** dans l'icône — le nom est déjà affiché dessous par le système.
- Variantes claire, sombre, teintée requises (icônes adaptatives, iOS 18+ — aucun repli
  conditionnel nécessaire, le plancher de l'app les couvre déjà). La variante teintée est un
  aplat monochrome : la marque doit y rester lisible sans son fond.

---

## 12. Ton et microcopy

### 12.1 Voix

**Ni familière, ni institutionnelle.** L'app est un arbitre : elle constate, elle n'interprète
pas. Elle ne se félicite pas, ne s'excuse pas, ne fait pas d'humour dans les fonctions
utilitaires.

**Règle d'adresse** : formulation **impersonnelle par défaut** — infinitif ou nominal.
« Ajouter un joueur », « Aucune partie enregistrée », « Manche validée ». Cela évite d'avoir à
trancher entre tutoiement et vouvoiement dans 95 % des chaînes, ce qui règle aussi le problème
de la traduction anglaise.

L'adresse directe (tutoiement) n'est autorisée que dans les textes de **célébration**, sur
l'écran de résultats — le seul endroit où l'app a le droit d'avoir une voix.

### 12.2 Règles par type

| Type | Règle | ✅ | ❌ |
|---|---|---|---|
| **Bouton** | Verbe à l'infinitif, 1 à 3 mots, nomme l'action précise | « Valider la manche » | « OK », « Confirmer » |
| **Titre d'écran** | Nom, sans article, 1 à 3 mots | « Joueurs » | « Vos joueurs » |
| **Erreur** | Ce qui s'est passé + quoi faire. Jamais de code, jamais le mot « erreur », jamais de blâme | « Un seul joueur peut fermer la manche. » | « Erreur : validation échouée (code 42) » |
| **État vide** | Un constat + une action | « Aucune partie. Commencer une partie » | « Il n'y a rien ici pour le moment… » |
| **Confirmation destructrice** | Nomme l'objet et l'irréversibilité | « Supprimer la partie du 12 juillet ? Cette action est définitive. » | « Êtes-vous sûr ? » |
| **Notification** | Le fait, sans injonction | « Partie de Skyjo en cours » | « N'oubliez pas de finir votre partie ! » |
| **Célébration** | Courte, factuelle, l'humour vient du fait lui-même | « Bob remonte de 4 places. » | « Waouh, quelle performance incroyable !! » |

### 12.3 Conventions d'écriture (français)

- **Pas de Title Case.** En français, seule la première lettre porte la majuscule.
- **Pas de point final** sur les libellés courts (boutons, titres, étiquettes) ; point final
  sur les phrases complètes.
- **Pas de point d'exclamation** hors écran de résultats, et jamais doublé.
- **Espace insécable** avant `:` `;` `!` `?` `»` et entre un nombre et son unité.
- **Nombres via `.formatted()`**, jamais de concaténation manuelle. Les pluriels passent par
  les règles du catalogue de chaînes, jamais par un `if count > 1`.
- Vocabulaire fixe, jamais synonymisé : **partie** (pas « jeu » ni « session »), **manche**
  (pas « tour » ni « round »), **joueur** (pas « participant » dans l'UI), **score** (pas
  « points » ni « résultat »).
- Le mot **« Ça Compte »** garde toujours sa majuscule et son accent, y compris en anglais.

---

## 13. Do's / Don'ts

### Toujours

1. **Utiliser un token.** Toute valeur littérale — couleur, taille, espacement, durée — est un
   bug. Si le token manque, on l'ajoute ici avant de coder.
2. **Vérifier le contraste par calcul, pas à l'œil.** Toute nouvelle paire couleur/fond passe
   par le script de vérification. Un contraste « qui a l'air bon » est un contraste non testé.
3. **Doubler le codage par la couleur.** Icône, forme, position ou libellé accompagnent
   toujours une information portée par la couleur.
4. **Laisser le système faire.** Barre de navigation, feuilles, Dynamic Type, mode sombre,
   haptique : le natif est meilleur que ce qu'on écrirait, et il évolue tout seul avec l'OS.
5. **Vérifier en AX5, en sombre, à VoiceOver et sur iPhone SE** avant de considérer un écran
   terminé. Ces quatre passes attrapent l'essentiel des défauts, et coûtent dix minutes.

### Jamais

1. **Ne pas mettre `brand/brass` sur l'écran de partie.** L'accent réservé à la célébration est
   ce qui fait exister la célébration. Le diluer la supprime.
2. **Ne pas poser d'ombre portée sur du Liquid Glass, ni sur son repli `regularMaterial`
   iOS 18-25.** L'élévation Apple se fait par matériau, jamais par ombre. Une ombre Material y
   trahit immédiatement un portage.
3. **Ne pas figer une taille de police en points.** C'est une régression d'accessibilité
   directe, et la plus fréquente.
4. **Ne pas rétrécir une zone tactile pour faire tenir du contenu.** 44 pt est un plancher, pas
   une cible négociable. C'est le contenu qui cède.
5. **Ne pas animer au-delà de 650 ms, ni faire rebondir hors résultats.** Une app de saisie
   utilisée quarante fois par soirée doit être invisible ; le mouvement décoratif y devient
   une gêne dès la troisième manche.

---

## 14. Tableau de synthèse des tokens

Directement exploitable en implémentation. Nommage identique dans les deux bases de code.

### Couleurs

| Token | Clair | Sombre |
|---|---|---|
| `brand/ink` | `#1F4899` | `#8FB2FF` |
| `brand/inkPressed` | `#173A80` | `#A9C3FF` |
| `brand/brass` | `#9A5B00` | `#F0A73F` |
| `brand/teal` | `#0A6A72` | `#4CC7D1` |
| `neutral/bg` | `#F6F7F9` | `#0B0E14` |
| `neutral/surface` | `#FFFFFF` | `#131822` |
| `neutral/sunken` | `#ECEEF2` | `#090C11` |
| `neutral/fill` | `#E3E6EC` | `#1D2432` |
| `neutral/border` | `#D4D9E2` | `#2B3342` |
| `neutral/borderStrong` | `#7E879A` | `#69738A` |
| `text/primary` | `#161B24` | `#EDF0F5` |
| `text/secondary` | `#4A5260` | `#BAC2D0` |
| `text/tertiary` | `#5A6373` | `#98A2B4` |
| `text/disabled` | `#9AA3B2` | `#5A6478` |
| `semantic/success` | `#0F6B43` | `#41CE92` |
| `semantic/error` | `#BC2418` | `#FF8A7A` |
| `semantic/warning` | `#8A5300` | `#FFC161` |
| `semantic/info` | `#1B5FA6` | `#79B6F7` |
| `player/1` … `player/10` | voir §1.5 | voir §1.5 |

### Typographie

| Token | pt | Graisse | Interligne |
|---|---|---|---|
| `type/h1` | 34 | Bold | 41 |
| `type/h2` | 28 | Bold | 34 |
| `type/h3` | 22 | Bold | 28 |
| `type/h4` | 20 | Semibold | 25 |
| `type/h5` | 17 | Semibold | 22 |
| `type/h6` | 15 | Semibold | 20 |
| `type/body` | 17 | Regular | 22 |
| `type/bodySmall` | 16 | Regular | 21 |
| `type/label` | 13 | Medium | 18 |
| `type/caption` | 12 | Regular | 16 |
| `type/caption2` | 11 | Regular | 13 |
| `type/button` | 17 | Semibold | 22 |
| `type/scoreXL` | 34 | Semibold Rounded | 41 |
| `type/scoreL` | 22 | Semibold Rounded | 28 |
| `type/scoreM` | 17 | Medium Rounded | 22 |

### Espacements, rayons, tailles

| Token | pt | | Token | pt | | Token | pt |
|---|---|---|---|---|---|---|---|
| `space/2xs` | 2 | | `radius/xs` | 6 | | `icon/sm` | 16 |
| `space/xs` | 4 | | `radius/sm` | 10 | | `icon/md` | 20 |
| `space/sm` | 8 | | `radius/md` | 14 | | `icon/base` | 24 |
| `space/md` | 12 | | `radius/lg` | 20 | | `icon/lg` | 28 |
| `space/lg` | 16 | | `radius/xl` | 28 | | `icon/xl` | 32 |
| `space/xl` | 24 | | `radius/full` | 999 | | `touch/min` | 44 |
| `space/2xl` | 32 | | `button/large` | 52 | | `touch/gap` | 8 |
| `space/3xl` | 48 | | `button/medium` | 44 | | `keypad/key` | 56 |
| `space/4xl` | 64 | | `button/small` | 32 | | `keypad/gap` | 12 |

### Mouvement

| Token | ms | | Token | ms |
|---|---|---|---|---|
| `motion/instant` | 0 | | `motion/standard` | 280 |
| `motion/fast` | 120 | | `motion/screen` | 350 |
| `motion/micro` | 180 | | `motion/celebrate` | 650 |

### Élévation

| Token | iOS | Android |
|---|---|---|
| `elev/0` | `neutral/bg` opaque | tonal 0 dp |
| `elev/1` | `neutral/surface` opaque | tonal 1 dp + ombre L1 |
| `elev/2` | `.glassEffect()` | tonal 3 dp + ombre L2 |
| `elev/3` | `.regularMaterial` | tonal 6 dp + ombre L3 |
| `elev/4` | feuille système | tonal 8 dp + ombre L4 |

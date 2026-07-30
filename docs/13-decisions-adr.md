# 13 — Décisions d'architecture (ADR)

Chaque décision structurante, son contexte, l'alternative écartée et pourquoi. Une décision
qu'on ne sait pas justifier six mois plus tard est une décision qu'on refera mal.

Statuts : **Acceptée** · Proposée · Remplacée · Obsolète

---

## ADR-0001 — SwiftUI + SwiftData plutôt qu'UIKit + Core Data

**Statut** : Acceptée · **Date** : 2026-07-29

**Contexte.** Application neuve, une seule personne au développement. *(Le plancher iOS a
changé depuis l'écriture de cet ADR — voir [ADR-0015](#adr-0015--plancher-ios-18-plutôt-quios-26-liquid-glass-en-amélioration-progressive), qui ne remet pas en cause le choix
ci-dessous.)*

**Décision.** SwiftUI pour l'intégralité de l'interface, SwiftData pour la persistance.

**Alternatives.** UIKit + Core Data — plus mature, plus de contrôle sur les cas limites, mais
trois à quatre fois plus de code pour des écrans qui sont essentiellement des listes et des
formulaires. Aucun besoin ici ne justifie ce contrôle.

**Conséquences.** SwiftUI + SwiftData sont disponibles dès iOS 13, donc indépendants du
plancher retenu ([ADR-0015](#adr-0015--plancher-ios-18-plutôt-quios-26-liquid-glass-en-amélioration-progressive)). On hérite des limites de SwiftData : pas de contraintes d'unicité
avec CloudKit, pas d'ordre garanti dans les collections. Toutes deux traitées en
[03](03-modele-de-donnees.md).

---

## ADR-0002 — Domaine pur, sans dépendance framework

**Statut** : Acceptée · **Date** : 2026-07-29

**Contexte.** Le calcul des scores est la seule partie du logiciel où une erreur est
inacceptable. Il doit aussi être ré-implémenté en Kotlin.

**Décision.** La cible `Domain` n'importe que `Foundation`, et seulement `UUID`, `Date`, `Data`,
`Codable`. Uniquement des `struct` immuables et `Sendable`, uniquement des fonctions pures.

**Alternatives.** Laisser les règles manipuler directement les objets SwiftData — plus court à
écrire, mais rend tout test dépendant d'un magasin, empêche le rejeu de golden files, et lie le
calcul au schéma disque.

**Conséquences.** Une centaine de lignes de mapping domaine ↔ persistance à écrire et à
maintenir. En échange : tests en millisecondes sans simulateur, portage Kotlin mécanique, et
une migration SwiftData ne peut jamais casser un calcul de score. La séparation est vérifiée
par le compilateur via le graphe de dépendances du package.

---

## ADR-0003 — Règles déclaratives, plus extensions impératives

**Statut** : Acceptée · **Date** : 2026-07-29

**Contexte.** 16 jeux prévus. Onze se résument à « saisir un nombre, cumuler, s'arrêter à un
seuil ». Cinq ont une arithmétique propre (Skyjo, Yams, Tarot, Wizard, Mölkky).

**Décision.** Deux couches. Un `GameDefinition` déclaratif en JSON couvre identité, contraintes
de saisie, conditions de fin et départages. Un protocole `GameRules` impératif, désigné par un
`engineID`, couvre le calcul non exprimable en données. Onze jeux partagent
`generic.sum.v1`.

**Alternatives.**
- *Tout impératif* — une classe par jeu : seize fois le même code pour les cas simples.
- *Tout déclaratif* — un moteur de règles assez expressif pour encoder le Tarot devient un
  langage de programmation mal conçu, impossible à déboguer et pénible à porter.

**Conséquences.** Le JSON déclaratif est partagé mot pour mot avec Android ; seule la couche
impérative est dupliquée, soit environ 2 000 lignes. Ajouter un jeu simple ne demande **aucun
code**. Le risque à surveiller est la dérive du déclaratif : toute troisième couche
d'abstraction doit passer par un nouvel ADR.

---

## ADR-0004 — Spécification partagée plutôt que Kotlin Multiplatform

**Statut** : Acceptée · **Date** : 2026-07-29

**Contexte.** Une version Android est prévue et doit être pleinement native.

**Décision.** Aucun partage de code. Un dossier `spec/` en JSON — définitions de jeux, schémas,
golden files — sert de source de vérité aux deux implémentations, chacune écrite dans son
langage.

**Alternatives.**
- *Kotlin Multiplatform* — une seule implémentation du moteur, mais impose Gradle dans le build
  iOS, éloigne de SwiftData, et rend l'app Apple partiellement non-idiomatique. Contredit
  frontalement l'exigence « outils natifs au maximum ».
- *Cœur Swift compilé pour Android* — outillage encore jeune, friction attendue sur le build,
  le débogage et la taille de l'APK.

**Conséquences.** Le moteur s'écrit deux fois. C'est le coût assumé. Il est encadré par les
golden files : une divergence de calcul fait échouer la suite de tests Android, elle ne peut
pas passer inaperçue. En contrepartie, chaque application est 100 % idiomatique et aucune
chaîne d'outils croisée n'est nécessaire.

---

## ADR-0005 — Event sourcing pour l'état d'une partie

**Statut** : Acceptée · **Date** : 2026-07-29

**Contexte.** Quatre besoins convergent : annuler ou corriger une manche, synchroniser une
partie entre appareils en direct, résoudre les conflits iCloud, et tester le moteur de façon
exhaustive.

**Décision.** `MatchState` ne se mute jamais. Il est le repli d'un journal d'événements
horodatés par une horloge de Lamport, trié par `(lamport, deviceID)`.

**Alternatives.** Muter l'état directement et implémenter l'annulation comme une opération
inverse par type d'action — il faudrait écrire et tester une inverse par événement, et cela ne
résoudrait ni la synchronisation ni les conflits.

**Conséquences.** Les quatre besoins sont satisfaits par la même mécanique. La fusion de deux
journaux est associative, commutative et idempotente, donc sûre quel que soit l'ordre
d'arrivée. Le coût est un rejeu à chaque ouverture de partie — moins d'une milliseconde pour
40 manches à 6 joueurs, aucune optimisation prévue. Le stockage double (journal + projection
matérialisée) ; en cas de divergence, le journal fait foi.

---

## ADR-0006 — Modèle compatible CloudKit dès la première version

**Statut** : Acceptée · **Date** : 2026-07-29

**Contexte.** La synchronisation entre les appareils du propriétaire est souhaitée, mais
n'est pas prioritaire pour un premier lancement.

**Décision.** Le schéma respecte **dès le départ** toutes les contraintes CloudKit : aucune
contrainte d'unicité, valeurs par défaut partout, relations optionnelles avec inverse,
pas de règle `.deny`, ordre explicite. La synchronisation elle-même est activée en P6 et reste
désactivable par l'utilisateur.

**Alternatives.** Concevoir un schéma libre et l'adapter plus tard — c'est une migration lourde
sur des données de production, pour un gain nul à l'écriture.

**Conséquences.** Quelques champs sont optionnels alors qu'ils sont logiquement obligatoires,
et l'unicité repose sur la génération d'`UUID` plutôt que sur le schéma. Ces contraintes sont
listées explicitement en [03](03-modele-de-donnees.md) pour qu'elles ne soient pas prises pour
de la négligence.

---

## ADR-0007 — MV avec `@Observable`, pas de ViewModel systématique

**Statut** : Acceptée · **Date** : 2026-07-29

**Contexte.** SwiftUI et `@Observable` rendent la couche ViewModel de MVVM largement redondante.

**Décision.** Lectures simples : `@Query` SwiftData directement dans la vue. Flux avec état :
un objet `@Observable` `@MainActor` **par flux métier**, pas par écran — `LiveMatchModel`,
`MatchSetupModel`, `PlayerEditorModel`. Aucun état métier dans `@State`.

**Alternatives.** Un ViewModel par vue — produit une couche de transfert sans logique, dont le
seul effet est d'allonger la chaîne entre la donnée et l'affichage.

**Conséquences.** Trois objets d'état pour toute l'application. Un flux traversant plusieurs
écrans partage naturellement le sien. Le risque est qu'un `LiveMatchModel` grossisse trop ; la
parade est que toute la logique de calcul est ailleurs, dans `Domain`.

---

## ADR-0008 — Partie partagée avec hôte autoritaire

**Statut** : Acceptée · **Date** : 2026-07-29

**Contexte.** Plusieurs appareils suivent la même partie autour d'une table, en local.

**Décision.** Un pair unique — le créateur — détient la vérité et est le seul à écrire dans
SwiftData. Les autres sont observateurs ou contributeurs ; une proposition de manche est
validée puis rediffusée par l'hôte.

**Alternatives.** Réplication pair-à-pair symétrique — techniquement possible puisque le
journal d'événements est commutatif, mais impose de gérer les partitions réseau, l'élection
d'un nouveau maître et une interface d'arbitrage. Pour trois téléphones à un mètre les uns des
autres pendant une heure, le rapport coût/bénéfice est mauvais.

**Conséquences.** Si l'hôte quitte, la partie n'est pas perdue : chaque pair a l'état complet
et peut la reprendre explicitement sur son appareil. La décision est réversible sans changer ni
le format des messages ni le modèle de données.

---

## ADR-0009 — Pavé numérique propriétaire plutôt que clavier système

**Statut** : Remplacée par [ADR-0013](#adr-0013--retour-au-clavier-système-plutôt-que-le-pavé-propriétaire) · **Date** : 2026-07-29

**Contexte.** La vitesse de saisie est la métrique produit numéro un : cinq scores en moins de
quinze secondes. C'est la seule entorse envisagée à la règle « tout au système ».

**Décision.** Un pavé numérique maison, permanent en bas d'écran, touches de 56 pt, avec une
touche « joueur suivant » qui valide et avance.

**Alternatives.** Le clavier `.numberPad` système — met environ 200 ms à apparaître, occupe la
moitié de l'écran, se ferme entre deux champs, et ne peut pas porter de touche « suivant » ni
de bascule de signe adaptée aux scores négatifs (Skyjo).

**Conséquences.** Un composant à écrire, à tester et à rendre accessible nous-mêmes — chaque
touche porte un libellé VoiceOver explicite et une cible de 56 pt. Le gain est mesurable et
c'est la seule justification acceptée pour recoder un élément système.

---

## ADR-0010 — Élévation sémantique, rendue différemment par plateforme

**Statut** : Acceptée · **Date** : 2026-07-29

**Contexte.** La charte graphique est bi-plateforme. Or iOS 26 sépare les plans par
translucidité et réfraction (Liquid Glass), tandis que Material 3 le fait par élévation tonale
et ombre portée. Les deux modèles sont incompatibles. *(Le plancher Apple étant iOS 18, Liquid
Glass lui-même est une amélioration progressive iOS 26+ avec repli Material — voir
[ADR-0015](#adr-0015--plancher-ios-18-plutôt-quios-26-liquid-glass-en-amélioration-progressive) —
ce qui ajoute un rendu Apple supplémentaire, pas un troisième modèle : le repli emprunte
toujours au matériau, jamais à l'ombre, contrairement à Android.)*

**Décision.** Les tokens d'élévation sont définis **sémantiquement** — `elev/0` à `elev/4`,
nommés par leur rôle (fond, posé, flottant, superposé, modal) — et non par une valeur d'ombre.
Chaque plateforme les rend selon sa propre convention.

**Alternatives.**
- *Une échelle d'ombres partagée* — donnerait une app iOS qui a l'air d'un portage Android.
  C'est le défaut le plus immédiatement visible qu'on puisse produire sur ce projet.
- *Deux systèmes d'élévation indépendants* — casserait la règle « une valeur, une seule
  définition » et laisserait les deux apps diverger silencieusement.

**Conséquences.** Le tableau de tokens porte deux colonnes de rendu au lieu d'une valeur. Un
développeur ne peut pas copier une ombre d'une plateforme à l'autre, ce qui est l'effet
recherché. Une seule ombre custom existe côté iOS (`shadow/floating`, barre d'action du mode
table iPad), documentée comme exception.

---

## ADR-0011 — Polices système uniquement, display réservée au logo

**Statut** : Acceptée · **Date** : 2026-07-29

**Contexte.** L'identité de marque demande du caractère, mais l'écran principal de
l'application est un tableau de chiffres consulté des dizaines de fois par soirée.

**Décision.** SF Pro sur iOS, Roboto sur Android, en titres comme en texte. Les scores utilisent
SF Pro Rounded en chiffres tabulaires. Une police display (Outfit, licence SIL OFL) est
réservée au **wordmark du logo** et vectorisée — elle n'est pas embarquée dans l'application.

**Alternatives.** Une police de marque partout — identité plus forte et strictement identique
sur les deux plateformes, mais au prix de Dynamic Type dégradé, de la perte de l'*optical
sizing*, de chiffres tabulaires à vérifier manuellement, d'environ 400 Ko embarqués, et d'une
app qui cesse de ressembler à son système.

**Conséquences.** La personnalité visuelle repose sur la couleur, l'espacement, les avatars et
les moments de célébration — pas sur la typographie. C'est un choix moins spectaculaire en
maquette et meilleur à l'usage. Les échelles typographiques iOS et Android diffèrent de 1 à
2 pt : c'est voulu, seule la hiérarchie est partagée.

---

## ADR-0012 — Aucune dépendance tierce côté Apple

**Statut** : Acceptée · **Date** : 2026-07-29

**Contexte.** L'application est hors ligne, sans compte, sans serveur, et ne fait ni réseau
distant ni rendu complexe. Tous ses besoins ont un équivalent système.

**Décision.** Zéro dépendance externe dans la version Apple. Toute proposition d'en ajouter une
exige un nouvel ADR.

**Alternatives.** Adopter les bibliothèques usuelles (composition, navigation, injection,
graphiques) — chacune ajoute une surface de mise à jour à chaque version d'iOS, pour remplacer
quelque chose que le système fournit déjà.

**Conséquences.** Compilation rapide, mises à jour d'OS sans risque de rupture, aucune
vérification de licence. Une exception est actée d'avance côté Android : **Vico**, pour les
graphiques, Compose n'ayant pas d'équivalent natif à Swift Charts. C'est l'écart d'écosystème
le plus concret entre les deux versions.

---

## ADR-0013 — Retour au clavier système plutôt que le pavé propriétaire

**Statut** : Acceptée · **Date** : 2026-07-30

**Contexte.** Retour d'usage sur l'écran de partie (ADR-0009) : le pavé numérique maison se lit
comme un décor qui imite un clavier plutôt que comme un contrôle système, ce qui nuit à la
confiance dans la saisie. Le gain de vitesse qui justifiait le pavé maison n'a pas été mesuré
en usage réel au-delà de l'intuition initiale.

**Décision.** `LiveMatchView` (Skyjo, Rami, 6 qui prend, Jeu libre, et tous les jeux
`generic.sum.v1`) utilise désormais un `TextField` par joueur avec `.keyboardType(.numberPad)`
— le clavier système. L'enchaînement « joueur suivant » et la bascule de signe (scores négatifs)
migrent vers la barre d'accessoires du clavier (`.toolbar(placement: .keyboard)`) plutôt que
d'être recodés en touches maison. `NumericKeypad` et `ScoreField` sont supprimés du package
`DesignSystem`.

**Alternatives.** Garder le pavé maison pour les jeux à scores négatifs (Skyjo, Rummikub, Jeu
libre) et basculer au clavier système uniquement pour les autres — deux mécaniques de saisie
coexistantes pour un seul écran partagé (`LiveMatchView`), plus coûteux à maintenir et
incohérent d'un jeu à l'autre.

**Conséquences.** Perte de la touche « 00 » (rendue inutile par un clavier réellement rapide) et
de la garantie de 200 ms d'affichage instantané de l'ADR-0009 — non mesurée comme un problème
en usage. Gain : moins de code propriétaire à maintenir et à rendre accessible soi-même (le
clavier système porte déjà VoiceOver, Dictée, Dynamic Type), cohérence avec la règle « tout au
système » que le pavé maison était la seule à enfreindre. Yams (`categorySheet`) et Belote
(`structured`) ne sont pas concernés : ils utilisaient déjà des `Stepper`/`Picker` natifs, jamais
le pavé numérique.

---

## ADR-0014 — Transport hybride Wi-Fi + Bluetooth LE plutôt que MultipeerConnectivity/Nearby Connections

**Statut** : Acceptée · **Date** : 2026-07-30

**Contexte.** La Phase 8 (partie partagée) était conçue autour de MultipeerConnectivity côté
Apple et de Nearby Connections en équivalent Android (doc [11](11-portage-android.md)). Ce sont
deux protocoles fermés, chacun propre à sa plateforme : un iPhone en MultipeerConnectivity ne
peut structurellement pas rejoindre un pair en Nearby Connections. Le doc 09 initial actait ce
non-interop comme « hors périmètre v1 ». La compatibilité Android étant désormais un objectif
explicite dès la conception de cette fonctionnalité, ce non-interop devient inacceptable : le
but est que des parties se partagent **entre plusieurs appareils**, quelle que soit leur
plateforme.

**Décision.** Remplacer les deux frameworks propriétaires par deux transports construits sur des
standards que les deux OS implémentent nativement et de façon interopérable sur le fil :

1. **Wi-Fi, transport principal** — découverte par mDNS/DNS-SD (RFC 6762/6763, `_cacompte._tcp`),
   socket TCP pour les données. `Network.framework` (`NWListener`/`NWBrowser`/`NWConnection`) côté
   Apple, `NsdManager` + `Socket`/`ServerSocket` côté Android.
2. **Bluetooth LE, secours** — service GATT dédié, sans dépendance à un réseau Wi-Fi commun.
   `CoreBluetooth` côté Apple, `BluetoothGattServer`/`BluetoothGatt` côté Android.

Le protocole applicatif (`WireMessage`, hôte autoritaire, horloge de Lamport) ne change pas : il
était déjà pensé indépendamment du transport (doc 09). Le chiffrement, assuré gratuitement par
MultipeerConnectivity, est reconstruit par-dessus : un code d'appairage à 6 chiffres saisi ou
scanné par le pair qui rejoint fait dériver (HKDF) une clé de session AES-GCM des deux côtés,
sans jamais transiter sur le réseau.

**Alternatives.**
- *Garder MultipeerConnectivity/Nearby Connections séparés* — le plus simple à construire (un
  seul framework haut niveau par plateforme), mais interdit structurellement tout groupe mixte
  iPhone + Android, ce qui contredit l'objectif produit.
- *Wi-Fi seul (mDNS + socket)* — suffisant pour l'interop et moins coûteux que l'option
  hybride, mais perd la capacité « zéro infrastructure » de MultipeerConnectivity : sans réseau
  Wi-Fi commun (aucune box, aucun partage de connexion), deux appareils ne peuvent plus se
  parler du tout. Le cas d'usage fondateur du doc 09 (le gîte sans réseau) suppose justement
  cette capacité.
- *Bluetooth LE seul* — couvre le cas « zéro infrastructure », mais en fait le transport
  unique alors que son débit est faible et son protocole entièrement à construire à la main
  (découpage/réassemblage de trames, MTU, rôle périphérique). Pénaliserait le cas le plus
  fréquent (un Wi-Fi commun existe) pour protéger le cas le plus rare.

**Conséquences.** Deux transports à construire, tester et maintenir au lieu d'un framework
système clé en main — la Phase 8 passe de 2 à 3 semaines, et l'étape F du portage Android
(doc 11) de 1,5 à 3 semaines. Le rôle périphérique BLE (`BluetoothGattServer`) est à valider tôt
sur le parc Android cible, son support variant selon les fabricants davantage que côté Apple.
En contrepartie, aucune dépendance tierce n'est ajoutée d'aucun côté (`Network.framework` et
`CoreBluetooth` sont système côté Apple ; `NsdManager`, `Socket` et `BluetoothGatt*` font partie
du SDK Android) — ADR-0012 n'est pas affecté — et le mécanisme d'appairage par code remplace
uniformément l'invitation MultipeerConnectivity sur les deux transports et les deux
plateformes. ADR-0008 (hôte autoritaire) n'est pas remis en cause : cette décision porte
uniquement sur le transport, pas sur le modèle de synchronisation.

---

## ADR-0015 — Plancher iOS 18 plutôt qu'iOS 26, Liquid Glass en amélioration progressive

**Statut** : Acceptée · **Date** : 2026-07-30

**Contexte.** ADR-0001 fixait le plancher à iOS 26 uniquement, pour un accès direct à Liquid
Glass, aux coins concentriques et à `@Entry` — ce dernier point était d'ailleurs inexact :
`@Entry` est une macro Swift 5.10, disponible dès iOS 17, indépendante du plancher OS. Un
plancher iOS 26 exclut tout appareil qui n'a pas encore reçu cette mise à jour, ce qui réduit le
public atteignable dès le lancement d'une app neuve. Aucun code du projet n'utilisait encore
Liquid Glass ni les coins concentriques au moment de cette décision : la charte graphique
([07](07-charte-graphique.md)) et le design system ([08](08-design-system.md)) les décrivaient
comme plan, pas comme implémentation existante — le changement de plancher ne défait donc aucun
travail déjà écrit.

**Décision.** Le plancher passe à **iOS 18**. Liquid Glass et les coins concentriques
deviennent une **amélioration progressive iOS 26+** : chaque point d'usage se code avec un
repli explicite plutôt qu'une supposition de disponibilité.

```swift
if #available(iOS 26, *) {
    view.glassEffect(in: .rect(cornerRadius: radius))
} else {
    view.background(.regularMaterial, in: .rect(cornerRadius: radius))
}
```

Le repli n'est pas un pis-aller improvisé : c'est déjà exactement ce que le code du design
system utilisait avant même cette décision (`.regularMaterial`, `.rect(cornerRadius:)` dans
`Card`, `Banner`, les styles de bouton — voir doc 08). Seule la branche iOS 26+ est nouvelle.

**Alternatives.**
- *Garder le plancher iOS 26* — aucun repli à écrire ni à tester, mais exclut tout appareil pas
  encore mis à jour vers la dernière version majeure, un coût direct sur l'audience pour une
  app qui n'a pas encore de base d'utilisateurs à qui imposer une mise à jour.
- *Abandonner Liquid Glass entièrement, un seul rendu Material sur toutes les versions* — le
  plus simple à maintenir et cohérent avec le code déjà écrit, mais renonce définitivement au
  langage visuel natif le plus récent d'Apple, y compris sur les appareils qui le supportent.
  Écarté explicitement : Liquid Glass reste la direction visuelle voulue, seulement différée à
  quand l'appareil le permet.

**Conséquences.** Chaque point de la charte qui mentionne Liquid Glass ou les coins
concentriques (doc 07 §5.1/§5.2, doc 08 « Liquid Glass », « Rayons concentriques », « Élévation »)
porte désormais deux rendus Apple au lieu d'un, et chaque composant concerné doit montrer les
deux dans sa galerie de previews Xcode plutôt qu'un seul. `ADR-0010` (élévation par plateforme)
gagne un rendu intermédiaire (Material iOS 18-25) sans changer de principe. Aucune dépendance
tierce ajoutée : `if #available` est un mécanisme du langage, pas une bibliothèque. La tab bar
système et l'icône adaptative (claire/sombre/teintée, iOS 18+) n'ont besoin d'aucun repli — elles
sont déjà couvertes par le nouveau plancher. Vérifié par build et lancement réels sur simulateur
iOS 18.6 (iPhone 16) en plus d'iOS 26, sans avertissement de disponibilité.

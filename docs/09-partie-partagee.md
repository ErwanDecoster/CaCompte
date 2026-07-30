# 08 — Partie partagée en direct

Plusieurs appareils suivent la même partie autour de la table, **sans Internet, sans compte,
sans serveur** — et **quelle que soit leur plateforme** : iPhone et Android doivent pouvoir
rejoindre la même partie. C'est une contrainte de premier ordre, pas un bonus : elle élimine
d'office toute techno propriétaire à une seule plateforme.

## Cas d'usage

Marion tient le score sur son iPhone. Théo, sceptique, veut voir le tableau sur son Pixel.
David, qui a une meilleure vue d'ensemble, voudrait saisir sa propre manche depuis son iPad.
Aucun des trois n'a de réseau : ils sont dans un gîte. Le groupe mélange les plateformes sans
même y penser — c'est le point de départ, pas un cas limite.

## Technologie

**Aucune techno propriétaire à une seule plateforme.** MultipeerConnectivity (Apple) et Nearby
Connections (Android) ont été écartés : ce sont deux protocoles fermés, chacun conçu pour ne
parler qu'à lui-même. Un iPhone en MultipeerConnectivity ne peut structurellement pas rejoindre
un pair en Nearby Connections — pas de bridge possible, ce n'est pas une question
d'implémentation mais de protocole. Pour un vrai partage cross-plateforme, il faut une couche
que les deux OS parlent nativement **et de façon interopérable sur le fil**, pas seulement une
« API équivalente ».

**Deux transports, choisis automatiquement selon ce qui est disponible :**

| | Découverte | Transport | Apple | Android |
|---|---|---|---|---|
| **Principal — Wi-Fi local** — **implémenté** | mDNS / DNS-SD (`_cacompte._tcp`), un standard IETF (RFC 6762/6763), pas une invention Apple | Socket TCP, trames préfixées par longueur | `NetService`/`NetServiceBrowser` (découverte) + `NWListener`/`NWConnection` (Network.framework, transport) | `NsdManager` + `Socket`/`ServerSocket` |
| **Secours — Bluetooth LE** — **écrit, non vérifié, pas branché** | Service GATT annoncé (UUID dédié, voir plus bas) | Écritures de caractéristique, découpées et réassemblées | `CBPeripheralManager` / `CBCentralManager` (CoreBluetooth) | `BluetoothGattServer` / `BluetoothGatt` |

Côté Apple, la découverte utilise volontairement **deux API différentes** pour une seule
raison pratique : `NWBrowser` (l'API la plus récente de `Network.framework`) ne remontait pas
les enregistrements TXT dans l'environnement où ceci a été construit et vérifié — confirmé par
un harnais de diagnostic isolé, alors que `dns-sd` au niveau système résolvait le même
enregistrement sans problème. `NetService`/`NetServiceBrowser` (l'API Bonjour historique) le
fait de façon fiable. Le transport lui-même reste entièrement sur `Network.framework`
(`NWListener`/`NWConnection`) : `NetService` ne sert qu'à la découverte et au TXT record, jamais
à transporter la moindre donnée applicative.

Le Wi-Fi est essayé en premier : débit confortable, latence négligeable, mDNS/DNS-SD est un
standard que les deux OS implémentent en parlant littéralement le même protocole sur le réseau
— contrairement à MultipeerConnectivity et Nearby Connections, qui *ressemblent* à des
équivalents mais ne s'interopèrent jamais. Sa seule exigence : les appareils doivent être sur le
même réseau Wi-Fi. S'il n'y en a pas dans la pièce, le partage de connexion (hotspot personnel)
d'un des téléphones en crée un en quelques secondes — c'est l'usage attendu quand aucune box
n'est disponible.

Le BLE prend le relais quand aucun réseau Wi-Fi commun n'est trouvé : Bluetooth Low Energy est
un standard cross-vendor (Bluetooth SIG), disponible nativement des deux côtés, qui ne demande
aucune infrastructure réseau — le mode réellement « zéro configuration » que le cas d'usage du
gîte suppose. En échange, son débit est faible et son protocole doit être entièrement construit
à la main (découpage en trames, réassemblage, gestion du rôle périphérique). C'est pourquoi il
reste un **secours**, pas le transport par défaut : la majorité des sessions passeront par le
Wi-Fi.

**Ce compromis est documenté dans [ADR-0014](13-decisions-adr.md).** Aucune des deux techno
n'est une dépendance tierce : `Network.framework` et `CoreBluetooth` sont des frameworks
système Apple ; `NsdManager`, `Socket` et `BluetoothGatt*` font partie du SDK Android. ADR-0012
(zéro dépendance tierce) n'est pas affecté.

## Modèle : hôte autoritaire

Inchangé, et **indépendant du transport** — c'est tout l'intérêt de l'avoir découplé dès le
départ. Un pair et un seul est **l'hôte** : celui qui a créé la partie. Il détient la vérité et
est le seul à écrire dans le stockage local (SwiftData côté Apple, Room côté Android).

```
        ┌──────────────┐
        │  HÔTE        │  crée la partie, persiste, arbitre
        │  Marion      │  seul écrivain du stockage local
        └──┬────────┬──┘
   invite  │        │  invite
      ┌────▼──┐  ┌──▼─────┐
      │ Théo  │  │ David  │   participants — plateforme indifférente
      │ vue   │  │ saisie │   état en mémoire uniquement
      └───────┘  └────────┘
```

Deux rôles pour un pair non-hôte, choisis par l'hôte à l'invitation :

- **Observateur** — reçoit et affiche, ne peut rien modifier.
- **Contributeur** — peut proposer une manche ; l'hôte l'accepte automatiquement si elle est
  valide.

Pourquoi un hôte autoritaire plutôt qu'une réplication pair-à-pair symétrique : le journal
d'événements rendrait techniquement la seconde possible, mais elle impose de gérer les
partitions réseau (deux sous-groupes qui divergent), l'élection d'un nouveau maître si l'hôte
part, et une interface pour arbitrer les conflits. Pour quelques téléphones à un mètre les uns
des autres pendant une heure, le rapport coût/bénéfice est mauvais. La décision est
[ADR-0008](13-decisions-adr.md) et ne change pas avec le choix de transport.

Elle reste réversible : le protocole étant un journal d'événements commutatif, passer à une
réplication symétrique plus tard ne changerait ni le format des messages, ni le modèle de
données.

## Abstraction de transport

`Sync` expose un protocole unique, et deux implémentations interchangeables derrière lui —
c'est la même idée que `GameRules` pour le moteur : une interface stable, plusieurs moteurs.

```swift
public protocol Transport: Sendable {
    /// Découvre les hôtes annonçant une partie, pendant la fenêtre donnée.
    func discover(timeout: Duration) -> AsyncStream<DiscoveredHost>
    /// Annonce cette partie aux appareils à portée.
    func advertise(matchID: UUID, gameID: String, participantCount: Int) async throws
    func stopAdvertising() async
    /// Connexions entrantes acceptées côté hôte (une par pair qui rejoint).
    func acceptIncoming() -> AsyncStream<any TransportSession>
    /// Connexion sortante côté pair qui rejoint — le code d'appairage n'y intervient pas : il
    /// n'est utilisé qu'ensuite, par `LiveSession`, pour dériver la clé de chiffrement.
    func connect(to host: DiscoveredHost) async throws -> any TransportSession
}

public protocol TransportSession: Sendable {
    var incoming: AsyncStream<Data> { get }
    func send(_ data: Data) async throws
    func close() async
}
```

`WifiTransport` (implémenté) et `BLETransport` (à venir) implémenteront chacun ce protocole.
`LiveSession` (dans `Sync`) ne connaît que `Transport` — elle ignore lequel des deux est actif,
exactement comme `MatchEngine` ignore quel `GameRules` elle appelle.

## Sélection du transport

**État actuel : Wi-Fi seul dans l'app.** `BLETransport` est écrit (`CaCompteKit/Sources/Sync/BLETransport.swift`)
mais rien dans `ShareSessionView`/`JoinMatchView` ne l'utilise encore — l'orchestration
Wi-Fi-puis-BLE décrite par `ADR-0014` (essayer le Wi-Fi, retomber sur le BLE si aucun hôte
trouvé) reste à écrire une fois ce transport validé sur appareils réels. Pour l'instant :

```
Hôte (Marion)                                          Rejoint (Théo)
 │
 ├─ advertise() sur Wi-Fi (mDNS)
 │  affiche : code d'appairage à 6 chiffres
 │
 │                                                       ├─ discover() sur Wi-Fi, ~60 s,
 │                                                       │  dédoublonné par matchID
 │                                                       ├─ saisit le code d'appairage,
 │                                                       │  choisit son rôle
 │◀──────────────────────────────────────────────────────┤  connect(host) puis attachToHost(...)
 │  connexion établie                                        (le code ne sert qu'au chiffrement,
 │                                                             pas à la connexion elle-même)
```

Le code s'affiche aussi en QR (`QRCodeView`, `CIFilter.qrCodeGenerator()` — système, zéro
dépendance) et se scanne de deux façons : un scanner intégré à l'écran « Rejoindre une partie »
(`QRScannerView`, `AVCaptureMetadataOutput`), ou l'appareil photo système via le schéma d'URL
personnalisé `cacompte://join?matchID=…&code=…` (`JoinLink`). Un schéma personnalisé plutôt qu'un
lien universel `https://` : ce dernier demanderait de posséder un nom de domaine et d'y héberger
un fichier de vérification (Associated Domains/App Links) — hors de portée pour l'instant. En
échange, l'ouverture depuis l'appareil photo système n'est garantie que sur iOS (Camera propose
« Ouvrir dans Ça Compte » pour un schéma personnalisé si l'app est installée) ; le scanner intégré
reste le chemin fiable sur toutes les plateformes, y compris une future version Android. Dans les
deux cas, le QR ne remplace que la frappe des 6 chiffres — la découverte Wi-Fi (ou BLE) reste
indispensable pour établir la connexion elle-même, et le rôle (observateur/contributeur) se
choisit toujours explicitement une fois l'hôte reconnu.

Aucune bascule de transport en cours de session, même une fois le BLE ajouté : si le transport
actif est perdu (Théo sort de portée Wi-Fi), l'app relance simplement la découverte depuis zéro
et peut retomber sur l'autre transport — traité comme une reconnexion normale (voir plus bas),
pas comme un handoff.

### `BLETransport` — conçu, non vérifié par exécution

Mêmes rôles que le Wi-Fi : l'hôte est le périphérique GATT (`CBPeripheralManager`, annonce et
sert les données), qui rejoint est le central (`CBCentralManager`, scanne et se connecte).

**La découverte ne peut pas fonctionner comme en Wi-Fi.** Un paquet d'annonce BLE ne porte que
31 octets au total, déjà presque entièrement pris par un UUID de service 128 bits — impossible
d'y glisser `gameID`/`participantCount`/`deviceName` comme dans le TXT record mDNS. La
découverte se fait donc en deux temps : l'annonce ne contient que l'UUID de service, puis
chaque périphérique trouvé est connecté brièvement pour lire une caractéristique d'info (JSON,
les mêmes champs qu'un `DiscoveredHost`), avant d'être déconnecté si l'utilisateur ne le
sélectionne pas. `connect(to:)` se reconnecte ensuite proprement — cette connexion de lecture
n'est jamais réutilisée pour la session elle-même.

**Cadrage.** Comme le Wi-Fi, un préfixe de longueur 4 octets délimite chaque `WireMessage`, mais
il doit en plus être découpé en morceaux de la taille d'une écriture de caractéristique (180
octets, une valeur prudente sous la plupart des tailles de MTU négociées) — une caractéristique
BLE ne transporte jamais un flux continu comme une socket TCP.

**Limite de plateforme actée, pas un bug** : `CBPeripheralManager` n'offre aucun moyen de couper
la connexion d'un central précis — seul le central peut se déconnecter lui-même. Côté hôte,
`close()` ne peut donc qu'arrêter d'écouter localement, sans réellement fermer le lien radio du
pair qui a quitté (contrairement au Wi-Fi, où fermer la `NWConnection` ferme la vraie connexion
des deux côtés).

**Pourquoi « non vérifié » plutôt que « testé »** : contrairement à `WifiTransport` (validé par
un harnais macOS autonome), le Bluetooth ne se prête pas à l'auto-test en self-communication sur
une seule machine — essayé explicitement avec un harnais similaire (périphérique et central dans
le même process) : l'autorisation système Bluetooth est accordée des deux côtés
(`CBCentralManager.authorization`/`CBPeripheralManager.authorization` retournent `.allowed`),
mais la découverte locale n'aboutit jamais, vraisemblablement une limite du framework en
self-discovery plutôt qu'un bug de code. Le simulateur iOS n'a de toute façon aucun support
Bluetooth. La recette se fait sur deux appareils physiques.

## Protocole applicatif

Un seul type de message, versionné, encodé en JSON compact et compressé, **identique quel que
soit le transport actif** — c'est la couche qui ne change jamais, celle que Wi-Fi et BLE
transportent aussi bien l'une que l'autre.

```swift
public struct WireMessage: Codable, Sendable {
    public let protocolVersion: Int          // 1
    public let matchID: UUID
    public let kind: Kind

    public enum Kind: Codable, Sendable {
        case hello(deviceName: String, appVersion: String, platform: Platform, role: Role, deviceID: String)
        case welcome(log: [StampedEvent], role: Role)   // hôte → nouveau pair, journal complet
        case events([StampedEvent])                     // diffusion
        case proposal([StampedEvent])                    // contributeur → hôte
        case rejection(eventID: UUID, reason: String)
        case heartbeat(lamport: UInt64)
        case goodbye
    }

    public enum Platform: String, Codable, Sendable { case apple, android }
}
```

`hello` porte `deviceID` — le même identifiant qui horodate les `StampedEvent` du pair
(`StampedEvent.deviceID`) — pour que l'hôte puisse relier « cette manche vient de X » à « X,
c'est Théo » et notifier (doc utilisateur : sans ça, une manche distante se contente de faire
monter les totaux sans expliquer pourquoi). Republié dans `LiveSession.ConnectedPeer`, `nil` tant
que le `hello` n'est pas encore arrivé.

`welcome` transporte le **journal d'événements** (`[StampedEvent]`), pas un type d'instantané
séparé : le nouveau pair appelle `MatchEngine.replay(log:)` en local, exactement comme au
lancement de l'app — une seule façon de reconstruire un `MatchState`, jamais deux. Un instantané
de partie pèse quelques kilo-octets, largement dans le budget des deux transports.

**Séquence de connexion**

```
Théo                                     Marion (hôte)
 │── connect(host) ─────────────────────▶│  transport.connect, sans le code
 │── attachToHost(…, pairingCode) ──────▶│  dérive la clé localement, envoie hello
 │── hello(role) ───────────────────────▶│
 │◀── welcome(log, role) ────────────────│  état complet, une seule fois
 │                                       │
 │◀── events([roundCommitted]) ──────────│  incréments ensuite
```

**Code erroné ou hôte injoignable.** `attachToHost` attend la confirmation `welcome` avant de
retourner, avec un délai de 8 secondes. Sans ce délai explicite, un code erroné ne produisait
*aucune* erreur : le `hello` chiffré avec la mauvaise clé arrive bien à l'hôte, qui ne peut
simplement pas le déchiffrer et ne répond donc jamais — l'écran restait sur « Connexion à la
partie… » indéfiniment, sans qu'on sache qu'autre chose avait échoué. Passé ce délai,
`attachToHost` lève `SessionError.noResponseFromHost`, distingué de `WifiTransportError.hostNotFound`
(l'hôte a disparu du réseau avant même la tentative de connexion) — deux messages différents
affichés à l'utilisateur plutôt qu'un seul générique « vérifie le code », qui avait fait perdre
du temps en recette à distinguer un vrai problème réseau d'un code mal saisi.

**Une manche saisie par un contributeur**

```
David (Android)                        Marion (hôte, iPhone)
 │── proposal([roundCommitted]) ──────▶│
 │                                     │  rules.validate(…)
 │                                     │  ├─ valide  → reduce, persiste
 │◀── events([roundCommitted]) ────────│  │           puis rediffuse à tous
 │                                     │  └─ invalide
 │◀── rejection(eventID, reason) ──────│
```

Le contributeur applique **optimistement** l'événement en local et l'annule si une `rejection`
arrive. Sur Wi-Fi local la latence est de quelques millisecondes ; sur BLE elle reste sous la
seconde. L'annulation ne sera visible que dans des cas pathologiques.

**L'annulation sur rejet doit vraiment annuler.** Une première version affichait le message de
rejet (`latestRejectionReason`) sans jamais retirer l'événement optimiste du journal local
(`SharedMatchModel.apply`, déduplication par id) : la manche restait affichée comme validée
malgré le rejet, donnant l'impression qu'aucune validation n'avait lieu côté hôte — alors
qu'elle avait bien lieu, seul l'affichage ne la reflétait pas. Corrigé : une `rejection` retire
l'événement du journal par son id et rejoue, ce qui annule visuellement la manche proposée.

**Reconnexion.** Un pair qui perd la connexion (poche, mise en veille, sortie de portée) relance
`discover()` et reçoit un `welcome` complet à la reconnexion. Pas de reprise incrémentale : un
instantané de partie pèse quelques kilo-octets, la complexité d'un delta ne se justifie pas.

**Départ explicite d'un pair.** `LiveSession.leave()` (pair) envoie `goodbye` puis **ferme
réellement la connexion** — les deux étapes comptent. Une première version ne fermait que la
référence locale à la session sans jamais fermer le socket sous-jacent : l'hôte ne voyait alors
jamais la connexion se terminer et continuait de lister ce pair comme connecté longtemps après
qu'il ait quitté l'écran (bug trouvé en recette sur appareils réels). Symétriquement,
`LiveSession.stopHosting()` (hôte) prévient chaque pair connecté puis ferme chaque connexion une
par une, pour la même raison.

**Fin de partie.** Une partie qui se conclut (fin normale, fin manuelle, abandon) arrête
automatiquement le partage côté hôte, juste après avoir diffusé l'état final aux pairs
connectés. Une première version ne le faisait pas : l'hôte continuait d'annoncer la partie sur
le réseau — visible et rejoignable depuis un autre appareil — longtemps après sa fin (bug trouvé
en recette). Côté pair, `SharedMatchView` distingue ce cas (« La partie est terminée. ») d'une
vraie perte de connexion (« Connexion à l'hôte perdue. ») via le statut du dernier `MatchState`
reçu — les deux se traduisent par la même coupure de connexion, mais une seule est un problème.

**Crash au premier plan après une mise en arrière-plan.** `NWListener`/`NWConnection` exposent
leur changement d'état via un `stateUpdateHandler` **persistant** : il continue de recevoir des
transitions bien après la toute première (`.ready`, résolue une fois pour établir la connexion).
Une mise en arrière-plan puis un retour au premier plan produit typiquement une nouvelle
transition (`.failed`/`.cancelled`) sur ce même handler — qui tentait alors de résoudre une
seconde fois une `CheckedContinuation` déjà résolue, ce qui **crashe systématiquement** (une
continuation ne tolère qu'une seule résolution). Corrigé aux deux endroits concernés
(`WifiTransport.advertise`, `WifiTransportSession.waitUntilReady`) : le handler se retire
lui-même dès sa première résolution, sur toutes les branches.

**La feuille « Rejoindre une partie » ne doit pas se fermer par balayage.** Une fermeture
interactive contournerait `SharedMatchModel.stop()` (qui appelle `LiveSession.leave()`) : la
connexion resterait ouverte sans que l'hôte ne le voie jamais — le même bug de pair fantôme déjà
corrigé pour un vrai tap sur « Quitter », mais par un autre chemin. `.interactiveDismissDisabled(true)`
force le passage par le bouton, qui nettoie correctement.

**Encourager le Wi-Fi plutôt que chercher dans le vide.** Wi-Fi coupé, `discover()`/`advertise()`
ne trouvent jamais rien ni personne, sans jamais le dire. `WiFiAvailability`
(`NWPathMonitor(requiredInterfaceType: .wifi)`, ignore la cellulaire — ce qui compte pour
mDNS/DNS-SD est l'interface locale, pas l'accès Internet) affiche un message explicite des deux
côtés (« Rejoindre » et « Partager ») invitant à activer le Wi-Fi, plutôt qu'un état « recherche »
qui ne dit jamais pourquoi il ne trouve rien. Pas encore de proposition de repli Bluetooth : ce
message évoluera une fois `BLETransport` branché.

**Départ de l'hôte.** La partie n'est pas perdue : chaque pair détient l'état complet en
mémoire. L'interface propose « Reprendre la partie sur cet appareil », ce qui crée une copie
locale persistée sous un nouveau `matchID`. Pas d'élection automatique — un choix explicite est
plus simple et plus prévisible qu'une bascule silencieuse.

## Horloge de Lamport

Chaque pair maintient un compteur :

- à chaque événement émis : `lamport += 1` ;
- à chaque événement reçu : `lamport = max(lamport, reçu) + 1`.

Le tri final se fait sur `(lamport, deviceID)`. `deviceID` est un `UUID` stable stocké de façon
durable et privée (Trousseau iOS, Keystore/`EncryptedSharedPreferences` Android), ce qui
départage de façon déterministe et identique sur tous les pairs — condition nécessaire pour que
le rejeu converge, quelle que soit la plateforme de chaque pair.

L'horloge murale (`occurredAt`) n'entre jamais dans l'ordonnancement. Deux appareils n'ont pas la
même heure, et un utilisateur peut changer la sienne en cours de partie.

## Appairage et chiffrement

MultipeerConnectivity et Nearby Connections chiffraient le transport pour nous, gratuitement.
Un socket TCP ou une caractéristique GATT ne chiffrent rien par défaut : cette couche doit être
reconstruite, la même pour les deux transports.

- L'hôte génère un **code d'appairage à 6 chiffres** à la création du partage (affiché en clair,
  aussi encodé dans un QR avec le `matchID` pour éviter la saisie).
- Le pair qui rejoint saisit ou scanne ce code **avant** toute connexion.
- Les deux côtés dérivent localement, par HKDF, une clé de session AES-GCM à partir du code —
  **le code ne transite jamais sur le réseau**, seul son résultat (la capacité à déchiffrer)
  prouve qu'on le connaît.
- Chaque `WireMessage` est chiffré avec cette clé avant émission, sur les deux transports.
  `CryptoKit` côté Apple, `javax.crypto` (AES/GCM, HMAC pour HKDF) côté Android — aucune
  dépendance tierce des deux côtés.

Ce mécanisme remplace aussi l'ancienne UX d'invitation MultipeerConnectivity (accepter un pair
identifié par son nom d'appareil) : le code d'appairage est **le** geste d'invitation, identique
sur Wi-Fi et sur BLE, identique sur Apple et Android.

## Configuration requise

**Apple** — `Info.plist`. Deux clés déjà en place pour le Wi-Fi (`App/Info.plist`) :

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Ça Compte utilise le réseau local pour partager la partie en cours avec les
appareils autour de la table. Aucune donnée ne quitte votre réseau.</string>

<key>NSBonjourServices</key>
<array>
    <string>_cacompte._tcp</string>
</array>
```

Une troisième, déjà présente dans `App/Info.plist` bien que `BLETransport` ne soit pas encore
appelé depuis l'app :

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Ça Compte utilise le Bluetooth pour partager la partie en cours quand aucun réseau
Wi-Fi commun n'est disponible.</string>
```

Contraintes à respecter :

- `serviceType` mDNS : 1 à 15 caractères, minuscules, chiffres et tirets — `"cacompte"`.
- UUID de service GATT dédié, généré une fois pour le projet (ex. `515FCEDB-1A0E-442A-A323-CF7E31FC5290`), identique côté Android.
- 8 pairs connectés au maximum, cohérent avec le maximum de joueurs du catalogue — à vérifier
  tôt côté BLE, où le nombre de connexions périphériques simultanées dépend du chipset et n'est
  pas garanti par la plateforme comme sur Wi-Fi.
- Le contexte d'annonce est plafonné (mDNS TXT record, ou payload d'annonce BLE ~31 o) : on y met
  l'identifiant de partie, le nom du jeu et le nombre de joueurs, jamais le journal.

**Android** — permissions runtime `BLUETOOTH_SCAN`, `BLUETOOTH_ADVERTISE`, `BLUETOOTH_CONNECT`
(Android 12+) et `NEARBY_WIFI_DEVICES` (Android 13+) en plus de l'accès réseau local.

## Sécurité et vie privée

- Portée strictement locale : rien ne quitte le Wi-Fi ou le Bluetooth de la pièce, sur aucun des
  deux transports.
- Chaque `WireMessage` est chiffré de bout en bout par la clé dérivée du code d'appairage (voir
  plus haut) — ni un tiers sur le même Wi-Fi, ni un appareil BLE à portée ne peut lire le trafic
  sans connaître ce code.
- Aucune donnée personnelle transmise hors de la partie en cours : seuls les pseudos des
  participants circulent (`Participant` ne porte ni avatar ni photo, uniquement `id`,
  `displayName`, `seatIndex`, `teamID`) — jamais la liste complète des fiches joueurs, les
  avatars, ni l'historique.
- L'invitation reste explicite des deux côtés — l'hôte affiche le code, le pair le saisit ou le
  scanne.
- Les autorisations réseau local / Bluetooth sont demandées au premier usage de la fonctionnalité,
  jamais au lancement. Un refus n'affecte rien d'autre : voir « Dégradation ».

## Dégradation

La partie partagée est un **supplément**, jamais un prérequis. Si aucun des deux transports
n'est disponible — autorisations refusées, Bluetooth coupé, aucun Wi-Fi commun, appareil non
compatible — l'écran de partie fonctionne à l'identique en solo. Aucun chemin de code du moteur
ni de la persistance ne dépend de `Sync`, ce que garantit le graphe de dépendances du package :
`Store` n'importe pas `Sync`.

## Tests

- **Sans réseau** : deux instances de `LiveSession` reliées par un transport en mémoire
  (`InMemoryTransport`, un troisième cas du protocole `Transport`, réservé aux tests). Couvre
  convergence, idempotence, ordre inversé, doublons — indépendant de savoir lequel de Wi-Fi ou
  BLE serait actif en vrai. 10 tests, `CaCompteKit/Tests/SyncTests`.
- **Propriété testée** : pour tout journal `L` et toute permutation `σ`,
  `replay(L) == replay(σ(L))`. Vérifiée sur des permutations aléatoires via des tests
  paramétrés Swift Testing (et Kotest côté Android).
- **`WifiTransport` réel, hors bac à sable de test** : un bundle `.xctest` n'a pas les
  entitlements réseau local d'une vraie app (`NSLocalNetworkUsageDescription`/`NSBonjourServices`
  du bundle réel), donc `NWListener`/`NetService` y échouent silencieusement — confirmé en
  isolant le problème avec un exécutable macOS autonome, hors tout bac à sable, où la découverte
  et l'échange de messages fonctionnent bout en bout. `WifiTransport` est donc vérifié par ce
  harnais séparé plutôt que par `SyncTests`, qui ne peut pas l'héberger.
- **Sur appareils réels (iPhone + iPad)** : partage Wi-Fi testé de bout en bout, y compris en
  observateur et en contributeur. Deux problèmes trouvés et corrigés directement en recette :
  un pair qui quitte restait listé comme connecté chez l'hôte (rien ne fermait jamais le socket
  — voir « Départ explicite d'un pair » plus haut), et un code d'appairage erroné ou un hôte
  injoignable ne produisait aucune erreur claire (voir « Code erroné ou hôte injoignable »).
  Reste à tester : Bluetooth (BLE pas encore implémenté), Android, mise en veille et mode avion
  en cours de partie. Non automatisable, inscrit à la check-list de recette de la Phase 9.
- **Golden du protocole** (`spec/wire/`) : pas encore fait. Resterait à écrire pour garantir que
  Swift et Kotlin produisent des octets JSON identiques pour un même `WireMessage`, sur le
  modèle des golden files de jeu — pertinent surtout une fois le portage Android entamé.

import Foundation

/// Doc utilisateur, révisé P9 — code d'appairage encodé en lien, pour éviter la saisie manuelle.
/// Contenu minimal : le code d'appairage lui-même — `SupabaseTransport.resolveGame(code:)` résout
/// tout le reste (matchID, jeu, nombre de joueurs, nom de l'appareil) à partir de ce seul code, ce
/// lien ne fait que remplacer la frappe des 6 chiffres.
///
/// Schéma personnalisé (`cacompte://`) plutôt qu'un lien universel `https://` : ce dernier
/// demanderait de posséder un nom de domaine et d'y héberger un fichier de vérification
/// (Associated Domains/App Links), une dépendance externe hors de portée pour l'instant. En
/// échange, l'ouverture depuis l'appareil photo système n'est garantie que sur iOS (Camera
/// propose « Ouvrir dans Ça Compte » pour un schéma personnalisé si l'app est installée) ; le
/// scanner intégré (`QRScannerView`) reste le chemin fiable sur toutes les plateformes.
enum JoinLink {
    private static let scheme = "cacompte"
    private static let host = "join"

    struct Payload: Equatable {
        let pairingCode: String
    }

    static func url(pairingCode: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [
            URLQueryItem(name: "code", value: pairingCode),
        ]
        return components.url
    }

    static func parse(_ url: URL) -> Payload? {
        guard url.scheme == scheme, url.host == host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems,
              let code = items.first(where: { $0.name == "code" })?.value else { return nil }
        return Payload(pairingCode: code)
    }
}

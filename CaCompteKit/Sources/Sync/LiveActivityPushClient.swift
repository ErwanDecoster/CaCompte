import Foundation
import Supabase

/// Doc utilisateur P9 — seul moyen fourni par Apple de rafraîchir une Live Activity (écran
/// verrouillé / Dynamic Island) pendant que l'app est suspendue en arrière-plan : un push APNs
/// dédié, envoyé par une fonction Edge Supabase (`supabase/functions/cacompte-live-activity-push`) plutôt
/// que par l'app elle-même (qui ne tourne justement plus à ce moment-là). Générique sur le contenu
/// (`some Encodable`) plutôt que sur `Domain.MatchActivityAttributes.ContentState` directement :
/// ce type n'existe que sous `#if os(iOS)` (`ActivityKit` indisponible sur macOS, dont `Domain`
/// doit rester buildable), alors que `Sync` cible aussi macOS — l'appelant (App, iOS uniquement)
/// passe son `ContentState` concret, `Sync` n'a besoin de rien en connaître de plus que `Encodable`.
public enum LiveActivityPushClient {
    private static let client = SupabaseClient(
        supabaseURL: SupabaseSyncConfig.projectURL, supabaseKey: SupabaseSyncConfig.anonKey)

    private struct TokenRow: Encodable {
        let matchID: UUID
        let deviceID: String
        let pushToken: String

        enum CodingKeys: String, CodingKey {
            case matchID = "match_id"
            case deviceID = "device_id"
            case pushToken = "push_token"
        }
    }

    /// Doc utilisateur — appelé à chaque rotation de jeton signalée par
    /// `Activity.pushTokenUpdates` (création de la Live Activity, ou rotation ultérieure par
    /// iOS) : `upsert` sur la clé primaire `(match_id, device_id)` remplace toujours l'ancien
    /// jeton plutôt que d'en accumuler plusieurs par appareil.
    ///
    /// `returning: .minimal` explicite — sans policy `select` pour l'anon sur cette table
    /// (volontaire, `supabase/migrations`), le comportement par défaut de `upsert`
    /// (`.representation`, qui tente de relire la ligne pour construire la réponse) échoue avec
    /// une erreur RLS trompeuse même quand l'insert a réellement eu lieu.
    public static func registerToken(matchID: UUID, deviceID: String, pushToken: String) async {
        print("[LiveActivityPushClient] BUILD-MARKER-MINIMAL-FIX registerToken called")
        do {
            try await client.from("cacompte_live_activity_tokens")
                .upsert(
                    TokenRow(matchID: matchID, deviceID: deviceID, pushToken: pushToken),
                    onConflict: "match_id,device_id",
                    returning: .minimal
                )
                .execute()
            print("[LiveActivityPushClient] registerToken OK match=\(matchID) device=\(deviceID)")
        } catch {
            print("[LiveActivityPushClient] registerToken FAILED: \(error)")
        }
    }

    private struct PushBody<Content: Encodable>: Encodable {
        let matchID: UUID
        let event: String
        let contentState: Content
    }

    /// Doc utilisateur — n'appeler que côté hôte (seul appareil qui fait foi sur le journal,
    /// `LiveMatchModel`) : un pair qui pousserait aussi créerait des mises à jour concurrentes et
    /// redondantes pour la même partie. Best-effort : une fonction Edge indisponible ou un jeton
    /// périmé ne doit jamais faire échouer la validation d'une manche, seulement priver le pair
    /// concerné d'une mise à jour en arrière-plan (son prochain retour au premier plan
    /// resynchronise de toute façon tout via `MatchConnectionCoordinator`).
    public static func push(matchID: UUID, event: String, contentState: some Encodable) async {
        guard
            let url = URL(
                string:
                    "\(SupabaseSyncConfig.projectURL.absoluteString)/functions/v1/cacompte-live-activity-push"
            )
        else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "Bearer \(SupabaseSyncConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(
            PushBody(matchID: matchID, event: event, contentState: contentState))
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("[LiveActivityPushClient] push status=\(status) body=\(String(data: data, encoding: .utf8) ?? "?")")
        } catch {
            print("[LiveActivityPushClient] push FAILED: \(error)")
        }
    }
}

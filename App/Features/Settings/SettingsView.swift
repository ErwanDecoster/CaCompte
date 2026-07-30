import DesignSystem
import Store
import SwiftUI

/// Doc 03 : « La sync est désactivable : un utilisateur qui refuse iCloud garde une app
/// pleinement fonctionnelle. Le basculement recrée le `ModelContainer` ; ce n'est pas une
/// migration. » — géré par `CaCompteApp`, qui observe `AppSettings.iCloudSyncEnabled`.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            @Bindable var settings = settings
            Form {
                Section {
                    Toggle("Synchronisation iCloud", isOn: $settings.iCloudSyncEnabled)
                        .tint(.brandInk)
                } footer: {
                    Text("Synchronise les joueurs et les parties entre tes appareils via iCloud. Désactivée, l'app reste pleinement fonctionnelle en local. Le changement s'applique au prochain lancement de l'app.")
                }

                Section {
                    Picker("Tri des joueurs", selection: $settings.playerSortMode) {
                        Text("Automatique").tag(AppSettings.PlayerSortMode.automatic)
                        Text("Manuel").tag(AppSettings.PlayerSortMode.manual)
                    }
                } footer: {
                    Text("Automatique : les joueurs les plus actifs (nombre de parties jouées) en premier. Manuel : réordonne-les toi-même dans l'onglet Joueurs.")
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}

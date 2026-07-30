import WidgetKit
import SwiftUI

@main
struct CaCompteWidgetBundle: WidgetBundle {
    var body: some Widget {
        MatchWidget()
        MatchLiveActivityWidget()
    }
}

import SwiftUI

struct RootView: View {
    @Bindable private var navigator = AppNavigator.shared

    var body: some View {
        TabView(selection: $navigator.tab) {
            Tab("Runs", systemImage: "figure.run", value: AppTab.runs) {
                RunsView()
            }
            Tab("Generate", systemImage: "point.topleft.down.to.point.bottomright.curvepath", value: AppTab.generate) {
                GenerateView()
            }
            Tab("Saved", systemImage: "bookmark", value: AppTab.saved) {
                SavedRoutesView()
            }
        }
    }
}

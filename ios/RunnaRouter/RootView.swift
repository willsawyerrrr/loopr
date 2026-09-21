import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Generate", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                GenerateView()
            }
            Tab("Saved", systemImage: "bookmark") {
                SavedRoutesView()
            }
        }
    }
}

import FocusFlowCore
import SwiftUI

@main
struct FocusFlowApp: App {
    @StateObject private var model = FocusFlowAppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.titleBar)
    }
}

import SwiftUI

/// 运行中的应用列表视图
struct RunningAppsView: View {
    @EnvironmentObject private var viewModel: InputMethodManager
    
    var body: some View {
        Section(TypeSwitchStrings.Apps.Section.runningCount(viewModel.runningApps.count)) {
            ForEach(viewModel.runningApps) { app in
                AppRowView(app: app)
            }
        }
    }
}

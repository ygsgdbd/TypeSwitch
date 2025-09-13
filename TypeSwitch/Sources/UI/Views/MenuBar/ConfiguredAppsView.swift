import SwiftUI

/// 已配置的应用列表视图
struct ConfiguredAppsView: View {
    @EnvironmentObject private var viewModel: InputMethodManager
    
    var body: some View {
        Section {
            Menu(TypeSwitchStrings.Apps.Section.configuredCount(viewModel.configuredApps.count)) {
                ForEach(viewModel.configuredApps) { app in
                    AppRowView(app: app)
                }
            }
        }
    }
}

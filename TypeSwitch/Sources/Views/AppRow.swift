import SwiftUI
import SwiftUIX

struct AppRow: View {
    let app: AppInfo
    
    var body: some View {
        HStack {
            HStack(spacing: 16) {
                AppIcon(app: app)
                    .equatable()
                AppName(app: app)
                    .equatable()
            }
            Spacer()
            InputMethodPicker(app: app)
        }
    }
}

private struct AppIcon: View, Equatable {
    let app: AppInfo
    
    static func == (lhs: AppIcon, rhs: AppIcon) -> Bool {
        lhs.app.bundleId == rhs.app.bundleId
    }
    
    var body: some View {
        app.icon
            .resizable()
            .aspectRatio(contentMode: .fit)
            .squareFrame(sideLength: 26)
    }
}

private struct AppName: View, Equatable {
    let app: AppInfo
    
    static func == (lhs: AppName, rhs: AppName) -> Bool {
        lhs.app.bundleId == rhs.app.bundleId
    }
    
    var body: some View {
        Text(app.name)
            .font(.system(size: 12))
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(width: 160, alignment: .leading)
    }
}

private struct InputMethodPicker: View {
    let app: AppInfo
    @EnvironmentObject private var viewModel: InputMethodManager
    
    var body: some View {
        Picker("", selection: makeBinding()) {
            Text("input_method.default".localized).tag("")
            ForEach(viewModel.inputMethods) { inputMethod in
                Text(inputMethod.name)
                    .font(.system(size: 11))
                    .tag(inputMethod.id)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(width: 200)
    }
    
    private func makeBinding() -> Binding<String> {
        Binding(
            get: { [app, viewModel] in
                viewModel.appSettings[app.bundleId]?.flatMap { $0 } ?? ""
            },
            set: { [app, viewModel] newValue in
                if newValue.isEmpty {
                    viewModel.appSettings[app.bundleId] = nil
                } else {
                    viewModel.appSettings[app.bundleId] = newValue
                }
            }
        )
    }
} 

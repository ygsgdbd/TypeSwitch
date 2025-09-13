import SwiftUI
import SwiftUIX

/// 应用行视图，处理单个应用的显示和输入法选择
struct AppRowView: View {
    let app: AppInfo
    @EnvironmentObject private var viewModel: InputMethodManager
    
    var body: some View {
        Menu {
            // 默认输入法选项
            Button(action: {
                viewModel.setInputMethod(for: app, to: nil)
            }) {
                if viewModel.getInputMethod(for: app) == nil {
                    Image(systemName: .checkmark)
                }
                Text(TypeSwitchStrings.InputMethod.defaultOption)
            }
            
            Divider()
            
            // 已安装的输入法选项
            ForEach(viewModel.inputMethods, id: \.id) { inputMethod in
                Button(action: {
                    viewModel.setInputMethod(for: app, to: inputMethod.id)
                }) {
                    if viewModel.getInputMethod(for: app) == inputMethod.id {
                        Image(systemName: .checkmark)
                    }
                    Text(inputMethod.name)
                }
            }
        } label: {
            // 应用行标签内容
            app.icon
            Text(app.name)
            viewModel.getSelectedInputMethodName(for: app).ifSome { Text($0) }
        }
    }
}

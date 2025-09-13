    @Published var inputMethods: [InputMethod] = []
    @Published var installedApps: [AppInfo] = []
    @Shared(.appStorage("appInputMethodSettings")) var appSettings: [String: String?] = [:]
    
    // UI 状态
    @Published var searchText = ""

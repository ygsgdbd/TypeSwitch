    private func selectInputMethod(_ inputMethodId: String) async {
        if inputMethodId.isEmpty {
            Task {
                await viewModel.setInputMethod(for: app, to: nil)
                withAnimation(.easeInOut(duration: 0.15)) {
                    // UI updates here
                }
            }
        } else {
            Task {
                await viewModel.setInputMethod(for: app, to: inputMethodId)
                withAnimation(.easeInOut(duration: 0.15)) {
                    // UI updates here
                }
            }
        }
    }

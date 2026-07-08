import AppKit
import SwiftUI

struct AboutWindowView: View {
    let appVersion: String
    let repositoryDisplayName: String
    let licenseName: String
    let copyright: String
    let openRepository: @MainActor () -> Void
    let closeWindow: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(spacing: 3) {
                    Text("TypeSwitch")
                        .font(.headline)
                    Text(appVersion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 12) {
                Text(TypeSwitchStrings.App.About.summary)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(title: TypeSwitchStrings.App.About.repositoryTitle) {
                        Button(repositoryDisplayName) {
                            openRepository()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    }

                    InfoRow(title: TypeSwitchStrings.App.About.licenseTitle) {
                        Text(licenseName)
                            .lineLimit(1)
                    }

                    InfoRow(title: TypeSwitchStrings.App.About.copyrightTitle) {
                        Text(copyright)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                Spacer()
                Button(TypeSwitchStrings.App.About.close) {
                    closeWindow()
                }
                .keyboardShortcut(.cancelAction)

                Button(TypeSwitchStrings.App.About.openRepository) {
                    openRepository()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(EdgeInsets(top: 22, leading: 24, bottom: 20, trailing: 24))
        .frame(width: 380, height: 320)
    }
}

private struct InfoRow<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

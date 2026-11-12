import AppKit
import SwiftUI

struct SettingsView: View {
    @State private var copied = false
    private let folder = FolderSync.shared.library.root

    /// The MCP server ships inside the app bundle.
    static var mcpCommand: String {
        let path = Bundle.main.url(forAuxiliaryExecutable: "litto-mcp")?.path ?? "/Applications/Litto.app/Contents/MacOS/litto-mcp"
        return "claude mcp add --scope user litto -- '\(path)'"
    }

    var body: some View {
        Form {
            Section("Claude") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("So Claude can create and fix your decks, run this once in Terminal:")
                    Text(Self.mcpCommand)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                    Button(copied ? "Copied" : "Copy command", systemImage: copied ? "checkmark" : "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Self.mcpCommand, forType: .string)
                        copied = true
                    }
                }
            }
            StudySettingsSection()
            Section("Shared folder") {
                LabeledContent("Decks and images") {
                    HStack {
                        Text(folder.path).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                        Button("Show") { NSWorkspace.shared.open(folder) }
                    }
                }
                if let error = FolderSync.shared.lastError {
                    Label(error, systemImage: "exclamationmark.circle")
                        .foregroundStyle(LittoStyle.danger)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
    }
}

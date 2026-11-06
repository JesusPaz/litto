import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage("autoSpeak") private var autoSpeak = true
    private let folder = FolderSync.shared.library.root

    var body: some View {
        Form {
            Toggle("Leer la palabra en voz alta al mostrarla", isOn: $autoSpeak)
            LabeledContent("Carpeta de mazos") {
                HStack {
                    Text(folder.path).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                    Button("Mostrar") { NSWorkspace.shared.open(folder) }
                }
            }
            if let error = FolderSync.shared.lastError {
                LabeledContent("Último error", value: error)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
    }
}

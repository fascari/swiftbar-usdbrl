import AppKit

import SwiftUI

@main
struct ConverterApp: App {
    @NSApplicationDelegateAdaptor(ConverterLifecycle.self) private var lifecycle
    @StateObject private var model = ConverterModel()

    var body: some Scene {
        WindowGroup("Payment converter") {
            ConverterView(draft: model)
                .frame(minWidth: 660, idealWidth: 730, minHeight: 610, idealHeight: 650)
                .task {
                    lifecycle.model = model
                    model.load()
                }
                .onOpenURL { url in model.select(url) }
        }
    }
}

@MainActor
final class ConverterLifecycle: NSObject, NSApplicationDelegate {
    weak var model: ConverterModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        if model.busy { return .terminateCancel }
        guard model.hasUnsavedChanges else { return .terminateNow }
        let warning = NSAlert()
        warning.messageText = model.text("Há alterações não salvas", "There are unsaved changes")
        warning.informativeText = model.text("Volte para concluir a edição ou descarte o rascunho.",
                                             "Go back to finish editing or discard the draft.")
        warning.addButton(withTitle: model.text("Voltar", "Go back"))
        warning.addButton(withTitle: model.text("Descartar", "Discard"))
        return warning.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}

import AppKit

/// The confirmation dialogs shown before a shelf is emptied.
///
/// Clearing deletes the copies EdgeShelf made and cannot be undone for text,
/// links and screenshots, so every entry point to it goes through here, and
/// every entry point asks the same question with the same wording.
enum ShelfConfirmation {

    /// Asks before emptying a single shelf.
    static func clearShelf() -> Bool {
        ask(title: L10n.clearShelfTitle, message: L10n.clearShelfConfirm)
    }

    /// Asks before emptying every shelf on every display.
    static func clearAllShelves() -> Bool {
        ask(title: L10n.removeAllTitle, message: L10n.removeAllInfo)
    }

    private static func ask(title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.cancel)
        alert.addButton(withTitle: L10n.removeAll)
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertSecondButtonReturn
    }
}

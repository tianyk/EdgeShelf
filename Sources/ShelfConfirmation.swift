import AppKit

/// The confirmation dialogs shown before a shelf is emptied.
///
/// Clearing removes items and deletes only files EdgeShelf itself stored
/// (pasted images, promised files, and legacy copies). User files are never
/// touched. It cannot be undone for text, links and images, so every entry
/// point asks the same question with the same wording.
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

import AppKit

final class PreferencesWindowController: NSWindowController {
    private let manager: ShelfManager
    private let prefs = Preferences.shared

    var onLanguageChanged: (() -> Void)?

    private let introLabel = NSTextField(wrappingLabelWithString: "")
    private let leftBox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let rightBox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let removeBox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let closeBox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let languageLabel = NSTextField(labelWithString: "")
    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let folderButton = NSButton(title: "", target: nil, action: nil)
    private let resetButton = NSButton(title: "", target: nil, action: nil)

    init(manager: ShelfManager) {
        self.manager = manager

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 340),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        buildUI()
        localizeUI()
        syncFromPreferences()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        introLabel.frame = NSRect(x: 24, y: 268, width: 432, height: 56)
        introLabel.font = .systemFont(ofSize: 11.5)
        introLabel.textColor = .secondaryLabelColor
        content.addSubview(introLabel)

        leftBox.frame = NSRect(x: 24, y: 236, width: 432, height: 22)
        leftBox.target = self
        leftBox.action = #selector(edgesChanged)
        content.addSubview(leftBox)

        rightBox.frame = NSRect(x: 24, y: 210, width: 432, height: 22)
        rightBox.target = self
        rightBox.action = #selector(edgesChanged)
        content.addSubview(rightBox)

        let separator = NSBox(frame: NSRect(x: 24, y: 194, width: 432, height: 1))
        separator.boxType = .separator
        content.addSubview(separator)

        removeBox.frame = NSRect(x: 24, y: 162, width: 432, height: 22)
        removeBox.target = self
        removeBox.action = #selector(behaviorChanged)
        content.addSubview(removeBox)

        closeBox.frame = NSRect(x: 24, y: 136, width: 432, height: 22)
        closeBox.target = self
        closeBox.action = #selector(behaviorChanged)
        content.addSubview(closeBox)

        languageLabel.frame = NSRect(x: 24, y: 96, width: 80, height: 22)
        languageLabel.font = .systemFont(ofSize: 13)
        content.addSubview(languageLabel)

        languagePopup.frame = NSRect(x: 112, y: 90, width: 240, height: 28)
        languagePopup.bezelStyle = .rounded
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)
        content.addSubview(languagePopup)

        folderButton.frame = NSRect(x: 24, y: 30, width: 210, height: 30)
        folderButton.bezelStyle = .rounded
        folderButton.font = .systemFont(ofSize: 12.5)
        folderButton.target = self
        folderButton.action = #selector(showDataFolder)
        content.addSubview(folderButton)

        resetButton.frame = NSRect(x: 242, y: 30, width: 210, height: 30)
        resetButton.bezelStyle = .rounded
        resetButton.font = .systemFont(ofSize: 12.5)
        resetButton.target = self
        resetButton.action = #selector(closeAllShelves)
        content.addSubview(resetButton)
    }

    private func localizeUI() {
        window?.title = L10n.prefsTitle
        introLabel.stringValue = L10n.prefsIntro
        leftBox.title = L10n.enableLeft
        rightBox.title = L10n.enableRight
        removeBox.title = L10n.removeAfterDragOut
        closeBox.title = L10n.closeWhenEmpty
        languageLabel.stringValue = L10n.languageLabel
        folderButton.title = L10n.showDataFolder
        resetButton.title = L10n.closeAllShelves
        rebuildLanguageMenu()
    }

    private func rebuildLanguageMenu() {
        languagePopup.removeAllItems()
        languagePopup.addItem(withTitle: L10n.followSystem)
        languagePopup.lastItem?.representedObject = AppLanguage.system.rawValue

        for language in [AppLanguage.english, .chinese, .french, .spanish, .russian, .arabic] {
            languagePopup.addItem(withTitle: language.nativeName)
            languagePopup.lastItem?.representedObject = language.rawValue
        }

        let selected = L10n.selectedLanguage
        if let item = languagePopup.itemArray.first(where: {
            ($0.representedObject as? String) == selected.rawValue
        }) {
            languagePopup.select(item)
        }
    }

    private func syncFromPreferences() {
        leftBox.state = prefs.leftEnabled ? .on : .off
        rightBox.state = prefs.rightEnabled ? .on : .off
        removeBox.state = prefs.removeAfterDragOut ? .on : .off
        closeBox.state = prefs.closeWhenEmpty ? .on : .off
    }

    func show() {
        localizeUI()
        syncFromPreferences()
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func edgesChanged() {
        prefs.leftEnabled = leftBox.state == .on
        prefs.rightEnabled = rightBox.state == .on
        manager.rebuildWindows()
    }

    @objc private func behaviorChanged() {
        prefs.removeAfterDragOut = removeBox.state == .on
        prefs.closeWhenEmpty = closeBox.state == .on
    }

    @objc private func languageChanged() {
        guard let raw = languagePopup.selectedItem?.representedObject as? String,
              let language = AppLanguage(rawValue: raw) else { return }

        L10n.setLanguage(language)

        // Let the popup menu finish tracking before rebuilding it and the
        // shelf windows.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.localizeUI()
            self.syncFromPreferences()
            self.manager.rebuildWindows()
            self.onLanguageChanged?()
        }
    }

    @objc private func showDataFolder() {
        NSWorkspace.shared.open(Store.shared.rootURL)
    }

    @objc private func closeAllShelves() {
        let alert = NSAlert()
        alert.messageText = L10n.removeAllTitle
        alert.informativeText = L10n.removeAllInfo
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.cancel)
        alert.addButton(withTitle: L10n.removeAll)
        if alert.runModal() == .alertSecondButtonReturn {
            manager.closeAllShelves()
        }
    }
}

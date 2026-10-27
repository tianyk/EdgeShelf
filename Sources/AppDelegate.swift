import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var manager: ShelfManager!
    private var dragMonitor: DragMonitor!
    private var statusItem: NSStatusItem!
    private var preferencesController: PreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if CommandLine.arguments.contains("--dark") {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }

        if let index = CommandLine.arguments.firstIndex(of: "--lang"),
           index + 1 < CommandLine.arguments.count,
           let language = AppLanguage.fromCode(CommandLine.arguments[index + 1]) {
            L10n.override = language
        }

        manager = ShelfManager()
        dragMonitor = DragMonitor(manager: manager)
        dragMonitor.start()

        setupStatusItem()

        if CommandLine.arguments.contains("--demo")
            || CommandLine.arguments.contains("--snapshot")
            || CommandLine.arguments.contains("--snapshot-many")
            || CommandLine.arguments.contains("--snapshot-collapsed")
            || CommandLine.arguments.contains("--debug-state")
            || CommandLine.arguments.contains("--debug-hover")
            || CommandLine.arguments.contains("--debug-drag")
            || CommandLine.arguments.contains("--debug-hittest") {
            manager.addDemoItems()
        }

        if CommandLine.arguments.contains("--prefs") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.showPreferences()
            }
        }

        if CommandLine.arguments.contains("--snapshot") || CommandLine.arguments.contains("--snapshot-many") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.writeSnapshot()
            }
        }

        if CommandLine.arguments.contains("--snapshot-collapsed") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.manager.collapseForSnapshot()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.writeSnapshot()
            }
        }

        if CommandLine.arguments.contains("--snapshot-empty") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.manager.showEmptyShelfForSnapshot()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.writeSnapshot()
            }
        }

        if CommandLine.arguments.contains("--debug-menus") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self else { return }
                print(self.manager.debugMenus())
                NSApp.terminate(nil)
            }
        }

        if CommandLine.arguments.contains("--debug-state") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                print(self?.manager.debugState() ?? "no manager")
                NSApp.terminate(nil)
            }
        }

        if CommandLine.arguments.contains("--debug-hover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.manager.hoverUpdate(cursor: NSPoint(x: 1, y: 500))
                print("after edge hover:\n\(self?.manager.debugState() ?? "")")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    self?.manager.hoverUpdate(cursor: NSPoint(x: 1100, y: 500))
                    print("after leaving:\n\(self?.manager.debugState() ?? "")")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        NSApp.terminate(nil)
                    }
                }
            }
        }

        if CommandLine.arguments.contains("--debug-hittest") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self,
                      let controller = self.manager.windows.first(where: { $0.key.edge == .left })?.value else {
                    NSApp.terminate(nil)
                    return
                }
                print(controller.shelfView.debugHitTestReport())
                NSApp.terminate(nil)
            }
        }

        if CommandLine.arguments.contains("--debug-drag") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.manager.beginDrag()
                self?.manager.updateDrag(cursor: NSPoint(x: 1, y: 500))
                print("during drag:\n\(self?.manager.debugState() ?? "")")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    self?.manager.endDrag()
                    print("after drag:\n\(self?.manager.debugState() ?? "")")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }

    private func writeSnapshot() {
        guard let controller = manager.windows.first(where: { $0.key.edge == .left })?.value else {
            NSApp.terminate(nil)
            return
        }
        let view = controller.shelfView
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            NSApp.terminate(nil)
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: "/tmp/edgeshelf-snapshot.png"))
            print("EdgeShelf snapshot: /tmp/edgeshelf-snapshot.png")
        }
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager?.flush()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "tray.full", accessibilityDescription: L10n.appName)
                ?? NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: L10n.appName)
            image?.isTemplate = true
            button.image = image
        }

        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        guard let statusItem else { return }
        statusItem.button?.toolTip = L10n.statusTooltip

        let menu = NSMenu()
        let show = NSMenuItem(title: L10n.showShelves, action: #selector(showShelves), keyEquivalent: "")
        show.target = self
        menu.addItem(show)

        let hideEmpty = NSMenuItem(title: L10n.hideEmptyShelves, action: #selector(hideEmptyShelves), keyEquivalent: "")
        hideEmpty.target = self
        menu.addItem(hideEmpty)

        menu.addItem(.separator())

        let clearAll = NSMenuItem(title: L10n.clearAllShelves, action: #selector(clearAllShelves), keyEquivalent: "")
        clearAll.target = self
        menu.addItem(clearAll)

        menu.addItem(.separator())

        let prefs = NSMenuItem(title: L10n.preferences, action: #selector(showPreferences), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        menu.addItem(.separator())

        let about = NSMenuItem(title: L10n.about, action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: L10n.quit, action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func showShelves() {
        manager.showAllNonEmpty()
    }

    @objc private func hideEmptyShelves() {
        manager.hideEmptyShelves()
    }

    @objc private func clearAllShelves() {
        guard manager.hasAnyItems else { return }
        if ShelfConfirmation.clearAllShelves() {
            manager.closeAllShelves()
        }
    }

    @objc private func showPreferences() {
        if preferencesController == nil {
            let controller = PreferencesWindowController(manager: manager)
            controller.onLanguageChanged = { [weak self] in
                self?.rebuildStatusMenu()
            }
            preferencesController = controller
        }
        preferencesController?.show()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
        alert.messageText = L10n.appName
        alert.informativeText = String(format: L10n.aboutText, version)
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.ok)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

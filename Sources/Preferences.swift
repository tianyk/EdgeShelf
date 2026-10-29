import AppKit

/// Single source of truth for preferences. Backed by UserDefaults so the app
/// behaves the same after a restart.
final class Preferences {
    static let shared = Preferences()

    private enum Key {
        static let leftEnabled = "leftEnabled"
        static let rightEnabled = "rightEnabled"
        static let removeAfterDragOut = "removeAfterDragOut"
        static let closeWhenEmpty = "closeWhenEmpty"
        static let mergeDroppedFiles = "mergeDroppedFiles"
    }

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            Key.leftEnabled: true,
            Key.rightEnabled: true,
            Key.removeAfterDragOut: true,
            Key.closeWhenEmpty: true,
            Key.mergeDroppedFiles: true,
        ])
    }

    var leftEnabled: Bool {
        get { defaults.bool(forKey: Key.leftEnabled) }
        set { defaults.set(newValue, forKey: Key.leftEnabled) }
    }

    var rightEnabled: Bool {
        get { defaults.bool(forKey: Key.rightEnabled) }
        set { defaults.set(newValue, forKey: Key.rightEnabled) }
    }

    var removeAfterDragOut: Bool {
        get { defaults.bool(forKey: Key.removeAfterDragOut) }
        set { defaults.set(newValue, forKey: Key.removeAfterDragOut) }
    }

    var closeWhenEmpty: Bool {
        get { defaults.bool(forKey: Key.closeWhenEmpty) }
        set { defaults.set(newValue, forKey: Key.closeWhenEmpty) }
    }

    /// A Finder drag can carry several files. On by default, they become one
    /// shelf card; dragging that card out moves every file in one session.
    var mergeDroppedFiles: Bool {
        get { defaults.bool(forKey: Key.mergeDroppedFiles) }
        set { defaults.set(newValue, forKey: Key.mergeDroppedFiles) }
    }

    var enabledEdges: [ShelfEdge] {
        var result: [ShelfEdge] = []
        if leftEnabled { result.append(.left) }
        if rightEnabled { result.append(.right) }
        return result
    }
}

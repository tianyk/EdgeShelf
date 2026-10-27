import AppKit

// MARK: - Edges

enum ShelfEdge: String, Codable, CaseIterable, Identifiable {
    case left
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: return L10n.leftEdge
        case .right: return L10n.rightEdge
        }
    }

    var isLeft: Bool { self == .left }
}

// MARK: - Items

enum ItemKind: String, Codable {
    case file
    case folder
    case image
    case text
    case url

    var symbolName: String {
        switch self {
        case .file: return "doc"
        case .folder: return "folder"
        case .image: return "photo"
        case .text: return "text.alignleft"
        case .url: return "link"
        }
    }

    var label: String {
        switch self {
        case .file: return L10n.file
        case .folder: return L10n.folder
        case .image: return L10n.image
        case .text: return L10n.text
        case .url: return L10n.link
        }
    }
}

struct ShelfItem: Codable, Identifiable, Equatable {
    var id: UUID
    var kind: ItemKind
    var displayName: String
    /// Path relative to the store's Items directory. Only used for content
    /// EdgeShelf owns: pasted images, promised files, and legacy copies.
    var relativePath: String?
    /// Original location for a Finder drop. The shelf references this path
    /// instead of copying it; when it disappears, the item leaves the shelf.
    var originalPath: String?
    var text: String?
    var urlString: String?
    var addedAt: Date
    var byteSize: Int64?

    init(kind: ItemKind,
         displayName: String,
         relativePath: String? = nil,
         originalPath: String? = nil,
         text: String? = nil,
         urlString: String? = nil,
         byteSize: Int64? = nil) {
        self.id = UUID()
        self.kind = kind
        self.displayName = displayName
        self.relativePath = relativePath
        self.originalPath = originalPath
        self.text = text
        self.urlString = urlString
        self.addedAt = Date()
        self.byteSize = byteSize
    }

    /// True for items whose content lives at a file-system path.
    var isFileBacked: Bool {
        switch kind {
        case .file, .folder, .image: return true
        case .text, .url: return false
        }
    }

    var subtitle: String {
        switch kind {
        case .text:
            let body = (text ?? "").replacingOccurrences(of: "\n", with: " ")
            return body.isEmpty ? L10n.text : String(body.prefix(48))
        case .url:
            return urlString ?? L10n.link
        case .folder:
            return L10n.folder
        case .image:
            return L10n.image
        case .file:
            if let byteSize {
                return ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
            }
            return L10n.file
        }
    }
}

// MARK: - Shelf identity and state

struct ShelfKey: Hashable, Codable {
    let screenID: String
    let edge: ShelfEdge
}

struct ShelfState: Codable {
    var key: ShelfKey
    var items: [ShelfItem]

    init(key: ShelfKey, items: [ShelfItem] = []) {
        self.key = key
        self.items = items
    }
}

// MARK: - Screen helpers

extension NSScreen {
    var edgeShelfDisplayID: String {
        let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return String(number?.uint32Value ?? 0)
    }
}

extension NSPoint {
    func distance(to other: NSPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}

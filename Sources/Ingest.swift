import AppKit
import UniformTypeIdentifiers

/// What a drag actually carries — after the cheap checks, before any decoding.
///
/// The order is the whole point of this type:
///
/// 1. Promised files: resolving one synchronously hangs the drop.
/// 2. File URLs: a Finder drag has to stay a file, because the item keeps its
///    original path instead of copying it, and dragging it back is then a
///    no-op instead of a "replace?" prompt.
/// 3. Bitmap data. A browser publishes an image's alt text as `.string`, the
///    `<img>` tag as `.html`, and often its address as a URL next to the
///    bitmap, so the bitmap has to be matched before those or the card ends
///    up holding a line of text instead of the picture.
/// 4. Web URLs.
/// 5. Plain text, which is lossless for the shelf and far cheaper than
///    importing rich text.
/// 6. Rich text (RTF, flat RTFD, HTML) that carries no plain-text flavour.
///    Some editors and "copy as rich text" sources publish only these; they
///    used to be dropped with a beep even though the view accepted them.
///
/// Decoding is deliberately left to the caller: importing HTML costs close to
/// a second on a cold launch and synchronises with the main thread, so it must
/// never run inside AppKit's drop callback.
enum IngestPayload {
    case promises([NSFilePromiseReceiver])
    case urls([URL])
    case bitmap(data: Data, fileExtension: String)
    case text(String)
    case richText(data: Data, documentType: NSAttributedString.DocumentType)

    static func classify(_ pasteboard: NSPasteboard) -> IngestPayload? {
        if let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil)
            as? [NSFilePromiseReceiver],
           !receivers.isEmpty {
            return .promises(receivers)
        }

        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: false]
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
        let fileURLs = urls.filter(\.isFileURL)
        if !fileURLs.isEmpty {
            return .urls(fileURLs)
        }

        if let bitmap = bitmapPayload(in: pasteboard) {
            return bitmap
        }

        if !urls.isEmpty {
            return .urls(urls)
        }

        if let text = plainText(in: pasteboard) {
            return .text(text)
        }

        return richTextPayload(in: pasteboard)
    }

    // MARK: - Bitmap

    /// The pasteboard types we store as a picture, in preference order.
    private static let bitmapTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]

    /// Image types AppKit has no pasteboard constant for. A drag is only
    /// offered to a shelf view that registered one of its types, so without
    /// these a HEIC or JPEG drag never reaches the ingest path at all.
    static let extraDraggedTypes: [NSPasteboard.PasteboardType] = [
        UTType.jpeg, .heic, .gif, .webP, .bmp,
    ].map { NSPasteboard.PasteboardType($0.identifier) }

    /// Returns the first image payload the pasteboard offers.
    ///
    /// The bytes are stored exactly as they arrived: re-encoding a photo
    /// through TIFF and PNG takes about a second for a 6 MP image, throws away
    /// the original quality, and is what used to run inside the drop callback.
    private static func bitmapPayload(in pasteboard: NSPasteboard) -> IngestPayload? {
        guard let declared = pasteboard.types else { return nil }

        var ordered: [NSPasteboard.PasteboardType] = bitmapTypes.filter { declared.contains($0) }
        for type in declared where !ordered.contains(type) {
            guard let utType = UTType(type.rawValue), utType.conforms(to: .image) else { continue }
            ordered.append(type)
        }

        for type in ordered {
            guard let data = pasteboard.data(forType: type), !data.isEmpty else { continue }
            let fileExtension = UTType(type.rawValue)?.preferredFilenameExtension ?? "img"
            return .bitmap(data: data, fileExtension: fileExtension)
        }
        return nil
    }

    // MARK: - Text

    /// Rich text flavours, cheapest first. RTF decodes in under a millisecond;
    /// HTML needs a full parser and is therefore last.
    private static let richTextTypes: [(type: NSPasteboard.PasteboardType,
                                       documentType: NSAttributedString.DocumentType)] = [
        (.rtf, .rtf),
        (.rtfd, .rtfd),
        (.html, .html),
    ]

    private static func plainText(in pasteboard: NSPasteboard) -> String? {
        guard let string = pasteboard.string(forType: .string) else { return nil }
        guard hasReadableText(string) else { return nil }
        return string
    }

    private static func richTextPayload(in pasteboard: NSPasteboard) -> IngestPayload? {
        guard let declared = pasteboard.types else { return nil }
        for entry in richTextTypes where declared.contains(entry.type) {
            guard let data = pasteboard.data(forType: entry.type), !data.isEmpty else { continue }
            return .richText(data: data, documentType: entry.documentType)
        }
        return nil
    }

    /// Rich text keeps an object-replacement character (U+FFFC) where a picture
    /// or attachment was, so a drag that is only an inline image collapses to a
    /// string that looks non-empty but has nothing readable in it.
    static func hasReadableText(_ string: String) -> Bool {
        !string
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    /// First non-empty line, clipped for the card title.
    static func firstLine(of string: String) -> String {
        let line = string.split(whereSeparator: \.isNewline).first.map(String.init) ?? string
        return String(line.prefix(60))
    }
}

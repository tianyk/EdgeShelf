import Foundation

// MARK: - Languages

enum AppLanguage: String, CaseIterable {
    case system
    case english
    case chinese
    case french
    case spanish
    case russian
    case arabic

    var nativeName: String {
        switch self {
        case .system: return ""
        case .english: return "English"
        case .chinese: return "中文"
        case .french: return "Français"
        case .spanish: return "Español"
        case .russian: return "Русский"
        case .arabic: return "العربية"
        }
    }

    var isRTL: Bool { self == .arabic }

    static func fromCode(_ code: String) -> AppLanguage? {
        switch code.lowercased() {
        case "en", "english": return .english
        case "zh", "zh-hans", "zh-hant", "chinese": return .chinese
        case "fr", "french": return .french
        case "es", "spanish": return .spanish
        case "ru", "russian": return .russian
        case "ar", "arabic": return .arabic
        case "system", "auto": return .system
        default: return nil
        }
    }
}

extension Notification.Name {
    static let hamsterLanguageDidChange = Notification.Name("com.doge.edgeshelf.languageDidChange")
}

// MARK: - Strings

/// Product name is intentionally never translated.
enum L10n {
    private static let defaultsKey = "appLanguage"

    /// Used by `--lang` for screenshots and testing, without persisting.
    static var override: AppLanguage?

    static var selectedLanguage: AppLanguage {
        get {
            let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
            return AppLanguage(rawValue: raw) ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }

    static var currentLanguage: AppLanguage {
        if let override, override != .system { return override }
        let selected = selectedLanguage
        return selected == .system ? systemLanguage() : selected
    }

    static var isRTL: Bool { currentLanguage == .arabic }

    static func setLanguage(_ language: AppLanguage) {
        selectedLanguage = language
        override = nil
        NotificationCenter.default.post(name: .hamsterLanguageDidChange, object: nil)
    }

    private static func systemLanguage() -> AppLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        if preferred.hasPrefix("zh") { return .chinese }
        if preferred.hasPrefix("fr") { return .french }
        if preferred.hasPrefix("es") { return .spanish }
        if preferred.hasPrefix("ru") { return .russian }
        if preferred.hasPrefix("ar") { return .arabic }
        return .english
    }

    static func string(_ key: String) -> String {
        let language = currentLanguage
        if let value = tables[language]?[key] { return value }
        return tables[.english]?[key] ?? key
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), arguments: arguments)
    }

    // Product name is deliberately independent of the selected language.
    static let appName = "Hamster"

    // Chrome / empty state.
    static var statusTooltip: String { string("statusTooltip") }
    static var dropHere: String { string("dropHere") }
    static var dropTypes: String { string("dropTypes") }
    static var copying: String { string("copying") }

    // Item kinds.
    static var file: String { string("file") }
    static var folder: String { string("folder") }
    static var image: String { string("image") }
    static var text: String { string("text") }
    static var link: String { string("link") }

    // Item actions.
    static var open: String { string("open") }
    static var openAll: String { string("openAll") }
    static var showInFinder: String { string("showInFinder") }
    static var showAllInFinder: String { string("showAllInFinder") }
    static var copy: String { string("copy") }
    static var copyAll: String { string("copyAll") }
    static var remove: String { string("remove") }
    static var removeFromShelf: String { string("removeFromShelf") }
    static var expandGroup: String { string("expandGroup") }
    static var collapseGroup: String { string("collapseGroup") }
    static var ungroup: String { string("ungroup") }
    static var removeGroup: String { string("removeGroup") }
    static var groupHelp: String { string("groupHelp") }

    /// “5 items” — the count is always at least two for a group.
    static func groupItems(_ count: Int) -> String {
        String(format: string("groupItems"), count)
    }

    // Shelf chrome.
    static var clearShelf: String { string("clearShelf") }
    static var clearShelfTitle: String { string("clearShelfTitle") }
    static var clearShelfConfirm: String { string("clearShelfConfirm") }
    static var clearAllShelves: String { string("clearAllShelves") }
    static var removeItemHelp: String { string("removeItemHelp") }

    // Status menu.
    static var showShelves: String { string("showShelves") }
    static var hideEmptyShelves: String { string("hideEmptyShelves") }
    static var preferences: String { string("preferences") }
    static var about: String { string("about") }
    static var quit: String { string("quit") }

    // Preferences.
    static var prefsTitle: String { string("prefsTitle") }
    static var enableLeft: String { string("enableLeft") }
    static var enableRight: String { string("enableRight") }
    static var removeAfterDragOut: String { string("removeAfterDragOut") }
    static var closeWhenEmpty: String { string("closeWhenEmpty") }
    static var mergeDroppedFiles: String { string("mergeDroppedFiles") }
    static var launchAtLogin: String { string("launchAtLogin") }
    static var launchAtLoginFailedTitle: String { string("launchAtLoginFailedTitle") }
    static func launchAtLoginFailed(_ detail: String) -> String {
        String(format: string("launchAtLoginFailed"), detail)
    }
    static var launchAtLoginNeedsApproval: String { string("launchAtLoginNeedsApproval") }
    static var launchAtLoginInactive: String { string("launchAtLoginInactive") }
    static var launchAtLoginHint: String { string("launchAtLoginHint") }
    static var openLoginItems: String { string("openLoginItems") }
    static var showDataFolder: String { string("showDataFolder") }
    static var closeAllShelves: String { string("closeAllShelves") }
    static var removeAllTitle: String { string("removeAllTitle") }
    static var removeAllInfo: String { string("removeAllInfo") }
    static var cancel: String { string("cancel") }
    static var removeAll: String { string("removeAll") }
    static var languageLabel: String { string("languageLabel") }
    static var followSystem: String { string("followSystem") }

    // About / misc.
    static var aboutText: String { string("aboutText") }
    static var ok: String { string("ok") }
    static var leftEdge: String { string("leftEdge") }
    static var rightEdge: String { string("rightEdge") }
    static var incomingFile: String { string("incomingFile") }

    // Demo content.
    static var demoWelcomeTitle: String { string("demoWelcomeTitle") }
    static var demoWelcomeText: String { string("demoWelcomeText") }
    static var demoDesignTitle: String { string("demoDesignTitle") }
    static var demoDesignText: String { string("demoDesignText") }
    static var demoReadingTitle: String { string("demoReadingTitle") }
    static var demoReadingText: String { string("demoReadingText") }
    static var demoScreenshotTitle: String { string("demoScreenshotTitle") }
    static var demoScreenshotText: String { string("demoScreenshotText") }
    static var demoFileName: String { string("demoFileName") }
    static var demoFileText: String { string("demoFileText") }

    // MARK: Tables

    private static let tables: [AppLanguage: [String: String]] = [
        .english: english,
        .chinese: chinese,
        .french: french,
        .spanish: spanish,
        .russian: russian,
        .arabic: arabic,
    ]

    private static let english: [String: String] = [
        "statusTooltip": "Hamster — drag items to a screen edge",
        "dropHere": "Drop anything here",
        "dropTypes": "Files · Folders · Text · Links",
        "copying": "Copying…",
        "file": "File",
        "folder": "Folder",
        "image": "Image",
        "text": "Text",
        "link": "Link",
        "open": "Open",
        "openAll": "Open All",
        "showInFinder": "Show in Finder",
        "showAllInFinder": "Show All in Finder",
        "copy": "Copy",
        "copyAll": "Copy All",
        "remove": "Remove",
        "removeFromShelf": "Remove from Shelf",
        "expandGroup": "Expand",
        "collapseGroup": "Collapse",
        "ungroup": "Split into Separate Items",
        "removeGroup": "Remove Group",
        "groupHelp": "Click to expand or collapse; drag to move every item",
        "groupItems": "%d items",
        "clearShelf": "Clear Shelf…",
        "clearAllShelves": "Clear All Shelves…",
        "clearShelfTitle": "Clear this shelf?",
        "clearShelfConfirm": "This removes every item from this shelf. Your original files and folders are not touched. Text, links and pasted images on the shelf cannot be recovered.",
        "removeItemHelp": "Remove from shelf",
        "showShelves": "Show Shelves",
        "hideEmptyShelves": "Hide Empty Shelves",
        "preferences": "Preferences…",
        "about": "About Hamster",
        "quit": "Quit Hamster",
        "prefsTitle": "Hamster Preferences",
        "enableLeft": "Enable the left screen edge",
        "enableRight": "Enable the right screen edge",
        "removeAfterDragOut": "Remove items after dragging them out",
        "closeWhenEmpty": "Close a shelf when its last item is removed",
        "mergeDroppedFiles": "Merge files dropped together into one item",
        "launchAtLogin": "Launch Hamster at login",
        "launchAtLoginFailedTitle": "Could not change Login Items",
        "launchAtLoginFailed": "Hamster could not update Login Items: %@",
        "launchAtLoginNeedsApproval": "Hamster is registered but needs your approval. Allow it in System Settings → General → Login Items.",
        "launchAtLoginInactive": "The login item did not become active.",
        "launchAtLoginHint": "If you are running Hamster from a build folder, move it to the Applications folder and try again.",
        "openLoginItems": "Open Login Items",
        "showDataFolder": "Show Data Folder",
        "closeAllShelves": "Close All Shelves",
        "removeAllTitle": "Remove all shelf items?",
        "removeAllInfo": "This removes every item from the shelves. Your original files and folders are not touched. Text, links and pasted images cannot be recovered.",
        "cancel": "Cancel",
        "removeAll": "Remove All",
        "languageLabel": "Language",
        "followSystem": "Follow System",
        "aboutText": """
        Hamster is a small reimplementation of Dropshelf for macOS 26/27.

        Drag files, folders, text, images or links to the left or right edge of the screen. The shelf points at the original file instead of making its own copy; deleting the original removes the item from the shelf.

        Version %@
        """,
        "ok": "OK",
        "leftEdge": "Left edge",
        "rightEdge": "Right edge",
        "incomingFile": "Incoming file",
        "demoWelcomeTitle": "Welcome to Hamster",
        "demoWelcomeText": "Drag files, folders, text, images or links to a screen edge.",
        "demoDesignTitle": "Design notes",
        "demoDesignText": "Cream panel, caramel accents, one clear card per item.",
        "demoReadingTitle": "Reading list",
        "demoReadingText": "A shelf should feel like a place, not a window.",
        "demoScreenshotTitle": "Screenshot.png",
        "demoScreenshotText": "A screenshot waiting to be dragged into a document.",
        "demoFileName": "Hamster demo.txt",
        "demoFileText": "This file was dropped onto an Hamster shelf.",
    ]

    private static let chinese: [String: String] = [
        "statusTooltip": "Hamster — 把文件拖到屏幕边缘",
        "dropHere": "把任何内容拖到这里",
        "dropTypes": "文件 · 文件夹 · 文本 · 链接",
        "copying": "正在复制…",
        "file": "文件",
        "folder": "文件夹",
        "image": "图片",
        "text": "文本",
        "link": "链接",
        "open": "打开",
        "openAll": "全部打开",
        "showInFinder": "在访达中显示",
        "showAllInFinder": "在访达中显示全部",
        "copy": "拷贝",
        "copyAll": "拷贝全部",
        "remove": "移除",
        "removeFromShelf": "从暂存面板移除",
        "expandGroup": "展开",
        "collapseGroup": "收起",
        "ungroup": "拆分为单独项目",
        "removeGroup": "移除这一组",
        "groupHelp": "点击展开或收起；拖动可移出全部项目",
        "groupItems": "%d 个项目",
        "clearShelf": "清空暂存面板…",
        "clearAllShelves": "清空所有暂存面板…",
        "clearShelfTitle": "清空这个暂存面板？",
        "clearShelfConfirm": "这会移除暂存面板上的所有项目，不会改动原始文件或文件夹。暂存面板上的文本、链接和粘贴的图片无法恢复。",
        "removeItemHelp": "从暂存面板移除",
        "showShelves": "显示所有暂存面板",
        "hideEmptyShelves": "隐藏空暂存面板",
        "preferences": "偏好设置…",
        "about": "关于 Hamster",
        "quit": "退出 Hamster",
        "prefsTitle": "Hamster 偏好设置",
        "enableLeft": "启用屏幕左边缘",
        "enableRight": "启用屏幕右边缘",
        "removeAfterDragOut": "拖出后移除项目",
        "closeWhenEmpty": "移除最后一个项目后关闭暂存面板",
        "mergeDroppedFiles": "把同一次拖入的多个文件合并为一项",
        "launchAtLogin": "登录时启动 Hamster",
        "launchAtLoginFailedTitle": "无法更改登录项",
        "launchAtLoginFailed": "Hamster 无法更新登录项：%@",
        "launchAtLoginNeedsApproval": "Hamster 已注册，但需要你的批准。请在“系统设置”→“通用”→“登录项”中允许它。",
        "launchAtLoginInactive": "登录项没有生效。",
        "launchAtLoginHint": "如果 Hamster 正在从构建目录运行，请把它移到“应用程序”文件夹后再试。",
        "openLoginItems": "打开登录项",
        "showDataFolder": "显示数据文件夹",
        "closeAllShelves": "关闭所有暂存面板",
        "removeAllTitle": "移除所有暂存面板项目？",
        "removeAllInfo": "这会移除所有暂存面板项目，不会改动原始文件或文件夹。文本、链接和粘贴的图片无法恢复。",
        "cancel": "取消",
        "removeAll": "全部移除",
        "languageLabel": "语言",
        "followSystem": "跟随系统",
        "aboutText": """
        Hamster 是一个为 macOS 26/27 重新实现的 Dropshelf。

        把文件、文件夹、文本、图片或链接拖到屏幕左/右边缘。暂存面板直接引用原始文件，不会额外复制；如果原文件被删除，项目也会从暂存面板上消失。

        版本 %@
        """,
        "ok": "好",
        "leftEdge": "左边缘",
        "rightEdge": "右边缘",
        "incomingFile": "正在接收文件",
        "demoWelcomeTitle": "欢迎使用 Hamster",
        "demoWelcomeText": "把文件、文件夹、文本、图片或链接拖到屏幕边缘。",
        "demoDesignTitle": "设计笔记",
        "demoDesignText": "奶油色面板、焦糖色点缀、每个项目一张清晰的卡片。",
        "demoReadingTitle": "阅读清单",
        "demoReadingText": "暂存面板应该像一个地方，而不是一个窗口。",
        "demoScreenshotTitle": "截图.png",
        "demoScreenshotText": "一张等待被拖进文档的截图。",
        "demoFileName": "Hamster 演示.txt",
        "demoFileText": "这个文件被拖进了 Hamster 暂存面板。",
    ]

    private static let french: [String: String] = [
        "statusTooltip": "Hamster — faites glisser des éléments vers un bord de l’écran",
        "dropHere": "Déposez n’importe quoi ici",
        "dropTypes": "Fichiers · Dossiers · Texte · Liens",
        "copying": "Copie…",
        "file": "Fichier",
        "folder": "Dossier",
        "image": "Image",
        "text": "Texte",
        "link": "Lien",
        "open": "Ouvrir",
        "openAll": "Tout ouvrir",
        "showInFinder": "Afficher dans le Finder",
        "showAllInFinder": "Tout afficher dans le Finder",
        "copy": "Copier",
        "copyAll": "Tout copier",
        "remove": "Retirer",
        "removeFromShelf": "Retirer de l’étagère",
        "expandGroup": "Développer",
        "collapseGroup": "Réduire",
        "ungroup": "Séparer en éléments distincts",
        "removeGroup": "Retirer le groupe",
        "groupHelp": "Cliquez pour développer ou réduire ; faites glisser pour déplacer tous les éléments",
        "groupItems": "%d éléments",
        "clearShelf": "Vider l’étagère…",
        "clearAllShelves": "Vider toutes les étagères…",
        "clearShelfTitle": "Vider cette étagère ?",
        "clearShelfConfirm": "Cela retire tous les éléments de cette étagère. Vos fichiers et dossiers d’origine ne sont pas modifiés. Le texte, les liens et les images collées sur l’étagère ne peuvent pas être récupérés.",
        "removeItemHelp": "Retirer de l’étagère",
        "showShelves": "Afficher les étagères",
        "hideEmptyShelves": "Masquer les étagères vides",
        "preferences": "Réglages…",
        "about": "À propos d’Hamster",
        "quit": "Quitter Hamster",
        "prefsTitle": "Réglages d’Hamster",
        "enableLeft": "Activer le bord gauche de l’écran",
        "enableRight": "Activer le bord droit de l’écran",
        "removeAfterDragOut": "Retirer les éléments après les avoir fait glisser",
        "closeWhenEmpty": "Fermer l’étagère quand son dernier élément est retiré",
        "mergeDroppedFiles": "Regrouper les fichiers déposés ensemble en un seul élément",
        "launchAtLogin": "Ouvrir Hamster à l’ouverture de session",
        "launchAtLoginFailedTitle": "Impossible de modifier les éléments d’ouverture",
        "launchAtLoginFailed": "Hamster n’a pas pu mettre à jour les éléments d’ouverture : %@",
        "launchAtLoginNeedsApproval": "Hamster est enregistré mais doit être autorisé. Autorisez-le dans Réglages Système → Général → Ouverture.",
        "launchAtLoginInactive": "L’élément d’ouverture n’a pas été activé.",
        "launchAtLoginHint": "Si Hamster est exécuté depuis un dossier de compilation, placez-le dans le dossier Applications puis réessayez.",
        "openLoginItems": "Ouvrir Ouverture",
        "showDataFolder": "Afficher le dossier de données",
        "closeAllShelves": "Fermer toutes les étagères",
        "removeAllTitle": "Retirer tous les éléments des étagères ?",
        "removeAllInfo": "Cela retire tous les éléments des étagères. Vos fichiers et dossiers d’origine ne sont pas modifiés. Le texte, les liens et les images collées ne peuvent pas être récupérés.",
        "cancel": "Annuler",
        "removeAll": "Tout retirer",
        "languageLabel": "Langue",
        "followSystem": "Suivre le système",
        "aboutText": """
        Hamster est une réimplémentation de Dropshelf pour macOS 26/27.

        Faites glisser des fichiers, dossiers, textes, images ou liens vers le bord gauche ou droit de l’écran. L’étagère fait référence au fichier d’origine sans en faire de copie ; si vous supprimez l’original, l’élément quitte aussi l’étagère.

        Version %@
        """,
        "ok": "OK",
        "leftEdge": "Bord gauche",
        "rightEdge": "Bord droit",
        "incomingFile": "Fichier entrant",
        "demoWelcomeTitle": "Bienvenue dans Hamster",
        "demoWelcomeText": "Faites glisser des fichiers, dossiers, textes, images ou liens vers un bord de l’écran.",
        "demoDesignTitle": "Notes de design",
        "demoDesignText": "Panneau crème, accents caramel, une carte claire par élément.",
        "demoReadingTitle": "Liste de lecture",
        "demoReadingText": "Une étagère doit être un lieu, pas une fenêtre.",
        "demoScreenshotTitle": "Capture.png",
        "demoScreenshotText": "Une capture en attente d’être glissée dans un document.",
        "demoFileName": "Démo Hamster.txt",
        "demoFileText": "Ce fichier a été déposé sur une étagère Hamster.",
    ]

    private static let spanish: [String: String] = [
        "statusTooltip": "Hamster — arrastra elementos a un borde de la pantalla",
        "dropHere": "Suelta cualquier cosa aquí",
        "dropTypes": "Archivos · Carpetas · Texto · Enlaces",
        "copying": "Copiando…",
        "file": "Archivo",
        "folder": "Carpeta",
        "image": "Imagen",
        "text": "Texto",
        "link": "Enlace",
        "open": "Abrir",
        "openAll": "Abrir todo",
        "showInFinder": "Mostrar en el Finder",
        "showAllInFinder": "Mostrar todo en el Finder",
        "copy": "Copiar",
        "copyAll": "Copiar todo",
        "remove": "Eliminar",
        "removeFromShelf": "Quitar del estante",
        "expandGroup": "Expandir",
        "collapseGroup": "Contraer",
        "ungroup": "Separar en elementos individuales",
        "removeGroup": "Quitar grupo",
        "groupHelp": "Haz clic para expandir o contraer; arrastra para mover todos los elementos",
        "groupItems": "%d elementos",
        "clearShelf": "Vaciar estante…",
        "clearAllShelves": "Vaciar todos los estantes…",
        "clearShelfTitle": "¿Vaciar este estante?",
        "clearShelfConfirm": "Esto quita todos los elementos de este estante. Tus archivos y carpetas originales no se modifican. El texto, los enlaces y las imágenes pegadas en el estante no se pueden recuperar.",
        "removeItemHelp": "Quitar del estante",
        "showShelves": "Mostrar estantes",
        "hideEmptyShelves": "Ocultar estantes vacíos",
        "preferences": "Ajustes…",
        "about": "Acerca de Hamster",
        "quit": "Salir de Hamster",
        "prefsTitle": "Ajustes de Hamster",
        "enableLeft": "Activar el borde izquierdo de la pantalla",
        "enableRight": "Activar el borde derecho de la pantalla",
        "removeAfterDragOut": "Quitar los elementos después de arrastrarlos",
        "closeWhenEmpty": "Cerrar el estante cuando se quite su último elemento",
        "mergeDroppedFiles": "Combinar los archivos soltados juntos en un solo elemento",
        "launchAtLogin": "Abrir Hamster al iniciar sesión",
        "launchAtLoginFailedTitle": "No se pudieron cambiar los ítems de inicio",
        "launchAtLoginFailed": "Hamster no pudo actualizar los ítems de inicio: %@",
        "launchAtLoginNeedsApproval": "Hamster está registrado pero necesita tu aprobación. Permítelo en Ajustes del Sistema → General → Ítems de inicio.",
        "launchAtLoginInactive": "El ítem de inicio no se activó.",
        "launchAtLoginHint": "Si ejecutas Hamster desde una carpeta de compilación, muévelo a la carpeta Aplicaciones e inténtalo de nuevo.",
        "openLoginItems": "Abrir ítems de inicio",
        "showDataFolder": "Mostrar carpeta de datos",
        "closeAllShelves": "Cerrar todos los estantes",
        "removeAllTitle": "¿Quitar todos los elementos de los estantes?",
        "removeAllInfo": "Esto quita todos los elementos de los estantes. Tus archivos y carpetas originales no se modifican. El texto, los enlaces y las imágenes pegadas no se pueden recuperar.",
        "cancel": "Cancelar",
        "removeAll": "Quitar todo",
        "languageLabel": "Idioma",
        "followSystem": "Seguir el sistema",
        "aboutText": """
        Hamster es una reimplementación de Dropshelf para macOS 26/27.

        Arrastra archivos, carpetas, texto, imágenes o enlaces al borde izquierdo o derecho de la pantalla. El estante hace referencia al archivo original sin hacer una copia: si eliminas el original, el elemento también desaparece del estante.

        Versión %@
        """,
        "ok": "Aceptar",
        "leftEdge": "Borde izquierdo",
        "rightEdge": "Borde derecho",
        "incomingFile": "Archivo entrante",
        "demoWelcomeTitle": "Bienvenido a Hamster",
        "demoWelcomeText": "Arrastra archivos, carpetas, texto, imágenes o enlaces a un borde de la pantalla.",
        "demoDesignTitle": "Notas de diseño",
        "demoDesignText": "Panel crema, detalles caramelo, una tarjeta clara por elemento.",
        "demoReadingTitle": "Lista de lectura",
        "demoReadingText": "Un estante debe sentirse como un lugar, no como una ventana.",
        "demoScreenshotTitle": "Captura.png",
        "demoScreenshotText": "Una captura esperando para arrastrarse a un documento.",
        "demoFileName": "Demostración Hamster.txt",
        "demoFileText": "Este archivo se soltó en un estante de Hamster.",
    ]

    private static let russian: [String: String] = [
        "statusTooltip": "Hamster — перетащите элементы к краю экрана",
        "dropHere": "Перетащите что угодно сюда",
        "dropTypes": "Файлы · Папки · Текст · Ссылки",
        "copying": "Копирование…",
        "file": "Файл",
        "folder": "Папка",
        "image": "Изображение",
        "text": "Текст",
        "link": "Ссылка",
        "open": "Открыть",
        "openAll": "Открыть все",
        "showInFinder": "Показать в Finder",
        "showAllInFinder": "Показать все в Finder",
        "copy": "Скопировать",
        "copyAll": "Скопировать все",
        "remove": "Удалить",
        "removeFromShelf": "Убрать с полки",
        "expandGroup": "Развернуть",
        "collapseGroup": "Свернуть",
        "ungroup": "Разделить на отдельные элементы",
        "removeGroup": "Удалить группу",
        "groupHelp": "Нажмите, чтобы развернуть или свернуть; перетащите, чтобы переместить все элементы",
        "groupItems": "Элементов: %d",
        "clearShelf": "Очистить полку…",
        "clearAllShelves": "Очистить все полки…",
        "clearShelfTitle": "Очистить эту полку?",
        "clearShelfConfirm": "Все элементы будут убраны с этой полки. Ваши исходные файлы и папки не затрагиваются. Текст, ссылки и вставленные изображения с полки восстановить нельзя.",
        "removeItemHelp": "Убрать с полки",
        "showShelves": "Показать полки",
        "hideEmptyShelves": "Скрыть пустые полки",
        "preferences": "Настройки…",
        "about": "Об Hamster",
        "quit": "Завершить Hamster",
        "prefsTitle": "Настройки Hamster",
        "enableLeft": "Включить левый край экрана",
        "enableRight": "Включить правый край экрана",
        "removeAfterDragOut": "Удалять элементы после перетаскивания",
        "closeWhenEmpty": "Закрывать полку после удаления последнего элемента",
        "mergeDroppedFiles": "Объединять файлы, перетащенные вместе, в один элемент",
        "launchAtLogin": "Запускать Hamster при входе",
        "launchAtLoginFailedTitle": "Не удалось изменить элементы входа",
        "launchAtLoginFailed": "Hamster не удалось обновить элементы входа: %@",
        "launchAtLoginNeedsApproval": "Hamster зарегистрирован, но требует вашего одобрения. Разрешите его в «Системных настройках» → «Основные» → «Элементы входа».",
        "launchAtLoginInactive": "Элемент входа не активировался.",
        "launchAtLoginHint": "Если Hamster запущен из папки сборки, переместите его в папку «Программы» и повторите попытку.",
        "openLoginItems": "Открыть элементы входа",
        "showDataFolder": "Показать папку данных",
        "closeAllShelves": "Закрыть все полки",
        "removeAllTitle": "Удалить все элементы с полок?",
        "removeAllInfo": "Все элементы будут убраны со всех полок. Ваши исходные файлы и папки не затрагиваются. Текст, ссылки и вставленные изображения восстановить нельзя.",
        "cancel": "Отмена",
        "removeAll": "Удалить всё",
        "languageLabel": "Язык",
        "followSystem": "Как в системе",
        "aboutText": """
        Hamster — реализация Dropshelf для macOS 26/27.

        Перетащите файлы, папки, текст, изображения или ссылки к левому или правому краю экрана. Полка ссылается на исходный файл и не создаёт его копию: если удалить оригинал, элемент исчезнет с полки.

        Версия %@
        """,
        "ok": "ОК",
        "leftEdge": "Левый край",
        "rightEdge": "Правый край",
        "incomingFile": "Получение файла",
        "demoWelcomeTitle": "Добро пожаловать в Hamster",
        "demoWelcomeText": "Перетащите файлы, папки, текст, изображения или ссылки к краю экрана.",
        "demoDesignTitle": "Заметки по дизайну",
        "demoDesignText": "Кремовая панель, карамельные акценты, отдельная карточка для каждого элемента.",
        "demoReadingTitle": "Список чтения",
        "demoReadingText": "Полка должна ощущаться как место, а не как окно.",
        "demoScreenshotTitle": "Снимок.png",
        "demoScreenshotText": "Снимок экрана, ожидающий перетаскивания в документ.",
        "demoFileName": "Демо Hamster.txt",
        "demoFileText": "Этот файл был перетащен на полку Hamster.",
    ]

    private static let arabic: [String: String] = [
        "statusTooltip": "Hamster — اسحب العناصر إلى حافة الشاشة",
        "dropHere": "أفلت أي شيء هنا",
        "dropTypes": "ملفات · مجلدات · نصوص · روابط",
        "copying": "جارٍ النسخ…",
        "file": "ملف",
        "folder": "مجلد",
        "image": "صورة",
        "text": "نص",
        "link": "رابط",
        "open": "فتح",
        "openAll": "فتح الكل",
        "showInFinder": "إظهار في Finder",
        "showAllInFinder": "إظهار الكل في Finder",
        "copy": "نسخ",
        "copyAll": "نسخ الكل",
        "remove": "إزالة",
        "removeFromShelf": "إزالة من الرف",
        "expandGroup": "توسيع",
        "collapseGroup": "طي",
        "ungroup": "فصل إلى عناصر منفردة",
        "removeGroup": "إزالة المجموعة",
        "groupHelp": "انقر للتوسيع أو الطي؛ اسحب لنقل كل العناصر",
        "groupItems": "%d عناصر",
        "clearShelf": "إفراغ الرف…",
        "clearAllShelves": "إفراغ كل الرفوف…",
        "clearShelfTitle": "إفراغ هذا الرف؟",
        "clearShelfConfirm": "سيؤدي هذا إلى إزالة كل العناصر من هذا الرف. لن تتأثر ملفاتك ومجلداتك الأصلية. لا يمكن استرداد النصوص والروابط والصور الملصقة على الرف.",
        "removeItemHelp": "إزالة من الرف",
        "showShelves": "إظهار الرفوف",
        "hideEmptyShelves": "إخفاء الرفوف الفارغة",
        "preferences": "الإعدادات…",
        "about": "حول Hamster",
        "quit": "إنهاء Hamster",
        "prefsTitle": "إعدادات Hamster",
        "enableLeft": "تفعيل الحافة اليسرى للشاشة",
        "enableRight": "تفعيل الحافة اليمنى للشاشة",
        "removeAfterDragOut": "إزالة العناصر بعد سحبها للخارج",
        "closeWhenEmpty": "إغلاق الرف عند إزالة آخر عنصر",
        "mergeDroppedFiles": "دمج الملفات التي تُسقط معًا في عنصر واحد",
        "launchAtLogin": "فتح Hamster عند تسجيل الدخول",
        "launchAtLoginFailedTitle": "تعذّر تغيير عناصر تسجيل الدخول",
        "launchAtLoginFailed": "تعذّر على Hamster تحديث عناصر تسجيل الدخول: %@",
        "launchAtLoginNeedsApproval": "تم تسجيل Hamster لكنه يحتاج إلى موافقتك. اسمح به في إعدادات النظام ← عام ← عناصر تسجيل الدخول.",
        "launchAtLoginInactive": "لم يتم تفعيل عنصر تسجيل الدخول.",
        "launchAtLoginHint": "إذا كنت تشغّل Hamster من مجلد البناء، فانقله إلى مجلد التطبيقات ثم حاول مرة أخرى.",
        "openLoginItems": "فتح عناصر تسجيل الدخول",
        "showDataFolder": "إظهار مجلد البيانات",
        "closeAllShelves": "إغلاق كل الرفوف",
        "removeAllTitle": "إزالة كل عناصر الرفوف؟",
        "removeAllInfo": "سيؤدي هذا إلى إزالة كل العناصر من الرفوف. لن تتأثر ملفاتك ومجلداتك الأصلية. لا يمكن استرداد النصوص والروابط والصور الملصقة.",
        "cancel": "إلغاء",
        "removeAll": "إزالة الكل",
        "languageLabel": "اللغة",
        "followSystem": "حسب النظام",
        "aboutText": """
        Hamster هو إعادة تنفيذ لتطبيق Dropshelf لنظام macOS 26/27.

        اسحب الملفات أو المجلدات أو النصوص أو الصور أو الروابط إلى الحافة اليسرى أو اليمنى للشاشة. يشير الرف إلى الملف الأصلي دون إنشاء نسخة منه: وإذا حذفت الأصل فسيختفي العنصر من الرف أيضًا.

        الإصدار %@
        """,
        "ok": "حسنًا",
        "leftEdge": "الحافة اليسرى",
        "rightEdge": "الحافة اليمنى",
        "incomingFile": "ملف قادم",
        "demoWelcomeTitle": "مرحبًا بك في Hamster",
        "demoWelcomeText": "اسحب الملفات أو المجلدات أو النصوص أو الصور أو الروابط إلى حافة الشاشة.",
        "demoDesignTitle": "ملاحظات التصميم",
        "demoDesignText": "لوحة كريمية، لمسات كراميل، بطاقة واضحة لكل عنصر.",
        "demoReadingTitle": "قائمة القراءة",
        "demoReadingText": "يجب أن يبدو الرف كمكان، لا كنافذة.",
        "demoScreenshotTitle": "لقطة.png",
        "demoScreenshotText": "لقطة شاشة تنتظر السحب إلى مستند.",
        "demoFileName": "عرض Hamster.txt",
        "demoFileText": "تم إفلات هذا الملف على رف Hamster.",
    ]
}

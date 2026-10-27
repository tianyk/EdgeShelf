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
    static let edgeShelfLanguageDidChange = Notification.Name("com.doge.edgeshelf.languageDidChange")
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
        NotificationCenter.default.post(name: .edgeShelfLanguageDidChange, object: nil)
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

    // Product name.
    static let appName = "EdgeShelf"

    // Chrome / empty state.
    static var shelf: String { string("shelf") }
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
    static var showInFinder: String { string("showInFinder") }
    static var copy: String { string("copy") }
    static var remove: String { string("remove") }
    static var removeFromShelf: String { string("removeFromShelf") }

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
    static var prefsIntro: String { string("prefsIntro") }
    static var enableLeft: String { string("enableLeft") }
    static var enableRight: String { string("enableRight") }
    static var removeAfterDragOut: String { string("removeAfterDragOut") }
    static var closeWhenEmpty: String { string("closeWhenEmpty") }
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
    static var unavailableFile: String { string("unavailableFile") }

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
        "shelf": "Shelf",
        "statusTooltip": "EdgeShelf — drag items to a screen edge",
        "dropHere": "Drop anything here",
        "dropTypes": "Files · Folders · Text · Links",
        "copying": "Copying…",
        "file": "File",
        "folder": "Folder",
        "image": "Image",
        "text": "Text",
        "link": "Link",
        "open": "Open",
        "showInFinder": "Show in Finder",
        "copy": "Copy",
        "remove": "Remove",
        "removeFromShelf": "Remove from Shelf",
        "clearShelf": "Clear Shelf…",
        "clearAllShelves": "Clear All Shelves…",
        "clearShelfTitle": "Clear this shelf?",
        "clearShelfConfirm": "This deletes the copies EdgeShelf made of these items. The originals are not affected. Text, links and screenshots on the shelf cannot be recovered.",
        "removeItemHelp": "Remove from shelf",
        "showShelves": "Show Shelves",
        "hideEmptyShelves": "Hide Empty Shelves",
        "preferences": "Preferences…",
        "about": "About EdgeShelf",
        "quit": "Quit EdgeShelf",
        "prefsTitle": "EdgeShelf Preferences",
        "prefsIntro": "Drag files, folders, text, images or links to a screen edge. A shelf will wait there until you drag the items back out.",
        "enableLeft": "Enable the left screen edge",
        "enableRight": "Enable the right screen edge",
        "removeAfterDragOut": "Remove items after dragging them out",
        "closeWhenEmpty": "Close a shelf when its last item is removed",
        "showDataFolder": "Show Data Folder",
        "closeAllShelves": "Close All Shelves",
        "removeAllTitle": "Remove all shelf items?",
        "removeAllInfo": "This deletes the copies EdgeShelf made of every item currently on a shelf. The originals are not affected.",
        "cancel": "Cancel",
        "removeAll": "Remove All",
        "languageLabel": "Language",
        "followSystem": "Follow System",
        "aboutText": """
        EdgeShelf is a small reimplementation of Dropshelf for macOS 26/27.

        Drag files, folders, text, images or links to the left or right edge of the screen. The shelf keeps a copy so the item stays available even if the original moves.

        Version %@
        """,
        "ok": "OK",
        "leftEdge": "Left edge",
        "rightEdge": "Right edge",
        "incomingFile": "Incoming file",
        "unavailableFile": "Unavailable file",
        "demoWelcomeTitle": "Welcome to EdgeShelf",
        "demoWelcomeText": "Drag files, folders, text, images or links to a screen edge.",
        "demoDesignTitle": "Design notes",
        "demoDesignText": "Warm paper panel, quiet stripes, one clear card per item.",
        "demoReadingTitle": "Reading list",
        "demoReadingText": "A shelf should feel like a place, not a window.",
        "demoScreenshotTitle": "Screenshot.png",
        "demoScreenshotText": "A screenshot waiting to be dragged into a document.",
        "demoFileName": "EdgeShelf demo.txt",
        "demoFileText": "This file was dropped onto an EdgeShelf shelf.",
    ]

    private static let chinese: [String: String] = [
        "shelf": "搁板",
        "statusTooltip": "EdgeShelf — 把文件拖到屏幕边缘",
        "dropHere": "把任何内容拖到这里",
        "dropTypes": "文件 · 文件夹 · 文本 · 链接",
        "copying": "正在复制…",
        "file": "文件",
        "folder": "文件夹",
        "image": "图片",
        "text": "文本",
        "link": "链接",
        "open": "打开",
        "showInFinder": "在访达中显示",
        "copy": "拷贝",
        "remove": "移除",
        "removeFromShelf": "从搁板移除",
        "clearShelf": "清空搁板…",
        "clearAllShelves": "清空所有搁板…",
        "clearShelfTitle": "清空这个搁板？",
        "clearShelfConfirm": "这会删除 EdgeShelf 为这些项目保存的副本，不会影响原始文件。搁板上的文本、链接和截屏无法恢复。",
        "removeItemHelp": "从搁板移除",
        "showShelves": "显示所有搁板",
        "hideEmptyShelves": "隐藏空搁板",
        "preferences": "偏好设置…",
        "about": "关于 EdgeShelf",
        "quit": "退出 EdgeShelf",
        "prefsTitle": "EdgeShelf 偏好设置",
        "prefsIntro": "把文件、文件夹、文本、图片或链接拖到屏幕边缘。搁板会一直保留，直到你把项目拖出去。",
        "enableLeft": "启用屏幕左边缘",
        "enableRight": "启用屏幕右边缘",
        "removeAfterDragOut": "拖出后移除项目",
        "closeWhenEmpty": "移除最后一个项目后关闭搁板",
        "showDataFolder": "显示数据文件夹",
        "closeAllShelves": "关闭所有搁板",
        "removeAllTitle": "移除所有搁板项目？",
        "removeAllInfo": "这会删除 EdgeShelf 为搁板上的每个项目保存的副本，不会影响原始文件。",
        "cancel": "取消",
        "removeAll": "全部移除",
        "languageLabel": "语言",
        "followSystem": "跟随系统",
        "aboutText": """
        EdgeShelf 是一个为 macOS 26/27 重新实现的 Dropshelf。

        把文件、文件夹、文本、图片或链接拖到屏幕左/右边缘。搁板会保存一份副本，所以原文件移动后项目仍然可用。

        版本 %@
        """,
        "ok": "好",
        "leftEdge": "左边缘",
        "rightEdge": "右边缘",
        "incomingFile": "正在接收文件",
        "unavailableFile": "文件不可用",
        "demoWelcomeTitle": "欢迎使用 EdgeShelf",
        "demoWelcomeText": "把文件、文件夹、文本、图片或链接拖到屏幕边缘。",
        "demoDesignTitle": "设计笔记",
        "demoDesignText": "暖纸色面板、克制的斜纹、每个项目一张清晰的卡片。",
        "demoReadingTitle": "阅读清单",
        "demoReadingText": "搁板应该像一个地方，而不是一个窗口。",
        "demoScreenshotTitle": "截图.png",
        "demoScreenshotText": "一张等待被拖进文档的截图。",
        "demoFileName": "EdgeShelf 演示.txt",
        "demoFileText": "这个文件被拖进了 EdgeShelf 搁板。",
    ]

    private static let french: [String: String] = [
        "shelf": "Étagère",
        "statusTooltip": "EdgeShelf — faites glisser des éléments vers un bord de l’écran",
        "dropHere": "Déposez n’importe quoi ici",
        "dropTypes": "Fichiers · Dossiers · Texte · Liens",
        "copying": "Copie…",
        "file": "Fichier",
        "folder": "Dossier",
        "image": "Image",
        "text": "Texte",
        "link": "Lien",
        "open": "Ouvrir",
        "showInFinder": "Afficher dans le Finder",
        "copy": "Copier",
        "remove": "Retirer",
        "removeFromShelf": "Retirer de l’étagère",
        "clearShelf": "Vider l’étagère…",
        "clearAllShelves": "Vider toutes les étagères…",
        "clearShelfTitle": "Vider cette étagère ?",
        "clearShelfConfirm": "Cela supprime les copies qu’EdgeShelf a faites de ces éléments. Les originaux ne sont pas affectés. Le texte, les liens et les captures d’écran de l’étagère ne peuvent pas être récupérés.",
        "removeItemHelp": "Retirer de l’étagère",
        "showShelves": "Afficher les étagères",
        "hideEmptyShelves": "Masquer les étagères vides",
        "preferences": "Réglages…",
        "about": "À propos d’EdgeShelf",
        "quit": "Quitter EdgeShelf",
        "prefsTitle": "Réglages d’EdgeShelf",
        "prefsIntro": "Faites glisser des fichiers, dossiers, textes, images ou liens vers un bord de l’écran. L’étagère reste là jusqu’à ce que vous en sortiez les éléments.",
        "enableLeft": "Activer le bord gauche de l’écran",
        "enableRight": "Activer le bord droit de l’écran",
        "removeAfterDragOut": "Retirer les éléments après les avoir fait glisser",
        "closeWhenEmpty": "Fermer l’étagère quand son dernier élément est retiré",
        "showDataFolder": "Afficher le dossier de données",
        "closeAllShelves": "Fermer toutes les étagères",
        "removeAllTitle": "Retirer tous les éléments des étagères ?",
        "removeAllInfo": "Cela supprime les copies qu’EdgeShelf a faites de chaque élément actuellement sur une étagère. Les originaux ne sont pas affectés.",
        "cancel": "Annuler",
        "removeAll": "Tout retirer",
        "languageLabel": "Langue",
        "followSystem": "Suivre le système",
        "aboutText": """
        EdgeShelf est une réimplémentation de Dropshelf pour macOS 26/27.

        Faites glisser des fichiers, dossiers, textes, images ou liens vers le bord gauche ou droit de l’écran. L’étagère conserve une copie pour que l’élément reste disponible même si l’original est déplacé.

        Version %@
        """,
        "ok": "OK",
        "leftEdge": "Bord gauche",
        "rightEdge": "Bord droit",
        "incomingFile": "Fichier entrant",
        "unavailableFile": "Fichier indisponible",
        "demoWelcomeTitle": "Bienvenue dans EdgeShelf",
        "demoWelcomeText": "Faites glisser des fichiers, dossiers, textes, images ou liens vers un bord de l’écran.",
        "demoDesignTitle": "Notes de design",
        "demoDesignText": "Panneau papier chaleureux, rayures discrètes, une carte claire par élément.",
        "demoReadingTitle": "Liste de lecture",
        "demoReadingText": "Une étagère doit être un lieu, pas une fenêtre.",
        "demoScreenshotTitle": "Capture.png",
        "demoScreenshotText": "Une capture en attente d’être glissée dans un document.",
        "demoFileName": "Démo EdgeShelf.txt",
        "demoFileText": "Ce fichier a été déposé sur une étagère EdgeShelf.",
    ]

    private static let spanish: [String: String] = [
        "shelf": "Estante",
        "statusTooltip": "EdgeShelf — arrastra elementos a un borde de la pantalla",
        "dropHere": "Suelta cualquier cosa aquí",
        "dropTypes": "Archivos · Carpetas · Texto · Enlaces",
        "copying": "Copiando…",
        "file": "Archivo",
        "folder": "Carpeta",
        "image": "Imagen",
        "text": "Texto",
        "link": "Enlace",
        "open": "Abrir",
        "showInFinder": "Mostrar en el Finder",
        "copy": "Copiar",
        "remove": "Eliminar",
        "removeFromShelf": "Quitar del estante",
        "clearShelf": "Vaciar estante…",
        "clearAllShelves": "Vaciar todos los estantes…",
        "clearShelfTitle": "¿Vaciar este estante?",
        "clearShelfConfirm": "Esto elimina las copias que EdgeShelf hizo de estos elementos. Los originales no se modifican. El texto, los enlaces y las capturas del estante no se pueden recuperar.",
        "removeItemHelp": "Quitar del estante",
        "showShelves": "Mostrar estantes",
        "hideEmptyShelves": "Ocultar estantes vacíos",
        "preferences": "Ajustes…",
        "about": "Acerca de EdgeShelf",
        "quit": "Salir de EdgeShelf",
        "prefsTitle": "Ajustes de EdgeShelf",
        "prefsIntro": "Arrastra archivos, carpetas, texto, imágenes o enlaces a un borde de la pantalla. El estante esperará allí hasta que saques los elementos.",
        "enableLeft": "Activar el borde izquierdo de la pantalla",
        "enableRight": "Activar el borde derecho de la pantalla",
        "removeAfterDragOut": "Quitar los elementos después de arrastrarlos",
        "closeWhenEmpty": "Cerrar el estante cuando se quite su último elemento",
        "showDataFolder": "Mostrar carpeta de datos",
        "closeAllShelves": "Cerrar todos los estantes",
        "removeAllTitle": "¿Quitar todos los elementos de los estantes?",
        "removeAllInfo": "Esto elimina las copias que EdgeShelf hizo de cada elemento que está en un estante. Los originales no se modifican.",
        "cancel": "Cancelar",
        "removeAll": "Quitar todo",
        "languageLabel": "Idioma",
        "followSystem": "Seguir el sistema",
        "aboutText": """
        EdgeShelf es una reimplementación de Dropshelf para macOS 26/27.

        Arrastra archivos, carpetas, texto, imágenes o enlaces al borde izquierdo o derecho de la pantalla. El estante guarda una copia para que el elemento siga disponible aunque muevas el original.

        Versión %@
        """,
        "ok": "Aceptar",
        "leftEdge": "Borde izquierdo",
        "rightEdge": "Borde derecho",
        "incomingFile": "Archivo entrante",
        "unavailableFile": "Archivo no disponible",
        "demoWelcomeTitle": "Bienvenido a EdgeShelf",
        "demoWelcomeText": "Arrastra archivos, carpetas, texto, imágenes o enlaces a un borde de la pantalla.",
        "demoDesignTitle": "Notas de diseño",
        "demoDesignText": "Panel de papel cálido, rayas discretas, una tarjeta clara por elemento.",
        "demoReadingTitle": "Lista de lectura",
        "demoReadingText": "Un estante debe sentirse como un lugar, no como una ventana.",
        "demoScreenshotTitle": "Captura.png",
        "demoScreenshotText": "Una captura esperando para arrastrarse a un documento.",
        "demoFileName": "Demostración EdgeShelf.txt",
        "demoFileText": "Este archivo se soltó en un estante de EdgeShelf.",
    ]

    private static let russian: [String: String] = [
        "shelf": "Полка",
        "statusTooltip": "EdgeShelf — перетащите элементы к краю экрана",
        "dropHere": "Перетащите что угодно сюда",
        "dropTypes": "Файлы · Папки · Текст · Ссылки",
        "copying": "Копирование…",
        "file": "Файл",
        "folder": "Папка",
        "image": "Изображение",
        "text": "Текст",
        "link": "Ссылка",
        "open": "Открыть",
        "showInFinder": "Показать в Finder",
        "copy": "Скопировать",
        "remove": "Удалить",
        "removeFromShelf": "Убрать с полки",
        "clearShelf": "Очистить полку…",
        "clearAllShelves": "Очистить все полки…",
        "clearShelfTitle": "Очистить эту полку?",
        "clearShelfConfirm": "Будут удалены копии, которые EdgeShelf сохранил для этих элементов. Оригиналы не затрагиваются. Текст, ссылки и снимки экрана с полки восстановить нельзя.",
        "removeItemHelp": "Убрать с полки",
        "showShelves": "Показать полки",
        "hideEmptyShelves": "Скрыть пустые полки",
        "preferences": "Настройки…",
        "about": "Об EdgeShelf",
        "quit": "Завершить EdgeShelf",
        "prefsTitle": "Настройки EdgeShelf",
        "prefsIntro": "Перетащите файлы, папки, текст, изображения или ссылки к краю экрана. Полка будет ждать там, пока вы не заберёте элементы.",
        "enableLeft": "Включить левый край экрана",
        "enableRight": "Включить правый край экрана",
        "removeAfterDragOut": "Удалять элементы после перетаскивания",
        "closeWhenEmpty": "Закрывать полку после удаления последнего элемента",
        "showDataFolder": "Показать папку данных",
        "closeAllShelves": "Закрыть все полки",
        "removeAllTitle": "Удалить все элементы с полок?",
        "removeAllInfo": "Будут удалены копии, которые EdgeShelf сохранил для каждого элемента на полках. Оригиналы не затрагиваются.",
        "cancel": "Отмена",
        "removeAll": "Удалить всё",
        "languageLabel": "Язык",
        "followSystem": "Как в системе",
        "aboutText": """
        EdgeShelf — реализация Dropshelf для macOS 26/27.

        Перетащите файлы, папки, текст, изображения или ссылки к левому или правому краю экрана. Полка сохраняет копию, поэтому элемент остаётся доступным, даже если оригинал перемещён.

        Версия %@
        """,
        "ok": "ОК",
        "leftEdge": "Левый край",
        "rightEdge": "Правый край",
        "incomingFile": "Получение файла",
        "unavailableFile": "Файл недоступен",
        "demoWelcomeTitle": "Добро пожаловать в EdgeShelf",
        "demoWelcomeText": "Перетащите файлы, папки, текст, изображения или ссылки к краю экрана.",
        "demoDesignTitle": "Заметки по дизайну",
        "demoDesignText": "Тёплая бумажная панель, тихие полосы, одна понятная карточка на элемент.",
        "demoReadingTitle": "Список чтения",
        "demoReadingText": "Полка должна ощущаться как место, а не как окно.",
        "demoScreenshotTitle": "Снимок.png",
        "demoScreenshotText": "Снимок экрана, ожидающий перетаскивания в документ.",
        "demoFileName": "Демо EdgeShelf.txt",
        "demoFileText": "Этот файл был перетащен на полку EdgeShelf.",
    ]

    private static let arabic: [String: String] = [
        "shelf": "رف",
        "statusTooltip": "EdgeShelf — اسحب العناصر إلى حافة الشاشة",
        "dropHere": "أفلت أي شيء هنا",
        "dropTypes": "ملفات · مجلدات · نصوص · روابط",
        "copying": "جارٍ النسخ…",
        "file": "ملف",
        "folder": "مجلد",
        "image": "صورة",
        "text": "نص",
        "link": "رابط",
        "open": "فتح",
        "showInFinder": "إظهار في Finder",
        "copy": "نسخ",
        "remove": "إزالة",
        "removeFromShelf": "إزالة من الرف",
        "clearShelf": "إفراغ الرف…",
        "clearAllShelves": "إفراغ كل الرفوف…",
        "clearShelfTitle": "إفراغ هذا الرف؟",
        "clearShelfConfirm": "سيؤدي هذا إلى حذف النسخ التي أنشأها EdgeShelf لهذه العناصر. لن تتأثر الملفات الأصلية. لا يمكن استرداد النصوص والروابط ولقطات الشاشة الموجودة على الرف.",
        "removeItemHelp": "إزالة من الرف",
        "showShelves": "إظهار الرفوف",
        "hideEmptyShelves": "إخفاء الرفوف الفارغة",
        "preferences": "الإعدادات…",
        "about": "حول EdgeShelf",
        "quit": "إنهاء EdgeShelf",
        "prefsTitle": "إعدادات EdgeShelf",
        "prefsIntro": "اسحب الملفات أو المجلدات أو النصوص أو الصور أو الروابط إلى حافة الشاشة. سيبقى الرف هناك حتى تسحب العناصر للخارج.",
        "enableLeft": "تفعيل الحافة اليسرى للشاشة",
        "enableRight": "تفعيل الحافة اليمنى للشاشة",
        "removeAfterDragOut": "إزالة العناصر بعد سحبها للخارج",
        "closeWhenEmpty": "إغلاق الرف عند إزالة آخر عنصر",
        "showDataFolder": "إظهار مجلد البيانات",
        "closeAllShelves": "إغلاق كل الرفوف",
        "removeAllTitle": "إزالة كل عناصر الرفوف؟",
        "removeAllInfo": "سيتم حذف النسخ التي أنشأها EdgeShelf لكل عنصر موجود على الرفوف. لن تتأثر الملفات الأصلية.",
        "cancel": "إلغاء",
        "removeAll": "إزالة الكل",
        "languageLabel": "اللغة",
        "followSystem": "حسب النظام",
        "aboutText": """
        EdgeShelf هو إعادة تنفيذ لتطبيق Dropshelf لنظام macOS 26/27.

        اسحب الملفات أو المجلدات أو النصوص أو الصور أو الروابط إلى الحافة اليسرى أو اليمنى للشاشة. يحتفظ الرف بنسخة ليبقى العنصر متاحًا حتى إذا نُقل الأصل.

        الإصدار %@
        """,
        "ok": "حسنًا",
        "leftEdge": "الحافة اليسرى",
        "rightEdge": "الحافة اليمنى",
        "incomingFile": "ملف قادم",
        "unavailableFile": "ملف غير متاح",
        "demoWelcomeTitle": "مرحبًا بك في EdgeShelf",
        "demoWelcomeText": "اسحب الملفات أو المجلدات أو النصوص أو الصور أو الروابط إلى حافة الشاشة.",
        "demoDesignTitle": "ملاحظات التصميم",
        "demoDesignText": "لوحة ورقية دافئة، خطوط قطرية هادئة، بطاقة واضحة لكل عنصر.",
        "demoReadingTitle": "قائمة القراءة",
        "demoReadingText": "يجب أن يبدو الرف كمكان، لا كنافذة.",
        "demoScreenshotTitle": "لقطة.png",
        "demoScreenshotText": "لقطة شاشة تنتظر السحب إلى مستند.",
        "demoFileName": "عرض EdgeShelf.txt",
        "demoFileText": "تم إفلات هذا الملف على رف EdgeShelf.",
    ]
}

import AppKit

// MARK: - Metrics

enum ShelfMetrics {
    static let panelWidth: CGFloat = 300
    static let shadowMargin: CGFloat = 10
    static let windowWidth: CGFloat = panelWidth + shadowMargin * 2

    static let headerHeight: CGFloat = 48
    static let contentInset: CGFloat = 14
    static let itemHeight: CGFloat = 64
    static let itemSpacing: CGFloat = 6
    static let topPadding: CGFloat = 10
    static let bottomPadding: CGFloat = 10

    static let minPanelHeight: CGFloat = 220
    static let maxPanelHeight: CGFloat = 560
    static let emptyPanelHeight: CGFloat = 260

    static let cornerRadius: CGFloat = 20
    static let itemCornerRadius: CGFloat = 12
    static let itemWidth: CGFloat = panelWidth - contentInset * 2

    static func panelHeight(forItemCount count: Int) -> CGFloat {
        guard count > 0 else { return emptyPanelHeight }
        let items = CGFloat(count) * itemHeight
        let gaps = CGFloat(max(0, count - 1)) * itemSpacing
        let raw = headerHeight + topPadding + items + gaps + bottomPadding
        return min(max(raw, minPanelHeight), maxPanelHeight)
    }

    static func windowHeight(forItemCount count: Int) -> CGFloat {
        panelHeight(forItemCount: count) + shadowMargin * 2
    }
}

// MARK: - Palette

enum ShelfTheme {
    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    // Warm terracotta accent. Chosen to stand out against the paper panel,
    // the graphite panel, and the blue desktop wallpaper.
    private static let accentLight = NSColor(calibratedRed: 0.80, green: 0.43, blue: 0.18, alpha: 1)
    private static let accentDark = NSColor(calibratedRed: 0.96, green: 0.62, blue: 0.32, alpha: 1)

    static let accent = dynamic(light: accentLight, dark: accentDark)
    static let accentText = dynamic(
        light: NSColor(calibratedRed: 0.62, green: 0.28, blue: 0.08, alpha: 1),
        dark: NSColor(calibratedRed: 1.00, green: 0.76, blue: 0.55, alpha: 1)
    )
    static let accentSoft = dynamic(
        light: accentLight.withAlphaComponent(0.14),
        dark: accentDark.withAlphaComponent(0.20)
    )
    static let accentBorder = dynamic(
        light: accentLight.withAlphaComponent(0.55),
        dark: accentDark.withAlphaComponent(0.65)
    )

    /// Warm paper in light mode, graphite in dark mode.
    static let panel = dynamic(
        light: NSColor(calibratedRed: 0.972, green: 0.968, blue: 0.954, alpha: 0.985),
        dark: NSColor(calibratedRed: 0.105, green: 0.105, blue: 0.115, alpha: 0.985)
    )

    static let card = dynamic(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.92),
        dark: NSColor(calibratedRed: 0.165, green: 0.165, blue: 0.178, alpha: 0.96)
    )

    static let cardHover = dynamic(
        light: NSColor(calibratedWhite: 1.0, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.215, green: 0.215, blue: 0.232, alpha: 1.0)
    )

    static let border = dynamic(
        light: NSColor.black.withAlphaComponent(0.075),
        dark: NSColor.white.withAlphaComponent(0.10)
    )

    static let stripe = dynamic(
        light: NSColor.black.withAlphaComponent(0.022),
        dark: NSColor.white.withAlphaComponent(0.030)
    )

    static let emptyFill = dynamic(
        light: accentLight.withAlphaComponent(0.06),
        dark: accentDark.withAlphaComponent(0.09)
    )

    static let tabTop = dynamic(
        light: accentLight.withAlphaComponent(0.98),
        dark: accentDark.withAlphaComponent(1.0)
    )

    static let tabBottom = dynamic(
        light: accentLight.withAlphaComponent(0.58),
        dark: accentDark.withAlphaComponent(0.62)
    )
}

// MARK: - Panel background

final class ShelfBackgroundView: NSView {
    private var isHighlighted = false

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.24
        layer?.shadowRadius = 18
        layer?.shadowOffset = CGSize(width: 0, height: -4)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setHighlighted(_ highlighted: Bool) {
        guard highlighted != isHighlighted else { return }
        isHighlighted = highlighted
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let radius = ShelfMetrics.cornerRadius
        layer?.shadowPath = CGPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                                   cornerWidth: radius,
                                   cornerHeight: radius,
                                   transform: nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = ShelfMetrics.cornerRadius
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        ShelfTheme.panel.setFill()
        path.fill()

        NSGraphicsContext.saveGraphicsState()
        path.addClip()

        // Soft top light.
        let gradient = NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.10),
            NSColor.white.withAlphaComponent(0.0),
        ])
        gradient?.draw(in: rect, angle: -90)

        // Dropshelf-style diagonal stripes, deliberately very quiet.
        ShelfTheme.stripe.setStroke()
        let spacing: CGFloat = 14
        var offset = -bounds.height
        while offset < bounds.width + bounds.height {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: offset, y: 0))
            line.line(to: NSPoint(x: offset + bounds.height, y: bounds.height))
            line.lineWidth = 1
            line.stroke()
            offset += spacing
        }

        NSGraphicsContext.restoreGraphicsState()

        // Inner border, accent on drop target.
        if isHighlighted {
            ShelfTheme.accent.withAlphaComponent(0.80).setStroke()
            path.lineWidth = 2
        } else {
            ShelfTheme.border.setStroke()
            path.lineWidth = 1
        }
        path.stroke()

        // Top highlight.
        let highlight = NSBezierPath()
        highlight.move(to: NSPoint(x: radius, y: bounds.height - 0.5))
        highlight.line(to: NSPoint(x: bounds.width - radius, y: bounds.height - 0.5))
        NSColor.white.withAlphaComponent(0.28).setStroke()
        highlight.lineWidth = 1
        highlight.stroke()
    }
}

// MARK: - Collapsed edge tab

final class ShelfTabView: NSView {
    private let gradient = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.masksToBounds = false
        layer?.shadowColor = ShelfTheme.accent.cgColor
        layer?.shadowOpacity = 0.35
        layer?.shadowRadius = 6
        layer?.shadowOffset = .zero
        gradient.cornerRadius = 4
        gradient.masksToBounds = true
        gradient.startPoint = CGPoint(x: 0.5, y: 1)
        gradient.endPoint = CGPoint(x: 0.5, y: 0)
        layer?.addSublayer(gradient)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        gradient.frame = bounds
        effectiveAppearance.performAsCurrentDrawingAppearance { [weak self] in
            guard let self else { return }
            self.gradient.colors = [
                ShelfTheme.tabTop.cgColor,
                ShelfTheme.tabBottom.cgColor,
            ]
            self.layer?.shadowColor = ShelfTheme.accent.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }
}

// MARK: - Empty state

final class EmptyStateView: NSView {
    private let dashedLayer = CAShapeLayer()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: L10n.dropHere)
    private let subtitleLabel = NSTextField(labelWithString: L10n.dropTypes)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        dashedLayer.fillColor = ShelfTheme.emptyFill.cgColor
        dashedLayer.strokeColor = ShelfTheme.accent.withAlphaComponent(0.32).cgColor
        dashedLayer.lineWidth = 1.5
        dashedLayer.lineDashPattern = [5, 4]
        dashedLayer.cornerRadius = 16
        layer?.addSublayer(dashedLayer)

        iconView.image = NSImage(systemSymbolName: "square.and.arrow.down.on.square",
                                 accessibilityDescription: L10n.dropHere)
        iconView.contentTintColor = .tertiaryLabelColor
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 10.5)
        subtitleLabel.textColor = .tertiaryLabelColor
        subtitleLabel.alignment = .center
        addSubview(subtitleLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let radius = 16
        dashedLayer.frame = bounds
        dashedLayer.path = CGPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                                  cornerWidth: CGFloat(radius),
                                  cornerHeight: CGFloat(radius),
                                  transform: nil)

        iconView.frame = NSRect(x: (bounds.width - 34) / 2, y: bounds.height - 66, width: 34, height: 34)
        titleLabel.frame = NSRect(x: 10, y: 38, width: bounds.width - 20, height: 18)
        subtitleLabel.frame = NSRect(x: 10, y: 18, width: bounds.width - 20, height: 15)
    }

    func setHighlighted(_ highlighted: Bool) {
        dashedLayer.strokeColor = ShelfTheme.accent
            .withAlphaComponent(highlighted ? 0.80 : 0.32).cgColor
        dashedLayer.fillColor = ShelfTheme.emptyFill.cgColor
    }
}

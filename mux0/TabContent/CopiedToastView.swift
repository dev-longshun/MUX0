import AppKit

/// Lightweight "Copied" toast that fades in at the bottom-right of its superview,
/// then fades out after a short delay. Adapts to the current terminal theme.
final class CopiedToastView: NSView {
    private let label = NSTextField(labelWithString: "")
    private var hideTask: Task<Void, Never>?

    /// Total visible duration before fade-out begins.
    private static let displayDuration: UInt64 = 2_500_000_000  // 2.5s
    /// Fade-in / fade-out animation duration.
    private static let fadeDuration: CFTimeInterval = 0.5
    /// Margin from the bottom-right corner of the superview.
    private static let margin: CGFloat = DT.Space.sm

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = DT.Radius.row
        alphaValue = 0

        label.font = DT.Font.small
        label.isBezeled = false
        label.isEditable = false
        label.drawsBackground = false
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DT.Space.sm),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DT.Space.sm),
            label.topAnchor.constraint(equalTo: topAnchor, constant: DT.Space.xs),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -DT.Space.xs),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Show the toast inside `parent`, positioned at bottom-right.
    /// If already visible, resets the timer.
    func show(in parent: NSView, theme: AppTheme) {
        hideTask?.cancel()

        // KAKU 风格：accent 紫色背景 + 白色文字
        layer?.backgroundColor = theme.accent.withAlphaComponent(
            theme.isDark ? 0.9 : 0.85
        ).cgColor
        label.textColor = .white
        label.stringValue = L10n.string("toast.copied")

        if superview !== parent {
            removeFromSuperview()
            translatesAutoresizingMaskIntoConstraints = false
            parent.addSubview(self)
            NSLayoutConstraint.activate([
                trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -Self.margin),
                bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -Self.margin),
            ])
        }

        // Fade in
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.fadeDuration
            animator().alphaValue = 1
        }

        // Schedule fade out
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.displayDuration)
            guard let self, !Task.isCancelled else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = Self.fadeDuration
                self.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                self?.removeFromSuperview()
            })
        }
    }
}

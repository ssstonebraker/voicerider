import AppKit

// MARK: - PermissionService presentation strings

extension PermissionService {

    /// One-sentence, user-task-shaped explanation rendered as the row subtitle.
    var userDescription: String {
        switch self {
        case .microphone:
            return "Record your voice while you hold the dictation hotkey."
        case .accessibility:
            return "Paste the transcribed text at your cursor by synthesizing Cmd+V."
        case .inputMonitoring:
            return "Detect the Right Option key globally so you can dictate from any app."
        }
    }

    /// Shown only on denied rows — explains the consequence of not granting.
    var denialConsequence: String {
        switch self {
        case .microphone:
            return "Without this, dictation cannot start."
        case .accessibility:
            return "Without this, transcribed text won't be pasted automatically."
        case .inputMonitoring:
            return "Without this, the hotkey won't work outside of VoiceRider's own window."
        }
    }

    /// SF Symbol name for the row icon.
    var iconName: String {
        switch self {
        case .microphone:      return "mic"
        case .accessibility:   return "cursorarrow.click.2"
        case .inputMonitoring: return "keyboard"
        }
    }
}

// MARK: - PermissionRowView

/// Single TCC row view: icon · title · subtitle · status pill · action button.
///
/// Renders from a `PermissionStatus`. Idempotent — calling `render`
/// repeatedly with the same value is a no-op visually.
@MainActor
final class PermissionRowView: NSView {

    let service: PermissionService

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")
    private let consequenceLabel = NSTextField(wrappingLabelWithString: "")
    private let statusPill = NSTextField(labelWithString: "")
    private let actionButton = NSButton(title: "", target: nil, action: nil)

    /// Called when the user clicks the row's action button.
    var onAction: () -> Void = {}

    /// Tracks last rendered state for idempotency.
    private var lastGranted: Bool?

    /// Test seam: incremented on every actual re-render.
    private(set) var renderCount = 0

    init(service: PermissionService) {
        self.service = service
        super.init(frame: .zero)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Renders the row from a `PermissionStatus`. Only re-renders if state changed.
    func render(_ status: PermissionStatus) {
        guard status.granted != lastGranted else { return }
        lastGranted = status.granted
        renderCount += 1

        if status.granted {
            statusPill.stringValue = "✓ Granted"
            statusPill.textColor = .systemGreen
            consequenceLabel.isHidden = true
            actionButton.title = "Open \(service.label) in Settings"
        } else {
            statusPill.stringValue = "✗ Not Granted"
            statusPill.textColor = .systemRed
            consequenceLabel.stringValue = "⚠️ \(service.denialConsequence)"
            consequenceLabel.isHidden = false
            actionButton.title = "Open \(service.label) in Settings"
        }

        setAccessibilityLabel("\(service.label) permission, \(status.granted ? "granted" : "not granted")")
    }

    // MARK: Private

    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false

        // Icon
        if let img = NSImage(systemSymbolName: service.iconName,
                             accessibilityDescription: service.label) {
            img.isTemplate = true
            iconView.image = img
        }
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        // Title
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.stringValue = service.label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Subtitle
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.stringValue = service.userDescription
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.preferredMaxLayoutWidth = 400

        // Consequence (hidden by default)
        consequenceLabel.font = .systemFont(ofSize: 11)
        consequenceLabel.textColor = .systemOrange
        consequenceLabel.isHidden = true
        consequenceLabel.translatesAutoresizingMaskIntoConstraints = false
        consequenceLabel.preferredMaxLayoutWidth = 400

        // Status pill
        statusPill.font = .systemFont(ofSize: 11, weight: .medium)
        statusPill.translatesAutoresizingMaskIntoConstraints = false
        statusPill.setContentHuggingPriority(.required, for: .horizontal)

        // Action button
        actionButton.bezelStyle = .rounded
        actionButton.controlSize = .small
        actionButton.target = self
        actionButton.action = #selector(buttonPressed)
        actionButton.translatesAutoresizingMaskIntoConstraints = false

        // Text stack (title + subtitle + consequence)
        let textStack = NSStackView(views: [titleLabel, subtitleLabel, consequenceLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        // Right column (pill + button)
        let rightStack = NSStackView(views: [statusPill, actionButton])
        rightStack.orientation = .vertical
        rightStack.alignment = .trailing
        rightStack.spacing = 4
        rightStack.translatesAutoresizingMaskIntoConstraints = false

        // Main horizontal
        let mainStack = NSStackView(views: [iconView, textStack, rightStack])
        mainStack.orientation = .horizontal
        mainStack.alignment = .top
        mainStack.spacing = 10
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    @objc private func buttonPressed() {
        actionButton.isEnabled = false
        onAction()
        // Rate-limit: re-enable after 800 ms (C14).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.actionButton.isEnabled = true
        }
    }
}

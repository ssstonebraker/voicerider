import AppKit

/// Single TCC-permission row: icon · title · subtitle · status pill · action button.
///
/// Renders a `PermissionStatus` by reflecting state into visual
/// elements: green "✓ Granted" pill when granted, red "✗ Denied"
/// pill with a denial-consequence subtitle when denied.
///
/// The row is `PermissionService`-keyed and references no other source
/// of truth for TCC state (Sauron — `Permissions.swift` is queried by
/// the controller, not by this view).
///
/// Annie: every property and method below is called from
/// `PermissionsWindowController.swift`. If any becomes orphaned,
/// delete it in the same PR.
@MainActor
final class PermissionRowView: NSView {

    let service: PermissionService

    private let iconLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")
    private let consequenceLabel = NSTextField(wrappingLabelWithString: "")
    private let statusPill = NSTextField(labelWithString: "")
    private let actionButton = NSButton(title: "", target: nil, action: nil)

    /// Fires when the user clicks the row's action button.
    var onAction: () -> Void = {}

    /// Tracks whether `render` was called (test seam for snapshot-diff
    /// assertions). Increments on every `render(_:)` call.
    private(set) var renderCount = 0

    init(service: PermissionService) {
        self.service = service
        super.init(frame: .zero)
        configureLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Render

    /// Renders the row from a `PermissionStatus`. Idempotent when the
    /// visual state has not changed. Called by the controller on every
    /// diff tick that includes this service.
    func render(_ status: PermissionStatus) {
        renderCount += 1

        iconLabel.stringValue = service.icon
        titleLabel.stringValue = service.label

        subtitleLabel.stringValue = service.userDescription

        if status.granted {
            statusPill.stringValue = "✓ Granted"
            statusPill.textColor = .systemGreen
            consequenceLabel.isHidden = true
            actionButton.title = "Open \(service.label) in Settings"
        } else {
            statusPill.stringValue = "✗ Denied"
            statusPill.textColor = .systemRed
            consequenceLabel.isHidden = false
            consequenceLabel.stringValue = "⚠️ " + service.denialConsequence
            actionButton.title = "Open \(service.label) in Settings"
        }

        setAccessibilityLabel("\(service.label) permission, \(status.granted ? "granted" : "denied")")
    }

    // MARK: Actions

    @objc private func buttonTapped() {
        actionButton.isEnabled = false
        onAction()
        // Rate-limit: re-enable after 800 ms (C14).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.actionButton.isEnabled = true
        }
    }

    // MARK: Layout

    private func configureLayout() {
        iconLabel.font = .systemFont(ofSize: 20)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        consequenceLabel.font = .systemFont(ofSize: 11)
        consequenceLabel.textColor = .systemOrange
        statusPill.font = .systemFont(ofSize: 11, weight: .medium)

        actionButton.bezelStyle = .rounded
        actionButton.controlSize = .small
        actionButton.target = self
        actionButton.action = #selector(buttonTapped)

        let titleStack = NSStackView(views: [titleLabel, statusPill])
        titleStack.orientation = .horizontal
        titleStack.distribution = .fill
        statusPill.setContentHuggingPriority(.required, for: .horizontal)

        let bodyStack = NSStackView(views: [titleStack, subtitleLabel, consequenceLabel, actionButton])
        bodyStack.orientation = .vertical
        bodyStack.alignment = .leading
        bodyStack.spacing = 4

        let rowStack = NSStackView(views: [iconLabel, bodyStack])
        rowStack.orientation = .horizontal
        rowStack.alignment = .top
        rowStack.spacing = 12
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(rowStack)
        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            rowStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            rowStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])

        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
    }
}

// MARK: - PermissionService presentation strings

/// Presentation-layer strings for each TCC service. Lives here (not
/// in PermissionStatus.swift) because these are UI concerns, not
/// data-model concerns. The data-model file's responsibility is the
/// snapshot; display text lives with the window/row code.
extension PermissionService {

    /// SF Symbol or emoji glyph for the row icon.
    var icon: String {
        switch self {
        case .microphone:      return "🎙️"
        case .accessibility:   return "🖱️"
        case .inputMonitoring: return "⌨️"
        }
    }

    /// One-sentence, user-task-shaped explanation. Rendered as the
    /// row subtitle. HCI: match between system and real world.
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

    /// "What happens if I deny this?" Shown only on denied rows.
    /// HCI: error prevention / visibility of system status.
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
}

import Testing
import Foundation
@testable import VoiceRider

// MARK: - PermissionService description fixtures

@Suite("PermissionServiceDescription")
struct PermissionServiceDescriptionTests {

    @Test("every service has a non-empty userDescription",
          arguments: PermissionService.allCases)
    func userDescriptionNonEmpty(service: PermissionService) {
        #expect(!service.userDescription.isEmpty)
    }

    @Test("every service has a non-empty denialConsequence",
          arguments: PermissionService.allCases)
    func denialConsequenceNonEmpty(service: PermissionService) {
        #expect(!service.denialConsequence.isEmpty)
    }

    @Test("every service has a non-empty iconName",
          arguments: PermissionService.allCases)
    func iconNameNonEmpty(service: PermissionService) {
        #expect(!service.iconName.isEmpty)
    }

    @Test("pinned userDescription values")
    func pinnedUserDescriptions() {
        #expect(PermissionService.microphone.userDescription
                == "Record your voice while you hold the dictation hotkey.")
        #expect(PermissionService.accessibility.userDescription
                == "Paste the transcribed text at your cursor by synthesizing Cmd+V.")
        #expect(PermissionService.inputMonitoring.userDescription
                == "Detect the Right Option key globally so you can dictate from any app.")
    }

    @Test("pinned denialConsequence values")
    func pinnedDenialConsequences() {
        #expect(PermissionService.microphone.denialConsequence
                == "Without this, dictation cannot start.")
        #expect(PermissionService.accessibility.denialConsequence
                == "Without this, transcribed text won't be pasted automatically.")
        #expect(PermissionService.inputMonitoring.denialConsequence
                == "Without this, the hotkey won't work outside of VoiceRider's own window.")
    }
}

// MARK: - PermissionRowView render tests

@Suite("PermissionRowView")
struct PermissionRowViewTests {

    @Test("render with granted status sets renderCount to 1")
    @MainActor func renderGranted() {
        let row = PermissionRowView(service: .microphone)
        let status = PermissionStatus(service: .microphone, granted: true)
        row.render(status)
        #expect(row.renderCount == 1)
    }

    @Test("render with denied status sets renderCount to 1")
    @MainActor func renderDenied() {
        let row = PermissionRowView(service: .accessibility)
        let status = PermissionStatus(service: .accessibility, granted: false)
        row.render(status)
        #expect(row.renderCount == 1)
    }

    @Test("render is idempotent — same state does not increment renderCount")
    @MainActor func renderIdempotent() {
        let row = PermissionRowView(service: .inputMonitoring)
        let status = PermissionStatus(service: .inputMonitoring, granted: true)
        row.render(status)
        row.render(status)
        row.render(status)
        #expect(row.renderCount == 1)
    }

    @Test("render flips state — two different renders bump count to 2")
    @MainActor func renderFlip() {
        let row = PermissionRowView(service: .microphone)
        row.render(PermissionStatus(service: .microphone, granted: false))
        row.render(PermissionStatus(service: .microphone, granted: true))
        #expect(row.renderCount == 2)
    }

    @Test("render all services in granted state",
          arguments: PermissionService.allCases)
    @MainActor func renderAllServicesGranted(service: PermissionService) {
        let row = PermissionRowView(service: service)
        let status = PermissionStatus(service: service, granted: true)
        row.render(status)
        #expect(row.renderCount == 1)
    }

    @Test("render all services in denied state",
          arguments: PermissionService.allCases)
    @MainActor func renderAllServicesDenied(service: PermissionService) {
        let row = PermissionRowView(service: service)
        let status = PermissionStatus(service: service, granted: false)
        row.render(status)
        #expect(row.renderCount == 1)
    }
}

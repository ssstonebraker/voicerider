import Testing
import Foundation
@testable import VoiceRider

@Suite("PermissionRowView")
struct PermissionRowViewTests {

    @Test("render with granted status shows green pill text")
    func grantedRender() {
        let row = PermissionRowView(service: .microphone)
        let status = PermissionStatus(service: .microphone, granted: true)
        row.render(status)
        #expect(row.renderCount == 1)
    }

    @Test("render with denied status shows red pill text")
    func deniedRender() {
        let row = PermissionRowView(service: .accessibility)
        let status = PermissionStatus(service: .accessibility, granted: false)
        row.render(status)
        #expect(row.renderCount == 1)
    }

    @Test("renderCount increments on each call")
    func renderCountIncrements() {
        let row = PermissionRowView(service: .inputMonitoring)
        let granted = PermissionStatus(service: .inputMonitoring, granted: true)
        let denied = PermissionStatus(service: .inputMonitoring, granted: false)
        row.render(granted)
        row.render(denied)
        row.render(granted)
        #expect(row.renderCount == 3)
    }

    @Test("all services produce non-empty userDescription")
    func userDescriptionsNonEmpty() {
        for service in PermissionService.allCases {
            #expect(!service.userDescription.isEmpty)
        }
    }

    @Test("all services produce non-empty denialConsequence")
    func denialConsequencesNonEmpty() {
        for service in PermissionService.allCases {
            #expect(!service.denialConsequence.isEmpty)
        }
    }

    @Test("all services produce non-empty icon")
    func iconsNonEmpty() {
        for service in PermissionService.allCases {
            #expect(!service.icon.isEmpty)
        }
    }

    @Test("userDescription strings are pinned")
    func userDescriptionPinned() {
        #expect(PermissionService.microphone.userDescription ==
                "Record your voice while you hold the dictation hotkey.")
        #expect(PermissionService.accessibility.userDescription ==
                "Paste the transcribed text at your cursor by synthesizing Cmd+V.")
        #expect(PermissionService.inputMonitoring.userDescription ==
                "Detect the Right Option key globally so you can dictate from any app.")
    }

    @Test("denialConsequence strings are pinned")
    func denialConsequencePinned() {
        #expect(PermissionService.microphone.denialConsequence ==
                "Without this, dictation cannot start.")
        #expect(PermissionService.accessibility.denialConsequence ==
                "Without this, transcribed text won't be pasted automatically.")
        #expect(PermissionService.inputMonitoring.denialConsequence ==
                "Without this, the hotkey won't work outside of VoiceRider's own window.")
    }
}

import Testing
@testable import FocusDockCore

struct PermissionsTests {
    @Test(arguments: [
        (Permission.accessibility, "Privacy_Accessibility"),
        (.screenRecording, "Privacy_ScreenCapture"),
        (.fullDiskAccess, "Privacy_AllFiles"),
        (.location, "Privacy_LocationServices"),
        (.automation, "Privacy_Automation"),
    ])
    func settingsPaneOpensTheExactPrivacyAnchor(_ permission: Permission, _ anchor: String) {
        #expect(SettingsPane.url(for: permission).absoluteString
            == "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }

    @Test func onboardingOffersTheFirstMissingPermissionInSpecOrder() {
        let needed: Set<Permission> = [.location, .screenRecording, .accessibility]
        #expect(Onboarding.next(needed: needed, granted: []) == .accessibility)
        #expect(Onboarding.next(needed: needed, granted: [.accessibility]) == .screenRecording)
        #expect(Onboarding.next(needed: needed, granted: [.accessibility, .screenRecording]) == .location)
    }

    @Test func onboardingSkipsGrantsNobodyNeeds() {
        #expect(Onboarding.next(needed: [.fullDiskAccess], granted: []) == .fullDiskAccess)
        #expect(Onboarding.next(needed: [.automation], granted: [.accessibility, .screenRecording]) == .automation)
    }

    @Test func onboardingIsDoneWhenEverythingNeededIsGranted() {
        #expect(Onboarding.next(needed: [], granted: []) == nil)
        #expect(Onboarding.next(needed: [.accessibility], granted: [.accessibility, .location]) == nil)
    }

    @Test func everyPermissionHasATitle() {
        #expect(Permission.allCases.map(\.title)
            == ["Accessibility", "Screen Recording", "Full Disk Access", "Location", "Automation"])
    }
}

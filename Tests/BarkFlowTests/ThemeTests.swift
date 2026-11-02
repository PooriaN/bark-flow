import XCTest
@testable import BarkFlow

final class ThemeTests: XCTestCase {
    func testSavedThemeAndUnknownFutureValueFallback() {
        let name="local.barkflow.theme-tests.\(UUID().uuidString)"
        let defaults=UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        XCTAssertEqual(FlowTheme.saved(in:defaults),.minimal)
        for theme in FlowTheme.allCases {
            theme.save(in:defaults)
            XCTAssertEqual(FlowTheme.saved(in:defaults),theme)
        }
        defaults.set("retired-theme",forKey:FlowTheme.preferenceKey)
        XCTAssertEqual(FlowTheme.saved(in:defaults),.minimal)
    }
    func testEnvelopeAttackReleaseAndNoiseFloor() {
        var envelope=VoiceEnvelope()
        envelope.receive(0.02,at:0)
        XCTAssertEqual(envelope.value(at:1),0)
        envelope.receive(1,at:1)
        let attack=envelope.value(at:1.035)
        XCTAssertEqual(attack,1-exp(-1),accuracy:0.00001)
        envelope.receive(0,at:2)
        let release=envelope.value(at:2.22)
        XCTAssertEqual(release,exp(-1),accuracy:0.00001)
        XCTAssertGreaterThan(release,envelope.value(at:3))
        XCTAssertEqual(VoiceEnvelope.normalized(.nan),0)
        XCTAssertEqual(VoiceEnvelope.normalized(-1),0)
        XCTAssertEqual(VoiceEnvelope.normalized(2),1)
    }
}

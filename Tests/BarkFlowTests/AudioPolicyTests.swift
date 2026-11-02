import XCTest
@testable import BarkFlow

final class AudioPolicyTests: XCTestCase {
    func testSilenceAndEmptyInputAreRejected() {
        XCTAssertFalse(AudioPolicy.hasSpeechEnergy([]))
        XCTAssertFalse(AudioPolicy.hasSpeechEnergy(Array(repeating: 0, count: 16000)))
        XCTAssertFalse(AudioPolicy.hasSpeechEnergy(Array(repeating: 0.00001, count: 16000)))
    }
    func testAudibleInputPassesEnergyGate() {
        let samples = (0..<16000).map { Float(sin(Double($0) * 0.17) * 0.1) }
        XCTAssertTrue(AudioPolicy.hasSpeechEnergy(samples))
    }
}

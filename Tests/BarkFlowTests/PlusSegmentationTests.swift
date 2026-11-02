import XCTest
@testable import BarkFlow

final class PlusSegmentationTests: XCTestCase {
    func testBoundaryWindowKeepsTheUtteranceTogether() {
        let samples = [Float](repeating:0.01,count:236_000)
        XCTAssertEqual(PlusRuntime.segments(samples),[0..<samples.count])
    }
    func testLongDictationHasNoDroppedOrRepeatedSamples() {
        for seconds in [120,600] {
            let samples = [Float](repeating:0.01,count:seconds*16_000)
            let pieces = PlusRuntime.segments(samples)
            var end = 0
            for piece in pieces {
                XCTAssertEqual(piece.lowerBound,end)
                XCTAssertGreaterThan(piece.count,0)
                XCTAssertLessThanOrEqual(piece.count,236_000)
                end = piece.upperBound
            }
            XCTAssertEqual(end,samples.count)
        }
    }
}

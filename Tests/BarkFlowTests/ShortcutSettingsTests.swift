import XCTest
import Carbon
@testable import BarkFlow

final class ShortcutSettingsTests: XCTestCase {
    func testSeparateDefaultsAndPersistence() throws {
        let bindings = ShortcutBindings.defaults
        XCTAssertFalse(bindings.usesSameKey)
        try bindings.start.validate(for:.start)
        try bindings.stop.validate(for:.stop)
        let restored = try JSONDecoder().decode(ShortcutBindings.self,from:JSONEncoder().encode(bindings))
        XCTAssertEqual(restored,bindings)
    }
    func testBareKeysCannotStealOrdinaryTyping() {
        XCTAssertThrowsError(try ShortcutChord(keyCode:0,modifiers:0,keyName:"A").validate(for:.start))
        XCTAssertThrowsError(try ShortcutChord(keyCode:0,modifiers:UInt32(shiftKey),keyName:"A").validate(for:.start))
    }
    func testSingleFunctionKeyAndEscapeStop() throws {
        let f6 = ShortcutChord(keyCode:97,modifiers:0,keyName:"F6")
        try f6.validate(for:.start)
        let esc = ShortcutChord(keyCode:53,modifiers:0,keyName:"Esc")
        try esc.validate(for:.stop)
        XCTAssertThrowsError(try esc.validate(for:.start))
        XCTAssertTrue(ShortcutBindings(start:f6,stop:f6).usesSameKey)
    }
}

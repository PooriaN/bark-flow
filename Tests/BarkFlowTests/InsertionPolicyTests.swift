import XCTest
@testable import BarkFlow

final class InsertionPolicyTests: XCTestCase {
    func testRecreatedBrowserFieldMatchesOnlyInSameWindow() {
        XCTAssertTrue(InsertionPolicy.sameDestination(sameObject:false,sameWindow:true,originalID:"editor",currentID:"editor",sameRole:true))
        XCTAssertFalse(InsertionPolicy.sameDestination(sameObject:false,sameWindow:false,originalID:"editor",currentID:"editor",sameRole:true))
        XCTAssertFalse(InsertionPolicy.sameDestination(sameObject:false,sameWindow:true,originalID:nil,currentID:nil,sameRole:true))
        XCTAssertFalse(InsertionPolicy.sameDestination(sameObject:false,sameWindow:true,originalID:"editor",currentID:"search",sameRole:true))
    }
    func testPasteIsNotConfirmedByAnUnchangedOrUnreadableField() {
        XCTAssertFalse(InsertionPolicy.confirmed(before:"hello",after:"hello",text:"hello"))
        XCTAssertFalse(InsertionPolicy.confirmed(before:nil,after:nil,text:"hello"))
        XCTAssertFalse(InsertionPolicy.confirmed(before:"before",after:"something else",text:"hello"))
        XCTAssertTrue(InsertionPolicy.confirmed(before:"before ",after:"before hello",text:"hello"))
    }
}

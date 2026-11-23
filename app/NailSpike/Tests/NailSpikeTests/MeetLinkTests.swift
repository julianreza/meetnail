import Foundation
import XCTest
@testable import NailSpike

final class MeetLinkTests: XCTestCase {
    func testOnlyCanonicalMeetLinksMayLaunchTheWorker() {
        XCTAssertTrue(MeetSession.validLink("https://meet.google.com/abc-defg-hij"))
        XCTAssertFalse(MeetSession.validLink("http://meet.google.com/abc-defg-hij"))
        XCTAssertFalse(MeetSession.validLink("https://meet.google.com.evil.example/abc-defg-hij"))
        XCTAssertFalse(MeetSession.validLink("https://meet.google.com/abc-defg-hij/other"))
        XCTAssertFalse(MeetSession.validLink("--login"))
    }
}

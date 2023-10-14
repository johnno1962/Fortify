import XCTest
@testable import Fortify

final class FortifyTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        var forced: String?
        do {
            try Fortify.protect {
                _ = forced!
            }
        } catch {
            print(error)
        }
        XCTAssertNil(forced)
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}

import XCTest
@testable import mux0

final class GhosttyBridgeCommandTests: XCTestCase {
    func testStartupInputTrimsCommandAndAppendsNewline() {
        XCTAssertEqual(
            WorkspaceDefaultCommand.startupInput(for: "  claude  "),
            "claude\n")
    }

    func testStartupInputReturnsNilForEmptyCommand() {
        XCTAssertNil(WorkspaceDefaultCommand.startupInput(for: nil))
        XCTAssertNil(WorkspaceDefaultCommand.startupInput(for: "   "))
    }
}

import XCTest
@testable import mux0

final class NotificationNamesTests: XCTestCase {
    func testNewMenuNotificationRawValues() {
        XCTAssertEqual(Notification.Name.mux0FocusNextPane.rawValue, "mux0.focusNextPane")
        XCTAssertEqual(Notification.Name.mux0FocusPrevPane.rawValue, "mux0.focusPrevPane")
        XCTAssertEqual(Notification.Name.mux0Copy.rawValue,          "mux0.copy")
        XCTAssertEqual(Notification.Name.mux0Paste.rawValue,         "mux0.paste")
        XCTAssertEqual(Notification.Name.mux0SelectAll.rawValue,     "mux0.selectAll")
    }
}

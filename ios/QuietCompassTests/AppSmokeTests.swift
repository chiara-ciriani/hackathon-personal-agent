import XCTest
import QuietCore
@testable import QuietCompass

final class AppSmokeTests: XCTestCase {
    @MainActor func testIdleModelDoesNotStartSensors() {
        let model = CompassModel()
        XCTAssertFalse(model.running)
        XCTAssertFalse(model.starting)
        XCTAssertNil(model.level)
    }
}

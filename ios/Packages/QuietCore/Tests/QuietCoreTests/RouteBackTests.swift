import XCTest
@testable import QuietCore

final class RouteBackTests: XCTestCase {
    private let session = UUID()

    /// An L-shaped walk: 6 m along −Z, then 4 m along +X, one crumb per metre.
    private func lWalk(segments: [Int]? = nil) -> [Crumb] {
        var points: [Position] = (0...6).map { Position(x: 0, z: -Double($0)) }
        points += (1...4).map { Position(x: Double($0), z: -6) }
        return points.enumerated().map { i, p in
            Crumb(sessionId: session, seq: i, segment: segments?[i] ?? 0, position: p, headingRad: 0,
                  t: Date(timeIntervalSince1970: Double(i)), tracking: .normal)
        }
    }

    func testRouteBackToStartReversesAndSimplifies() throws {
        let crumbs = lWalk()
        let route = try XCTUnwrap(RouteBack.route(crumbs: crumbs, to: Position(x: 0, z: 0),
                                                  targetCrumbId: crumbs[0].id))
        XCTAssertFalse(route.isPartial)
        XCTAssertEqual(route.path.first, Position(x: 4, z: -6))
        XCTAssertEqual(route.path.last, Position(x: 0, z: 0))
        XCTAssertEqual(route.keypoints, [Position(x: 4, z: -6), Position(x: 0, z: -6), Position(x: 0, z: 0)])
        XCTAssertEqual(route.lengthM, 10, accuracy: 1e-9)
        XCTAssertEqual(route.walkMinutes, 10 / 0.8 / 60, accuracy: 1e-9)
    }

    func testTargetAfterCurrentWalksForward() throws {
        let crumbs = lWalk()
        let route = try XCTUnwrap(RouteBack.route(crumbs: crumbs, to: Position(x: 4, z: -6),
                                                  fromCrumbId: crumbs[2].id))
        XCTAssertEqual(route.path.first, Position(x: 0, z: -2))
        XCTAssertEqual(route.path.last, Position(x: 4, z: -6))
        XCTAssertEqual(route.lengthM, 8, accuracy: 1e-9)
    }

    func testTargetWithoutCrumbIdSnapsToNearestCrumbAndEndsAtTarget() throws {
        let crumbs = lWalk()
        let target = Position(x: 0.5, z: -3.2)
        let route = try XCTUnwrap(RouteBack.route(crumbs: crumbs, to: target))
        XCTAssertEqual(route.path.last, target)
        XCTAssertEqual(route.path[route.path.count - 2], Position(x: 0, z: -3))
    }

    func testCurrentPositionIsPrepended() throws {
        let crumbs = lWalk()
        let route = try XCTUnwrap(RouteBack.route(crumbs: crumbs, to: .init(x: 0, z: 0),
                                                  targetCrumbId: crumbs[0].id, current: .init(x: 4.6, z: -6)))
        XCTAssertEqual(route.path.first, Position(x: 4.6, z: -6))
    }

    func testSegmentGapReturnsPartialPath() throws {
        // Crumbs 0...3 in segment 0, the rest in segment 1.
        let crumbs = lWalk(segments: [0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1])
        let route = try XCTUnwrap(RouteBack.route(crumbs: crumbs, to: .init(x: 0, z: 0),
                                                  targetCrumbId: crumbs[0].id))
        XCTAssertTrue(route.isPartial)
        XCTAssertEqual(route.path.last, Position(x: 0, z: -4)) // first crumb of segment 1
        XCTAssertFalse(route.path.contains(Position(x: 0, z: 0)))
    }

    func testEmptyCrumbsGiveNoRoute() {
        XCTAssertNil(RouteBack.route(crumbs: [], to: .init(x: 0, z: 0)))
        XCTAssertNil(RouteBack.route(crumbs: lWalk(), to: .init(x: 0, z: 0), fromCrumbId: UUID()))
    }

    func testRDPKeepsEndpointsAndDropsNoise() {
        let noisy = [Position(x: 0, z: 0), Position(x: 1, z: 0.3), Position(x: 2, z: -0.2),
                     Position(x: 3, z: 0.1), Position(x: 4, z: 0)]
        XCTAssertEqual(RouteBack.simplify(noisy, epsilon: 0.75), [noisy[0], noisy[4]])
        XCTAssertEqual(RouteBack.simplify(Array(noisy.prefix(2)), epsilon: 0.75).count, 2)
    }

    func testNextTurnInstructions() throws {
        let crumbs = lWalk()
        let route = try XCTUnwrap(RouteBack.route(crumbs: crumbs, to: .init(x: 0, z: 0), targetCrumbId: crumbs[0].id))
        // At (4,-6) facing −X (heading −π/2): the corner (0,-6) is straight ahead.
        var turn = try XCTUnwrap(RouteBack.nextTurn(on: route, from: .init(x: 4, z: -6), headingRad: -.pi / 2))
        XCTAssertEqual(turn.keypointIndex, 1)
        XCTAssertEqual(turn.instruction, .straight)
        XCTAssertEqual(turn.distanceToKeypointM, 4, accuracy: 1e-9)
        XCTAssertEqual(turn.remainingM, 10, accuracy: 1e-9)
        XCTAssertFalse(turn.hasArrived)

        // At the corner still facing −X: the start (0,0) is towards +Z, which is to the left.
        turn = try XCTUnwrap(RouteBack.nextTurn(on: route, from: .init(x: 0.2, z: -6), headingRad: -.pi / 2))
        XCTAssertEqual(turn.keypointIndex, 2)
        XCTAssertEqual(turn.instruction, .left)

        // Facing +X at the far end: corner is behind, i.e. a large turn; sign decides left/right.
        turn = try XCTUnwrap(RouteBack.nextTurn(on: route, from: .init(x: 4, z: -6.5), headingRad: .pi / 2 + 0.6))
        XCTAssertEqual(turn.instruction, .right)

        // 20° off is inside the dead zone.
        turn = try XCTUnwrap(RouteBack.nextTurn(on: route, from: .init(x: 4, z: -6), headingRad: -.pi / 2 + 20 * .pi / 180))
        XCTAssertEqual(turn.instruction, .straight)

        // Unknown heading: distance only.
        turn = try XCTUnwrap(RouteBack.nextTurn(on: route, from: .init(x: 0, z: -1.5), headingRad: nil))
        XCTAssertNil(turn.instruction)
        XCTAssertTrue(turn.hasArrived)
    }

    func testPlaceLocatorRadius() {
        let near = Place(sessionId: session, label: "Window", position: .init(x: 1, z: 1), crumbId: nil)
        let far = Place(sessionId: session, label: "Bar", position: .init(x: 10, z: 0), crumbId: nil)
        let locator = PlaceLocator(places: [far, near])
        XCTAssertEqual(locator.nearestPlace(to: .init(x: 0, z: 0))?.id, near.id) // 1.41 m
        XCTAssertNil(locator.nearestPlace(to: .init(x: 5, z: 0)))
        XCTAssertNil(locator.nearestPlace(to: nil))
    }

    func testPlaceLocatorZones() {
        let old = Place(sessionId: session, label: "Coffee", position: nil, crumbId: nil, zone: "Coffee bar",
                        createdAt: Date(timeIntervalSince1970: 1))
        let new = Place(sessionId: session, label: "Coffee 2", position: nil, crumbId: nil, zone: "coffee bar ",
                        createdAt: Date(timeIntervalSince1970: 2))
        let locator = PlaceLocator(places: [old, new])
        XCTAssertEqual(locator.placeId(position: nil, zone: "COFFEE BAR"), new.id)
        XCTAssertNil(locator.placeId(position: nil, zone: "Stage"))
        XCTAssertNil(locator.placeId(position: nil, zone: nil))
    }

    func testZoneRouteRemovesLoops() {
        let visits = ["Entrance", "Hall", "Stage", "Hall", "Coffee bar"]
        XCTAssertEqual(ZoneRoute.stepsBack(visits: visits, to: "Entrance"), ["Coffee bar", "Hall", "Entrance"])
        XCTAssertEqual(ZoneRoute.stepsBack(visits: visits, to: "Stage"), ["Coffee bar", "Hall", "Stage"])
        XCTAssertEqual(ZoneRoute.stepsBack(visits: visits, to: "Roof"), ["Roof"])
        XCTAssertEqual(ZoneRoute.stepsBack(visits: ["Hall", "Hall"], to: "hall"), ["Hall"])
    }
}

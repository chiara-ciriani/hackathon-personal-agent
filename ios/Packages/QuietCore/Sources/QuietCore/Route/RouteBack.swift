import Foundation

/// A route back to a target, built by reversing the path the user actually walked.
public struct Route: Sendable, Hashable {
    /// Every crumb position on the way, user end first.
    public var path: [Position]
    /// `path` simplified with Ramer–Douglas–Peucker into turn keypoints; first is the start, last the end.
    public var keypoints: [Position]
    /// True when the walked path crosses a tracking gap before reaching the target. `path` then
    /// ends at the edge of the current segment, and the UI should say the rest is unmapped.
    public var isPartial: Bool
    /// Walked length along `path`, in metres.
    public var lengthM: Double
    /// Estimated walk time at `RouteBack.walkingSpeedMps`.
    public var walkMinutes: Double { lengthM / RouteBack.walkingSpeedMps / 60 }
}

public enum TurnInstruction: String, Sendable, Hashable {
    case straight, left, right

    public var phrase: String {
        switch self {
        case .straight: "Keep going straight"
        case .left: "Turn left"
        case .right: "Turn right"
        }
    }
}

/// Where to go next along a route, from the user's current pose.
public struct NextTurn: Sendable, Hashable {
    /// Index into `Route.keypoints` of the keypoint to head for.
    public var keypointIndex: Int
    public var distanceToKeypointM: Double
    /// Remaining walk to the route's end through the remaining keypoints.
    public var remainingM: Double
    /// Bearing to the keypoint relative to the user's heading, radians in (−π, π]; positive is to the right.
    public var relativeBearingRad: Double?
    /// nil when the heading is unknown.
    public var instruction: TurnInstruction?
    /// True once the user is within `RouteBack.arrivalRadiusM` of the route's end.
    public var hasArrived: Bool
}

public enum RouteBack {
    public static let walkingSpeedMps = 0.8
    public static let simplifyEpsilonM = 0.75
    public static let straightDeadZoneRad = 25 * Double.pi / 180
    public static let arrivalRadiusM = 2.0
    /// A keypoint closer than this counts as reached and guidance moves on to the next one.
    public static let keypointReachedM = 1.0

    /// Builds the route from the user to `target` along the recorded crumbs.
    ///
    /// - Parameters:
    ///   - crumbs: the session's crumbs, in any order (sorted by `seq` here).
    ///   - target: where to end, usually the place's position.
    ///   - targetCrumbId: the crumb the place was marked at, if known; otherwise the crumb nearest `target`.
    ///   - fromCrumbId: the crumb to start from; defaults to the latest crumb.
    ///   - current: the user's live position, prepended when it differs from the start crumb.
    /// - Returns: nil when there are no crumbs or the start crumb is unknown.
    public static func route(crumbs: [Crumb], to target: Position, targetCrumbId: UUID? = nil,
                             fromCrumbId: UUID? = nil, current: Position? = nil) -> Route? {
        let ordered = crumbs.sorted { $0.seq < $1.seq }
        guard !ordered.isEmpty else { return nil }

        let startIndex: Int
        if let fromCrumbId {
            guard let i = ordered.firstIndex(where: { $0.id == fromCrumbId }) else { return nil }
            startIndex = i
        } else {
            startIndex = ordered.count - 1
        }
        let targetIndex = targetCrumbId.flatMap { id in ordered.firstIndex { $0.id == id } }
            ?? nearestIndex(in: ordered, to: target)

        // Walk from the start towards the target in recorded order, stopping at a segment boundary.
        let step = targetIndex >= startIndex ? 1 : -1
        var indices = [startIndex]
        var isPartial = false
        var i = startIndex
        while i != targetIndex {
            let next = i + step
            if ordered[next].segment != ordered[i].segment {
                isPartial = true
                break
            }
            indices.append(next)
            i = next
        }

        var path = indices.map { ordered[$0].position }
        if let current, let first = path.first, current.distance(to: first) > 0.1 {
            path.insert(current, at: 0)
        }
        if !isPartial, let last = path.last, target.distance(to: last) > 0.3 {
            path.append(target)
        }
        return Route(path: path, keypoints: simplify(path, epsilon: simplifyEpsilonM),
                     isPartial: isPartial, lengthM: length(of: path))
    }

    /// Guidance towards the next keypoint not yet reached.
    public static func nextTurn(on route: Route, from position: Position, headingRad: Double?) -> NextTurn? {
        let points = route.keypoints
        guard let end = points.last else { return nil }
        let hasArrived = position.distance(to: end) <= arrivalRadiusM

        // The next keypoint is the end of the polyline leg closest to the user, skipping reached ones.
        var target = 0
        if points.count > 1 {
            var best = Double.infinity
            for leg in 0..<(points.count - 1) {
                let d = distance(from: position, toSegment: points[leg], points[leg + 1])
                if d < best { best = d; target = leg + 1 }
            }
            while target < points.count - 1, position.distance(to: points[target]) < keypointReachedM {
                target += 1
            }
        }

        let toKeypoint = position.distance(to: points[target])
        let rest = target < points.count - 1 ? length(of: Array(points[target...])) : 0
        var relative: Double?
        var instruction: TurnInstruction?
        if let headingRad, toKeypoint > 0.01 {
            let rel = Heading.normalize(Heading.bearing(from: position, to: points[target]) - headingRad)
            relative = rel
            instruction = abs(rel) <= straightDeadZoneRad ? .straight : (rel > 0 ? .right : .left)
        }
        return NextTurn(keypointIndex: target, distanceToKeypointM: toKeypoint, remainingM: toKeypoint + rest,
                        relativeBearingRad: relative, instruction: instruction, hasArrived: hasArrived)
    }

    // MARK: - Geometry

    public static func length(of path: [Position]) -> Double {
        zip(path, path.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    /// Ramer–Douglas–Peucker simplification. Keeps the first and last points.
    public static func simplify(_ points: [Position], epsilon: Double) -> [Position] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack = [(0, points.count - 1)]
        while case let (lo, hi)? = stack.popLast() {
            guard hi > lo + 1 else { continue }
            var maxD = 0.0, maxI = lo
            for k in (lo + 1)..<hi {
                let d = distance(from: points[k], toSegment: points[lo], points[hi])
                if d > maxD { maxD = d; maxI = k }
            }
            if maxD > epsilon {
                keep[maxI] = true
                stack.append((lo, maxI))
                stack.append((maxI, hi))
            }
        }
        return points.indices.filter { keep[$0] }.map { points[$0] }
    }

    public static func distance(from p: Position, toSegment a: Position, _ b: Position) -> Double {
        let dx = b.x - a.x, dz = b.z - a.z
        let len2 = dx * dx + dz * dz
        guard len2 > 1e-12 else { return p.distance(to: a) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.z - a.z) * dz) / len2))
        return p.distance(to: Position(x: a.x + t * dx, z: a.z + t * dz))
    }

    static func nearestIndex(in crumbs: [Crumb], to target: Position) -> Int {
        var best = 0, bestD = Double.infinity
        for (i, c) in crumbs.enumerated() {
            let d = c.position.distance(to: target)
            if d < bestD { bestD = d; best = i }
        }
        return best
    }
}

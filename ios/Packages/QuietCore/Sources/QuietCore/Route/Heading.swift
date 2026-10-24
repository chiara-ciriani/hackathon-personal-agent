// Heading convention shared by tracking, routing and the minimap.
//
// Heading is a yaw angle in radians on the floor plane of the AR world frame (gravity-aligned,
// arbitrary yaw). 0 means facing world −Z, which is where the camera pointed when the AR session
// started. Angles grow clockwise seen from above, like a compass bearing: +π/2 faces world +X.
// On the minimap, world −Z is drawn up and +X right, so a heading draws as (sin h, −cos h)
// in screen coordinates (y down).
import Foundation

public enum Heading {
    /// Heading from the camera transform's third column (the camera's +Z axis, which points out of the
    /// back of the screen, i.e. towards the user). The camera looks along −Z, so forward = −column2.
    /// Returns nil when the forward vector is close to vertical (phone held flat), where yaw is unstable.
    public static func fromCameraZAxis(x: Double, z: Double, minHorizontal: Double = 0.2) -> Double? {
        let forwardX = -x, forwardZ = -z
        guard (forwardX * forwardX + forwardZ * forwardZ).squareRoot() >= minHorizontal else { return nil }
        return atan2(forwardX, -forwardZ)
    }

    /// Bearing of the straight line from `from` to `to`, in the heading convention.
    public static func bearing(from: Position, to: Position) -> Double {
        atan2(to.x - from.x, -(to.z - from.z))
    }

    /// Normalises an angle to (−π, π].
    public static func normalize(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a <= -.pi { a += 2 * .pi }
        if a > .pi { a -= 2 * .pi }
        return a
    }

    public static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}

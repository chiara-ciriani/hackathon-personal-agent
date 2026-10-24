import Foundation

/// Finds which marked place an observation belongs to. An immutable snapshot: rebuild it when places change.
public struct PlaceLocator: Sendable {
    public static let defaultRadiusM = 2.0

    public let places: [Place]
    public let radiusM: Double

    public init(places: [Place], radiusM: Double = PlaceLocator.defaultRadiusM) {
        self.places = places
        self.radiusM = radiusM
    }

    /// Mode A/C: the nearest place with a position within `radiusM`, or nil.
    public func nearestPlace(to position: Position?) -> Place? {
        guard let position else { return nil }
        var best: Place?
        var bestD = radiusM
        for place in places {
            guard let p = place.position else { continue }
            let d = p.distance(to: position)
            if d <= bestD { bestD = d; best = place }
        }
        return best
    }

    /// Mode B: the place for a zone label (case- and whitespace-insensitive); the newest wins on duplicates.
    public func place(inZone zone: String?) -> Place? {
        guard let key = zone.map(Self.zoneKey), !key.isEmpty else { return nil }
        return places.filter { $0.zone.map(Self.zoneKey) == key }.max { $0.createdAt < $1.createdAt }
    }

    /// Picks the right lookup for the capture mode.
    public func placeId(position: Position?, zone: String?) -> UUID? {
        if let position { return nearestPlace(to: position)?.id }
        return place(inZone: zone)?.id
    }

    static func zoneKey(_ zone: String) -> String {
        zone.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Mode B has no positions; the way back is the zones visited, in reverse, from the current zone to the target.
public enum ZoneRoute {
    /// - Parameters:
    ///   - visits: zone labels in the order the user entered them (repeats allowed).
    ///   - target: the target place's zone.
    /// - Returns: zones to walk through, current first and target last, with loops removed;
    ///   just `[target]` when the target was never visited.
    public static func stepsBack(visits: [String], to target: String) -> [String] {
        let key = PlaceLocator.zoneKey(target)
        var collapsed: [String] = []
        for zone in visits where collapsed.last.map(PlaceLocator.zoneKey) != PlaceLocator.zoneKey(zone) {
            collapsed.append(zone)
        }
        guard let targetIndex = collapsed.lastIndex(where: { PlaceLocator.zoneKey($0) == key }) else {
            return [target]
        }
        var steps: [String] = []
        for zone in collapsed[targetIndex...].reversed() {
            // Cut loops: if a zone already appears in the steps, the user can go straight from there.
            if let seen = steps.firstIndex(where: { PlaceLocator.zoneKey($0) == PlaceLocator.zoneKey(zone) }) {
                steps.removeSubrange((seen + 1)...)
            } else {
                steps.append(zone)
            }
        }
        return steps
    }
}

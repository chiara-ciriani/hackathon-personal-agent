// Top-down map of the walk: crumbs as a path, places as labelled dots with their level in words, the user
// as an arrow, and the route back when guidance is active (CompassModel computes the route). World −Z is drawn up and +X right (see
// QuietCore/Route/Heading.swift), so a heading h points along (sin h, −cos h) on screen.
import QuietCore
import SwiftUI

struct MinimapView: View {
    var model: CompassModel

    var body: some View {
        let summaries = model.placeSummaries
        let median = model.companion.sessionMedian
        VStack(alignment: .leading, spacing: 12) {
            if let turn = model.nextTurn {
                Card {
                    Text(turn.hasArrived ? "You're there" : (turn.instruction?.phrase ?? "Head along the line"))
                        .font(.title2.weight(.semibold))
                    if !turn.hasArrived {
                        Text("Next turn in \(LevelDescription.distance(turn.distanceToKeypointM)), \(LevelDescription.distance(turn.remainingM)) to go")
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            } else if !model.direction.isEmpty {
                GentleBanner(text: model.direction, systemImage: "location.north")
            }
            MapCanvas(crumbs: model.crumbs, places: summaries, median: median,
                      pose: model.pose, route: model.route, targetId: model.guidance?.targetPlaceId)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityElement()
                .accessibilityLabel(accessibilitySummary(summaries, median: median))
            if model.route?.isPartial == true {
                GentleBanner(text: "Part of the way back wasn't tracked. Follow the line as far as it goes, then look around for the spot.")
            }
        }
        .padding(16)
        .background(Theme.background)
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func accessibilitySummary(_ summaries: [CompassModel.PlaceSummary], median: Double?) -> String {
        var parts = ["Map of your walk with \(summaries.count) marked spots."]
        for s in summaries.prefix(5) {
            parts.append("\(s.place.label): \(LevelDescription.short(s.lastLevel, median: median)).")
        }
        if let turn = model.nextTurn, let i = turn.instruction {
            parts.append("\(i.phrase), \(LevelDescription.distance(turn.distanceToKeypointM)).")
        }
        return parts.joined(separator: " ")
    }
}

struct MapCanvas: View {
    var crumbs: [Crumb]
    var places: [CompassModel.PlaceSummary]
    var median: Double?
    var pose: PoseSample?
    var route: Route?
    var targetId: UUID?

    var body: some View {
        Canvas { ctx, size in
            let points = crumbs.map(\.position) + places.compactMap(\.place.position)
                + (pose?.position.map { [$0] } ?? []) + (route?.path ?? [])
            guard !points.isEmpty else {
                ctx.draw(Text("Walk a few steps to start the map").font(.body).foregroundStyle(.secondary),
                         at: CGPoint(x: size.width / 2, y: size.height / 2))
                return
            }
            let frame = MapFrame(points: points, size: size)

            // Walked path, one stroke per tracking segment.
            for segment in Dictionary(grouping: crumbs, by: \.segment).values {
                let ordered = segment.sorted { $0.seq < $1.seq }
                guard ordered.count > 1 else { continue }
                var path = Path()
                path.move(to: frame.point(ordered[0].position))
                for c in ordered.dropFirst() { path.addLine(to: frame.point(c.position)) }
                ctx.stroke(path, with: .color(.secondary.opacity(0.45)),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }

            // Route back.
            if let route, route.keypoints.count > 1 {
                var path = Path()
                path.move(to: frame.point(route.keypoints[0]))
                for p in route.keypoints.dropFirst() { path.addLine(to: frame.point(p)) }
                ctx.stroke(path, with: .color(Theme.accent),
                           style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round, dash: [10, 6]))
            }

            // Places.
            for s in places {
                guard let p = s.place.position else { continue }
                let c = frame.point(p)
                let isTarget = s.id == targetId
                let r: CGFloat = isTarget ? 10 : 7
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(Theme.levelColor(s.lastLevel, median: median)))
                if isTarget {
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r - 4, y: c.y - r - 4, width: 2 * r + 8, height: 2 * r + 8)),
                               with: .color(Theme.accent), lineWidth: 2)
                }
                let label = Text("\(s.place.label)\n\(LevelDescription.short(s.lastLevel, median: median))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                ctx.draw(label, at: CGPoint(x: c.x, y: c.y - r - 6), anchor: .bottom)
            }

            // User arrow.
            if let pos = pose?.position {
                let c = frame.point(pos)
                let h = pose?.headingRad ?? 0
                let dir = CGPoint(x: sin(h), y: -cos(h))
                let side = CGPoint(x: -dir.y, y: dir.x)
                var arrow = Path()
                arrow.move(to: CGPoint(x: c.x + dir.x * 14, y: c.y + dir.y * 14))
                arrow.addLine(to: CGPoint(x: c.x - dir.x * 8 + side.x * 8, y: c.y - dir.y * 8 + side.y * 8))
                arrow.addLine(to: CGPoint(x: c.x - dir.x * 3, y: c.y - dir.y * 3))
                arrow.addLine(to: CGPoint(x: c.x - dir.x * 8 - side.x * 8, y: c.y - dir.y * 8 - side.y * 8))
                arrow.closeSubpath()
                ctx.fill(arrow, with: .color(Theme.accent))
                ctx.stroke(arrow, with: .color(.white), lineWidth: 1.5)
            }
        }
    }
}

/// Fits world points into the canvas with a margin, keeping metres square.
struct MapFrame {
    var minX: Double, maxX: Double, minZ: Double, maxZ: Double
    var scale: Double
    var offset: CGPoint

    init(points: [Position], size: CGSize, margin: Double = 44, minSpanM: Double = 8) {
        var minX = points.map(\.x).min() ?? 0, maxX = points.map(\.x).max() ?? 0
        var minZ = points.map(\.z).min() ?? 0, maxZ = points.map(\.z).max() ?? 0
        if maxX - minX < minSpanM { let c = (minX + maxX) / 2; minX = c - minSpanM / 2; maxX = c + minSpanM / 2 }
        if maxZ - minZ < minSpanM { let c = (minZ + maxZ) / 2; minZ = c - minSpanM / 2; maxZ = c + minSpanM / 2 }
        self.minX = minX; self.maxX = maxX; self.minZ = minZ; self.maxZ = maxZ
        let w = max(1, Double(size.width) - 2 * margin), h = max(1, Double(size.height) - 2 * margin)
        scale = min(w / (maxX - minX), h / (maxZ - minZ))
        offset = CGPoint(x: (Double(size.width) - (maxX - minX) * scale) / 2,
                         y: (Double(size.height) - (maxZ - minZ) * scale) / 2)
    }

    /// World (x, z) to screen: +X right, −Z up.
    func point(_ p: Position) -> CGPoint {
        CGPoint(x: offset.x + (p.x - minX) * scale, y: offset.y + (p.z - minZ) * scale)
    }
}

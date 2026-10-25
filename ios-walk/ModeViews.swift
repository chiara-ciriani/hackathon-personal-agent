import SwiftUI
import simd

// Radar, Locate and Walk map screens. Levels everywhere are relative dBFS from this phone:
// never SPL, never dBA.

// MARK: - Radar

struct RadarView: View {
    @Bindable var model: CompassModel
    @State private var northUp = false

    var body: some View {
        VStack(spacing: 12) {
            RadarDial(snapshot: model.radar, rotation: northUp ? 0 : -model.phoneBearing,
                      northLabel: model.reference == .arkitTrueNorth ? "N (true)" : (model.reference == .magneticNorth ? "N" : "ref"))
            Group {
                if let b = model.radar.dominantBearing {
                    Text(String(format: "Loudest from %.0f° %@", b, Compass.point(b))).font(.title2.monospacedDigit())
                    Text(String(format: "band level %.1f dBFS (relative), confidence %.0f%%",
                                model.radar.dominantLevelDBFS ?? -120, (model.radar.dominantConfidence ?? 0) * 100))
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                } else {
                    Text("Nothing confident heard yet").font(.title3)
                }
            }
            HStack {
                Toggle("North up", isOn: $northUp).toggleStyle(.button)
                Spacer()
                Button("Reset", systemImage: "arrow.counterclockwise", role: .destructive) { model.resetRadar() }
                    .buttonStyle(.bordered)
            }
            Text("Stand still and turn slowly. Each 15° wedge collects the sound that arrived from that direction over the last ~20 s (confidence ≥ the slider). Wedge length and colour: relative to the loudest wedge (0 to −30). Grey: not heard yet.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct RadarDial: View {
    let snapshot: RadarSnapshot
    /// Degrees added to every world bearing before drawing (−phone bearing = heading-up).
    let rotation: Double
    let northLabel: String

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2 - 18
            for f in [1.0 / 3, 2.0 / 3, 1] {
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r * f, y: c.y - r * f, width: 2 * r * f, height: 2 * r * f)),
                           with: .color(.secondary.opacity(0.3)), lineWidth: 1)
            }
            let half = SectorRadar.width / 2
            for s in snapshot.sectors {
                let a = s.centre + rotation
                if let rel = s.relativeDB {
                    let f = max(0, min(1, 1 + rel / 30))            // 0 dB -> 1, −30 dB -> 0
                    let len = r * (0.15 + 0.85 * f)
                    ctx.fill(Self.wedge(c, len, a - half, a + half),
                             with: .color(Color(hue: 0.62 * (1 - f), saturation: 0.85, brightness: 0.95)))
                } else {
                    ctx.fill(Self.wedge(c, r, a - half, a + half), with: .color(.gray.opacity(0.15)))
                }
            }
            if let b = snapshot.dominantBearing {
                var p = Path()
                p.move(to: c)
                p.addLine(to: Self.point(c, r + 4, b + rotation))
                ctx.stroke(p, with: .color(.primary), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            ctx.draw(Text(northLabel).font(.caption.bold()).foregroundStyle(.red), at: Self.point(c, r + 10, rotation))
        }
        .frame(width: 290, height: 290)
    }

    /// Screen point at `radius` along compass bearing `deg` (0 = up, clockwise).
    static func point(_ c: CGPoint, _ radius: Double, _ deg: Double) -> CGPoint {
        let a = deg * .pi / 180
        return CGPoint(x: c.x + radius * sin(a), y: c.y - radius * cos(a))
    }

    static func wedge(_ c: CGPoint, _ radius: Double, _ from: Double, _ to: Double) -> Path {
        var p = Path()
        p.move(to: c)
        for i in 0...6 { p.addLine(to: point(c, radius, from + (to - from) * Double(i) / 6)) }
        p.closeSubpath()
        return p
    }
}

// MARK: - Locate

struct LocateView: View {
    @Bindable var model: CompassModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Locate mode (starts ARKit, uses the camera)", isOn: $model.locateMode)
            if model.locateMode || model.ar.kind != .off {
                Text("ARKit: \(model.ar.detail)" + (model.ar.position.map {
                    let p = ARFrameMath.eastNorth(x: $0.x, z: $0.y)
                    return String(format: ", at %.1f m E, %.1f m N", p.x, p.y)
                } ?? ""))
                .font(.caption.monospacedDigit())
                .foregroundStyle(model.ar.isNormal ? Color.secondary : Color.orange)
            }
            Picker("Position from", selection: $model.positionSource) {
                ForEach(PositionSource.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            switch model.positionSource {
            case .arkit:
                EmptyView()
            case .typed:
                HStack {
                    Text("x east")
                    TextField("m", value: $model.typedEast, format: .number).keyboardType(.numbersAndPunctuation)
                    Text("y north")
                    TextField("m", value: $model.typedNorth, format: .number).keyboardType(.numbersAndPunctuation)
                }
                .textFieldStyle(.roundedBorder)
            case .walked:
                HStack {
                    Text("walked")
                    TextField("m", value: $model.walkedMetres, format: .number).keyboardType(.numbersAndPunctuation)
                    Text("m toward")
                    TextField("°", value: $model.walkedBearing, format: .number).keyboardType(.numbersAndPunctuation)
                    Button("phone") { model.walkedBearing = model.phoneBearing.rounded() }.buttonStyle(.bordered)
                }
                .textFieldStyle(.roundedBorder)
                Text("First capture is at (0, 0); each next one is that far along that bearing from the previous.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Text(model.recentRadar.dominantBearing.map { String(format: "Dominant now: %.0f° %@, confidence %.0f%%", $0,
                                                                Compass.point($0), (model.recentRadar.dominantConfidence ?? 0) * 100) }
                 ?? "Dominant now: none confident in the last 2 s")
                .font(.callout.monospacedDigit())
            Button("Capture bearing here", systemImage: "scope") { model.captureBearing() }
                .buttonStyle(.borderedProminent)
            if !model.locateMessage.isEmpty {
                Text(model.locateMessage).font(.caption).foregroundStyle(.secondary)
            }

            ForEach(Array(model.captures.enumerated()), id: \.element.id) { i, c in
                HStack {
                    Text(String(format: "%d. (%.1f, %.1f) m  %.0f° %@  conf %.0f%%", i + 1, c.position.x, c.position.y,
                                c.bearing, Compass.point(c.bearing), c.confidence * 100))
                        .font(.caption.monospacedDigit())
                    Spacer()
                    Button("Remove", systemImage: "xmark.circle") { model.removeCapture(c.id) }.labelStyle(.iconOnly)
                }
            }

            resultText
            LocatePlot(captures: model.captures, result: model.locateResult)
                .frame(height: 280)
            HStack {
                Button("Save as source", systemImage: "mappin.and.ellipse") { model.saveSource() }
                    .buttonStyle(.bordered)
                    .disabled({ if case .success = model.locateResult { false } else { true } }())
                Spacer()
                Button("Clear captures", role: .destructive) { model.clearCaptures() }
            }
            if !model.located.isEmpty {
                GroupBox("Located sources") {
                    ForEach(model.located) { s in
                        Text(s.summary).font(.callout.monospacedDigit()).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Text("Capture from 2–3 spots a few metres apart while the source plays. Start = (0, 0) = where ARKit started (or your typed origin).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var resultText: some View {
        switch model.locateResult {
        case .success(let e):
            Text(Triangulation.describe(e) + (e.rejectedRays.isEmpty ? "" : "  (ignored \(e.rejectedRays.count) ray pointing away)"))
                .font(.headline.monospacedDigit())
        case .failure(.nearlyParallel(let angle)):
            Text(String(format: "Rays nearly parallel (%.0f° apart, need ≥ 15°). Move sideways and capture again.", angle))
                .foregroundStyle(.orange)
        case .failure(.pointsBehind):
            Text("Rays point away from each other: check the bearings.").foregroundStyle(.orange)
        case .failure(.needTwoRays), nil:
            Text("Need at least 2 captures").foregroundStyle(.secondary)
        }
    }
}

/// Top-down plot in metres, north up: capture spots, their rays, the estimate and its uncertainty.
struct LocatePlot: View {
    let captures: [BearingCapture]
    let result: Result<SourceEstimate, TriangulationFailure>?

    var body: some View {
        Canvas { ctx, size in
            var pts = captures.map(\.position) + [.zero]
            var est: SourceEstimate?
            if case .success(let e) = result {
                est = e
                let u = min(e.uncertainty, 20)
                pts += [e.position + SIMD2(u, u), e.position - SIMD2(u, u)]
            }
            if captures.count == 1 { pts.append(captures[0].position + 4 * Compass.unit(captures[0].bearing)) }
            let lo = SIMD2(pts.map(\.x).min()!, pts.map(\.y).min()!) - 1.5
            let hi = SIMD2(pts.map(\.x).max()!, pts.map(\.y).max()!) + 1.5
            let span = max(hi.x - lo.x, hi.y - lo.y, 4)
            let scale = min(size.width, size.height) / span
            let mid = (lo + hi) / 2
            func screen(_ p: SIMD2<Double>) -> CGPoint {
                CGPoint(x: size.width / 2 + (p.x - mid.x) * scale, y: size.height / 2 - (p.y - mid.y) * scale)
            }
            // 1 m grid (5 m when zoomed out).
            let step = span > 25 ? 5.0 : 1.0
            var grid = Path()
            for k in Int((mid.x - span) / step)...Int((mid.x + span) / step) {
                let x = screen(SIMD2(Double(k) * step, 0)).x
                grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            for k in Int((mid.y - span) / step)...Int((mid.y + span) / step) {
                let y = screen(SIMD2(0, Double(k) * step)).y
                grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            ctx.stroke(grid, with: .color(.secondary.opacity(0.15)), lineWidth: 0.5)
            ctx.draw(Text("+").font(.caption), at: screen(.zero))
            for (i, c) in captures.enumerated() {
                var ray = Path()
                ray.move(to: screen(c.position))
                ray.addLine(to: screen(c.position + 3 * span * Compass.unit(c.bearing)))
                let used = est.map { !$0.rejectedRays.contains(i) } ?? true
                ctx.stroke(ray, with: .color(used ? .blue.opacity(0.4 + 0.6 * c.confidence) : .gray),
                           style: StrokeStyle(lineWidth: 2, dash: used ? [] : [4, 4]))
                let p = screen(c.position)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(.blue))
                ctx.draw(Text("\(i + 1)").font(.caption2.bold()), at: CGPoint(x: p.x + 10, y: p.y + 10))
            }
            if let e = est {
                let p = screen(e.position)
                let u = e.uncertainty * scale
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - u, y: p.y - u, width: 2 * u, height: 2 * u)), with: .color(.red.opacity(0.15)))
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - u, y: p.y - u, width: 2 * u, height: 2 * u)), with: .color(.red), lineWidth: 1)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)), with: .color(.red))
            }
            ctx.draw(Text("N ↑   grid \(Int(step)) m").font(.caption2).foregroundStyle(.secondary),
                     at: CGPoint(x: 60, y: 10))
        }
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Walk map

struct WalkView: View {
    @Bindable var model: CompassModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                model.isRecording ? model.stopWalk() : model.startWalk()
            } label: {
                Label(model.isRecording ? "Stop" : "Record", systemImage: model.isRecording ? "stop.fill" : "record.circle")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.isRecording ? .red : .accentColor)

            if model.isRecording || model.ar.kind != .off {
                Text(model.ar.isNormal ? "ARKit: tracking normal" : "ARKit: \(model.ar.detail)")
                    .font(.callout.bold())
                    .foregroundStyle(model.ar.isNormal ? Color.green : Color.orange)
            }
            if !model.walkMessage.isEmpty { Text(model.walkMessage).font(.caption) }
            if let r = model.replaying {
                HStack {
                    Text(String(format: "Replay %@: %.0f / %.0f s (10×)", r.walkID, model.replayTime, r.samples.last?.t ?? 0))
                        .font(.caption.monospacedDigit())
                    Spacer()
                    Button("Stop replay") { model.stopReplay() }
                }
            }

            Toggle("Level from ARKit mic (use if the audio stops while ARKit runs)", isOn: $model.arAudioFallback)
                .font(.caption)
            if model.arAudioFallback, let db = model.arAudioLevelDB {
                Text(String(format: "ARKit mic level %.1f dBFS (relative)", db)).font(.caption.monospacedDigit())
            }
            FieldMapView(field: model.field, path: model.mapPath, user: model.mapUser)
            legend

            if !model.savedWalks.isEmpty {
                GroupBox("Saved walks") {
                    ForEach(model.savedWalks) { w in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(w.record.walkID).font(.caption.monospaced())
                                Text(String(format: "%d samples, %.0f s", w.record.samples.count, w.record.samples.last?.t ?? 0))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Replay", systemImage: "play.fill") { model.replay(w.record) }
                                .labelStyle(.iconOnly).disabled(model.isRecording)
                            ShareLink(item: w.url) { Image(systemName: "square.and.arrow.up") }
                        }
                    }
                }
            }
            Text("Press Record and walk slowly holding the phone camera-forward. One sample every 2 s (position from ARKit, level = W/mono relative dBFS). Grey = not measured (> 3 m from any sample). Numbered circles: the 3 quietest measured spots.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var legend: some View {
        if let range = model.field?.levelRange {
            HStack {
                Text(String(format: "quiet %.0f", range.lowerBound))
                LinearGradient(colors: [FieldMapView.color(0), FieldMapView.color(0.5), FieldMapView.color(1)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(height: 8).clipShape(Capsule())
                Text(String(format: "%.0f loud", range.upperBound))
            }
            .font(.caption2.monospacedDigit())
            Text("relative dBFS within this walk, not SPL").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// Top-down sound field: raw ARKit x to the right, z downward, so north (−z) is up.
struct FieldMapView: View {
    let field: SoundField?
    let path: [SIMD2<Double>]
    let user: SIMD2<Double>?

    static func color(_ f: Double) -> Color { Color(hue: 0.33 * (1 - f), saturation: 0.85, brightness: 0.9) }

    var body: some View {
        Canvas { ctx, size in
            guard let field else {
                ctx.draw(Text("No samples yet").foregroundStyle(.secondary), at: CGPoint(x: size.width / 2, y: size.height / 2))
                return
            }
            let w = Double(field.cols) * field.cellM, h = Double(field.rows) * field.cellM
            let scale = min(size.width / w, size.height / h)
            let ox = (size.width - w * scale) / 2, oy = (size.height - h * scale) / 2
            func screen(_ x: Double, _ z: Double) -> CGPoint {
                CGPoint(x: ox + (x - field.originX) * scale, y: oy + (z - field.originZ) * scale)
            }
            let lo = field.levelRange?.lowerBound ?? 0
            let span = max((field.levelRange?.upperBound ?? 0) - lo, 1)
            let cell = field.cellM * scale
            for c in field.cells {
                let p = screen(c.x, c.z)
                let rect = CGRect(x: p.x - cell / 2, y: p.y - cell / 2, width: cell + 0.5, height: cell + 0.5)
                if let level = c.levelDB {
                    ctx.fill(Path(rect), with: .color(Self.color((level - lo) / span).opacity(0.25 + 0.75 * c.confidence)))
                } else {
                    ctx.fill(Path(rect), with: .color(.gray.opacity(0.2)))
                }
            }
            if path.count > 1 {
                var line = Path()
                line.move(to: screen(path[0].x, path[0].y))
                for p in path.dropFirst() { line.addLine(to: screen(p.x, p.y)) }
                ctx.stroke(line, with: .color(.primary.opacity(0.7)), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            }
            for (i, s) in field.quietSpots.enumerated() {
                let p = screen(s.x, s.z)
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 11, y: p.y - 11, width: 22, height: 22)), with: .color(.blue), lineWidth: 3)
                ctx.draw(Text("\(i + 1)").font(.caption.bold()).foregroundStyle(.blue), at: p)
            }
            if let u = user {
                let p = screen(u.x, u.y)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)), with: .color(.white))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(.accentColor))
            }
            ctx.draw(Text(String(format: "N ↑   cell %.1f m", field.cellM)).font(.caption2).foregroundStyle(.secondary),
                     at: CGPoint(x: 60, y: 10))
        }
        .frame(height: 340)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

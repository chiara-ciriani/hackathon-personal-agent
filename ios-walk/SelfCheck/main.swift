// Self-check for the pure maths. NOT part of the Xcode app target (do not drag this folder in).
// Run from the ios/ folder on any Mac with a Swift toolchain:
//   swiftc -O SoundField.swift SourceMap.swift SelfCheck/main.swift -o /tmp/qc-selfcheck && /tmp/qc-selfcheck
import Foundation
import simd

nonisolated(unsafe) var failures = 0
func check(_ ok: Bool, _ what: String) {
    print((ok ? "PASS  " : "FAIL  ") + what)
    if !ok { failures += 1 }
}
func f1(_ v: Double?) -> String { v.map { String(format: "%.2f", $0) } ?? "nil" }

// Deterministic pseudo-random numbers (LCG), so the run is reproducible.
nonisolated(unsafe) var seed: UInt64 = 12345
func rnd() -> Double {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return Double(seed >> 11) / Double(1 << 53)
}

// MARK: (a) Radar: a synthetic source at 45° fills the 45° sector

do {
    var radar = SectorRadar(timeConstant: 20)
    let hop = 1024.0 / 48_000
    var t = 0.0
    // 10 s: source at 45° ± 5° (conf 0.8-1.0), interleaved with diffuse windows (conf < 0.3,
    // random bearing) and weak confident reflections at random bearings (energy 1/100).
    for i in 0..<Int(10 / hop) {
        t += hop
        let w: WindowObservation
        switch i % 4 {
        case 0, 1: w = WindowObservation(bearing: 45 + (rnd() - 0.5) * 10, elevation: 5, confidence: 0.8 + 0.2 * rnd(), energy: 1e-4, duration: hop)
        case 2: w = WindowObservation(bearing: rnd() * 360, elevation: 0, confidence: 0.3 * rnd(), energy: 1e-4, duration: hop)
        default: w = WindowObservation(bearing: rnd() * 360, elevation: 0, confidence: 0.6, energy: 1e-6, duration: hop)
        }
        radar.add(w, threshold: 0.5, time: t)
    }
    let s = radar.snapshot()
    let s3 = s.sectors[3]
    print("      45° sector: rel \(f1(s3.relativeDB)) level \(f1(s3.levelDBFS)) dBFS-rel, \(f1(s3.seconds)) s, dominant bearing \(f1(s.dominantBearing))")
    let others = s.sectors.indices.filter { $0 != 3 }.compactMap { s.sectors[$0].relativeDB }
    print("      other heard sectors: \(others.count), loudest of them \(f1(others.max()))")
    check(SectorRadar.sector(for: 45) == 3 && s.dominant == 3, "(a) synthetic source at 45° -> dominant sector index 3 (centre 45°)")
    check(abs((s.dominantBearing ?? 0) - 45) < 3, "(a) refined dominant bearing within 3° of 45° (got \(f1(s.dominantBearing)))")
    check((others.max() ?? -100) < -15, "(a) every other heard sector at least 15 below the 45° sector")
    check(SectorRadar.sector(for: 359) == 0 && SectorRadar.sector(for: 7.4) == 0 && SectorRadar.sector(for: 7.6) == 1,
          "(a) sector edges: 359° and 7.4° -> sector 0, 7.6° -> sector 1")

    // Forgetting: the source moves to 200° for 60 s (3 time constants).
    for _ in 0..<Int(60 / hop) {
        t += hop
        radar.add(WindowObservation(bearing: 200, elevation: 0, confidence: 0.9, energy: 1e-4, duration: hop), threshold: 0.5, time: t)
    }
    let s2 = radar.snapshot()
    check(s2.dominant == SectorRadar.sector(for: 200) && (s2.sectors[3].relativeDB ?? -99) < -10,
          "(a) after 60 s at 200° the dominant sector moves to \(SectorRadar.sector(for: 200)) and 45° fades (rel \(f1(s2.sectors[3].relativeDB)))")
    radar.reset()
    check(radar.snapshot().dominant == nil && !radar.snapshot().sectors.contains { $0.heard }, "(a) reset -> nothing heard")
}

// MARK: (b) Two rays: (0,0) at 45° and (4,0) at 135° (maths angles, CCW from +x) meet at (2,2)

do {
    let rays = [BearingRay(origin: [0, 0], mathAngle: 45), BearingRay(origin: [4, 0], mathAngle: 135)]
    print("      compass bearings: \(f1(rays[0].bearing))°, \(f1(rays[1].bearing))°")
    switch Triangulation.locate(rays) {
    case .success(let e):
        print("      estimate (\(f1(e.position.x)), \(f1(e.position.y))) ±\(f1(e.uncertainty)) m, crossing \(f1(e.maxCrossingAngle))°")
        check(simd_distance(e.position, [2, 2]) < 1e-9, "(b) intersection at (2, 2)")
        check(e.residualRMS < 1e-9 && e.uncertainty > 0 && e.uncertainty < 1, "(b) zero residual, finite uncertainty (\(f1(e.uncertainty)) m)")
    case .failure(let f): check(false, "(b) intersection at (2, 2): \(f)")
    }
    // Same thing in compass bearings, plus a third noisy, low-confidence ray.
    let three = [BearingRay(origin: [0, 0], bearing: 45, confidence: 0.9), BearingRay(origin: [4, 0], bearing: 315, confidence: 0.9),
                 BearingRay(origin: [2, -3], bearing: 5, confidence: 0.5)]
    if case .success(let e) = Triangulation.locate(three) {
        print("      3 rays (one 5° off): (\(f1(e.position.x)), \(f1(e.position.y))) ±\(f1(e.uncertainty)) m, rms \(f1(e.residualRMS)); \(Triangulation.describe(e))")
        check(simd_distance(e.position, [2, 2]) < 0.6, "(b) three rays with one 5° off -> within 0.6 m of (2, 2)")
    } else { check(false, "(b) three rays") }
    // A ray pointing away from the others' crossing is dropped.
    let away = [BearingRay(origin: [0, 0], bearing: 45), BearingRay(origin: [4, 0], bearing: 315), BearingRay(origin: [2, 5], bearing: 0)]
    if case .success(let e) = Triangulation.locate(away) {
        check(e.rejectedRays == [2] && simd_distance(e.position, [2, 2]) < 1e-6, "(b) ray pointing away is rejected (rejected \(e.rejectedRays))")
    } else { check(false, "(b) ray pointing away is rejected") }
}

// MARK: (c) Parallel rays are refused

do {
    let parallel = Triangulation.locate([BearingRay(origin: [0, 0], bearing: 30), BearingRay(origin: [3, 0], bearing: 30)])
    check(parallel == .failure(.nearlyParallel(maxAngle: 0)), "(c) parallel rays refused (\(parallel))")
    let near = Triangulation.locate([BearingRay(origin: [0, 0], bearing: 30), BearingRay(origin: [3, 0], bearing: 20)])
    if case .failure(.nearlyParallel) = near { check(true, "(c) rays 10° apart refused (< 15°)") } else { check(false, "(c) rays 10° apart refused: \(near)") }
    let opposite = Triangulation.locate([BearingRay(origin: [0, 0], bearing: 90), BearingRay(origin: [0, 1], bearing: 270)])
    if case .failure(.nearlyParallel) = opposite { check(true, "(c) anti-parallel rays refused") } else { check(false, "(c) anti-parallel: \(opposite)") }
    let wide = Triangulation.locate([BearingRay(origin: [0, 0], bearing: 30), BearingRay(origin: [3, 0], bearing: 10)])
    if case .success = wide { check(true, "(c) rays 20° apart accepted") } else { check(false, "(c) rays 20° apart accepted: \(wide)") }
    check(Triangulation.locate([BearingRay(origin: [0, 0], bearing: 30)]) == .failure(.needTwoRays), "(c) one ray refused")
}

// MARK: ARKit camera -> app world frame

do {
    // Phone upright in portrait, rear camera facing true north. Camera axes in ARKit world:
    // camera +x = device bottom = down, camera +y = device right edge = east, camera +z = south.
    let axes = ARFrameMath.deviceAxesNWU(cameraX: [0, -1, 0], cameraY: [1, 0, 0], cameraZ: [0, 0, 1])
    func bearingNWU(_ v: SIMD3<Double>) -> Double { Compass.normalize(atan2(-v.y, v.x) * 180 / .pi) }
    check(abs(bearingNWU(-axes.z) - 0) < 1e-9, "AR: rear camera direction -> bearing 0 (north)")
    check(abs(bearingNWU(axes.x) - 90) < 1e-9, "AR: device right edge -> bearing 90 (east)")
    check(simd_distance(axes.y, [0, 0, 1]) < 1e-9, "AR: device top edge -> up")
    check(ARFrameMath.eastNorth(x: 1, z: -2) == SIMD2(1, 2), "AR: position x=1, z=-2 -> 1 m east, 2 m north")
}

// MARK: Walk map (port of sound_field.py)

do {
    // L-shaped walk: quiet (-50) at the x=0 end, loud (-20) at the x=10 end, then north along x=0.
    var samples: [FieldSample] = []
    for i in 0...20 { let x = Double(i) * 0.5; samples.append(FieldSample(x: x, z: 0, levelDB: -50 + 3 * x, ageMin: 0)) }
    for i in 1...20 { samples.append(FieldSample(x: 0, z: -Double(i) * 0.5, levelDB: -45, ageMin: 0)) }
    let field = SoundField.build(samples: samples, user: [0, 0])!
    print("      grid \(field.cols)×\(field.rows) cells of \(field.cellM) m, range \(f1(field.levelRange?.lowerBound))…\(f1(field.levelRange?.upperBound))")
    for s in field.quietSpots { print("      quiet spot (\(f1(s.x)), \(f1(s.z))) \(f1(s.levelDB)) conf \(f1(s.confidence))") }
    let first = field.quietSpots.first
    check(first != nil && first!.x < 1.5 && abs(first!.z) < 1.5, "walk: quietest spot is at the quiet end (near x=0, z=0)")
    check(field.quietSpots.allSatisfy { $0.x < 5 }, "walk: no quiet spot at the loud end")
    let far = field.cell(atX: 10.5, z: -10.5)
    check(far != nil && far!.levelDB == nil && far!.confidence == 0, "walk: far unwalked corner (10.5, -10.5) is grey (nil, nearest \(f1(far?.nearestM)) m)")
    let onPath = field.cell(atX: 9.9, z: 0.1)
    check((onPath?.levelDB ?? -99) > -30 && (onPath?.confidence ?? 0) > 0.9, "walk: loud end reads loud (\(f1(onPath?.levelDB))) with confidence \(f1(onPath?.confidence))")
    // Age: an old loud reading on a spot is outweighed by a fresh quiet one there.
    let aged = SoundField.build(samples: [FieldSample(x: 0, z: 0, levelDB: -20, ageMin: 60), FieldSample(x: 0, z: 0, levelDB: -50, ageMin: 0)])!
    check((aged.cell(atX: 0.1, z: 0.1)?.levelDB ?? 0) < -45, "walk: fresh reading outweighs a 60-min-old one (\(f1(aged.cell(atX: 0.1, z: 0.1)?.levelDB)))")
    // Cross-check numbers against sound_field.py (printed for comparison).
    let probe = SoundField.build(samples: [FieldSample(x: 0, z: 0, levelDB: -40, ageMin: 0), FieldSample(x: 2, z: 0, levelDB: -20, ageMin: 10)])!
    let c = probe.cell(atX: 1.1, z: 0.1)!
    print("      PROBE cols=\(probe.cols) rows=\(probe.rows) cell(\(c.x), \(c.z)) level=\(String(format: "%.6f", c.levelDB!)) conf=\(String(format: "%.6f", c.confidence)) spots=\(probe.quietSpots.map { "(\($0.x),\($0.z),\(String(format: "%.4f", $0.levelDB)))" })")

    // JSON shape.
    let walk = WalkRecord(walkID: "walk-test", device: "iPhone18,1 iOS 26.0", startedAt: "2026-10-24T17:00:00Z",
                          samples: [WalkSample(t: 2, x: 0.5, z: -1.25, levelDBFS: -42.5, tracking: "normal")])
    let data = try! JSONEncoder().encode(walk)
    let obj = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    let sample = (obj["samples"] as! [[String: Any]])[0]
    check(Set(obj.keys) == ["walk_id", "device", "started_at", "samples"] && Set(sample.keys) == ["t", "x", "z", "level_dbfs", "tracking"],
          "walk JSON keys: \(obj.keys.sorted()) / \(sample.keys.sorted())")
    check(try! JSONDecoder().decode(WalkRecord.self, from: data) == walk, "walk JSON round-trips")
}

print(failures == 0 ? "\nALL CHECKS PASSED" : "\n\(failures) CHECK(S) FAILED")
exit(failures == 0 ? 0 : 1)

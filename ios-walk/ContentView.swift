import SwiftUI
import UIKit

struct ContentView: View {
    @State private var model = CompassModel()
    @State private var showAdvanced = false

    var body: some View {
        QuietMapView(model: model, showAdvanced: $showAdvanced)
            .sheet(isPresented: $showAdvanced) {
                NavigationStack {
                    AdvancedView(model: model)
                        .toolbar { Button("Done") { showAdvanced = false } }
                }
            }
            .task {
                await model.start()
                // Mapping starts on its own: open the app and walk.
                if !model.isRecording { model.startWalk() }
            }
            .task(id: model.autoLog) {
                while model.autoLog, !Task.isCancelled {
                    model.logNow()
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            .onChange(of: model.settings) { model.settingsChanged() }
            .onChange(of: model.threshold) { model.settingsChanged() }
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
    }
}

/// Every mode (compass, radar, locate, walk map with replay and export) and the debug panel.
struct AdvancedView: View {
    @Bindable var model: CompassModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                Picker("Mode", selection: $model.mode) {
                    ForEach(AppMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                switch model.mode {
                case .compass:
                    CompassDial(arrowAngle: model.arrowAngle,
                                northAngle: -model.phoneBearing,
                                showsArrow: model.showsArrow,
                                northLabel: model.reference == .magneticNorth ? "N"
                                    : model.reference == .arkitTrueNorth ? "N (true)" : "ref")
                    readout
                    LevelMeter(rmsDB: model.level?.rmsDB, peakDB: model.level?.peakDB)
                    detection
                    calibration
                    logSection
                case .radar:
                    RadarView(model: model)
                    LevelMeter(rmsDB: model.level?.rmsDB, peakDB: model.level?.peakDB)
                    detection
                case .locate:
                    LocateView(model: model)
                    detection
                case .walk:
                    WalkView(model: model)
                    LevelMeter(rmsDB: model.level?.rmsDB, peakDB: model.level?.peakDB)
                }
                DebugPanel(model: model)
            }
            .padding()
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("Quiet Compass").font(.largeTitle.bold())
            Text(model.status).font(.subheadline).foregroundStyle(.secondary)
            Text("Experimental: FOA axis mapping is unverified, calibrate first")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    private var readout: some View {
        VStack(spacing: 4) {
            if let e = model.estimate {
                Text(model.showsArrow ? "\(Int(e.bearingWorld.rounded()))° from \(model.reference == .magneticNorth ? "N" : "ref")" : "Abstaining")
                    .font(.title.monospacedDigit())
                Text("confidence \(Int((e.confidence * 100).rounded()))%   elevation \(Int(e.elevation.rounded()))°")
                    .font(.callout.monospacedDigit())
            } else if model.stream.channelCount > 0 && model.stream.channelCount < 4 {
                Text("No direction: receiving \(model.stream.channelCount) channel(s), FOA needs 4")
                    .font(.callout).foregroundStyle(.red)
            } else {
                Text("Waiting for audio…").font(.callout)
            }
        }
        .multilineTextAlignment(.center)
    }

    private var detection: some View {
        GroupBox("Detection") {
            HStack {
                Text("Abstain below")
                Spacer()
                Text("\(Int((model.threshold * 100).rounded()))% confidence").monospacedDigit()
            }
            Slider(value: $model.threshold, in: 0...1)
        }
    }

    private var calibration: some View {
        GroupBox("Calibration") {
            Picker("Channel order", selection: $model.settings.order) {
                ForEach(ChannelOrder.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Picker("FOA front is", selection: $model.settings.mount) {
                ForEach(MountPreset.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Toggle("Swap X and Y", isOn: $model.settings.swapXY)
            Toggle("Negate X (front/back)", isOn: $model.settings.negateX)
            Toggle("Negate Y (left/right)", isOn: $model.settings.negateY)
        }
    }

    private var logSection: some View {
        GroupBox("Log") {
            HStack {
                Button("Log", systemImage: "plus.circle") { model.logNow() }
                    .buttonStyle(.borderedProminent)
                Toggle("Auto 5 Hz", isOn: $model.autoLog).toggleStyle(.button)
                Spacer()
                if let url = model.csvURL {
                    ShareLink(item: url) { Label("CSV", systemImage: "square.and.arrow.up") }
                }
            }
            HStack {
                Text("\(model.rows.count) rows").foregroundStyle(.secondary)
                Spacer()
                Button("Clear", role: .destructive) { model.clearLog() }
            }
        }
    }
}

struct CompassDial: View {
    let arrowAngle: Double
    let northAngle: Double
    let showsArrow: Bool
    let northLabel: String

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 2)
            // Full-size frame so the rotation pivots on the dial centre, not the label.
            Text(northLabel).font(.caption.bold()).foregroundStyle(.red)
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .rotationEffect(.degrees(northAngle))
            if showsArrow {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 110))
                    .foregroundStyle(.tint)
                    .rotationEffect(.degrees(arrowAngle))
            } else {
                Image(systemName: "questionmark")
                    .font(.system(size: 50))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 270, height: 270)
    }
}

struct LevelMeter: View {
    let rmsDB: Float?
    let peakDB: Float?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: normalized(rmsDB))
            Text(rmsDB.map { String(format: "W level %.1f dBFS, peak %.1f (relative, uncalibrated)", $0, peakDB ?? -120) }
                 ?? "No level yet")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    /// -80...0 dBFS -> 0...1
    private func normalized(_ db: Float?) -> Double {
        guard let db else { return 0 }
        return Double(min(1, max(0, (db + 80) / 80)))
    }
}

struct DebugPanel: View {
    let model: CompassModel

    var body: some View {
        GroupBox("What the phone actually delivers") {
            VStack(alignment: .leading, spacing: 6) {
                row("FOA supported", model.stream.foaSupported.map { $0 ? "yes" : "NO" } ?? "?")
                row("FOA requested", model.stream.foaRequested ? "yes" : "no")
                row("Session running", model.stream.sessionRunning ? "yes" : "no")
                row("Channels", "\(model.stream.channelCount)")
                row("Sample rate", String(format: "%.0f Hz", model.stream.sampleRate))
                row("Format", model.stream.formatText)
                row("Layout tag", model.stream.layoutText)
                row("Per-channel dB", model.level?.perChannelDB.map { String(format: "%.0f", $0) }
                    .joined(separator: " / ") ?? "-")
                row("FOA azimuth", model.estimate.map { String(format: "%.0f° CCW from +X", $0.azimuthFOA) } ?? "-")
                row("Phone bearing", String(format: "%.0f°", model.phoneBearing))
                row("Reference", model.reference.label)
                row("Gravity check", String(format: "%+.2f (want ≈ +1)", model.gravityCheck))
                row("DOA world frame", model.radarFromARKit ? "ARKit camera (true N)" : "CoreMotion")
                row("ARKit", model.ar.detail)
                row("ARKit − CoreMotion heading", model.ar.headingDifference.map {
                    String(format: "%+.0f° (want ≈ declination, +13° in SF)", $0) } ?? "-")
                row("Audio event", model.audioEvent.isEmpty ? "-" : model.audioEvent)
                Button("Restart audio", systemImage: "arrow.clockwise") { model.restartAudio() }
                    .font(.caption)
            }
            .font(.caption.monospaced())
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }
}

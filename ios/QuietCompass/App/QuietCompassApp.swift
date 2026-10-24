import SwiftUI
import QuietCore

@main
struct QuietCompassApp: App {
    @State private var model = CompassModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            CompassView(model: model)
                .onChange(of: scenePhase) { _, phase in
                    // Keep measuring sound in the background; only path tracking stops.
                    if phase == .background { Task { await model.enterBackground() } }
                    if phase == .active { model.enterForeground(); Task { await model.refreshWearables() } }
                }
        }
    }
}

private struct CompassView: View {
    @Bindable var model: CompassModel
    @Environment(\.openURL) private var openURL
    @State private var arrivalGuidance: Guidance?
    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("https://your-server", text: $model.serverAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField("Server access token", text: $model.token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save and connect") { Task { await model.saveConnection() } }
                        .disabled(model.running || model.starting)
                    Text(model.message).font(.callout).accessibilityIdentifier("connection-status")
                }
                Section("Measure this place") {
                    if let level = model.level {
                        if !model.running { Text("Last measurement").font(.caption) }
                        Text("\(level.formatted(.number.precision(.fractionLength(1)))) dBFS relative")
                            .font(.title2.monospacedDigit())
                    } else { Text("No measurement yet") }
                    Text("Path: \(model.tracking)")
                    Text("\(model.pending) uploads pending")
                    Text("The microphone extracts sound levels on this phone. The camera tracks your path. Only summaries and path points go to your private server. Sound keeps being measured if you lock the phone or switch apps; path tracking needs the app open.")
                        .font(.footnote)
                    if model.running || model.starting {
                        Button("Stop measuring", role: .destructive) { Task { await model.stop() } }
                    } else {
                        Button("Start measuring") { model.start() }
                    }
                    Button("Retry pending uploads") { Task { await model.sync() } }
                }
                Section("Noise alerts") {
                    Toggle("Alert me when it's too loud", isOn: $model.alertsOn)
                    Stepper("Too loud = \(Int(model.sensitivityDb)) dB above comfortable", value: $model.sensitivityDb, in: 4...20, step: 2)
                    Text(model.hasBaseline ? "Alerts compare against your comfortable level." :
                         "Your first measurement counts as comfortable until you mark one.").font(.footnote)
                    if model.running {
                        Button("This feels comfortable") { model.markComfortable() }
                        Button("Snooze alerts for 30 minutes") { model.snoozeAlerts() }
                    }
                    if let alert = model.lastAlert { Text(alert).font(.callout) }
                }
                if !model.running {
                    CaptureSettingsSection(companion: model.companion, disabled: model.starting)
                }
                if model.running {
                    LevelInWordsSection(companion: model.companion)
                    Section {
                        NavigationLink("Map of your walk") { MinimapView(model: model) }
                    }
                    Section("Mark a place") {
                        TextField("Place name", text: $model.placeLabel)
                        Toggle("Seating available", isOn: $model.seating)
                        Toggle("Step-free access verified", isOn: $model.stepFree)
                        Button("Mark here") { Task { await model.markPlace() } }
                    }
                    PlaceLevelsSection(model: model)
                }
                if let guidance = model.guidance {
                    Section("Walk to \(guidance.targetLabel)") {
                        if let reason = guidance.reason { Text(reason) }
                        Text(model.direction)
                        NavigationLink("Show on the map") { MinimapView(model: model) }
                        Button("I've arrived") { arrivalGuidance = guidance }
                        Button("Cancel route", role: .cancel) { Task { await model.finishGuidance(.cancelled) } }
                    }
                }
                ShareSection(companion: model.companion)
                Section("Apple Health") {
                    Text("Read yesterday's sleep, steps, resting heart rate and HRV from Apple Health, including supported watches. Preview before sharing with your server and agent.").font(.footnote)
                    Button("Choose access and preview") { Task { await model.previewHealth() } }
                        .disabled(model.wearableBusy)
                    if let summary = model.healthPreview {
                        Text(summary.note).font(.footnote)
                        if summary.metrics.isEmpty { Text("No readable samples. Health does not tell apps whether read access was denied.") }
                        ForEach(summary.metrics) { metric in
                            Text("\(metric.name): \(metric.value.formatted()) \(metric.unit) · \(metric.day)")
                        }
                        Button("Share this summary with my agent") { Task { await model.shareHealth() } }
                            .disabled(model.wearableBusy || summary.metrics.isEmpty)
                        Button("Discard preview", role: .cancel) { model.healthPreview = nil }
                    }
                    Button("Delete shared Apple Health summary", role: .destructive) { Task { await model.disconnect("apple_health") } }
                        .disabled(model.wearableBusy)
                }
                Section("Oura") {
                    Text("Authorize Oura in your browser, then sync daily sleep, readiness and activity summaries. Your private server checks for updates every 15 minutes until disconnected.").font(.footnote)
                    Button(model.ouraConnected ? "Reconnect Oura" : "Connect Oura") {
                        Task { if let url = await model.connectOura() { openURL(url) } }
                    }.disabled(model.wearableBusy || !model.canConnectOura)
                    if !model.canConnectOura { Text("The server needs an Oura app configuration.").font(.footnote) }
                    Button("Sync Oura") { Task { await model.syncOura() } }
                        .disabled(model.wearableBusy || !model.ouraConnected)
                    Button("Disconnect Oura and delete summaries", role: .destructive) { Task { await model.disconnect("oura") } }
                        .disabled(model.wearableBusy || !model.ouraConnected)
                    Text(model.wearableText).font(.footnote)
                    Button("Refresh connection status") { Task { await model.refreshWearables() } }
                }
            }
            .navigationTitle("Quiet Compass")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { DiagnosticsView(model: model) } label: {
                        Label("Diagnostics", systemImage: "stethoscope")
                    }
                }
            }
            .sheet(item: $arrivalGuidance) { guidance in
                ArrivalCheckView(model: model, guidance: guidance)
            }
            .task { await model.sync(); await model.refreshWearables() }
        }
    }
}

extension Guidance: @retroactive Identifiable {
    public var id: String { "\(sessionId.uuidString)/\(targetPlaceId.uuidString)/\(updatedAt.timeIntervalSince1970)" }
}

// Hour-0 spike tests, server health, pending uploads and the session id.
import QuietCore
import SwiftUI
import UIKit

struct DiagnosticsView: View {
    var model: CompassModel
    @State private var health: String?
    @State private var pinging = false
    @State private var copied = false

    private var runner: SpikeRunner { model.companion.spikeRunner }

    var body: some View {
        Form {
            Section {
                ForEach(SpikeTest.allCases, id: \.self) { test in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(test.title).font(.headline)
                        Text(test.explanation).font(.footnote).foregroundStyle(.secondary)
                        Button("Run") { Task { await runner.run(test) } }
                            .disabled(runner.isRunning || model.running || model.starting)
                        if let report = runner.reports.first(where: { $0.test == test }) {
                            Text(Self.verdict(report.passed)).font(.body.weight(.semibold))
                            ForEach(Array(report.lines.enumerated()), id: \.offset) { _, line in
                                Text(line).font(.footnote.monospaced()).textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                if runner.isRunning {
                    VStack(alignment: .leading, spacing: 6) {
                        if let prompt = runner.prompt { Text(prompt).font(.title3) }
                        if let s = runner.secondsLeft { Text("\(s) s left").font(.body.monospacedDigit()) }
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Sensor checks")
            } footer: {
                Text("Stop measuring before running a check. Results pick the capture mode: A if both spatial checks pass, B if only the first does, C otherwise.")
            }

            Section("Server") {
                Button(pinging ? "Checking…" : "Check the server") {
                    pinging = true
                    Task { health = await model.pingServer(); pinging = false }
                }
                .disabled(pinging)
                if let health { Text(health).font(.callout) }
                Text("\(model.pending) uploads pending")
                Text(model.message).font(.footnote).foregroundStyle(.secondary)
                Button("Retry pending uploads") { Task { await model.sync() } }
            }

            Section("Session") {
                if let id = model.sessionIdText {
                    Text(id).font(.footnote.monospaced()).textSelection(.enabled)
                    Button(copied ? "Copied" : "Copy session id") {
                        UIPasteboard.general.string = id
                        copied = true
                    }
                } else {
                    Text("No session yet.").foregroundStyle(.secondary)
                }
                Text("Capture mode: \(CaptureSettingsSection.title(model.companion.captureMode))")
                Text("Feedback given this session: \(model.companion.feedbackCount)")
                #if targetEnvironment(simulator)
                Text("Simulator: mock sound and a scripted walk around a 10 × 6 m rectangle.").font(.footnote)
                #endif
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }

    static func verdict(_ passed: Bool?) -> String {
        switch passed {
        case true?: "Passed"
        case false?: "Did not pass"
        case nil: "No verdict"
        }
    }
}

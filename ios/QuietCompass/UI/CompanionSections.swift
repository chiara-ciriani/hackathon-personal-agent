// Form sections CompassView adds on top of its own: how to measure (capture mode, classifier), sharing,
// the live level in words with the dwell indicator, the place list with last level and age, and links to the
// map, the arrival check and Diagnostics.
import QuietCore
import SwiftUI

/// Capture mode and classifier, shown while not recording.
struct CaptureSettingsSection: View {
    @Bindable var companion: CompanionFeatures
    var disabled: Bool

    var body: some View {
        Section {
            Picker("How to measure", selection: $companion.captureMode) {
                ForEach(CompanionFeatures.selectableModes, id: \.self) { mode in
                    Text(Self.title(mode)).tag(mode)
                }
            }
            .disabled(disabled)
            Text(Self.explanation(companion.captureMode)).font(.footnote).foregroundStyle(.secondary)
            Toggle("Recognise kinds of sound (speech, music)", isOn: $companion.classifierEnabled)
                .disabled(disabled)
        } header: {
            Text("Capture")
        } footer: {
            Text("Run the checks in Diagnostics to see which mode works on this phone. Changes apply to the next recording.")
        }
    }

    static func title(_ mode: CaptureMode) -> String {
        switch mode {
        case .spatialAR: "Spatial sound and path (A)"
        case .spatialZones: "Spatial sound and named areas (B)"
        case .arLevels: "Path and loudness (C)"
        }
    }

    static func explanation(_ mode: CaptureMode) -> String {
        switch mode {
        case .spatialAR: "Four microphones and the camera path. Can hint where sound comes from. Needs the spatial-audio check to pass."
        case .spatialZones: "Four microphones, no camera; you name the area you're in."
        case .arLevels: "Overall loudness and the camera path. Works on the most phones."
        }
    }
}

/// The opt-in toggle for the shared sound layer.
struct ShareSection: View {
    @Bindable var companion: CompanionFeatures

    var body: some View {
        Section {
            Toggle("Share anonymous sound summaries", isOn: $companion.shareContributions)
            Text("After you stay 30 seconds at a marked spot, a small loudness summary of that spot is shared to help other people's agents; no audio, route or identity is included.")
                .font(.footnote)
            if companion.shareContributions, let text = companion.lastContributionText {
                Text(text).font(.callout).foregroundStyle(.secondary)
            }
        } header: {
            Text("Shared map")
        }
    }
}

/// Level in words relative to the session median, plus the dwell indicator.
struct LevelInWordsSection: View {
    var companion: CompanionFeatures
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let dwell = companion.dwell
        Section("Right now") {
            VStack(alignment: .leading, spacing: 10) {
                Text(companion.levelWords)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                RelativeMeter(fraction: LevelDescription.meterFraction(companion.liveLevel, median: companion.sessionMedian),
                              color: Theme.levelColor(companion.liveLevel, median: companion.sessionMedian))
                    .frame(height: 12)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: companion.liveLevel)
                    .accessibilityHidden(true)
                Text("Compared with the middle level of this session.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Right now: \(companion.levelWords)")

            VStack(alignment: .leading, spacing: 8) {
                Label(dwell.placeId == nil ? "Not at a marked spot" : dwell.label,
                      systemImage: dwell.confidence == .ok ? "checkmark.circle" : "hourglass")
                    .font(.body.monospacedDigit())
                if dwell.placeId != nil {
                    ProgressView(value: min(dwell.seconds, dwell.targetSeconds), total: dwell.targetSeconds)
                        .tint(Theme.calm)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Marked places with their last level in words and its age.
struct PlaceLevelsSection: View {
    var model: CompassModel

    var body: some View {
        let median = model.companion.sessionMedian
        Section("Your spots") {
            ForEach(model.placeSummaries) { s in
                HStack(spacing: 12) {
                    Circle().fill(Theme.levelColor(s.lastLevel, median: median)).frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.place.label).font(.body.weight(.semibold))
                        Text(Self.detail(s, median: median)).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    static func detail(_ s: CompassModel.PlaceSummary, median: Double?) -> String {
        guard let at = s.lastMeasuredAt else { return "not measured yet" }
        return "\(LevelDescription.short(s.lastLevel, median: median)), \(LevelDescription.age(since: at))"
    }
}

/// A horizontal bar with a centre tick for the session median.
struct RelativeMeter: View {
    var fraction: Double
    var color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule().fill(color).frame(width: max(8, geo.size.width * fraction))
                Rectangle().fill(Color.primary.opacity(0.35))
                    .frame(width: 2)
                    .offset(x: geo.size.width / 2 - 1)
            }
        }
    }
}

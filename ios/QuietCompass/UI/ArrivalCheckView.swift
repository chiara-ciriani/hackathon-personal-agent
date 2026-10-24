// "I've arrived" flow: a 30 s fresh measurement at the destination, then goal/verdict/feel feedback, then
// guidance status "arrived" (CompassModel.finishGuidance). Feedback goes through CompassModel's outbox.
import QuietCore
import SwiftUI

struct ArrivalCheckView: View {
    var model: CompassModel
    var guidance: Guidance
    @Environment(\.dismiss) private var dismiss
    @State private var elapsed = 0
    @State private var showFeedback = false
    private let duration = 30

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Checking how it sounds here")
                    .font(.title2.weight(.semibold))
                Text("Keep the phone still for 30 seconds.")
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(min(elapsed, duration)), total: Double(duration))
                    .tint(Theme.calm)
                    .accessibilityLabel("Measuring")
                    .accessibilityValue("\(min(elapsed, duration)) of \(duration) seconds")
                Text("measuring \(min(elapsed, duration)) s / \(duration) s")
                    .font(.title3.monospacedDigit())
                    .accessibilityHidden(true)
                Card {
                    Text("Right now").font(.headline).foregroundStyle(.secondary)
                    Text(model.companion.levelWords).font(.title3.weight(.semibold))
                }
                Spacer()
                Button(elapsed >= duration ? "How was it?" : "Skip the check") { showFeedback = true }
                    .buttonStyle(CalmButtonStyle(prominent: elapsed >= duration))
            }
            .padding(20)
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .task {
                while elapsed < duration && !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    elapsed += 1
                }
            }
            .navigationDestination(isPresented: $showFeedback) {
                FeedbackSheet(placeLabel: guidance.targetLabel) { answer in
                    Task {
                        if let answer {
                            await model.submitFeedback(placeId: guidance.targetPlaceId, goal: answer.goal,
                                                       verdict: answer.verdict, feel: answer.feel)
                        }
                        await model.finishGuidance(.arrived)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct FeedbackSheet: View {
    struct Answer { var goal: Goal; var verdict: Verdict; var feel: Feel? }
    var placeLabel: String
    /// nil when skipped.
    var onDone: (Answer?) -> Void

    @State private var goal: Goal = .rest
    @State private var verdict: Verdict?
    @State private var feel: Feel?

    var body: some View {
        Form {
            Section("What did you come here for?") {
                Picker("Goal", selection: $goal) {
                    Text("Talk").tag(Goal.talk)
                    Text("Rest").tag(Goal.rest)
                    Text("Work").tag(Goal.work)
                }
                .pickerStyle(.segmented)
            }
            Section("Does \(placeLabel) work for that?") {
                ForEach(Verdict.allCases, id: \.self) { v in
                    choice(Self.verdictText(v), selected: verdict == v) { verdict = v }
                }
            }
            Section("How does it feel? (optional)") {
                ForEach(Feel.allCases, id: \.self) { f in
                    choice(Self.feelText(f), selected: feel == f) { feel = (feel == f ? nil : f) }
                }
            }
            Section {
                Button("Save") {
                    guard let verdict else { return }
                    onDone(Answer(goal: goal, verdict: verdict, feel: feel))
                }
                .disabled(verdict == nil)
                Button("Skip") { onDone(nil) }
            } footer: {
                Text("Your answer stays private and helps your agent learn what works for you.")
            }
        }
        .navigationTitle("How was it?")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func choice(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(text).foregroundStyle(.primary)
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    static func verdictText(_ v: Verdict) -> String {
        switch v {
        case .good: "Good"
        case .ok: "Okay"
        case .bad: "Not for me"
        }
    }

    static func feelText(_ f: Feel) -> String {
        switch f {
        case .calm: "Calm"
        case .neutral: "Neutral"
        case .chaotic: "Too busy"
        }
    }
}

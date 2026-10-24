// CompassModel hooks for CompanionFeatures, plus the feedback upload and the read-only accessors the
// minimap, arrival check and Diagnostics need. Uses CompassModel's PhoneServer (and PhoneOutbox for feedback);
// no second network stack.
import Foundation
import QuietCore

extension CompassModel {
    struct PlaceSummary: Identifiable, Hashable {
        var place: Place
        var lastLevel: Double?
        var lastMeasuredAt: Date?
        var id: UUID { place.id }
    }

    /// Newest first, with the last measured level of each place.
    var placeSummaries: [PlaceSummary] {
        places.reversed().map { p in
            let o = companion.lastObservationByPlace[p.id]
            return PlaceSummary(place: p, lastLevel: o?.levelDbfsRel, lastMeasuredAt: o?.t)
        }
    }

    /// Next turn on the active route from the latest normal pose, for the minimap.
    var nextTurn: NextTurn? {
        guard let route, let pose, pose.tracking == .normal, let position = pose.position else { return nil }
        return RouteBack.nextTurn(on: route, from: position, headingRad: pose.headingRad)
    }

    var sessionIdText: String? { session?.id.uuidString.lowercased() }

    // MARK: - Called from start()'s frame loop

    func companionFrame(_ frame: FeatureFrame, pose: PoseSample?) {
        let position = pose?.tracking == .normal ? pose?.position : nil
        let placeId = PlaceLocator(places: places).nearestPlace(to: position)?.id
        guard let window = companion.ingest(frame: frame, placeId: placeId) else { return }
        pendingContributionWindows.append(window)
    }

    /// Called after an observation was queued. Shares a contribution for any finished window, when opted in.
    func companionObservation(_ observation: QuietCore.Observation) async {
        companion.record(observation)
        let windows = pendingContributionWindows
        pendingContributionWindows = []
        guard companion.shareContributions, let session, let server else { return }
        let ready = windows.compactMap { window -> (SharedContribution, Place)? in
            guard let place = places.first(where: { $0.id == window.placeId }),
                  let contribution = companion.contribution(for: window, place: place, profile: session.deviceProfile)
            else { return nil }
            return (contribution, place)
        }
        guard !ready.isEmpty else { return }
        // Off the frame loop: a slow network must not hold up capture.
        Task {
            for (contribution, place) in ready {
                await share(contribution, place: place, server: server)
            }
        }
    }

    private func share(_ contribution: SharedContribution, place: Place, server: PhoneServer) async {
        // Retry anything that failed earlier first (oldest first), then this one.
        for waiting in companion.takeRetryableContributions() {
            await send(waiting.contribution, label: waiting.label, server: server)
        }
        await send(contribution, label: place.label, server: server)
    }

    /// Posts directly instead of through PhoneOutbox: the outbox retries its head item forever, so a
    /// contribution the server rejects as invalid would block every later observation upload. Failed
    /// contributions wait in a small in-memory queue and are retried with the next one.
    private func send(_ contribution: SharedContribution, label: String, server: PhoneServer) async {
        do {
            let body = try ContractJSON.encoder().encode(ContributionSubmission(contribution: contribution))
            let data = try await server.request("/v1/contributions", method: "POST", body: body)
            let result = try ContractJSON.decoder().decode(ContributionResult.self, from: data)
            companion.setContributionText("\(label): \(result.displayText)")
        } catch {
            let kept = companion.keepForRetry(contribution, label: label)
            companion.setContributionText(kept
                ? "\(label): not shared yet (\(error.localizedDescription)); will try again"
                : "\(label): not shared (\(error.localizedDescription))")
        }
    }

    // MARK: - Feedback (arrival check)

    func submitFeedback(placeId: UUID, goal: Goal, verdict: Verdict, feel: Feel?) async {
        guard let session, let server, let outbox else {
            message = "Save a server connection first."
            return
        }
        let feedback = Feedback(sessionId: session.id, placeId: placeId, goal: goal, verdict: verdict, feel: feel)
        do {
            try await outbox.enqueue(FeedbackBatch(feedback: [feedback]), path: "/v1/feedback", server: server)
            companion.noteFeedback()
            await sync()
        } catch {
            message = error.localizedDescription
        }
    }

    // MARK: - Diagnostics

    func pingServer() async -> String {
        guard let origin = server?.origin else { return "No server saved yet." }
        return await CompanionFeatures.pingHealth(origin: origin)
    }
}

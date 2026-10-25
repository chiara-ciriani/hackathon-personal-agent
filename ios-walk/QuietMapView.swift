import SwiftUI

/// The default screen: the room's noise map filling in as you walk, and an arrow to the quietest spot measured.
struct QuietMapView: View {
    @Bindable var model: CompassModel
    @Bindable var agent: AgentLink
    @Binding var showAdvanced: Bool

    var body: some View {
        ScrollView { VStack(spacing: 14) {
            HStack {
                Text("Quiet Map").font(.title.bold())
                Spacer()
                Button("Advanced", systemImage: "slider.horizontal.3") { showAdvanced = true }
                    .labelStyle(.iconOnly).font(.title2).disabled(agent.hasLink)
            }
            FieldMapView(field: model.field, path: model.mapPath, user: model.mapUser)
            if agent.hasLink { AgentPanel(agent: agent, model: model) } else { guidance }
            if !agent.hasLink && !agent.message.isEmpty { Text(agent.message).font(.caption).foregroundStyle(.secondary) }
            Button {
                if agent.hasLink { agent.disconnect(model: model) }
                else if model.isRecording { model.stopWalk() }
                else { Task { await model.start(); if model.stream.sessionRunning { model.startWalk() } } }
            } label: {
                Label(agent.hasLink ? "Disconnect agent" : model.isRecording ? "Stop and save" : "Start a new map",
                      systemImage: model.isRecording ? "stop.fill" : "figure.walk")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.isRecording ? .gray : .green)
            Text(statusLine)
                .font(.caption)
                .foregroundStyle(model.isRecording && !model.ar.isNormal ? Color.orange : Color.secondary)
            Spacer(minLength: 0)
        }
        .padding() }
        .overlay { EdgeGlow(turn: glowTurn) }
        .sensoryFeedback(.impact(weight: .light), trigger: glowTurn.map(EdgeGlow.side)) { _, side in side == .ahead }
    }

    /// Where the edge glow points: the agent's destination when it advised a move, otherwise the
    /// quietest measured spot, but only while the spot you stand on is loud. Nil keeps the screen calm.
    private var glowTurn: Double? {
        guard model.ar.isNormal, let me = model.mapUser else { return nil }
        let target: (x: Double, z: Double)
        if agent.hasLink {
            guard let advice = agent.advice, advice.action == "move", let destination = advice.destination,
                  destination.kind == "room", destination.requestId == agent.lastRequestId,
                  let expires = AgentProtocol.date(advice.expiresAt), expires > Date() else { return nil }
            target = (destination.x, destination.z)
        } else {
            guard model.isRecording, let spot = model.field?.quietSpots.first, (hereLoudness ?? 0) >= 0.66 else { return nil }
            target = (spot.x, spot.z)
        }
        let dx = target.x - me.x, dz = target.z - me.y  // mapUser is (x, z)
        guard (dx * dx + dz * dz).squareRoot() >= 1.5 else { return nil }
        return Geo.degrees(atan2(dx, -dz)) - model.phoneBearing
    }

    @ViewBuilder private var guidance: some View {
        if model.isRecording, model.ar.isNormal, let spot = model.field?.quietSpots.first, let me = model.mapUser {
            let dx = spot.x - me.x, dz = spot.z - me.y  // mapUser is (x, z)
            let distance = (dx * dx + dz * dz).squareRoot()
            if distance < 1.5 {
                card(arrow: nil, title: "You're at the quietest spot you've measured", detail: detail(spot))
            } else {
                // ARKit runs with gravityAndHeading: +x is east and -z is north.
                let bearing = (Geo.degrees(atan2(dx, -dz)) + 360).truncatingRemainder(dividingBy: 360)
                card(arrow: bearing - model.phoneBearing,
                     title: String(format: "Quieter spot %.0f m away", distance),
                     detail: detail(spot))
            }
        } else {
            card(arrow: nil,
                 title: model.isRecording ? "Keep walking to map the room" : "Tap Start a new map and walk around",
                 detail: "Hold the phone up, camera forward. Grey means not measured yet.")
        }
    }

    private func detail(_ spot: QuietSpot) -> String {
        let age = spot.ageMin < 1 ? "measured just now" : String(format: "measured %.0f min ago", spot.ageMin)
        return [hereText, age].compactMap { $0 }.joined(separator: " · ")
    }

    /// How loud the spot you stand on is, from 0 (this walk's quietest) to 1 (its loudest).
    private var hereLoudness: Double? {
        guard let field = model.field, let me = model.mapUser, let range = field.levelRange,
              let level = field.cell(atX: me.x, z: me.y)?.levelDB else { return nil }
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return nil }
        return (level - range.lowerBound) / span
    }

    private var hereText: String? {
        hereLoudness.map { $0 < 0.33 ? "Here: quiet" : $0 < 0.66 ? "Here: moderate" : "Here: loud" }
    }

    private var statusLine: String {
        guard model.isRecording else { return "Not mapping. Saved maps are under Advanced → Walk map." }
        guard model.ar.isNormal else { return "Tracking: \(model.ar.detail). Move slowly and point the camera at the room." }
        return "Mapping · \(model.walk?.samples.count ?? 0) readings"
    }

    private func card(arrow: Double?, title: String, detail: String) -> some View {
        HStack(spacing: 16) {
            if let arrow {
                Image(systemName: "arrow.up")
                    .font(.system(size: 44, weight: .bold))
                    .rotationEffect(.degrees(arrow))
                    .foregroundStyle(.green)
                    .accessibilityLabel("Direction to the quieter spot")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }
}

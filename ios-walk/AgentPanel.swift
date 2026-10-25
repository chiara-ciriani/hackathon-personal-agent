import SwiftUI

struct AgentPanel: View {
    @Bindable var agent: AgentLink
    let model: CompassModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(agent.connected ? "Agent connected" : "Connect your agent", systemImage: "link")
                .font(.headline)
            Text(agent.message).font(.subheadline).foregroundStyle(.secondary)
            if !agent.connected && !agent.connecting {
                Text("Your agent uses sound readings and, if allowed, your approximate location to personalize advice. With location access, a coarse sound summary and location are also shared to unlock nearby community readings for 15 minutes. No audio or camera images are sent. Monitoring stops when you leave the app.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Allow agent and share readings") { agent.connect(model: model) }
                    .buttonStyle(.borderedProminent).tint(.purple)
            }
            if agent.connecting { ProgressView("Connecting…") }
            if let advice = agent.advice {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let expires = AgentProtocol.date(advice.expiresAt), expires > context.date {
                        Text("FROM YOUR AGENT").font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text(advice.message).font(.body)
                        if advice.action == "move", let destination = advice.destination,
                           destination.kind == "room", destination.requestId == agent.lastRequestId,
                           model.ar.isNormal, let me = model.mapUser {
                            let dx = destination.x - me.x, dz = destination.z - me.y
                            let distance = hypot(dx, dz)
                            let bearing = atan2(dx, -dz) * 180 / .pi
                            HStack {
                                if distance >= 1.5 {
                                    Image(systemName: "arrow.up").font(.largeTitle)
                                        .rotationEffect(.degrees(bearing - model.phoneBearing))
                                        .accessibilityLabel("Direction toward the agent's measured destination")
                                }
                                Text(distance < 1.5 ? "Near the measured spot" : String(format: "%.0f m toward the measured spot", distance))
                            }.foregroundStyle(.purple)
                            Text("Straight-line direction. Check the path around you.").font(.caption)
                        } else if advice.action == "move" {
                            Text("Direction paused. Move the camera slowly to restore tracking.").font(.caption)
                        }
                    } else { Text("Recommendation expired. Ask your agent to measure again.").font(.caption) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.purple.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

import SwiftUI

/// A soft glow on the screen edge that shows which way to turn, so the direction can be read
/// out of the corner of the eye, without reading text or a map.
struct EdgeGlow: View {
    enum Side: Equatable { case ahead, left, right, behind }

    /// The target's bearing relative to where the phone points, in degrees. Nil hides the glow.
    let turn: Double?

    static func side(_ turn: Double) -> Side {
        let a = (turn.truncatingRemainder(dividingBy: 360) + 540).truncatingRemainder(dividingBy: 360) - 180
        if abs(a) <= 25 { return .ahead }
        if abs(a) >= 150 { return .behind }
        return a < 0 ? .left : .right
    }

    var body: some View {
        ZStack {
            if let turn {
                switch Self.side(turn) {
                case .ahead:
                    // Facing the right way: the whole border breathes slowly.
                    TimelineView(.animation) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate
                        RoundedRectangle(cornerRadius: 48)
                            .strokeBorder(Color.green.opacity(0.55 + 0.25 * sin(phase * .pi / 2)), lineWidth: 18)
                            .blur(radius: 8)
                    }
                case .left: edge(.leading)
                case .right: edge(.trailing)
                case .behind: edge(.bottom)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.4), value: turn.map(Self.side))
        .accessibilityHidden(true)
    }

    private func edge(_ edge: Edge) -> some View {
        let horizontal = edge == .leading || edge == .trailing
        let start: UnitPoint = edge == .leading ? .leading : edge == .trailing ? .trailing : .bottom
        let end: UnitPoint = edge == .leading ? .trailing : edge == .trailing ? .leading : .top
        return LinearGradient(colors: [Color.green.opacity(0.75), .clear], startPoint: start, endPoint: end)
            .frame(width: horizontal ? 70 : nil, height: horizontal ? nil : 90)
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: edge == .leading ? .leading : edge == .trailing ? .trailing : .bottom)
    }
}

// SPDX-License-Identifier: AGPL-3.0-or-later
//
// 0.8.2: la guía de MotoLink en la pantalla bloqueada y en la Dynamic Island.
import ActivityKit
import SwiftUI
import WidgetKit

@main
struct MotoLinkLiveBundle: WidgetBundle {
    var body: some Widget {
        NavLiveActivity()
    }
}

struct NavLiveActivity: Widget {
    private static let accent = Color(red: 0.16, green: 0.47, blue: 1.0)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NavActivityAttributes.self) { context in
            LockScreenGuide(state: context.state, destination: context.attributes.destination)
                .activityBackgroundTint(Color.black.opacity(0.82))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ManeuverTile(state: s, size: 52)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(s.arrived ? "" : LiveFormat.distance(s.distance))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        if s.speedLimit > 0 && !s.arrived { LimitBadge(kmh: s.speedLimit, size: 26) }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(headline(s))
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)
                        if !s.arrived {
                            HStack(spacing: 6) {
                                Text("Llegada")
                                Text(s.eta, style: .time)
                                Text("·")
                                Text(LiveFormat.distance(s.remainingDistance))
                            }
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: LiveFormat.symbol(kind: s.kind, arrived: s.arrived))
                    .foregroundColor(Self.accent)
            } compactTrailing: {
                Text(s.arrived ? "Llegaste" : LiveFormat.distance(s.distance))
                    .monospacedDigit()
                    .font(.system(size: 14, weight: .semibold))
            } minimal: {
                Image(systemName: LiveFormat.symbol(kind: s.kind, arrived: s.arrived))
                    .foregroundColor(Self.accent)
            }
        }
    }

    fileprivate static func tint() -> Color { accent }
}

private func headline(_ s: NavActivityAttributes.ContentState) -> String {
    if s.arrived { return "Has llegado a tu destino" }
    if s.rerouting { return "Recalculando la ruta…" }
    return s.instruction
}

private struct ManeuverTile: View {
    let state: NavActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(state.rerouting ? Color.orange : NavLiveActivity.tint())
            Image(systemName: LiveFormat.symbol(kind: state.kind, arrived: state.arrived))
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}

private struct LimitBadge: View {
    let kmh: Int
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color.white)
            Circle().strokeBorder(Color.red, lineWidth: size * 0.12)
            Text("\(kmh)")
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundColor(.black)
                .minimumScaleFactor(0.6)
        }
        .frame(width: size, height: size)
    }
}

private struct LockScreenGuide: View {
    let state: NavActivityAttributes.ContentState
    let destination: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ManeuverTile(state: state, size: 58)
            VStack(alignment: .leading, spacing: 3) {
                if !state.arrived {
                    Text(LiveFormat.distance(state.distance))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                Text(headline(state))
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if state.arrived {
                        Text(destination)
                    } else {
                        Text("Llegada")
                        Text(state.eta, style: .time)
                        Text("· \(LiveFormat.distance(state.remainingDistance))")
                    }
                }
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
            }
            .foregroundColor(.white)
            Spacer(minLength: 0)
            if state.speedLimit > 0 && !state.arrived {
                LimitBadge(kmh: state.speedLimit, size: 40)
            }
        }
        .padding(16)
    }
}

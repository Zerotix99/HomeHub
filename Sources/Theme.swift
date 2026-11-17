import SwiftUI

enum HubTheme {
    static let bg = Color(red: 0.027, green: 0.039, blue: 0.071)          // #070A12
    static let card = Color(red: 0.071, green: 0.102, blue: 0.184)        // #121A2F
    static let cardElevated = Color(red: 0.098, green: 0.141, blue: 0.247)// #19243F
    static let border = Color.white.opacity(0.10)
    static let borderStrong = Color.white.opacity(0.20)

    static let emerald = Color(red: 0.063, green: 0.725, blue: 0.506)     // #10B981
    static let sky = Color(red: 0.220, green: 0.741, blue: 0.973)         // #38BDF8
    static let indigo = Color(red: 0.388, green: 0.400, blue: 0.945)      // #6366F1
    static let purple = Color(red: 0.659, green: 0.333, blue: 0.969)      // #A855F7
    static let pink = Color(red: 0.925, green: 0.282, blue: 0.600)        // #EC4899
    static let amber = Color(red: 0.961, green: 0.620, blue: 0.043)       // #F59E0B
    static let rose = Color(red: 0.957, green: 0.247, blue: 0.369)        // #F43F5E
}

struct IconBadge: View {
    let symbol: String
    let colors: [Color]
    var size: CGFloat = 38
    var iconSize: CGFloat = 17

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
                .shadow(color: (colors.first ?? .blue).opacity(0.35), radius: 6, y: 3)

            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

struct GlowChip: View {
    let text: String
    let dotColor: Color
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(dotColor)
            } else {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: dotColor, radius: 4)
            }
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(HubTheme.cardElevated.opacity(0.85), in: Capsule())
        .overlay(Capsule().stroke(HubTheme.border, lineWidth: 1))
    }
}

struct StatusBadgePill: View {
    let text: String
    let active: Bool
    var activeColor: Color = HubTheme.emerald

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .heavy))
            .tracking(0.4)
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background((active ? activeColor : HubTheme.rose).opacity(0.18), in: Capsule())
            .overlay(Capsule().stroke((active ? activeColor : HubTheme.rose).opacity(0.42), lineWidth: 1))
            .foregroundStyle(active ? activeColor : HubTheme.rose)
    }
}

struct HubCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 20
    var highlightColor: Color? = nil

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(HubTheme.card.opacity(0.88))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                (highlightColor ?? .white).opacity(highlightColor != nil ? 0.45 : 0.16),
                                (highlightColor ?? .white).opacity(highlightColor != nil ? 0.15 : 0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
}

extension View {
    func hubCard(cornerRadius: CGFloat = 20, highlight: Color? = nil) -> some View {
        modifier(HubCardModifier(cornerRadius: cornerRadius, highlightColor: highlight))
    }
}

struct PiGatewayBar: View {
    @EnvironmentObject var client: HubClient

    var body: some View {
        HStack(spacing: 10) {
            IconBadge(symbol: "cpu.fill", colors: [HubTheme.emerald, HubTheme.sky], size: 32, iconSize: 14)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text("Pi 4 Gateway")
                        .font(.system(size: 12, weight: .bold))
                    Text("• \(client.activeRouteLabel)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HubTheme.sky)
                }
                let temp = client.jellyStatus?.piStats?.tempC.map { String(format: "%.1f°C", $0) } ?? "--°C"
                let up = client.jellyStatus?.piStats?.uptime ?? "Bereit"
                Text("\(temp) • Up: \(up)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 4) {
                Circle()
                    .fill(client.sideJITOnline ? HubTheme.emerald : HubTheme.amber)
                    .frame(width: 6, height: 6)
                Text(client.sideJITOnline ? "JIT BEREIT" : "WOL BEREIT")
                    .font(.system(size: 9.5, weight: .heavy))
                    .foregroundStyle(client.sideJITOnline ? HubTheme.emerald : HubTheme.sky)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((client.sideJITOnline ? HubTheme.emerald : HubTheme.sky).opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke((client.sideJITOnline ? HubTheme.emerald : HubTheme.sky).opacity(0.35), lineWidth: 1))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .hubCard(cornerRadius: 16)
    }
}

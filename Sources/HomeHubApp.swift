import SwiftUI

@main
struct HomeHubApp: App {
    @StateObject private var client = HubClient()

    init() {
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(red: 0.04, green: 0.06, blue: 0.11, alpha: 0.96)
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(client)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootTabView: View {
    @EnvironmentObject var client: HubClient
    @State private var selectedTab: Int = 0

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
                JellyControlView()
                    .tabItem {
                        Label("JellyControl", systemImage: "bolt.circle.fill")
                    }
                    .tag(0)

                DealRadarView(switchToDevicesTab: { selectedTab = 2 })
                    .tabItem {
                        Label("Deal Radar", systemImage: "tag.fill")
                    }
                    .badge(client.dealState?.stats.activeDeals ?? 0)
                    .tag(1)

                DeviceManagerTabView()
                    .tabItem {
                        Label("Geräte", systemImage: "slider.horizontal.below.rectangle")
                    }
                    .tag(2)

                SystemView()
                    .tabItem {
                        Label("System & JIT", systemImage: "cpu.fill")
                    }
                    .tag(3)
            }
            .tint(HubTheme.sky)

            if let toast = client.toastMessage {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(HubTheme.sky)
                    Text(toast)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(HubTheme.cardElevated, in: Capsule())
                .overlay(Capsule().stroke(HubTheme.sky.opacity(0.55), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 14, y: 6)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(99)
            }
        }
        .task {
            await client.resolveActiveHost()
            async let j: () = client.refreshJelly()
            async let d: () = client.refreshDealState()
            async let c: () = client.fetchDealConfig()
            async let a: () = client.checkAnisetteHealth()
            async let s: () = client.checkSideJIT()
            _ = await (j, d, c, a, s)
        }
    }
}

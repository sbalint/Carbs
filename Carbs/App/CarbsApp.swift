import SwiftUI
import SwiftData

@main
struct CarbsApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Profile.self, Food.self, FoodEntry.self, WeightLog.self, CheckIn.self])
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [Profile]

    var body: some View {
        Group {
            if let profile = profiles.first {
                MainTabView(profile: profile)
            } else {
                SetupView()
            }
        }
        #if DEBUG
        .onAppear { DemoData.seedIfNeeded(context) }
        #endif
    }
}

struct MainTabView: View {
    @Bindable var profile: Profile
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            DiaryView(profile: profile)
                .tabItem { Label("Diary", systemImage: "book.closed") }.tag(0)
            CoachView(profile: profile)
                .tabItem { Label("Coach", systemImage: "chart.line.uptrend.xyaxis") }.tag(1)
            MeView(profile: profile)
                .tabItem { Label("Me", systemImage: "person") }.tag(2)
            SettingsView(profile: profile)
                .tabItem { Label("Settings", systemImage: "gearshape") }.tag(3)
        }
        #if DEBUG
        .onAppear { tab = DemoData.initialTab }
        #endif
        .tint(Theme.primary)
    }
}

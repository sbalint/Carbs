import SwiftUI
import SwiftData

@main
struct CarbsApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(Self.container)
    }

    /// Kept in Carbs' own container. With an App Group entitlement (for Loop), SwiftData would
    /// otherwise default to the shared group container and the existing diary would seem to vanish.
    static let container: ModelContainer = {
        let schema = Schema([Profile.self, Food.self, FoodEntry.self, WeightLog.self, CheckIn.self])
        let configuration = ModelConfiguration(schema: schema, groupContainer: .none)
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Could not open the Carbs database: \(error)")
        }
    }()
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

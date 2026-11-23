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
    @Environment(\.scenePhase) private var scenePhase
    @Query private var profiles: [Profile]

    var body: some View {
        Group {
            if let profile = profiles.first {
                MainTabView(profile: profile)
            } else {
                SetupView()
            }
        }
        // Tapping a number selects it: type to replace it, or leave it as it was.
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { note in
            guard let field = note.object as? UITextField,
                  [.decimalPad, .numberPad].contains(field.keyboardType) else { return }
            DispatchQueue.main.async { field.selectAll(nil) }
        }
        // Pull new weigh-ins from Apple Health when it's turned on and each time the app comes forward.
        .task(id: profiles.first?.healthImport) { await importHealth() }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await importHealth() } } }
        #if DEBUG
        .onAppear { DemoData.seedIfNeeded(context) }
        #endif
    }

    private func importHealth() async {
        guard let profile = profiles.first else { return }
        await HealthImport.run(profile: profile, context: context)
    }
}

struct MainTabView: View {
    @Bindable var profile: Profile
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0
    /// The tabs are rebuilt when this changes, so opening the app in the morning shows today
    /// rather than the day it was last left on.
    @State private var day = Date.now.startOfDay

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
        .id(day)
        .onChange(of: scenePhase) { if scenePhase == .active { day = Date.now.startOfDay } }
        // Midnight passing while the app is open.
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            day = Date.now.startOfDay
        }
        #if DEBUG
        .onAppear { tab = DemoData.initialTab }
        #endif
        .tint(Theme.primary)
    }
}

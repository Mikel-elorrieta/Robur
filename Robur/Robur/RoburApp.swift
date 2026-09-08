import SwiftUI
import SwiftData

@main
struct RoburApp: App {
    let container: ModelContainer = {
        let schema = Schema([Exercise.self, Routine.self, RoutineExercise.self, WorkoutSession.self, WorkoutSet.self,
                             Food.self, MealEntry.self, PlannedMeal.self, BodyMeasurement.self, UserProfile.self])
        let config = ModelConfiguration("Robur", schema: schema)
        do { return try ModelContainer(for: schema, configurations: [config]) }
        catch { fatalError("No se pudo crear el ModelContainer: \(error)") }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(.roburAccent)
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @State private var seeded = false
    @State private var health = HealthKitService.shared

    var body: some View {
        Group {
            if let profile = profiles.first {
                MainTabView(profile: profile)
            } else {
                OnboardingView()
            }
        }
        .environment(health)
        .task {
            guard !seeded else { return }
            seeded = true
            SeedService.seedIfNeeded(context: context)
            if AppSettings.healthKitEnabled { await health.requestAuthorization() }
        }
    }
}

struct MainTabView: View {
    let profile: UserProfile
    var body: some View {
        TabView {
            TodayView(profile: profile).tabItem { Label("Hoy", systemImage: "sun.max.fill") }
            WorkoutHomeView(profile: profile).tabItem { Label("Entreno", systemImage: "dumbbell.fill") }
            DietHomeView(profile: profile).tabItem { Label("Dieta", systemImage: "fork.knife") }
            ProgressHomeView(profile: profile).tabItem { Label("Progreso", systemImage: "chart.line.uptrend.xyaxis") }
            SettingsView(profile: profile).tabItem { Label("Ajustes", systemImage: "gearshape.fill") }
        }
    }
}

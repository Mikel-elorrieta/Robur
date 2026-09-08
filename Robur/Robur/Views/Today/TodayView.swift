import SwiftUI
import SwiftData
import Charts

struct TodayView: View {
    let profile: UserProfile
    @Environment(\.modelContext) private var context
    @Environment(HealthKitService.self) private var health
    @AppStorage(SettingsKey.healthKitEnabled) private var healthKitEnabled = false

    @Query(sort: \BodyMeasurement.date, order: .reverse) private var measurements: [BodyMeasurement]
    @Query private var todayMeals: [MealEntry]
    @Query private var todaySessions: [WorkoutSession]

    init(profile: UserProfile) {
        self.profile = profile
        let start = Date.now.dayStart, end = start.adding(days: 1)
        _todayMeals = Query(filter: #Predicate<MealEntry> { $0.date >= start && $0.date < end })
        _todaySessions = Query(filter: #Predicate<WorkoutSession> { $0.startedAt >= start && $0.startedAt < end }, sort: \.startedAt)
    }

    private var weight: Double { measurements.first?.weightKg ?? 75 }
    private var targets: CalorieCalculator.MacroTargets { CalorieCalculator.macroTargets(profile: profile, weightKg: weight) }
    private var eaten: Double { todayMeals.reduce(0) { $0 + $1.kcal } }
    private var burnedWorkouts: Double { todaySessions.reduce(0) { $0 + $1.estimatedCalories } }
    private var protein: Double { todayMeals.reduce(0) { $0 + $1.protein } }
    private var carbs: Double { todayMeals.reduce(0) { $0 + $1.carbs } }
    private var fat: Double { todayMeals.reduce(0) { $0 + $1.fat } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    balanceCard
                    if healthKitEnabled { healthCards } else { healthPrompt }
                    macros
                    if !todaySessions.isEmpty { sessionsToday }
                    if let m = measurements.first { weightCard(m) }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(greeting)
            .refreshable { await health.refresh() }
            .task { if healthKitEnabled { await health.refresh() } }
        }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: .now)
        let s = h < 13 ? "Egun on" : h < 20 ? "Arratsalde on" : "Gabon"
        return profile.name.isEmpty ? s : "\(s), \(profile.name)"
    }

    private var balanceCard: some View {
        let remaining = targets.kcal - eaten + burnedWorkouts
        return HStack(spacing: 18) {
            ZStack {
                RingView(progress: targets.kcal > 0 ? eaten / targets.kcal : 0, lineWidth: 12)
                VStack {
                    Text(remaining.g0).font(.title.bold())
                    Text(remaining >= 0 ? "restantes" : "de más").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 120, height: 120)
            VStack(alignment: .leading, spacing: 8) {
                row("Objetivo", targets.kcal.g0, "target")
                row("Comido", eaten.g0, "fork.knife")
                row("Entreno", "+\(burnedWorkouts.g0)", "flame.fill")
                if healthKitEnabled { row("Activo (Salud)", health.activeEnergyToday.g0, "figure.walk") }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func row(_ l: String, _ v: String, _ icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption).frame(width: 16).foregroundStyle(.roburAccent)
            Text(l).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(v).font(.subheadline.monospacedDigit().bold())
        }
    }

    private var healthCards: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                StatCard(title: "Pasos", value: health.stepsToday.formatted(), subtitle: "objetivo \(profile.stepGoal.formatted())", icon: "figure.walk", color: .green)
                StatCard(title: "Ejercicio", value: "\(health.exerciseMinutesToday) min", subtitle: "\(health.distanceKmToday.g1) km", icon: "heart.fill", color: .pink)
            }
            if health.lastDays.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pasos últimos 14 días").font(.caption).foregroundStyle(.secondary)
                    Chart(health.lastDays) { d in
                        BarMark(x: .value("Día", d.date, unit: .day), y: .value("Pasos", d.steps))
                            .foregroundStyle(d.steps >= profile.stepGoal ? Color.green : Color.green.opacity(0.4))
                        RuleMark(y: .value("Objetivo", profile.stepGoal)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4])).foregroundStyle(.secondary)
                    }
                    .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { _ in AxisValueLabel(format: .dateTime.day(), centered: true) } }
                    .frame(height: 120)
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var healthPrompt: some View {
        HStack {
            Image(systemName: "heart.text.square.fill").font(.title2).foregroundStyle(.pink)
            VStack(alignment: .leading) {
                Text("Conecta Salud").bold()
                Text("Pasos, minutos de ejercicio y guardar tus entrenos en Apple Salud.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Activar") {
                healthKitEnabled = true
                Task { await health.requestAuthorization() }
            }.buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var macros: some View {
        VStack(spacing: 10) {
            MacroBar(label: "Proteína", value: protein, target: targets.protein, color: .roburProtein)
            MacroBar(label: "Hidratos", value: carbs, target: targets.carbs, color: .roburCarbs)
            MacroBar(label: "Grasa", value: fat, target: targets.fat, color: .roburFat)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var sessionsToday: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Entrenos de hoy").font(.headline)
            ForEach(todaySessions) { s in
                HStack {
                    Image(systemName: "dumbbell.fill").foregroundStyle(.roburAccent)
                    VStack(alignment: .leading) {
                        Text(s.routineName).bold()
                        Text("\(s.completedSets.count) series · \(s.totalVolumeKg.g0) kg · \(s.durationSeconds.hhmm)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(s.estimatedCalories.kcalText).font(.subheadline.bold())
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func weightCard(_ m: BodyMeasurement) -> some View {
        let days = Calendar.current.dateComponents([.day], from: m.date, to: .now).day ?? 0
        return HStack {
            Image(systemName: "scalemass.fill").foregroundStyle(.roburAccent)
            VStack(alignment: .leading) {
                Text("\(m.weightKg.g1) kg").bold()
                Text(days == 0 ? "Pesado hoy" : "Hace \(days) días").font(.caption).foregroundStyle(days >= profile.weighInReminderDays ? .orange : .secondary)
            }
            Spacer()
            if days >= profile.weighInReminderDays { Text("Toca pesarse").font(.caption.bold()).foregroundStyle(.orange) }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

import SwiftUI
import SwiftData

struct DietHomeView: View {
    let profile: UserProfile
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyMeasurement.date, order: .reverse) private var measurements: [BodyMeasurement]
    @Query(sort: \MealEntry.createdAt) private var allEntries: [MealEntry]
    @Query private var plan: [PlannedMeal]

    @State private var date = Date.now.dayStart
    @State private var addTarget: MealType?
    @State private var aiTarget: MealType?
    @State private var scanTarget: MealType?
    @State private var showPlan = false

    private var entries: [MealEntry] { allEntries.filter { $0.date == date } }
    private var targets: CalorieCalculator.MacroTargets { CalorieCalculator.macroTargets(profile: profile, weightKg: measurements.first?.weightKg ?? 75) }
    private var kcal: Double { entries.reduce(0) { $0 + $1.kcal } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    dayPicker
                    summary
                }
                ForEach(MealType.allCases) { meal in
                    let list = entries.filter { $0.mealType == meal }
                    let planned = plan.filter { $0.weekday == Calendar.current.component(.weekday, from: date) && $0.mealType == meal }
                    Section {
                        ForEach(list) { e in MealEntryRow(entry: e) }
                            .onDelete { idx in idx.map { list[$0] }.forEach { context.delete($0) }; try? context.save() }
                        if list.isEmpty && !planned.isEmpty {
                            Button { apply(planned, to: meal) } label: {
                                Label("Aplicar plan: \(planned.map(\.name).joined(separator: ", "))", systemImage: "calendar.badge.checkmark").font(.subheadline)
                            }
                        }
                        HStack(spacing: 18) {
                            Button { addTarget = meal } label: { Label("Añadir", systemImage: "plus.circle.fill") }
                            Button { scanTarget = meal } label: { Image(systemName: "barcode.viewfinder") }
                            Button { aiTarget = meal } label: { Image(systemName: "camera.fill") }
                            Spacer()
                        }
                        .buttonStyle(.borderless).font(.subheadline)
                    } header: {
                        HStack {
                            Label(meal.label, systemImage: meal.icon)
                            Spacer()
                            Text(list.reduce(0) { $0 + $1.kcal }.kcalText).font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Dieta")
            .toolbar {
                ToolbarItem(placement: .primaryAction) { Button { showPlan = true } label: { Label("Plan semanal", systemImage: "calendar") } }
            }
            .sheet(item: $addTarget) { meal in FoodSearchView(date: date, meal: meal) }
            .sheet(item: $aiTarget) { meal in AIFoodCameraView(date: date, meal: meal) }
            .sheet(item: $scanTarget) { meal in BarcodeScannerView(date: date, meal: meal) }
            .sheet(isPresented: $showPlan) { WeeklyPlanView() }
        }
    }

    private var dayPicker: some View {
        HStack {
            Button { date = date.adding(days: -1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            VStack(spacing: 2) {
                Text(date.isToday ? "Hoy" : date.weekdayName).font(.headline)
                Text(date.formatted(date: .long, time: .omitted)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { date = date.adding(days: 1) } label: { Image(systemName: "chevron.right") }.disabled(date.isToday)
        }
        .buttonStyle(.borderless)
    }

    private var summary: some View {
        VStack(spacing: 10) {
            HStack {
                Text("\(kcal.g0)").font(.title.bold()) + Text(" / \(targets.kcal.g0) kcal").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                let rest = targets.kcal - kcal
                Text(rest >= 0 ? "quedan \(rest.g0)" : "\((-rest).g0) de más").font(.subheadline.bold()).foregroundStyle(rest >= 0 ? .green : .orange)
            }
            MacroBar(label: "Proteína", value: entries.reduce(0) { $0 + $1.protein }, target: targets.protein, color: .roburProtein)
            MacroBar(label: "Hidratos", value: entries.reduce(0) { $0 + $1.carbs }, target: targets.carbs, color: .roburCarbs)
            MacroBar(label: "Grasa", value: entries.reduce(0) { $0 + $1.fat }, target: targets.fat, color: .roburFat)
        }
        .padding(.vertical, 4)
    }

    private func apply(_ planned: [PlannedMeal], to meal: MealType) {
        for p in planned {
            context.insert(MealEntry(date: date, mealType: meal, name: p.name, grams: p.grams, kcal: p.kcal, protein: p.protein, carbs: p.carbs, fat: p.fat, source: "plan", foodId: p.foodId))
        }
        try? context.save()
    }
}

struct MealEntryRow: View {
    let entry: MealEntry
    var body: some View {
        HStack {
            if let f = entry.photoFilename {
                StoredPhoto(filename: f).frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).lineLimit(1)
                Text("\(entry.grams.g0) g · P \(entry.protein.g0) · H \(entry.carbs.g0) · G \(entry.fat.g0)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(entry.kcal.g0).font(.subheadline.bold().monospacedDigit())
            if entry.source == "ai" { Image(systemName: "sparkles").font(.caption2).foregroundStyle(.purple) }
        }
    }
}

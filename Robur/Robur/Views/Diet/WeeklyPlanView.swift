import SwiftUI
import SwiftData

/// Menú semanal: qué toca cada día en cada comida. Se aplica al diario desde la pestaña Dieta.
struct WeeklyPlanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var plan: [PlannedMeal]
    @State private var target: PlanTarget?
    @State private var copyFrom: Int?

    struct PlanTarget: Identifiable { let weekday: Int; let meal: MealType; var id: String { "\(weekday)-\(meal.rawValue)" } }

    struct Day: Identifiable { let wd: Int; let name: String; var id: Int { wd } }
    // Lunes a domingo (Calendar: 1 = domingo)
    private let days: [Day] = [Day(wd: 2, name: "Lunes"), Day(wd: 3, name: "Martes"), Day(wd: 4, name: "Miércoles"), Day(wd: 5, name: "Jueves"),
                               Day(wd: 6, name: "Viernes"), Day(wd: 7, name: "Sábado"), Day(wd: 1, name: "Domingo")]

    var body: some View {
        NavigationStack {
            List {
                ForEach(days) { day in
                    let wd = day.wd
                    let dayItems = plan.filter { $0.weekday == wd }
                    Section {
                        ForEach(MealType.allCases) { meal in
                            let list = dayItems.filter { $0.mealType == meal }
                            DisclosureGroup {
                                ForEach(list) { p in
                                    HStack {
                                        Text(p.name).lineLimit(1)
                                        Spacer()
                                        Text("\(p.grams.g0) g · \(p.kcal.g0) kcal").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .onDelete { idx in idx.map { list[$0] }.forEach { context.delete($0) }; try? context.save() }
                                Button { target = PlanTarget(weekday: wd, meal: meal) } label: { Label("Añadir", systemImage: "plus") }.font(.subheadline)
                            } label: {
                                HStack {
                                    Label(meal.label, systemImage: meal.icon)
                                    Spacer()
                                    Text(list.isEmpty ? "—" : "\(list.count) · \(list.reduce(0) { $0 + $1.kcal }.g0) kcal").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text(day.name)
                            Spacer()
                            Text("\(dayItems.reduce(0) { $0 + $1.kcal }.g0) kcal").font(.caption)
                            if !dayItems.isEmpty {
                                Menu {
                                    ForEach(days.filter { $0.wd != wd }) { d in Button("Copiar a \(d.name)") { copy(from: wd, to: d.wd) } }
                                } label: { Image(systemName: "doc.on.doc").font(.caption) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Plan semanal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
            .sheet(item: $target) { t in
                FoodPickerView { food, grams in
                    context.insert(PlannedMeal(weekday: t.weekday, mealType: t.meal, food: food, grams: grams))
                    try? context.save()
                }
            }
        }
    }

    private func copy(from: Int, to: Int) {
        plan.filter { $0.weekday == to }.forEach { context.delete($0) }
        for p in plan.filter({ $0.weekday == from }) {
            let food = Food(id: p.foodId ?? UUID().uuidString, name: p.name, kcal: p.kcal / p.grams * 100, protein: p.protein / p.grams * 100,
                            carbs: p.carbs / p.grams * 100, fat: p.fat / p.grams * 100)
            context.insert(PlannedMeal(weekday: to, mealType: p.mealType, food: food, grams: p.grams))
        }
        try? context.save()
    }
}

/// Selector de alimento + cantidad, reutilizable (plan semanal).
struct FoodPickerView: View {
    let onPick: (Food, Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Food.name) private var foods: [Food]
    @State private var search = ""
    @State private var selected: Food?
    @State private var showCustom = false

    private var filtered: [Food] {
        let q = search.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if q.isEmpty { return foods.sorted { ($0.isFavorite ? 0 : 1, -$0.usageCount, $0.name) < ($1.isFavorite ? 0 : 1, -$1.usageCount, $1.name) } }
        return foods.filter { $0.displayName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { f in Button { selected = f } label: { FoodRow(food: f) }.tint(.primary) }
                Button { showCustom = true } label: { Label("Crear alimento propio", systemImage: "plus.circle") }
            }
            .searchable(text: $search, prompt: "Buscar alimento")
            .navigationTitle("Elegir alimento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
            .sheet(item: $selected) { f in PortionSheet(food: f) { g in onPick(f, g); dismiss() } }
            .sheet(isPresented: $showCustom) { CustomFoodView { selected = $0 } }
        }
    }
}

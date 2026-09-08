import SwiftUI
import SwiftData

struct FoodSearchView: View {
    let date: Date
    let meal: MealType
    var onDone: (() -> Void)? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Food.name) private var foods: [Food]

    @State private var search = ""
    @State private var offResults: [OpenFoodFactsService.Product] = []
    @State private var offLoading = false
    @State private var offError: String?
    @State private var selected: Food?
    @State private var showCustom = false
    @State private var added = 0

    private var local: [Food] {
        let q = search.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let base = q.isEmpty ? foods.sorted { ($0.isFavorite ? 0 : 1, -$0.usageCount, $0.name) < ($1.isFavorite ? 0 : 1, -$1.usageCount, $1.name) }
                             : foods.filter { $0.displayName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(q) }
        return Array(base.prefix(q.isEmpty ? 30 : 60))
    }

    var body: some View {
        NavigationStack {
            List {
                if added > 0 {
                    Section { Label("\(added) añadido\(added == 1 ? "" : "s") a \(meal.label)", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }
                Section(search.isEmpty ? "Frecuentes y favoritos" : "Mis alimentos") {
                    if local.isEmpty { Text("Nada por aquí. Prueba en Open Food Facts o crea uno.").foregroundStyle(.secondary).font(.subheadline) }
                    ForEach(local) { f in
                        Button { selected = f } label: { FoodRow(food: f) }.tint(.primary)
                    }
                }
                if !search.isEmpty {
                    Section("Open Food Facts") {
                        if offLoading { ProgressView() }
                        else if let e = offError { Text(e).foregroundStyle(.secondary).font(.subheadline) }
                        else if offResults.isEmpty {
                            Button { Task { await searchOFF() } } label: { Label("Buscar \"\(search)\" en Open Food Facts", systemImage: "magnifyingglass") }
                        }
                        ForEach(offResults) { p in
                            Button { selected = p.toFood() } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).lineLimit(1)
                                    Text("\(p.brand ?? "") · \(p.kcal.g0) kcal/100 g · P \(p.protein.g0) H \(p.carbs.g0) G \(p.fat.g0)").font(.caption).foregroundStyle(.secondary)
                                }
                            }.tint(.primary)
                        }
                    }
                }
                Section { Button { showCustom = true } label: { Label("Crear alimento propio", systemImage: "plus.circle") } }
            }
            .searchable(text: $search, prompt: "Buscar alimento")
            .onSubmit(of: .search) { Task { await searchOFF() } }
            .onChange(of: search) { _, _ in offResults = []; offError = nil }
            .navigationTitle(meal.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { onDone?(); dismiss() } } }
            .sheet(item: $selected) { f in
                PortionSheet(food: f) { grams in add(food: f, grams: grams) }
            }
            .sheet(isPresented: $showCustom) { CustomFoodView { selected = $0 } }
        }
    }

    private func searchOFF() async {
        guard search.count >= 2 else { return }
        offLoading = true; offError = nil
        do { offResults = try await OpenFoodFactsService().search(search); if offResults.isEmpty { offError = "Sin resultados en Open Food Facts." } }
        catch { offError = error.localizedDescription }
        offLoading = false
    }

    private func add(food: Food, grams: Double) {
        // Si el alimento viene de OFF y no está guardado, lo guardamos para la próxima.
        if food.modelContext == nil {
            if let existing = foods.first(where: { $0.id == food.id }) { existing.usageCount += 1; context.insert(MealEntry(date: date, mealType: meal, food: existing, grams: grams, source: "off")) }
            else { context.insert(food); food.usageCount = 1; context.insert(MealEntry(date: date, mealType: meal, food: food, grams: grams, source: "off")) }
        } else {
            food.usageCount += 1
            context.insert(MealEntry(date: date, mealType: meal, food: food, grams: grams))
        }
        try? context.save()
        added += 1
        selected = nil
    }
}

struct FoodRow: View {
    let food: Food
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if food.isFavorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                    Text(food.displayName).lineLimit(1)
                }
                Text("\(food.kcal.g0) kcal/100 g · P \(food.protein.g0) · H \(food.carbs.g0) · G \(food.fat.g0)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(food.category).font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

/// Elegir cantidad en gramos (o raciones) para un alimento.
struct PortionSheet: View {
    @Bindable var food: Food
    let onAdd: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var grams: Double = 100
    @State private var useServing = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(food.displayName).font(.headline)
                    HStack {
                        Text("Cantidad")
                        Spacer()
                        TextField("g", value: $grams, format: .number.precision(.fractionLength(0))).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                        Text("g")
                    }
                    HStack {
                        ForEach([food.servingGrams, 50, 100, 150, 200].uniqued(), id: \.self) { g in
                            Button("\(g.g0) g") { grams = g }.buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                    Toggle("Favorito", isOn: $food.isFavorite)
                }
                Section("Con \(grams.g0) g") {
                    let f = grams / 100
                    LabeledContent("Calorías", value: (food.kcal * f).kcalText)
                    LabeledContent("Proteína", value: "\((food.protein * f).g1) g")
                    LabeledContent("Hidratos", value: "\((food.carbs * f).g1) g")
                    LabeledContent("Grasa", value: "\((food.fat * f).g1) g")
                }
            }
            .navigationTitle("Cantidad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Añadir") { onAdd(grams); dismiss() }.disabled(grams <= 0) }
            }
            .onAppear { grams = food.servingGrams }
        }
        .presentationDetents([.medium, .large])
    }
}

struct CustomFoodView: View {
    var onCreate: ((Food) -> Void)? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kcal = 0.0
    @State private var protein = 0.0
    @State private var carbs = 0.0
    @State private var fat = 0.0
    @State private var serving = 100.0

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre", text: $name)
                Section("Por 100 g") {
                    num("kcal", $kcal); num("Proteína (g)", $protein); num("Hidratos (g)", $carbs); num("Grasa (g)", $fat)
                }
                Section { num("Ración habitual (g)", $serving) }
            }
            .navigationTitle("Alimento propio")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        let f = Food(name: name, kcal: kcal, protein: protein, carbs: carbs, fat: fat, servingGrams: serving, category: "Propios", source: "custom")
                        context.insert(f); try? context.save(); onCreate?(f); dismiss()
                    }.disabled(name.isEmpty)
                }
            }
        }
    }

    private func num(_ label: String, _ v: Binding<Double>) -> some View {
        HStack { Text(label); Spacer(); TextField("0", value: v, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90) }
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] { var seen = Set<Element>(); return filter { seen.insert($0).inserted } }
}

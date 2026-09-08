import SwiftUI
import SwiftData

struct RoutineEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let routine: Routine?

    @State private var name = ""
    @State private var notes = ""
    @State private var colorHex = "#E4572E"
    @State private var items: [Draft] = []
    @State private var showPicker = false

    struct Draft: Identifiable {
        let id = UUID()
        var exercise: Exercise
        var sets: Int
        var reps: Int
        var weight: Double?
        var rest: Int
    }

    private let colors = ["#E4572E", "#3A86FF", "#2EC4B6", "#FFBE0B", "#8338EC", "#FF006E", "#6A994E"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Rutina") {
                    TextField("Nombre (p. ej. Torso A)", text: $name)
                    TextField("Notas", text: $notes, axis: .vertical)
                    HStack {
                        ForEach(colors, id: \.self) { c in
                            Circle().fill(Color(hex: c)).frame(width: 26, height: 26)
                                .overlay(Circle().stroke(.primary, lineWidth: colorHex == c ? 2 : 0))
                                .onTapGesture { colorHex = c }
                        }
                    }
                }
                Section {
                    ForEach($items) { $d in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(d.exercise.displayName).font(.headline)
                            HStack(spacing: 12) {
                                Stepper("\(d.sets) series", value: $d.sets, in: 1...10).font(.caption)
                            }
                            HStack(spacing: 12) {
                                Stepper("\(d.reps) reps", value: $d.reps, in: 1...50).font(.caption)
                            }
                            HStack {
                                Text("Peso").font(.caption)
                                TextField("kg", value: $d.weight, format: .number).keyboardType(.decimalPad).textFieldStyle(.roundedBorder).frame(width: 80)
                                Text("Descanso").font(.caption)
                                Picker("", selection: $d.rest) { ForEach([30, 45, 60, 90, 120, 150, 180], id: \.self) { Text("\($0) s").tag($0) } }.labelsHidden()
                            }
                        }
                    }
                    .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { items.remove(atOffsets: $0) }
                    Button { showPicker = true } label: { Label("Añadir ejercicio", systemImage: "plus.circle.fill") }
                } header: {
                    HStack { Text("Ejercicios (\(items.count))"); Spacer(); EditButton().font(.caption) }
                }
            }
            .navigationTitle(routine == nil ? "Nueva rutina" : "Editar rutina")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || items.isEmpty) }
            }
            .sheet(isPresented: $showPicker) {
                ExercisePickerView { ex in items.append(Draft(exercise: ex, sets: 3, reps: 10, weight: nil, rest: 90)) }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let r = routine, items.isEmpty else { return }
        name = r.name; notes = r.notes; colorHex = r.colorHex
        items = r.sortedItems.compactMap { i in i.exercise.map { Draft(exercise: $0, sets: i.targetSets, reps: i.targetReps, weight: i.targetWeightKg, rest: i.restSeconds) } }
    }

    private func save() {
        let r = routine ?? Routine(name: name)
        if routine == nil { context.insert(r) }
        r.name = name; r.notes = notes; r.colorHex = colorHex
        r.items.forEach { context.delete($0) }
        r.items = []
        for (i, d) in items.enumerated() {
            let re = RoutineExercise(exercise: d.exercise, order: i, targetSets: d.sets, targetReps: d.reps, targetWeightKg: d.weight, restSeconds: d.rest)
            re.routine = r
            context.insert(re)
        }
        try? context.save()
        dismiss()
    }
}

// MARK: - Selector / biblioteca de ejercicios

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (Exercise) -> Void
    var body: some View {
        NavigationStack {
            ExerciseLibraryView(onPick: { ex in onPick(ex); dismiss() })
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
        }
    }
}

struct ExerciseLibraryView: View {
    var onPick: ((Exercise) -> Void)? = nil
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.name) private var all: [Exercise]
    @State private var search = ""
    @State private var muscle: String? = nil
    @State private var equipment: String? = nil
    @State private var onlyTranslated = true
    @State private var showCustom = false

    private var filtered: [Exercise] {
        let q = search.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return all.filter { e in
            if onlyTranslated && e.nameEs == nil && !e.isCustom && q.isEmpty { return false }
            if let m = muscle, !e.primaryMuscles.contains(m) { return false }
            if let eq = equipment, e.equipment != eq { return false }
            if q.isEmpty { return true }
            let hay = (e.displayName + " " + e.name + " " + e.primaryMuscles.map(Vocab.muscle).joined(separator: " "))
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return hay.contains(q)
        }
        .sorted { ($0.isFavorite ? 0 : 1, $0.nameEs == nil ? 1 : 0, $0.displayName) < ($1.isFavorite ? 0 : 1, $1.nameEs == nil ? 1 : 0, $1.displayName) }
    }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        chip("Todos", selected: muscle == nil) { muscle = nil }
                        ForEach(Vocab.muscleNames.keys.sorted(), id: \.self) { m in
                            chip(Vocab.muscle(m), selected: muscle == m) { muscle = muscle == m ? nil : m }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                Picker("Equipo", selection: $equipment) {
                    Text("Cualquiera").tag(String?.none)
                    ForEach(Vocab.equipmentNames.keys.sorted(), id: \.self) { Text(Vocab.equipment($0)).tag(String?.some($0)) }
                }
                Toggle("Solo los traducidos al español", isOn: $onlyTranslated)
            }
            Section("\(filtered.count) ejercicios") {
                ForEach(filtered) { e in
                    if let onPick {
                        Button { onPick(e) } label: { ExerciseRow(exercise: e) }.tint(.primary)
                    } else {
                        NavigationLink { ExerciseDetailView(exercise: e) } label: { ExerciseRow(exercise: e) }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Buscar ejercicio o músculo")
        .navigationTitle("Ejercicios")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { showCustom = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showCustom) { CustomExerciseView() }
    }

    private func chip(_ t: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 6)
                .background(selected ? Color.roburAccent : Color(.tertiarySystemFill), in: Capsule())
                .foregroundStyle(selected ? .white : .primary)
        }.buttonStyle(.plain)
    }
}

struct ExerciseRow: View {
    let exercise: Exercise
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if exercise.isFavorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                    Text(exercise.displayName).font(.body)
                }
                Text("\(exercise.primaryMuscles.map(Vocab.muscle).joined(separator: ", ")) · \(Vocab.equipment(exercise.equipment))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if exercise.isCardio { Image(systemName: "heart.fill").foregroundStyle(.pink).font(.caption) }
        }
    }
}

struct ExerciseDetailView: View {
    @Bindable var exercise: Exercise
    var body: some View {
        List {
            if !exercise.imageURLs.isEmpty {
                Section {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(exercise.imageURLs, id: \.self) { url in
                                AsyncImage(url: url) { img in img.resizable().scaledToFit() } placeholder: { ProgressView() }
                                    .frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets())
                }
            }
            Section {
                LabeledContent("Músculos", value: exercise.primaryMuscles.map(Vocab.muscle).joined(separator: ", "))
                if !exercise.secondaryMuscles.isEmpty { LabeledContent("Secundarios", value: exercise.secondaryMuscles.map(Vocab.muscle).joined(separator: ", ")) }
                LabeledContent("Equipo", value: Vocab.equipment(exercise.equipment))
                LabeledContent("Tipo", value: Vocab.category(exercise.category))
                LabeledContent("Nivel", value: Vocab.level(exercise.level))
                LabeledContent("MET", value: exercise.met.g1)
                Toggle("Favorito", isOn: $exercise.isFavorite)
            }
            if !exercise.instructions.isEmpty {
                Section("Instrucciones (inglés)") {
                    ForEach(Array(exercise.instructions.enumerated()), id: \.offset) { i, t in
                        Text("\(i + 1). \(t)").font(.subheadline)
                    }
                }
            }
            if exercise.nameEs != exercise.name, exercise.nameEs != nil {
                Section { Text(exercise.name).foregroundStyle(.secondary) } header: { Text("Nombre original") }
            }
        }
        .navigationTitle(exercise.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CustomExerciseView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var muscle = "chest"
    @State private var equipment = "machine"
    @State private var isCardio = false
    @State private var met = 5.0
    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre", text: $name)
                Picker("Músculo principal", selection: $muscle) { ForEach(Vocab.muscleNames.keys.sorted(), id: \.self) { Text(Vocab.muscle($0)).tag($0) } }
                Picker("Equipo", selection: $equipment) { ForEach(Vocab.equipmentNames.keys.sorted(), id: \.self) { Text(Vocab.equipment($0)).tag($0) } }
                Toggle("Es cardio (se registra por tiempo)", isOn: $isCardio)
                Stepper("MET: \(met.g1)", value: $met, in: 1...15, step: 0.5)
                Text("MET orientativo: fuerza 3.5-6, cardio suave 5, correr 8-11.").font(.caption).foregroundStyle(.secondary)
            }
            .navigationTitle("Ejercicio propio")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        let e = Exercise(id: "custom_\(UUID().uuidString)", name: name, nameEs: name, category: isCardio ? "cardio" : "strength",
                                         equipment: equipment, primaryMuscles: [muscle], met: met, isCustom: true)
                        context.insert(e); try? context.save(); dismiss()
                    }.disabled(name.isEmpty)
                }
            }
        }
    }
}

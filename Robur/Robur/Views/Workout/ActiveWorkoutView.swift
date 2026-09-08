import SwiftUI
import SwiftData

struct ActiveWorkoutView: View {
    @Bindable var session: WorkoutSession
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitService.self) private var health

    @State private var showPicker = false
    @State private var showFinish = false
    @State private var restRemaining: Int = 0
    @State private var restTotal: Int = 90
    @State private var timer: Timer?
    @State private var now = Date.now
    @State private var healthError: String?

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            List {
                ForEach(session.exercisesInOrder, id: \.id) { ex in
                    Section {
                        ForEach(sets(for: ex)) { set in
                            SetRow(set: set, isCardio: ex.isCardio) { completed(set) }
                        }
                        .onDelete { idx in
                            let s = sets(for: ex)
                            idx.map { s[$0] }.forEach { context.delete($0) }
                            renumber(ex)
                        }
                        Button { addSet(to: ex) } label: { Label("Añadir serie", systemImage: "plus") }.font(.subheadline)
                    } header: {
                        HStack {
                            Text(ex.displayName)
                            Spacer()
                            Text(lastTimeText(ex)).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                Section {
                    Button { showPicker = true } label: { Label("Añadir ejercicio", systemImage: "plus.circle.fill") }
                }
                Section("Notas") {
                    TextField("Cómo ha ido…", text: $session.notes, axis: .vertical)
                }
            }
            .navigationTitle(session.routineName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Label(session.durationSeconds.mmss, systemImage: "timer").monospacedDigit().font(.subheadline)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Terminar") { showFinish = true }.bold()
                }
            }
            .safeAreaInset(edge: .bottom) { restBar }
            .onReceive(clock) { now = $0 }
            .sheet(isPresented: $showPicker) { ExercisePickerView { addExercise($0) } }
            .confirmationDialog("¿Terminar el entreno?", isPresented: $showFinish, titleVisibility: .visible) {
                Button("Guardar entreno") { finish() }
                Button("Descartar entreno", role: .destructive) { discard() }
            } message: {
                Text("\(session.completedSets.count) series · \(session.totalVolumeKg.g0) kg · ~\(session.estimatedCalories.g0) kcal")
            }
            .alert("Salud", isPresented: .constant(healthError != nil)) {
                Button("OK") { healthError = nil; dismiss() }
            } message: { Text(healthError ?? "") }
        }
        .interactiveDismissDisabled()
    }

    // MARK: Descanso

    @ViewBuilder private var restBar: some View {
        if restRemaining > 0 {
            HStack {
                Image(systemName: "hourglass")
                Text("Descanso \(TimeInterval(restRemaining).mmss)").monospacedDigit().bold()
                Spacer()
                Button("+30 s") { restRemaining += 30; restTotal += 30 }.buttonStyle(.bordered).controlSize(.small)
                Button("Saltar") { stopRest() }.buttonStyle(.bordered).controlSize(.small)
            }
            .padding()
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                GeometryReader { g in
                    Rectangle().fill(Color.roburAccent).frame(width: g.size.width * (1 - Double(restRemaining) / Double(max(restTotal, 1))), height: 3)
                }.frame(height: 3)
            }
        }
    }

    private func startRest(_ seconds: Int) {
        timer?.invalidate()
        restTotal = seconds; restRemaining = seconds
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if restRemaining > 0 { restRemaining -= 1 }
            if restRemaining == 0 { stopRest(); UINotificationFeedbackGenerator().notificationOccurred(.success) }
        }
    }

    private func stopRest() { timer?.invalidate(); timer = nil; restRemaining = 0 }

    // MARK: Series

    private func sets(for ex: Exercise) -> [WorkoutSet] {
        session.sets.filter { $0.exercise?.id == ex.id }.sorted { $0.setIndex < $1.setIndex }
    }

    private func completed(_ set: WorkoutSet) {
        set.completed.toggle()
        set.completedAt = set.completed ? .now : nil
        if set.completed {
            let rest = restSeconds(for: set.exercise)
            if rest > 0 && !(set.exercise?.isCardio ?? false) { startRest(rest) }
        }
        try? context.save()
    }

    private func restSeconds(for ex: Exercise?) -> Int {
        guard let ex else { return 90 }
        // Si viene de una rutina, usa su descanso; si no, 90 s.
        return ex.routineUses.first(where: { $0.routine?.name == session.routineName })?.restSeconds ?? 90
    }

    private func addSet(to ex: Exercise) {
        let existing = sets(for: ex)
        let last = existing.last
        let s = WorkoutSet(exercise: ex, order: (session.sets.map(\.order).max() ?? -1) + 1, setIndex: existing.count + 1,
                           reps: last?.reps ?? 10, weightKg: last?.weightKg, durationSeconds: last?.durationSeconds)
        s.session = session
        context.insert(s)
        try? context.save()
    }

    private func addExercise(_ ex: Exercise) {
        if sets(for: ex).isEmpty {
            let lastW = ex.sets.filter { $0.completed }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }.first?.weightKg
            for i in 1...3 {
                let s = WorkoutSet(exercise: ex, order: (session.sets.map(\.order).max() ?? -1) + 1, setIndex: i, reps: ex.isCardio ? 1 : 10,
                                   weightKg: lastW, durationSeconds: ex.isCardio ? 600 : nil)
                s.session = session
                context.insert(s)
            }
        } else { addSet(to: ex) }
        try? context.save()
    }

    private func renumber(_ ex: Exercise) {
        for (i, s) in sets(for: ex).enumerated() { s.setIndex = i + 1 }
    }

    private func lastTimeText(_ ex: Exercise) -> String {
        let prev = ex.sets.filter { $0.completed && $0.session?.id != session.id }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        guard let p = prev.first else { return "Primera vez" }
        if let w = p.weightKg { return "Última vez: \(p.reps)×\(w.g1) kg" }
        return "Última vez: \(p.reps) reps"
    }

    // MARK: Fin

    private func finish() {
        stopRest()
        session.sets.filter { !$0.completed }.forEach { context.delete($0) }
        session.endedAt = .now
        try? context.save()
        if AppSettings.healthKitEnabled && AppSettings.autoSaveWorkouts && !session.completedSets.isEmpty {
            Task {
                do { try await health.saveWorkout(session: session); session.healthKitSaved = true; try? context.save(); dismiss() }
                catch { healthError = "El entreno se ha guardado en Robur pero no en Salud: \(error.localizedDescription)" }
            }
        } else { dismiss() }
    }

    private func discard() {
        stopRest()
        context.delete(session)
        try? context.save()
        dismiss()
    }
}

struct SetRow: View {
    @Bindable var set: WorkoutSet
    let isCardio: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(set.setIndex)").font(.caption.bold()).frame(width: 22, height: 22).background(Color(.tertiarySystemFill), in: Circle())
            if isCardio {
                field("min", value: Binding(get: { Double(set.durationSeconds ?? 0) / 60 }, set: { set.durationSeconds = Int($0 * 60) }))
            } else {
                field("kg", value: Binding(get: { set.weightKg ?? 0 }, set: { set.weightKg = $0 > 0 ? $0 : nil }))
                Text("×").foregroundStyle(.secondary)
                intField("reps", value: $set.reps)
            }
            Spacer()
            Button(action: onToggle) {
                Image(systemName: set.completed ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(set.completed ? .green : .secondary)
            }.buttonStyle(.plain)
        }
        .listRowBackground(set.completed ? Color.green.opacity(0.08) : nil)
    }

    private func field(_ unit: String, value: Binding<Double>) -> some View {
        HStack(spacing: 2) {
            TextField("0", value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad).multilineTextAlignment(.center).frame(width: 60)
                .padding(6).background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }
    }
    private func intField(_ unit: String, value: Binding<Int>) -> some View {
        HStack(spacing: 2) {
            TextField("0", value: value, format: .number)
                .keyboardType(.numberPad).multilineTextAlignment(.center).frame(width: 50)
                .padding(6).background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }
    }
}

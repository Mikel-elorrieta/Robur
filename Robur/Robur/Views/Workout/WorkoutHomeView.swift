import SwiftUI
import SwiftData

struct WorkoutHomeView: View {
    let profile: UserProfile
    @Environment(\.modelContext) private var context
    @Query(sort: \Routine.createdAt) private var routines: [Routine]
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt == nil }) private var activeSessions: [WorkoutSession]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    @State private var editingRoutine: Routine?
    @State private var showNewRoutine = false
    @State private var activeSession: WorkoutSession?

    var body: some View {
        NavigationStack {
            List {
                if let s = activeSessions.first {
                    Section {
                        Button { activeSession = s } label: {
                            HStack {
                                Image(systemName: "record.circle").foregroundStyle(.red).symbolEffect(.pulse)
                                VStack(alignment: .leading) {
                                    Text("Entreno en curso: \(s.routineName)").bold()
                                    Text("Empezado \(s.startedAt.formatted(date: .omitted, time: .shortened)) · \(s.completedSets.count) series").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                        }.tint(.primary)
                    }
                }

                Section("Rutinas") {
                    if routines.isEmpty {
                        EmptyHint(icon: "list.bullet.clipboard", text: "Crea tu primera rutina con el + de arriba.\nO empieza un entreno libre.")
                    }
                    ForEach(routines) { r in
                        RoutineRow(routine: r, onStart: { start(routine: r) }, onEdit: { editingRoutine = r })
                    }
                    .onDelete { idx in idx.map { routines[$0] }.forEach { context.delete($0) } }
                }

                Section {
                    Button { start(routine: nil) } label: { Label("Entreno libre (sin rutina)", systemImage: "bolt.fill") }
                    NavigationLink { SessionHistoryView() } label: { Label("Historial (\(sessions.filter { $0.endedAt != nil }.count))", systemImage: "clock.arrow.circlepath") }
                    NavigationLink { ExerciseLibraryView() } label: { Label("Biblioteca de ejercicios", systemImage: "books.vertical.fill") }
                }
            }
            .navigationTitle("Entreno")
            .toolbar {
                Button { showNewRoutine = true } label: { Image(systemName: "plus") }
            }
            .sheet(isPresented: $showNewRoutine) { RoutineEditorView(routine: nil) }
            .sheet(item: $editingRoutine) { RoutineEditorView(routine: $0) }
            .fullScreenCover(item: $activeSession) { ActiveWorkoutView(session: $0) }
        }
    }

    private func start(routine: Routine?) {
        if let s = activeSessions.first { activeSession = s; return }
        let weight = LatestWeight.kg(context: context)
        let s = WorkoutSession(routineName: routine?.name ?? "Entreno libre", bodyWeightKg: weight)
        context.insert(s)
        var order = 0
        if let r = routine {
            for item in r.sortedItems {
                guard let ex = item.exercise else { continue }
                let last = lastWeight(for: ex)
                for i in 0..<item.targetSets {
                    let set = WorkoutSet(exercise: ex, order: order, setIndex: i + 1, reps: item.targetReps, weightKg: item.targetWeightKg ?? last)
                    set.session = s
                    context.insert(set)
                    order += 1
                }
            }
        }
        try? context.save()
        activeSession = s
    }

    /// Último peso usado con ese ejercicio (para precargar).
    private func lastWeight(for ex: Exercise) -> Double? {
        ex.sets.filter { $0.completed && $0.weightKg != nil }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }.first?.weightKg
    }
}

struct RoutineRow: View {
    let routine: Routine
    let onStart: () -> Void
    let onEdit: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4).fill(Color(hex: routine.colorHex)).frame(width: 6, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(routine.name).font(.headline)
                Text(routine.sortedItems.compactMap { $0.exercise?.displayName }.prefix(4).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text("\(routine.items.count) ejercicios · \(routine.items.reduce(0) { $0 + $1.targetSets }) series").font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            Button(action: onStart) { Image(systemName: "play.fill").padding(8).background(.roburAccent, in: Circle()).foregroundStyle(.white) }.buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
    }
}

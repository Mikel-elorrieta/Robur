import SwiftUI
import SwiftData
import Charts

struct SessionHistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt != nil }, sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    struct WeekGroup: Identifiable {
        let start: Date; let sessions: [WorkoutSession]
        var id: Date { start }
        var volume: Double { sessions.reduce(0) { $0 + $1.totalVolumeKg } }
    }

    private var byWeek: [WeekGroup] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: sessions) { cal.dateInterval(of: .weekOfYear, for: $0.startedAt)?.start ?? $0.startedAt.dayStart }
        return groups.map { WeekGroup(start: $0.key, sessions: $0.value) }.sorted { $0.start > $1.start }
    }

    var body: some View {
        List {
            if sessions.isEmpty { EmptyHint(icon: "clock", text: "Aún no hay entrenos guardados.") }
            if sessions.count >= 2 {
                Section("Volumen semanal (kg)") {
                    Chart(Array(byWeek.prefix(8).reversed())) { w in
                        BarMark(x: .value("Semana", w.start, unit: .weekOfYear), y: .value("kg", w.volume))
                            .foregroundStyle(Color.roburAccent)
                    }
                    .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear)) { _ in AxisValueLabel(format: .dateTime.day().month(), centered: true) } }
                    .frame(height: 140)
                }
            }
            ForEach(byWeek) { w in
                Section("Semana del \(w.start.formatted(.dateTime.day().month()))  ·  \(w.sessions.count) entrenos") {
                    ForEach(w.sessions) { s in
                        NavigationLink { SessionDetailView(session: s) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.routineName).font(.headline)
                                    Text("\(s.startedAt.shortDay) · \(s.durationSeconds.hhmm) · \(s.completedSets.count) series").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("\(s.totalVolumeKg.g0) kg").font(.subheadline.bold())
                                    Text(s.estimatedCalories.kcalText).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { idx in idx.map { w.sessions[$0] }.forEach { context.delete($0) } }
                }
            }
        }
        .navigationTitle("Historial")
    }
}

struct SessionDetailView: View {
    @Bindable var session: WorkoutSession
    @Environment(HealthKitService.self) private var health
    @State private var msg: String?

    var body: some View {
        List {
            Section {
                LabeledContent("Fecha", value: session.startedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Duración", value: session.durationSeconds.hhmm)
                LabeledContent("Series", value: "\(session.completedSets.count)")
                LabeledContent("Volumen", value: "\(session.totalVolumeKg.g0) kg")
                LabeledContent("kcal estimadas", value: session.estimatedCalories.g0)
                LabeledContent("Peso corporal usado", value: "\(session.bodyWeightKg.g1) kg")
                HStack {
                    Text("Apple Salud")
                    Spacer()
                    if session.healthKitSaved { Label("Guardado", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.subheadline) }
                    else if AppSettings.healthKitEnabled {
                        Button("Guardar ahora") {
                            Task {
                                do { try await health.saveWorkout(session: session); session.healthKitSaved = true; msg = "Guardado en Salud" }
                                catch { msg = error.localizedDescription }
                            }
                        }.font(.subheadline)
                    } else { Text("No activado").foregroundStyle(.secondary).font(.subheadline) }
                }
            }
            ForEach(session.exercisesInOrder, id: \.id) { ex in
                Section(ex.displayName) {
                    ForEach(session.completedSets.filter { $0.exercise?.id == ex.id }.sorted { $0.setIndex < $1.setIndex }) { s in
                        HStack {
                            Text("Serie \(s.setIndex)").foregroundStyle(.secondary)
                            Spacer()
                            if ex.isCardio, let d = s.durationSeconds { Text("\(d / 60) min") }
                            else { Text("\(s.reps) × \(s.weightKg?.g1 ?? "—") kg").monospacedDigit() }
                        }
                    }
                }
            }
            if !session.notes.isEmpty { Section("Notas") { Text(session.notes) } }
        }
        .navigationTitle(session.routineName)
        .navigationBarTitleDisplayMode(.inline)
        .alert(msg ?? "", isPresented: .constant(msg != nil)) { Button("OK") { msg = nil } }
    }
}

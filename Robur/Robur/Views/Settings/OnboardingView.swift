import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var heightCm: Double = 175
    @State private var weightKg: Double = 75
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -25, to: .now)!
    @State private var sex: Sex = .male
    @State private var activity: ActivityLevel = .moderate
    @State private var goal: Goal = .maintain

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Robur").font(.system(size: 40, weight: .black, design: .rounded)).foregroundStyle(.roburAccent)
                        Text("Entreno, dieta y progreso en un sitio. Rellena esto una vez y calculo tus objetivos.").foregroundStyle(.secondary)
                    }
                }
                Section("Tú") {
                    TextField("Nombre", text: $name)
                    Picker("Sexo", selection: $sex) { ForEach(Sex.allCases) { Text($0.label).tag($0) } }
                    DatePicker("Fecha de nacimiento", selection: $birthDate, displayedComponents: .date)
                    Stepper("Altura: \(heightCm.g0) cm", value: $heightCm, in: 120...230)
                    HStack {
                        Text("Peso actual")
                        Spacer()
                        TextField("kg", value: $weightKg, format: .number.precision(.fractionLength(1))).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                        Text("kg").foregroundStyle(.secondary)
                    }
                }
                Section("Actividad y objetivo") {
                    Picker("Actividad", selection: $activity) { ForEach(ActivityLevel.allCases) { Text($0.label).tag($0) } }
                    Picker("Objetivo", selection: $goal) { ForEach(Goal.allCases) { Text($0.label).tag($0) } }
                }
                Section {
                    Button { save() } label: { Text("Empezar").frame(maxWidth: .infinity).bold() }
                        .buttonStyle(.borderedProminent)
                        .disabled(weightKg < 30)
                }
            }
            .navigationTitle("Bienvenido")
        }
    }

    private func save() {
        let p = UserProfile(name: name, heightCm: heightCm, birthDate: birthDate, sex: sex, activity: activity, goal: goal)
        context.insert(p)
        context.insert(BodyMeasurement(weightKg: weightKg, notes: "Peso inicial"))
        try? context.save()
        Reminders.scheduleWeighIn(afterDays: p.weighInReminderDays, from: .now)
    }
}

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var context
    @Environment(HealthKitService.self) private var health
    @Query(sort: \BodyMeasurement.date, order: .reverse) private var measurements: [BodyMeasurement]

    @AppStorage(SettingsKey.healthKitEnabled) private var healthKitEnabled = false
    @AppStorage(SettingsKey.autoSaveWorkouts) private var autoSaveWorkouts = true
    @AppStorage(SettingsKey.autoSaveWeight) private var autoSaveWeight = true
    @AppStorage(SettingsKey.claudeModel) private var model = SettingsKey.defaultModel
    @State private var apiKey = ""
    @State private var keySaved = false
    @State private var showReset = false

    private var weight: Double { measurements.first?.weightKg ?? 75 }
    private var targets: CalorieCalculator.MacroTargets { CalorieCalculator.macroTargets(profile: profile, weightKg: weight) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Perfil") {
                    TextField("Nombre", text: $profile.name)
                    Picker("Sexo", selection: $profile.sex) { ForEach(Sex.allCases) { Text($0.label).tag($0) } }
                    DatePicker("Nacimiento", selection: $profile.birthDate, displayedComponents: .date)
                    Stepper("Altura: \(profile.heightCm.g0) cm", value: $profile.heightCm, in: 120...230)
                    Picker("Actividad", selection: $profile.activity) { ForEach(ActivityLevel.allCases) { Text($0.label).tag($0) } }
                    Picker("Objetivo", selection: $profile.goal) { ForEach(Goal.allCases) { Text($0.label).tag($0) } }
                    Stepper("Proteína: \(profile.proteinPerKg.g1) g/kg", value: $profile.proteinPerKg, in: 1.0...3.0, step: 0.1)
                    Stepper("Pasos objetivo: \(profile.stepGoal.formatted())", value: $profile.stepGoal, in: 2000...30000, step: 500)
                    Stepper("Recordatorio de pesaje cada \(profile.weighInReminderDays) días", value: $profile.weighInReminderDays, in: 1...60)
                        .onChange(of: profile.weighInReminderDays) { _, d in Reminders.scheduleWeighIn(afterDays: d, from: measurements.first?.date ?? .now) }
                }
                Section {
                    LabeledContent("BMR (Mifflin-St Jeor)", value: CalorieCalculator.bmr(profile: profile, weightKg: weight).kcalText)
                    LabeledContent("TDEE", value: CalorieCalculator.tdee(profile: profile, weightKg: weight).kcalText)
                    LabeledContent("Objetivo diario", value: targets.kcal.kcalText)
                    LabeledContent("Macros", value: "P \(targets.protein.g0) · H \(targets.carbs.g0) · G \(targets.fat.g0) g")
                } header: { Text("Objetivos calculados") } footer: { Text("Con tu último peso registrado (\(weight.g1) kg).") }

                Section("Apple Salud") {
                    Toggle("Sincronizar con Salud", isOn: $healthKitEnabled)
                        .onChange(of: healthKitEnabled) { _, on in if on { Task { await health.requestAuthorization() } } }
                    if healthKitEnabled {
                        Toggle("Guardar entrenos en Salud", isOn: $autoSaveWorkouts)
                        Toggle("Guardar peso en Salud", isOn: $autoSaveWeight)
                        Button("Importar último peso de Salud") {
                            Task {
                                if let (kg, d) = await health.latestBodyMass() {
                                    context.insert(BodyMeasurement(date: d, weightKg: kg, notes: "Importado de Salud")); try? context.save()
                                }
                            }
                        }
                        if let r = health.lastRefresh { Text("Última lectura: \(r.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                    }
                }

                Section {
                    SecureField("API key (sk-ant-…)", text: $apiKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Modelo", text: $model).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button(keySaved ? "Guardada ✓" : "Guardar API key") {
                        Keychain.set(apiKey, account: Keychain.apiKeyAccount); keySaved = true
                    }.disabled(apiKey.isEmpty)
                } header: { Text("Cámara IA (Anthropic)") } footer: {
                    Text("La key se guarda en el Llavero del iPhone y solo se usa para analizar fotos de comida. Coste aproximado: <1 céntimo por foto.")
                }

                Section {
                    Button("Borrar todos los datos", role: .destructive) { showReset = true }
                } footer: { Text("Robur v1.0 · Ejercicios: free-exercise-db (dominio público) · Productos: Open Food Facts (ODbL)") }
            }
            .navigationTitle("Ajustes")
            .onAppear { apiKey = Keychain.get(account: Keychain.apiKeyAccount); keySaved = !apiKey.isEmpty }
            .onChange(of: apiKey) { _, _ in keySaved = false }
            .confirmationDialog("¿Borrar todo?", isPresented: $showReset, titleVisibility: .visible) {
                Button("Borrar entrenos, dieta y registros", role: .destructive) { reset() }
            } message: { Text("Se mantienen la biblioteca de ejercicios y alimentos.") }
        }
    }

    private func reset() {
        try? context.delete(model: WorkoutSession.self)
        try? context.delete(model: MealEntry.self)
        try? context.delete(model: PlannedMeal.self)
        try? context.delete(model: Routine.self)
        measurements.forEach { $0.photoFilenames.forEach(PhotoStore.delete) }
        try? context.delete(model: BodyMeasurement.self)
        try? context.save()
    }
}

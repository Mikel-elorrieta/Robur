import Foundation
import SwiftData

// MARK: - Ejercicios y rutinas

@Model
final class Exercise {
    @Attribute(.unique) var id: String
    var name: String
    var nameEs: String?
    var category: String        // strength, cardio, stretching...
    var equipment: String
    var level: String
    var mechanic: String?
    var force: String?
    var primaryMuscles: [String]
    var secondaryMuscles: [String]
    var instructions: [String]
    var images: [String]        // rutas relativas a free-exercise-db
    var met: Double
    var isCustom: Bool
    var isFavorite: Bool

    @Relationship(deleteRule: .cascade, inverse: \RoutineExercise.exercise) var routineUses: [RoutineExercise] = []
    @Relationship(deleteRule: .nullify, inverse: \WorkoutSet.exercise) var sets: [WorkoutSet] = []

    init(id: String, name: String, nameEs: String? = nil, category: String = "strength", equipment: String = "other",
         level: String = "beginner", mechanic: String? = nil, force: String? = nil,
         primaryMuscles: [String] = [], secondaryMuscles: [String] = [], instructions: [String] = [],
         images: [String] = [], met: Double = 5.0, isCustom: Bool = false, isFavorite: Bool = false) {
        self.id = id; self.name = name; self.nameEs = nameEs; self.category = category; self.equipment = equipment
        self.level = level; self.mechanic = mechanic; self.force = force; self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles; self.instructions = instructions; self.images = images
        self.met = met; self.isCustom = isCustom; self.isFavorite = isFavorite
    }

    /// Nombre a mostrar: español si existe, si no el original.
    var displayName: String { nameEs ?? name }
    var isCardio: Bool { category == "cardio" }

    static let imageBase = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/"
    var imageURLs: [URL] { images.compactMap { URL(string: Exercise.imageBase + $0) } }
}

@Model
final class Routine {
    var name: String
    var notes: String
    var createdAt: Date
    var colorHex: String
    @Relationship(deleteRule: .cascade, inverse: \RoutineExercise.routine) var items: [RoutineExercise] = []

    init(name: String, notes: String = "", colorHex: String = "#E4572E") {
        self.name = name; self.notes = notes; self.createdAt = .now; self.colorHex = colorHex
    }

    var sortedItems: [RoutineExercise] { items.sorted { $0.order < $1.order } }
}

@Model
final class RoutineExercise {
    var order: Int
    var targetSets: Int
    var targetReps: Int
    var targetWeightKg: Double?
    var restSeconds: Int
    var exercise: Exercise?
    var routine: Routine?

    init(exercise: Exercise, order: Int, targetSets: Int = 3, targetReps: Int = 10, targetWeightKg: Double? = nil, restSeconds: Int = 90) {
        self.exercise = exercise; self.order = order; self.targetSets = targetSets; self.targetReps = targetReps
        self.targetWeightKg = targetWeightKg; self.restSeconds = restSeconds
    }
}

@Model
final class WorkoutSession {
    var startedAt: Date
    var endedAt: Date?
    var routineName: String
    var notes: String
    var bodyWeightKg: Double     // peso usado para el cálculo de kcal
    var healthKitSaved: Bool
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.session) var sets: [WorkoutSet] = []

    init(routineName: String, bodyWeightKg: Double) {
        self.startedAt = .now; self.routineName = routineName; self.notes = ""; self.bodyWeightKg = bodyWeightKg; self.healthKitSaved = false
    }

    var isActive: Bool { endedAt == nil }
    var durationSeconds: TimeInterval { (endedAt ?? .now).timeIntervalSince(startedAt) }
    var completedSets: [WorkoutSet] { sets.filter(\.completed) }
    var totalVolumeKg: Double { completedSets.reduce(0) { $0 + Double($1.reps) * ($1.weightKg ?? 0) } }

    /// kcal estimadas con MET ponderado por el tiempo de sesión.
    var estimatedCalories: Double {
        CalorieCalculator.sessionCalories(session: self)
    }

    /// Ejercicios en orden de aparición.
    var exercisesInOrder: [Exercise] {
        var seen = Set<String>(); var out: [Exercise] = []
        for s in sets.sorted(by: { $0.order < $1.order }) {
            if let e = s.exercise, !seen.contains(e.id) { seen.insert(e.id); out.append(e) }
        }
        return out
    }
}

@Model
final class WorkoutSet {
    var order: Int
    var setIndex: Int
    var reps: Int
    var weightKg: Double?
    var durationSeconds: Int?    // para cardio
    var completed: Bool
    var completedAt: Date?
    var exercise: Exercise?
    var session: WorkoutSession?

    init(exercise: Exercise, order: Int, setIndex: Int, reps: Int, weightKg: Double?, durationSeconds: Int? = nil) {
        self.exercise = exercise; self.order = order; self.setIndex = setIndex; self.reps = reps
        self.weightKg = weightKg; self.durationSeconds = durationSeconds; self.completed = false
    }
}

// MARK: - Dieta

enum MealType: String, Codable, CaseIterable, Identifiable {
    case desayuno, almuerzo, comida, merienda, cena
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .desayuno: return "sunrise.fill"
        case .almuerzo: return "cup.and.saucer.fill"
        case .comida: return "fork.knife"
        case .merienda: return "leaf.fill"
        case .cena: return "moon.stars.fill"
        }
    }
    static var main: [MealType] { [.desayuno, .comida, .cena] }
}

@Model
final class Food {
    @Attribute(.unique) var id: String
    var name: String
    var brand: String?
    var kcal: Double        // por 100 g
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double
    var servingGrams: Double
    var category: String
    var source: String      // seed | off | custom | ai
    var barcode: String?
    var isFavorite: Bool
    var usageCount: Int

    init(id: String = UUID().uuidString, name: String, brand: String? = nil, kcal: Double, protein: Double, carbs: Double, fat: Double,
         fiber: Double = 0, servingGrams: Double = 100, category: String = "Otros", source: String = "custom", barcode: String? = nil) {
        self.id = id; self.name = name; self.brand = brand; self.kcal = kcal; self.protein = protein; self.carbs = carbs
        self.fat = fat; self.fiber = fiber; self.servingGrams = servingGrams; self.category = category; self.source = source
        self.barcode = barcode; self.isFavorite = false; self.usageCount = 0
    }

    var displayName: String { brand.map { "\(name) (\($0))" } ?? name }
}

/// Una entrada del diario: alimento + gramos, con macros congelados (por si el alimento cambia o viene de la IA).
@Model
final class MealEntry {
    var date: Date          // día (normalizado a 00:00)
    var mealTypeRaw: String
    var name: String
    var grams: Double
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var source: String      // manual | off | ai | plan
    var foodId: String?
    var photoFilename: String?
    var createdAt: Date

    init(date: Date, mealType: MealType, name: String, grams: Double, kcal: Double, protein: Double, carbs: Double, fat: Double,
         source: String = "manual", foodId: String? = nil, photoFilename: String? = nil) {
        self.date = Calendar.current.startOfDay(for: date); self.mealTypeRaw = mealType.rawValue; self.name = name; self.grams = grams
        self.kcal = kcal; self.protein = protein; self.carbs = carbs; self.fat = fat; self.source = source
        self.foodId = foodId; self.photoFilename = photoFilename; self.createdAt = .now
    }

    convenience init(date: Date, mealType: MealType, food: Food, grams: Double, source: String = "manual") {
        let f = grams / 100
        self.init(date: date, mealType: mealType, name: food.displayName, grams: grams, kcal: food.kcal * f,
                  protein: food.protein * f, carbs: food.carbs * f, fat: food.fat * f, source: source, foodId: food.id)
    }

    var mealType: MealType { MealType(rawValue: mealTypeRaw) ?? .comida }
}

/// Plantilla de menú semanal: lo que "toca" comer cada día. Se aplica al diario con un toque.
@Model
final class PlannedMeal {
    var weekday: Int        // 1 = domingo ... 7 = sábado (Calendar)
    var mealTypeRaw: String
    var name: String
    var grams: Double
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var foodId: String?

    init(weekday: Int, mealType: MealType, food: Food, grams: Double) {
        let f = grams / 100
        self.weekday = weekday; self.mealTypeRaw = mealType.rawValue; self.name = food.displayName; self.grams = grams
        self.kcal = food.kcal * f; self.protein = food.protein * f; self.carbs = food.carbs * f; self.fat = food.fat * f; self.foodId = food.id
    }

    var mealType: MealType { MealType(rawValue: mealTypeRaw) ?? .comida }
}

// MARK: - Progreso corporal

@Model
final class BodyMeasurement {
    var date: Date
    var weightKg: Double
    var bodyFatPct: Double?
    var waistCm: Double?
    var notes: String
    var photoFilenames: [String]

    init(date: Date = .now, weightKg: Double, bodyFatPct: Double? = nil, waistCm: Double? = nil, notes: String = "", photoFilenames: [String] = []) {
        self.date = date; self.weightKg = weightKg; self.bodyFatPct = bodyFatPct; self.waistCm = waistCm; self.notes = notes; self.photoFilenames = photoFilenames
    }
}

// MARK: - Perfil

enum Sex: String, Codable, CaseIterable, Identifiable {
    case male, female
    var id: String { rawValue }
    var label: String { self == .male ? "Hombre" : "Mujer" }
}

enum ActivityLevel: Double, Codable, CaseIterable, Identifiable {
    case sedentary = 1.2, light = 1.375, moderate = 1.55, active = 1.725, veryActive = 1.9
    var id: Double { rawValue }
    var label: String {
        switch self {
        case .sedentary: "Sedentario"
        case .light: "Ligero (1-3 días/sem)"
        case .moderate: "Moderado (3-5 días/sem)"
        case .active: "Activo (6-7 días/sem)"
        case .veryActive: "Muy activo (2x/día)"
        }
    }
}

enum Goal: String, Codable, CaseIterable, Identifiable {
    case cut, maintain, bulk
    var id: String { rawValue }
    var label: String {
        switch self {
        case .cut: return "Definir"
        case .maintain: return "Mantener"
        case .bulk: return "Volumen"
        }
    }
    var kcalDelta: Double {
        switch self {
        case .cut: return -400
        case .maintain: return 0
        case .bulk: return 300
        }
    }
}

@Model
final class UserProfile {
    var name: String
    var heightCm: Double
    var birthDate: Date
    var sexRaw: String
    var activityRaw: Double
    var goalRaw: String
    var stepGoal: Int
    var proteinPerKg: Double
    var weighInReminderDays: Int
    var createdAt: Date

    init(name: String = "", heightCm: Double = 175, birthDate: Date = Calendar.current.date(byAdding: .year, value: -25, to: .now)!,
         sex: Sex = .male, activity: ActivityLevel = .moderate, goal: Goal = .maintain) {
        self.name = name; self.heightCm = heightCm; self.birthDate = birthDate; self.sexRaw = sex.rawValue
        self.activityRaw = activity.rawValue; self.goalRaw = goal.rawValue; self.stepGoal = 10_000; self.proteinPerKg = 1.8
        self.weighInReminderDays = 14; self.createdAt = .now
    }

    var sex: Sex { get { Sex(rawValue: sexRaw) ?? .male } set { sexRaw = newValue.rawValue } }
    var activity: ActivityLevel { get { ActivityLevel(rawValue: activityRaw) ?? .moderate } set { activityRaw = newValue.rawValue } }
    var goal: Goal { get { Goal(rawValue: goalRaw) ?? .maintain } set { goalRaw = newValue.rawValue } }
    var age: Int { Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? 25 }
}

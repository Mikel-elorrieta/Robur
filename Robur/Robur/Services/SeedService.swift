import Foundation
import SwiftData

/// Carga los JSON embebidos (ejercicios, alimentos) en SwiftData la primera vez.
enum SeedService {

    struct ExerciseDTO: Decodable {
        let id: String; let name: String; let nameEs: String?; let category: String; let equipment: String
        let level: String; let mechanic: String?; let force: String?
        let primaryMuscles: [String]; let secondaryMuscles: [String]; let instructions: [String]; let images: [String]; let met: Double
    }
    struct FoodDTO: Decodable {
        let id: String; let name: String; let kcal: Double; let protein: Double; let carbs: Double; let fat: Double
        let fiber: Double; let servingGrams: Double; let category: String; let source: String
    }
    struct METDTO: Decodable { let name: String; let met: Double }

    private static let seedVersionKey = "seedVersion"
    private static let currentSeedVersion = 1

    static func seedIfNeeded(context: ModelContext) {
        let done = UserDefaults.standard.integer(forKey: seedVersionKey)
        guard done < currentSeedVersion else { return }
        do {
            try seedExercises(context: context)
            try seedFoods(context: context)
            try context.save()
            UserDefaults.standard.set(currentSeedVersion, forKey: seedVersionKey)
        } catch {
            print("Seed error: \(error)")
        }
    }

    private static func load<T: Decodable>(_ name: String, as: T.Type) throws -> T {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            throw NSError(domain: "Seed", code: 1, userInfo: [NSLocalizedDescriptionKey: "No se encuentra \(name).json"])
        }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    private static func seedExercises(context: ModelContext) throws {
        let existing = try context.fetchCount(FetchDescriptor<Exercise>())
        guard existing == 0 else { return }
        let dtos = try load("exercises", as: [ExerciseDTO].self)
        for d in dtos {
            context.insert(Exercise(id: d.id, name: d.name, nameEs: d.nameEs, category: d.category, equipment: d.equipment,
                                    level: d.level, mechanic: d.mechanic, force: d.force, primaryMuscles: d.primaryMuscles,
                                    secondaryMuscles: d.secondaryMuscles, instructions: d.instructions, images: d.images, met: d.met))
        }
    }

    private static func seedFoods(context: ModelContext) throws {
        let existing = try context.fetchCount(FetchDescriptor<Food>())
        guard existing == 0 else { return }
        let dtos = try load("foods", as: [FoodDTO].self)
        for d in dtos {
            context.insert(Food(id: d.id, name: d.name, kcal: d.kcal, protein: d.protein, carbs: d.carbs, fat: d.fat,
                                fiber: d.fiber, servingGrams: d.servingGrams, category: d.category, source: d.source))
        }
    }

    /// Tabla MET para actividades manuales (cardio fuera del gym).
    static func mets() -> [METDTO] {
        (try? load("mets", as: [METDTO].self)) ?? []
    }
}

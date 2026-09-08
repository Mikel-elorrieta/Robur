import Foundation

/// Fórmulas: Mifflin-St Jeor para BMR, factor de actividad para TDEE, METs para gasto de sesión.
enum CalorieCalculator {

    static func bmr(profile: UserProfile, weightKg: Double) -> Double {
        let base = 10 * weightKg + 6.25 * profile.heightCm - 5 * Double(profile.age)
        return profile.sex == .male ? base + 5 : base - 161
    }

    static func tdee(profile: UserProfile, weightKg: Double) -> Double {
        bmr(profile: profile, weightKg: weightKg) * profile.activity.rawValue
    }

    static func dailyTarget(profile: UserProfile, weightKg: Double) -> Double {
        max(1200, tdee(profile: profile, weightKg: weightKg) + profile.goal.kcalDelta)
    }

    struct MacroTargets { let kcal: Double; let protein: Double; let carbs: Double; let fat: Double }

    /// Proteína por kg configurable, grasa 25-30 % kcal, resto hidratos.
    static func macroTargets(profile: UserProfile, weightKg: Double) -> MacroTargets {
        let kcal = dailyTarget(profile: profile, weightKg: weightKg)
        let protein = profile.proteinPerKg * weightKg
        let fat = kcal * 0.27 / 9
        let carbs = max(0, (kcal - protein * 4 - fat * 9) / 4)
        return MacroTargets(kcal: kcal, protein: protein, carbs: carbs, fat: fat)
    }

    /// kcal = MET × peso(kg) × horas
    static func calories(met: Double, weightKg: Double, seconds: TimeInterval) -> Double {
        met * weightKg * (seconds / 3600)
    }

    /// Gasto de una sesión de fuerza: se reparte la duración total entre los ejercicios ejecutados
    /// ponderando por nº de series completadas, y se aplica el MET de cada ejercicio.
    /// Si el ejercicio es cardio con duración registrada, usa esa duración directamente.
    static func sessionCalories(session: WorkoutSession) -> Double {
        let sets = session.completedSets
        guard !sets.isEmpty else { return 0 }
        let weight = session.bodyWeightKg
        var total = 0.0
        var strengthSets: [WorkoutSet] = []
        for s in sets {
            if let e = s.exercise, e.isCardio, let d = s.durationSeconds, d > 0 {
                total += calories(met: e.met, weightKg: weight, seconds: TimeInterval(d))
            } else {
                strengthSets.append(s)
            }
        }
        guard !strengthSets.isEmpty else { return total }
        // Tiempo de fuerza = duración de sesión menos el cardio explícito.
        let cardioSeconds = sets.compactMap { s -> Int? in (s.exercise?.isCardio ?? false) ? s.durationSeconds : nil }.reduce(0, +)
        let strengthSeconds = max(session.durationSeconds - Double(cardioSeconds), Double(strengthSets.count) * 45) // mínimo 45 s/serie
        let perSet = strengthSeconds / Double(strengthSets.count)
        for s in strengthSets {
            let met = s.exercise?.met ?? 5.0
            total += calories(met: met, weightKg: weight, seconds: perSet)
        }
        return total
    }
}

import Foundation
import HealthKit
import Observation

/// Lectura de pasos / minutos de ejercicio / energía activa y escritura de entrenos y peso en Salud.
@Observable @MainActor
final class HealthKitService {
    static let shared = HealthKitService()

    let store = HKHealthStore()
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    var authorized = false

    // Datos de hoy
    var stepsToday: Int = 0
    var exerciseMinutesToday: Int = 0
    var activeEnergyToday: Double = 0
    var distanceKmToday: Double = 0
    var lastRefresh: Date?

    struct DayStat: Identifiable {
        let date: Date; let steps: Int; let exerciseMinutes: Int; let activeEnergy: Double
        var id: Date { date }
    }
    var lastDays: [DayStat] = []

    private let stepType = HKQuantityType(.stepCount)
    private let exerciseType = HKQuantityType(.appleExerciseTime)
    private let energyType = HKQuantityType(.activeEnergyBurned)
    private let distanceType = HKQuantityType(.distanceWalkingRunning)
    private let massType = HKQuantityType(.bodyMass)

    func requestAuthorization() async {
        guard isAvailable else { return }
        let read: Set<HKObjectType> = [stepType, exerciseType, energyType, distanceType, massType, HKObjectType.workoutType()]
        let write: Set<HKSampleType> = [HKObjectType.workoutType(), massType, energyType]
        do {
            try await store.requestAuthorization(toShare: write, read: read)
            authorized = true
            await refresh()
        } catch {
            print("HealthKit auth error: \(error)")
        }
    }

    // MARK: Lectura

    func refresh() async {
        guard isAvailable else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        async let steps = sum(type: stepType, unit: .count(), from: start, to: .now)
        async let minutes = sum(type: exerciseType, unit: .minute(), from: start, to: .now)
        async let energy = sum(type: energyType, unit: .kilocalorie(), from: start, to: .now)
        async let dist = sum(type: distanceType, unit: .meterUnit(with: .kilo), from: start, to: .now)
        let (s, m, e, d) = await (steps, minutes, energy, dist)
        stepsToday = Int(s); exerciseMinutesToday = Int(m); activeEnergyToday = e; distanceKmToday = d
        lastDays = await dailyStats(days: 14)
        lastRefresh = .now
    }

    func sum(type: HKQuantityType, unit: HKUnit, from: Date, to: Date) async -> Double {
        await withCheckedContinuation { cont in
            let pred = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(q)
        }
    }

    func dailyStats(days: Int) async -> [DayStat] {
        let cal = Calendar.current
        let end = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: .now)!)
        let start = cal.date(byAdding: .day, value: -days + 1, to: cal.startOfDay(for: .now))!
        async let steps = collection(type: stepType, unit: .count(), start: start, end: end)
        async let mins = collection(type: exerciseType, unit: .minute(), start: start, end: end)
        async let energy = collection(type: energyType, unit: .kilocalorie(), start: start, end: end)
        let (s, m, e) = await (steps, mins, energy)
        var out: [DayStat] = []
        var d = start
        while d < end {
            out.append(DayStat(date: d, steps: Int(s[d] ?? 0), exerciseMinutes: Int(m[d] ?? 0), activeEnergy: e[d] ?? 0))
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        return out
    }

    private func collection(type: HKQuantityType, unit: HKUnit, start: Date, end: Date) async -> [Date: Double] {
        await withCheckedContinuation { cont in
            let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let q = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: pred, options: .cumulativeSum,
                                                anchorDate: start, intervalComponents: DateComponents(day: 1))
            q.initialResultsHandler = { _, results, _ in
                var dict: [Date: Double] = [:]
                results?.enumerateStatistics(from: start, to: end) { stat, _ in
                    dict[stat.startDate] = stat.sumQuantity()?.doubleValue(for: unit) ?? 0
                }
                cont.resume(returning: dict)
            }
            store.execute(q)
        }
    }

    /// Último peso registrado en Salud (por si se quiere importar).
    func latestBodyMass() async -> (Double, Date)? {
        await withCheckedContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let q = HKSampleQuery(sampleType: massType, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                if let s = samples?.first as? HKQuantitySample {
                    cont.resume(returning: (s.quantity.doubleValue(for: .gramUnit(with: .kilo)), s.startDate))
                } else { cont.resume(returning: nil) }
            }
            store.execute(q)
        }
    }

    // MARK: Escritura

    /// Guarda la sesión como entreno de fuerza (functionalStrengthTraining) con las kcal estimadas.
    func saveWorkout(session: WorkoutSession) async throws {
        guard isAvailable, let end = session.endedAt else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        try await builder.beginCollection(at: session.startedAt)
        let kcal = session.estimatedCalories
        if kcal > 0 {
            let q = HKQuantity(unit: .kilocalorie(), doubleValue: kcal)
            let sample = HKQuantitySample(type: energyType, quantity: q, start: session.startedAt, end: end)
            try await builder.addSamples([sample])
        }
        try await builder.addMetadata([HKMetadataKeyWorkoutBrandName: "Robur", "routine": session.routineName])
        try await builder.endCollection(at: end)
        _ = try await builder.finishWorkout()
    }

    func saveBodyMass(kg: Double, date: Date) async throws {
        guard isAvailable else { return }
        let sample = HKQuantitySample(type: massType, quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg), start: date, end: date)
        try await store.save(sample)
    }
}

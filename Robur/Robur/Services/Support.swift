import Foundation
import UIKit
import Security
import UserNotifications
import SwiftUI

// MARK: - Keychain (API key)

enum Keychain {
    static let apiKeyAccount = "anthropic_api_key"

    static func set(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account, kSecAttrService as String: "Robur"]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var add = query; add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(account: String) -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account,
                                    kSecAttrService as String: "Robur", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Fotos en disco (Documents/photos)

enum PhotoStore {
    static var dir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    @discardableResult
    static func save(_ image: UIImage, maxSide: CGFloat = 1600) -> String? {
        let name = "\(UUID().uuidString).jpg"
        guard let data = image.resized(maxSide: maxSide).jpegData(compressionQuality: 0.82) else { return nil }
        do { try data.write(to: dir.appendingPathComponent(name)); return name } catch { return nil }
    }

    static func load(_ name: String) -> UIImage? {
        UIImage(contentsOfFile: dir.appendingPathComponent(name).path)
    }

    static func delete(_ name: String) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
    }
}

// MARK: - Notificaciones (recordatorio de pesaje)

enum Reminders {
    static let weighInId = "weighin"

    static func scheduleWeighIn(afterDays days: Int, from lastDate: Date) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            center.removePendingNotificationRequests(withIdentifiers: [weighInId])
            var fire = Calendar.current.date(byAdding: .day, value: days, to: lastDate) ?? .now
            fire = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: fire) ?? fire
            if fire < .now { fire = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!.addingTimeInterval(8 * 3600) }
            let content = UNMutableNotificationContent()
            content.title = "Toca pesarse"
            content.body = "Han pasado \(days) días desde el último registro. Sube el peso y una foto a Robur."
            content.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let req = UNNotificationRequest(identifier: weighInId, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            center.add(req)
        }
    }
}

// MARK: - Traducciones de vocabulario de free-exercise-db

enum Vocab {
    static let muscleNames: [String: String] = [
        "abdominals": "Abdominales", "abductors": "Abductores", "adductors": "Aductores", "biceps": "Bíceps", "calves": "Gemelos",
        "chest": "Pecho", "forearms": "Antebrazos", "glutes": "Glúteos", "hamstrings": "Isquios", "lats": "Dorsales",
        "lower back": "Lumbar", "middle back": "Espalda media", "neck": "Cuello", "quadriceps": "Cuádriceps", "shoulders": "Hombros",
        "traps": "Trapecios", "triceps": "Tríceps",
    ]
    static let equipmentNames: [String: String] = [
        "barbell": "Barra", "dumbbell": "Mancuernas", "cable": "Polea", "machine": "Máquina", "body only": "Peso corporal",
        "kettlebells": "Kettlebell", "bands": "Bandas", "medicine ball": "Balón medicinal", "exercise ball": "Fitball",
        "foam roll": "Foam roller", "e-z curl bar": "Barra Z", "other": "Otro",
    ]
    static let categoryNames: [String: String] = [
        "strength": "Fuerza", "cardio": "Cardio", "stretching": "Estiramiento", "plyometrics": "Pliometría",
        "powerlifting": "Powerlifting", "olympic weightlifting": "Halterofilia", "strongman": "Strongman",
    ]
    static let levelNames: [String: String] = ["beginner": "Principiante", "intermediate": "Intermedio", "expert": "Avanzado"]

    static func muscle(_ s: String) -> String { muscleNames[s] ?? s.capitalized }
    static func equipment(_ s: String) -> String { equipmentNames[s] ?? s.capitalized }
    static func category(_ s: String) -> String { categoryNames[s] ?? s.capitalized }
    static func level(_ s: String) -> String { levelNames[s] ?? s.capitalized }
}

// MARK: - Helpers de formato

extension Double {
    var kcalText: String { "\(Int(rounded())) kcal" }
    var g0: String { String(format: "%.0f", self) }
    var g1: String { String(format: "%.1f", self) }
    func formatted(_ decimals: Int) -> String { String(format: "%.\(decimals)f", self) }
}

extension Date {
    var dayStart: Date { Calendar.current.startOfDay(for: self) }
    var isToday: Bool { Calendar.current.isDateInToday(self) }
    func adding(days: Int) -> Date { Calendar.current.date(byAdding: .day, value: days, to: self)! }
    var shortDay: String { formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) }
    var weekdayName: String { formatted(.dateTime.weekday(.wide)).capitalized }
}

extension TimeInterval {
    var mmss: String {
        let s = Int(self); return String(format: "%d:%02d", s / 60, s % 60)
    }
    var hhmm: String {
        let s = Int(self); return s >= 3600 ? String(format: "%dh %02dmin", s / 3600, (s % 3600) / 60) : "\(s / 60) min"
    }
}

extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0; Scanner(string: h).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
    static let roburAccent = Color(hex: "#E4572E")
    static let roburProtein = Color(hex: "#3A86FF")
    static let roburCarbs = Color(hex: "#FFBE0B")
    static let roburFat = Color(hex: "#FB5607")
}

/// Para poder escribir .foregroundStyle(.roburAccent) / .background(.roburAccent, in:) etc.
extension ShapeStyle where Self == Color {
    static var roburAccent: Color { Color.roburAccent }
    static var roburProtein: Color { Color.roburProtein }
    static var roburCarbs: Color { Color.roburCarbs }
    static var roburFat: Color { Color.roburFat }
}

// MARK: - Ajustes persistidos sencillos

/// Claves compartidas con @AppStorage en las vistas.
enum SettingsKey {
    static let claudeModel = "claudeModel"
    static let healthKitEnabled = "healthKitEnabled"
    static let autoSaveWorkouts = "autoSaveWorkoutsToHealth"
    static let autoSaveWeight = "autoSaveWeightToHealth"
    static let defaultModel = "claude-sonnet-4-5"
}

enum AppSettings {
    static var claudeModel: String { UserDefaults.standard.string(forKey: SettingsKey.claudeModel).flatMap { $0.isEmpty ? nil : $0 } ?? SettingsKey.defaultModel }
    static var healthKitEnabled: Bool { UserDefaults.standard.bool(forKey: SettingsKey.healthKitEnabled) }
    static var autoSaveWorkouts: Bool { UserDefaults.standard.object(forKey: SettingsKey.autoSaveWorkouts) as? Bool ?? true }
    static var autoSaveWeight: Bool { UserDefaults.standard.object(forKey: SettingsKey.autoSaveWeight) as? Bool ?? true }
}

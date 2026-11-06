import Foundation

@MainActor
enum Measurements {
    static let dateKeys = ["first_log_at", "logged_day_7", "invite_tapped_at", "invite_sent_at", "joined_share_at"]
    static var didChange: (() -> Void)?
    static func once(_ key: String, at date: Date = .now, defaults: UserDefaults = AppGroup.defaults) {
        guard dateKeys.contains(key), defaults.object(forKey: "measure.\(key)") == nil else { return }
        defaults.set(date, forKey: "measure.\(key)")
        didChange?()
    }
    static func recordLog(at date: Date = .now, defaults: UserDefaults = AppGroup.defaults, calendar: Calendar = .current) {
        once("first_log_at", at: date, defaults: defaults)
        if let first = defaults.object(forKey: "measure.first_log_at") as? Date,
           calendar.dateComponents([.day], from: calendar.startOfDay(for: first), to: calendar.startOfDay(for: date)).day == 6 {
            once("logged_day_7", at: date, defaults: defaults)
        }
        defaults.set(defaults.integer(forKey: "measure.logs_count") + 1, forKey: "measure.logs_count")
        didChange?()
    }
    static func trialSource(_ value: String, defaults: UserDefaults = AppGroup.defaults) {
        guard ["onboarding", "invite", "extra_pet", "sitter", "settings"].contains(value) else { return }
        if defaults.string(forKey: "measure.trial_source") == nil { defaults.set(value, forKey: "measure.trial_source") }
        didChange?()
    }
    static func attributes(defaults: UserDefaults = AppGroup.defaults) -> [String: String] {
        var result = ConversionDiagnostics.subscriberAttributes
        for key in dateKeys {
            if let date = defaults.object(forKey: "measure.\(key)") as? Date { result[key] = ISO8601DateFormatter().string(from: date) }
        }
        if let source = defaults.string(forKey: "measure.trial_source") { result["trial_source"] = source }
        if defaults.object(forKey: "measure.logs_count") != nil { result["logs_count"] = String(defaults.integer(forKey: "measure.logs_count")) }
        result["offering_id"] = AppConfig.offering
        return result
    }
}

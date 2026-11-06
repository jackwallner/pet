import Foundation

/// The system rating prompt: from the second launch, at a positive moment, at most every 30 days.
enum RatingAsk {
    static let cooldown: TimeInterval = 30 * 24 * 60 * 60

    static func noteLaunch(defaults: UserDefaults = AppGroup.defaults) {
        defaults.set(defaults.integer(forKey: "rating.launches") + 1, forKey: "rating.launches")
    }
    static func isDue(at now: Date = .now, defaults: UserDefaults = AppGroup.defaults) -> Bool {
        guard defaults.integer(forKey: "rating.launches") >= 2, !defaults.bool(forKey: "rating.wroteReview") else { return false }
        guard let last = defaults.object(forKey: "rating.lastAsked") as? Date else { return true }
        return now.timeIntervalSince(last) >= cooldown
    }
    static func markAsked(at now: Date = .now, defaults: UserDefaults = AppGroup.defaults) {
        defaults.set(now, forKey: "rating.lastAsked")
    }
    static func markWroteReview(defaults: UserDefaults = AppGroup.defaults) {
        defaults.set(true, forKey: "rating.wroteReview")
    }
}

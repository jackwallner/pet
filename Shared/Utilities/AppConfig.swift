import Foundation

enum AppConfig {
    static let displayName = "Biscuit"
    static let productionRevenueCatKey = "appl_mKdSNRaSbsfMyXKhWQwAMKMbnEx"
    static let entitlement = "pro"
    static let offering = "default"
    static let monthly = "com.jackwallner.pet.monthly"
    static let yearly = "com.jackwallner.pet.yearly"
    static let privacyURL = URL(string: "https://jackwallner.github.io/pet/privacy-policy.html")!
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let supportURL = URL(string: "https://jackwallner.github.io/pet/support.html")!
    static let reviewURL = URL(string: "https://apps.apple.com/app/id6831707940?action=write-review")!
    static let disclaimer = "Biscuit is a record keeper. Your veterinarian directs your pet's care."
}

enum AppGroup {
    static let id = "group.com.jackwallner.pet"
    static let bundleID = "com.jackwallner.pet"
    static let subsystem = bundleID
    static let cloudKitContainerID = "iCloud.com.jackwallner.pet"
    static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }
    static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
}

enum LaunchOptions {
    static func contains(_ key: String) -> Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(key)
        #else
        false
        #endif
    }
    static func value(_ key: String) -> String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: key), index + 1 < args.count else { return nil }
        return args[index + 1]
        #else
        return nil
        #endif
    }
}

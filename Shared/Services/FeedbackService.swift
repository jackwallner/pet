import Foundation

/// A TestFlight suggestion starts a build session on Jack's Mac, so only TestFlight builds
/// show the form. App Store builds keep the mail link and can never reach the endpoint.
enum Distribution {
    static let isTestFlight: Bool = {
        #if DEBUG
        true
        #else
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }()

    /// The ops poller builds only "testflight" suggestions.
    static var channel: String { isTestFlight ? "testflight" : "app_store" }
}

/// A suggestion and how far it has got. The build session writes the status.
struct FeedbackItem: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let createdAt: Date
    let text: String
    let status: String
    let reply: String?
    let build: String?

    enum CodingKeys: String, CodingKey {
        case id, text, status, reply, build
        case createdAt = "created_at"
    }

    var statusLabel: String {
        switch status {
        case "new", "queued": "Received"
        case "working": "Being built"
        case "shipped": build.map { "In TestFlight build \($0)" } ?? "In TestFlight"
        case "declined": "Not this time"
        default: status.capitalized
        }
    }
}

struct FeedbackDraft: Encodable, Sendable {
    let app = "pet"
    let installID: String
    let name: String
    let text: String
    let context: [String: String]
    /// JPEG, base64, at most about 1.5 MB.
    let screenshot: String?

    enum CodingKeys: String, CodingKey {
        case app, name, text, context, screenshot
        case installID = "install_id"
    }
}

/// Talks to the tester-feedback edge function. The app key only lets a build post
/// suggestions and read back its own.
struct FeedbackService: Sendable {
    let endpoint: URL?
    let key: String
    /// Debug builds never touch the network: a real send starts a build session.
    var stubbed = false

    static var current: FeedbackService {
        #if DEBUG
        FeedbackService(endpoint: nil, key: "", stubbed: true)
        #else
        FeedbackService(
            endpoint: (Bundle.main.object(forInfoDictionaryKey: "PET_FEEDBACK_URL") as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) },
            key: Bundle.main.object(forInfoDictionaryKey: "PET_FEEDBACK_KEY") as? String ?? "")
        #endif
    }

    static var installID: String {
        let name = "feedbackInstallID"
        if let saved = AppGroup.defaults.string(forKey: name) { return saved }
        let made = UUID().uuidString
        AppGroup.defaults.set(made, forKey: name)
        return made
    }

    enum Failure: LocalizedError {
        case notConfigured, server(String)
        var errorDescription: String? {
            switch self {
            case .notConfigured: "This build can't send suggestions."
            case .server(let why): why
            }
        }
    }

    func send(_ draft: FeedbackDraft) async throws -> Int {
        if stubbed { return 0 }
        guard let endpoint, !key.isEmpty else { throw Failure.notConfigured }
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-app-key")
        request.httpBody = try JSONEncoder().encode(draft)
        let (data, response) = try await URLSession.shared.data(for: request)
        struct Created: Decodable { let id: Int }
        guard (response as? HTTPURLResponse)?.statusCode == 200, let created = try? JSONDecoder().decode(Created.self, from: data) else {
            throw Failure.server("The server didn't take it.")
        }
        return created.id
    }

    func mine(installID: String) async throws -> [FeedbackItem] {
        if stubbed { return LaunchOptions.contains("-SuggestionSamples") ? Self.samples : [] }
        guard let endpoint, !key.isEmpty, var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { throw Failure.notConfigured }
        components.queryItems = [URLQueryItem(name: "app", value: "pet"), URLQueryItem(name: "install_id", value: installID)]
        guard let url = components.url else { throw Failure.notConfigured }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(key, forHTTPHeaderField: "x-app-key")
        let (data, _) = try await URLSession.shared.data(for: request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: raw) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: raw) ?? .now
        }
        return try decoder.decode([FeedbackItem].self, from: data)
    }

    private static let samples = [
        FeedbackItem(id: 2, createdAt: .now, text: "Show who gave the last dose on the Now screen", status: "working", reply: nil, build: nil),
        FeedbackItem(id: 1, createdAt: .now, text: "Let me add a note to a walk", status: "shipped", reply: "Tap a walk in History to add a note.", build: "4"),
    ]
}

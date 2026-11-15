import SwiftUI

enum Theme {
    static let accent = Color(light: UIColor(red: 0.43, green: 0.28, blue: 0.17, alpha: 1), dark: UIColor(red: 0.90, green: 0.70, blue: 0.48, alpha: 1))
    static let buttonInk = Color(light: .white, dark: UIColor(red: 0.16, green: 0.12, blue: 0.08, alpha: 1))
    static let background = Color(light: UIColor(red: 0.97, green: 0.95, blue: 0.91, alpha: 1), dark: UIColor(red: 0.10, green: 0.095, blue: 0.085, alpha: 1))
    static let surface = Color(light: .white, dark: UIColor(red: 0.16, green: 0.15, blue: 0.13, alpha: 1))
}

private extension Color {
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

struct PrimaryButton: View {
    let title: String
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.headline).foregroundStyle(Theme.buttonInk).frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(disabled)
    }
}

struct EditedLine: View {
    let author: String
    let date: Date
    var body: some View {
        Text("Edited by \(author), \(date.formatted(date: .abbreviated, time: .shortened))")
            .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

struct SyncLine: View {
    @ObservedObject var sync: CloudSyncState
    let store: String?
    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { time in
            let last = sync.lastSynced(store: store)
            Group {
                if sync.stale(store: store, at: time.date) && sync.checking(store: store, at: time.date) {
                    // Checking, but the age of what is shown stays visible.
                    Text("Checking iCloud. \(last.map { "Last updated \(NowSummary.when($0, now: time.date))" } ?? "")").font(.footnote).foregroundStyle(.secondary)
                } else if sync.stale(store: store, at: time.date) {
                    // Stale state must be impossible to miss: the tiles below may be behind.
                    Label(staleText(last: last, now: time.date), systemImage: "exclamationmark.icloud")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                } else {
                    Text("Updated \(last.map { NowSummary.when($0, now: time.date) } ?? "")").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("sync.status")
        }
    }
    private func staleText(last: Date?, now: Date) -> String {
        let since = last.map { "Not updated since \(NowSummary.when($0, now: now))" } ?? "Not updated yet"
        if !sync.mirrors(store: store) { return "iCloud unavailable. \(since)" }
        if !sync.connected { return "Offline. \(since)" }
        if sync.problem(store: store) { return "Sync needs attention. \(since)" }
        return since
    }
}

struct LapseBanner: View {
    @EnvironmentObject private var events: EventStore
    var body: some View {
        // A solo log with one pet loses nothing on lapse, so it gets no banner.
        if events.access.lapsed(at: .now) && (events.isSharedLog || events.pets.count > 1) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Household subscription ended").font(.subheadline.weight(.semibold))
                if events.isOwner { Text("Solo logging continues on your first pet.") }
                else if events.canWrite, let date = events.access.readOnlyFrom {
                    Text("Read-only from \(date.formatted(date: .abbreviated, time: .shortened))")
                } else { Text("This shared log is read-only.") }
            }
            .font(.footnote).padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("household.lapsed")
        }
    }
}

extension View {
    func biscuitList() -> some View { scrollContentBackground(.hidden).background(Theme.background) }
}

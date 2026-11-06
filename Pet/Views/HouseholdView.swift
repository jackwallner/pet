import CloudKit
import SwiftUI
import VisionKit

struct HouseholdView: View {
    @EnvironmentObject private var events: EventStore
    @EnvironmentObject private var sharing: SharingService
    @EnvironmentObject private var store: StoreService
    @State private var paywall = false
    @State private var invite = false
    @State private var manage = false
    var body: some View {
        List {
            Section { LapseBanner() }
            if events.isOwner {
                Section { SharedWorkflowPreview().listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
                Section {
                    Text("Live sharing uses iPhone and iCloud.").foregroundStyle(.secondary)
                    Text("People joining your household pay nothing.").foregroundStyle(.secondary)
                    Button("Invite") {
                        Measurements.once("invite_tapped_at")
                        if events.access.active(at: .now) { invite = true } else { paywall = true }
                    }.accessibilityIdentifier("household.invite").disabled(events.pet == nil)
                }
            } else {
                Section { Label("Joined household", systemImage: "person.2"); Text("Your access is covered by the household owner.") }
            }
            if let share = sharing.share {
                Section("People") {
                    ForEach(Array(share.participants.enumerated()), id: \.offset) { _, person in
                        Text(person.userIdentity.nameComponents.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .short) } ?? (person.role == .owner ? "Owner" : "Caregiver"))
                    }
                    Button(events.isOwner ? "Manage sharing" : "Leave household") { manage = true }
                }
            }
            Section { NavigationLink("Join a household") { JoinView() } }
            if events.isOwner {
                Section {
                    Button("Restore purchases") { Task { await store.restore() } }.disabled(store.busy)
                    if let until = events.household?.householdActiveUntil { LabeledContent("Household active until", value: until.formatted(date: .abbreviated, time: .shortened)) }
                    if let error = store.error { Text(error).font(.footnote).foregroundStyle(.secondary) }
                    if events.access.active(at: .now) { Link("Manage subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!) }
                }
            }
        }.biscuitList().navigationTitle("Household").navigationBarTitleDisplayMode(.inline)
        .task { await sharing.refresh() }
        .sheet(isPresented: $paywall) { NavigationStack { PaywallView(source: "invite", onboarding: false) } }
        .sheet(isPresented: $invite) { NavigationStack { InviteView() } }
        .sheet(isPresented: $manage) {
            if let share = sharing.share { CloudSharingController(share: share, container: CKContainer(identifier: AppGroup.cloudKitContainerID)) { updated, stopped in Task { await sharing.persist(updated, stopped: stopped) } } }
        }
    }
}

struct InviteView: View {
    var previewURL: URL? = nil
    @EnvironmentObject private var sharing: SharingService
    @EnvironmentObject private var events: EventStore
    @State private var sending = false
    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 24) {
                if let url = previewURL ?? sharing.inviteURL, let qr = ShareInvite.qrCode(for: url) {
                    Image(decorative: qr, scale: 1).interpolation(.none).resizable().scaledToFit().frame(maxWidth: 260).padding(16).background(.white)
                        .accessibilityLabel("Household invitation QR code")
                    if previewURL != nil { Text("Example invitation").font(.footnote).foregroundStyle(.secondary) }
                    Text("Anyone with this link can join and add entries.").font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    PrimaryButton(title: "Send invitation") { sending = true }.disabled(previewURL != nil).accessibilityIdentifier("invite.send")
                } else if sharing.busy {
                    ProgressView("Preparing invitation")
                } else {
                    ContentUnavailableView("Invite by link or QR", systemImage: "qrcode")
                    Text("Sharing needs iCloud on both iPhones.").foregroundStyle(.secondary)
                    PrimaryButton(title: "Prepare invitation") { Task { await sharing.prepareInvite() } }.disabled(!events.access.active(at: .now))
                }
            }.padding(20)
        }.background(Theme.background).navigationTitle("Invite").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { DismissButton() } }
        .task { if previewURL == nil && events.access.active(at: .now) && sharing.available { await sharing.prepareInvite() } }
        .sheet(isPresented: $sending) {
            if let url = sharing.inviteURL {
                ActivitySheet(items: [url]) { completed in
                    if completed { Task { @MainActor in Measurements.once("invite_sent_at"); StoreService.shared.syncAttributes() } }
                }
            }
        }
    }
}

struct JoinView: View {
    @EnvironmentObject private var sharing: SharingService
    @State private var link = ""
    @State private var scanning = false
    var body: some View {
        Form {
            Section {
                TextField("Invitation link", text: $link, axis: .vertical).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("join.link")
                Button("Scan QR code") { scanning = true }.disabled(!DataScannerViewController.isSupported || !DataScannerViewController.isAvailable)
                Button(sharing.busy ? "Joining" : "Join household") { Task { await sharing.join(link) } }
                    .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sharing.busy).accessibilityIdentifier("join.submit")
            }
            Section { Text("Join with iCloud on this iPhone. The household owner covers access.").foregroundStyle(.secondary) }
        }.biscuitList().navigationTitle("Join household").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { DismissButton() } }
        .sheet(isPresented: $scanning) { InviteScanner { value in link = value; scanning = false } }
    }
}

struct InviteScanner: UIViewControllerRepresentable {
    let scanned: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(scanned: scanned) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced, recognizesMultipleItems: false, isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }
    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let scanned: (String) -> Void
        init(scanned: @escaping (String) -> Void) { self.scanned = scanned }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let barcode) in addedItems {
                if let text = barcode.payloadStringValue, ShareInvite.url(in: text) != nil { dataScanner.stopScanning(); scanned(text); return }
            }
        }
    }
}

struct CloudSharingController: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let finished: (CKShare, Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(share: share, finished: finished) }
    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowReadWrite, .allowPublic]
        return controller
    }
    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}
    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let share: CKShare
        let finished: (CKShare, Bool) -> Void
        init(share: CKShare, finished: @escaping (CKShare, Bool) -> Void) { self.share = share; self.finished = finished }
        func itemTitle(for csc: UICloudSharingController) -> String? { "Household log" }
        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) { SharingService.shared.error = "Sharing changes could not be saved. Please try again." }
        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) { finished(csc.share ?? share, false) }
        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) { finished(csc.share ?? share, true) }
    }
}

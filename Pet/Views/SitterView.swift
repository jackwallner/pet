import PDFKit
import SwiftUI

struct SitterView: View {
    @EnvironmentObject private var events: EventStore
    @State private var url: URL?
    @State private var share = false
    @State private var paywall = false
    @State private var error: String?
    var body: some View {
        Group {
            if let url { PDFPreview(url: url) }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Image(systemName: "doc.text").font(.system(size: 48)).foregroundStyle(Theme.accent)
                        Text("One-page PDF").font(.title2.weight(.semibold))
                        Text("Last logged, medication instructions and recurring items.")
                        Text("A snapshot to share with a sitter.").foregroundStyle(.secondary)
                        if let error { Text(error).foregroundStyle(.secondary) }
                    }.padding(20)
                }.background(Theme.background)
            }
        }
        .navigationTitle("Sitter sheet").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: url == nil ? "Create sitter sheet" : "Share PDF", disabled: events.pet == nil) {
                if url != nil { share = true }
                else if events.access.active(at: .now) { build() }
                else if events.isOwner { paywall = true }
                else { error = "The household owner can renew access." }
            }.accessibilityIdentifier("sitter.create").padding(20).background(Theme.background)
        }
        .sheet(isPresented: $share) { if let url { ActivitySheet(items: [url]) } }
        .sheet(isPresented: $paywall, onDismiss: { if events.access.active(at: .now) { build() } }) { NavigationStack { PaywallView(source: "sitter", onboarding: false) } }
        .task { if LaunchOptions.value("-ScreenshotRoute") == "sitter", events.access.active(at: .now) { build() } }
    }
    private func build() {
        guard let pet = events.pet else { return }
        do { url = try SitterPDF.file(SitterSnapshot.build(pet: pet, medications: events.medications, dueItems: events.dueItems, events: events.events, lastSync: events.sync.lastSynced)) }
        catch { self.error = error.localizedDescription }
    }
}

struct PDFPreview: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.backgroundColor = .secondarySystemBackground
        view.document = PDFDocument(url: url)
        view.accessibilityIdentifier = "sitter.pdf"
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {}
}

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
            if let url { PDFPreview(url: url).id(url) }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Image(systemName: "doc.text").font(.system(size: 48)).foregroundStyle(Theme.accent)
                        Text(events.pets.count > 1 ? "One page per pet" : "One-page PDF").font(.title2.weight(.semibold))
                        if let error { Text(error).foregroundStyle(.secondary) }
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.background)
            }
        }
        .navigationTitle("Sitter sheet").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: url == nil ? "Create sitter sheet" : "Share PDF", disabled: events.pet == nil) {
                // Rebuild at share time so an entry logged while the preview was open is on the sheet.
                if url != nil { build(); if url != nil && error == nil { share = true } }
                else if events.access.active(at: .now) { build() }
                else if events.isOwner { paywall = true }
                else { error = "The household owner can renew access." }
            }.accessibilityIdentifier("sitter.create").padding(20).background(Theme.background)
        }
        .sheet(isPresented: $share) { if let url { ActivitySheet(items: [url]) } }
        .sheet(isPresented: $paywall, onDismiss: { if events.access.active(at: .now) { build() } }) { NavigationStack { PaywallView(source: "sitter", onboarding: false) } }
        .task { if LaunchOptions.value("-ScreenshotRoute") == "sitter", events.access.active(at: .now) { build() } }
    }
    /// Every pet in the household, the one on screen first: a sitter minds them all.
    private func build() {
        guard let current = events.pet else { return }
        error = nil
        let pets = [current] + events.pets.filter { $0.id != current.id }
        let lastSync = events.sync.lastSynced(store: events.syncStoreID)
        do {
            url = try SitterPDF.file(pets.map { pet in
                SitterSnapshot.build(pet: pet, medications: events.medications, dueItems: events.dueItems, events: events.events,
                                     lastSync: lastSync, shared: events.isSharedLog, photo: events.petPhotos[pet.id])
            })
        } catch { self.error = error.localizedDescription; url = nil }
    }
}

struct PDFPreview: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        // One page per pet: scroll through them all before sharing.
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .secondarySystemBackground
        view.document = PDFDocument(url: url)
        view.accessibilityIdentifier = "sitter.pdf"
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {}
}

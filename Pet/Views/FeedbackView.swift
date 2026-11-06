import PhotosUI
import SwiftUI
import UIKit

struct FeedbackView: View {
    @EnvironmentObject private var events: EventStore
    @Environment(\.dismiss) private var dismiss
    let onSent: (FeedbackItem) -> Void
    @State private var text = ""
    @State private var photo: PhotosPickerItem?
    @State private var screenshot: UIImage?
    @State private var sending = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .focused($focused)
                        .frame(minHeight: 180)
                        .accessibilityIdentifier("feedback.text")
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("What should change?").foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                            }
                        }
                }
                Section {
                    PhotosPicker(selection: $photo, matching: .screenshots) {
                        Label(screenshot == nil ? "Attach a screenshot" : "Screenshot attached", systemImage: screenshot == nil ? "photo" : "checkmark.circle")
                    }
                    if screenshot != nil {
                        Button("Remove screenshot", role: .destructive) { photo = nil; screenshot = nil }
                    }
                }
                if let error { Section { Text(error).font(.footnote).foregroundStyle(.red) } }
            }
            .biscuitList()
            .navigationTitle("Suggest a change")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { DismissButton() }
                ToolbarItem(placement: .confirmationAction) {
                    if sending { ProgressView() }
                    else {
                        Button("Send") { Task { await send() } }
                            .disabled(trimmed.count < 3)
                            .accessibilityIdentifier("feedback.send")
                    }
                }
            }
        }
        .interactiveDismissDisabled(sending)
        .onAppear { focused = true }
        .onChange(of: photo) { _, item in Task { await load(item) } }
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        screenshot = image
    }

    private func send() async {
        sending = true
        error = nil
        defer { sending = false }
        let info = Bundle.main.infoDictionary
        let device = UIDevice.current
        let draft = FeedbackDraft(
            installID: FeedbackService.installID,
            name: events.caregiver,
            text: trimmed,
            context: [
                "version": info?["CFBundleShortVersionString"] as? String ?? "",
                "build": info?["CFBundleVersion"] as? String ?? "",
                "screen": "settings",
                "device": device.model,
                "os": "\(device.systemName) \(device.systemVersion)",
                "text_size": UIApplication.shared.preferredContentSizeCategory.rawValue,
                "channel": Distribution.channel,
            ],
            screenshot: screenshot.flatMap(Self.encode))
        do {
            let id = try await FeedbackService.current.send(draft)
            onSent(FeedbackItem(id: id, createdAt: .now, text: trimmed, status: "new", reply: nil, build: nil))
            dismiss()
        } catch {
            self.error = "Couldn't send. \(error.localizedDescription)"
        }
    }

    /// Downscaled JPEG, base64, small enough for the endpoint's 1.5 MB cap.
    private static func encode(_ image: UIImage) -> String? {
        let scale = min(1, 1400 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        var quality: CGFloat = 0.7
        while quality > 0.2 {
            if let data = resized.jpegData(compressionQuality: quality), data.count < 1_000_000 { return data.base64EncodedString() }
            quality -= 0.15
        }
        return nil
    }
}

struct SuggestionRow: View {
    let item: FeedbackItem
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.text).lineLimit(3)
            Text(item.statusLabel).font(.footnote).foregroundStyle(.secondary)
            if let reply = item.reply { Text(reply).font(.footnote) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.suggestion")
    }
}

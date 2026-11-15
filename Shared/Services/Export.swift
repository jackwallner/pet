import Foundation
import UIKit

enum LogExport {
    static func csv(pets: [PetProfile], medications: [Medication], events: [EventRecord]) -> String {
        func quote(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let names = Dictionary(uniqueKeysWithValues: pets.map { ($0.id, $0.name) })
        let meds = Dictionary(uniqueKeysWithValues: medications.map { ($0.id, $0.name) })
        let iso = ISO8601DateFormatter()
        let header = ["id", "pet", "kind", "occurred_at", "recorded_at", "who", "recorded_by", "action", "target_id", "medication", "status", "scheduled_at", "note"]
        let rows = EventLedger.ordered(events).map { event in
            [event.id.uuidString, names[event.petID] ?? "", event.kind.rawValue,
             iso.string(from: event.occurredAt), iso.string(from: event.recordedAt), event.performedBy, event.author,
             event.action.rawValue, event.targetID?.uuidString ?? "", event.medicationID.flatMap { meds[$0] } ?? "",
             event.doseStatus?.rawValue ?? "", event.scheduledAt.map(iso.string) ?? "", event.note].map(quote).joined(separator: ",")
        }
        return ([header.joined(separator: ",")] + rows).joined(separator: "\r\n") + "\r\n"
    }
    static func file(pets: [PetProfile], medications: [Medication], events: [EventRecord]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(AppConfig.displayName)-log-\(UUID().uuidString.prefix(8)).csv")
        try Data(csv(pets: pets, medications: medications, events: events).utf8).write(to: url, options: .atomic)
        return url
    }
}

struct SitterSnapshot: Equatable {
    static let headings: Set<String> = ["ABOUT", "MEDICATIONS", "RECURRING ITEMS", "LAST LOGGED"]
    let title: String
    let lines: [String]
    var photo: UIImage?
    /// What a sitter follows comes first: the pet, each medication with its own last dose, then routines.
    /// `lastSync` is nil for a log nobody shares, where a sync time means nothing.
    static func build(pet: PetProfile, medications: [Medication], dueItems: [DueItem], events: [EventRecord],
                      lastSync: Date?, shared: Bool = true, now: Date = .now, photo: UIImage? = nil, calendar: Calendar = .current) -> SitterSnapshot {
        func day(_ date: Date) -> String { date.formatted(.dateTime.month(.abbreviated).day()) }
        var lines = ["As of \(now.formatted(date: .abbreviated, time: .shortened)). Check with the household for changes."]
        if shared { lines.append("Last sync: \(lastSync?.formatted(date: .abbreviated, time: .shortened) ?? "Unavailable")") }
        lines += ["", "ABOUT"]
        lines += about(pet, now: now)
        // A finished course stays off the sheet, so a sitter never keeps giving it.
        let today = calendar.startOfDay(for: now)
        let meds = medications.filter { $0.petID == pet.id && !$0.archived && ($0.asNeeded || ($0.endDate.map { calendar.startOfDay(for: $0) >= today } ?? true)) }
        if !meds.isEmpty { lines += ["", "MEDICATIONS"] }
        for med in meds {
            var schedule = med.asNeeded ? "As needed" : med.minutes.compactMap { ScheduleEngine.date(forMinutes: $0, onDayOf: now) }.map { $0.formatted(date: .omitted, time: .shortened) }.joined(separator: ", ")
            if !med.asNeeded {
                schedule += ", " + (med.weekdays.isEmpty || Set(med.weekdays).count == 7 ? "every day" : med.weekdays.map { calendar.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", "))
                if calendar.startOfDay(for: med.startDate) > today { schedule += ", starts \(day(med.startDate))" }
                if let end = med.endDate { schedule += ", until \(day(end))" }
            }
            lines.append("\(med.name): \(schedule)")
            if let last = NowSummary.lastDose(med.id, events: events.filter { $0.petID == pet.id }) {
                lines.append("Last: \(last.doseStatus?.rawValue ?? "Logged") \(last.occurredAt.formatted(date: .abbreviated, time: .shortened)), \(last.performedBy)")
            } else { lines.append("Last: Nothing logged") }
            if !med.instructions.isEmpty { lines.append(med.instructions) }
        }
        let items = dueItems.filter { $0.petID == pet.id && !$0.archived }
        if !items.isEmpty { lines += ["", "RECURRING ITEMS"] }
        for item in items { lines.append("\(item.name): \(DueEngine.summary(item, events: events, now: now, calendar: calendar))") }
        lines += ["", "LAST LOGGED"]
        // A hidden button's entries still count. Meds are listed per medication above when there are any.
        let hidden = EventKind.loggable.filter { !pet.shownLogKinds.contains($0) && NowSummary.last($0, petID: pet.id, events: events) != nil }
        for kind in pet.shownLogKinds + hidden where !(kind == .meds && !meds.isEmpty) {
            if let last = NowSummary.last(kind, petID: pet.id, events: events) {
                lines.append("\(kind.rawValue): \(last.occurredAt.formatted(date: .abbreviated, time: .shortened)), \(last.performedBy)\(last.doseStatus.map { ", \($0.rawValue)" } ?? "")")
            } else { lines.append("\(kind.rawValue): Nothing logged") }
        }
        lines += ["", AppConfig.disclaimer]
        return SitterSnapshot(title: "\(pet.name)'s sitter sheet", lines: lines, photo: photo)
    }
    private static func about(_ pet: PetProfile, now: Date) -> [String] {
        let age = pet.birthday.flatMap { PetAge.text(birthday: $0, now: now) }
        var lines = [[pet.species.rawValue, age].compactMap { $0 }.joined(separator: ", ")]
        let vet = [pet.vet, pet.vetPhone].compactMap { $0 }.joined(separator: ", ")
        if !vet.isEmpty { lines.append("Vet: \(vet)") }
        if let microchip = pet.microchip { lines.append("Microchip: \(microchip)") }
        if let insurance = pet.insurance { lines.append("Insurance: \(insurance)") }
        if let notes = pet.notes { lines.append(notes) }
        return lines
    }
}

@MainActor
enum SitterPDF {
    enum PDFError: LocalizedError {
        case tooLong(String)
        var errorDescription: String? {
            guard case .tooLong(let title) = self else { return nil }
            return "\(title) exceeds one page. Shorten the pet notes or medication instructions, then try again."
        }
    }
    /// Below this a sitter, often reading on a phone or a printout, cannot comfortably read the instructions.
    static let minimumSize: CGFloat = 10
    private static let page = CGRect(x: 0, y: 0, width: 612, height: 792)
    /// One snapshot fitted to its page: the text shrinks first, then the line spacing tightens at the floor,
    /// so a household with many medications still gets a sheet instead of an error.
    private struct Layout {
        let snapshot: SitterSnapshot
        let text: NSAttributedString
        let bodyRect: CGRect
        let titleRect: CGRect
        let titleSize: CGFloat
    }
    private static func layout(_ snapshot: SitterSnapshot) throws -> Layout {
        let bodyRect = snapshot.photo == nil ? CGRect(x: 40, y: 100, width: 532, height: 640) : CGRect(x: 40, y: 148, width: 532, height: 592)
        func body(_ size: CGFloat, spacing: CGFloat) -> NSAttributedString {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = spacing
            let text = NSMutableAttributedString()
            for (index, line) in snapshot.lines.enumerated() {
                let font = SitterSnapshot.headings.contains(line) ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
                text.append(NSAttributedString(string: line + (index < snapshot.lines.count - 1 ? "\n" : ""),
                                               attributes: [.font: font, .foregroundColor: UIColor.black, .paragraphStyle: paragraph]))
            }
            return text
        }
        func fits(_ text: NSAttributedString) -> Bool {
            text.boundingRect(with: CGSize(width: bodyRect.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height <= bodyRect.height
        }
        var fitted: NSAttributedString?
        for spacing in [4, 2, 0] as [CGFloat] {
            var size: CGFloat = 15
            while size > minimumSize && !fits(body(size, spacing: spacing)) { size -= 0.5 }
            if fits(body(size, spacing: spacing)) { fitted = body(size, spacing: spacing); break }
        }
        guard let text = fitted else { throw PDFError.tooLong(snapshot.title) }
        let titleRect = CGRect(x: 40, y: 40, width: snapshot.photo == nil ? 532 : 416, height: 52)
        func titleHeight(_ size: CGFloat) -> CGFloat {
            (snapshot.title as NSString).boundingRect(with: CGSize(width: titleRect.width, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, attributes: [.font: UIFont.boldSystemFont(ofSize: size)], context: nil).height
        }
        var titleSize: CGFloat = 25
        while titleSize > 12 && titleHeight(titleSize) > titleRect.height { titleSize -= 0.5 }
        guard titleHeight(titleSize) <= titleRect.height else { throw PDFError.tooLong(snapshot.title) }
        return Layout(snapshot: snapshot, text: text, bodyRect: bodyRect, titleRect: titleRect, titleSize: titleSize)
    }
    static func data(_ snapshot: SitterSnapshot) throws -> Data { try data([snapshot]) }
    /// One page per pet, so a sitter minding two dogs gets both on one PDF.
    static func data(_ snapshots: [SitterSnapshot]) throws -> Data {
        let layouts = try snapshots.map(layout)
        return UIGraphicsPDFRenderer(bounds: page).pdfData { renderer in
            for layout in layouts {
                renderer.beginPage()
                (layout.snapshot.title as NSString).draw(in: layout.titleRect, withAttributes: [.font: UIFont.boldSystemFont(ofSize: layout.titleSize), .foregroundColor: UIColor.black])
                layout.text.draw(in: layout.bodyRect)
                if let photo = layout.snapshot.photo { draw(photo, filling: CGRect(x: 472, y: 36, width: 100, height: 100), in: renderer.cgContext) }
            }
        }
    }
    private static func draw(_ photo: UIImage, filling rect: CGRect, in context: CGContext) {
        guard photo.size.width > 0, photo.size.height > 0 else { return }
        let scale = max(rect.width / photo.size.width, rect.height / photo.size.height)
        let size = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
        context.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: 12).addClip()
        photo.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
        context.restoreGState()
    }
    static func file(_ snapshot: SitterSnapshot) throws -> URL { try file([snapshot]) }
    static func file(_ snapshots: [SitterSnapshot]) throws -> URL {
        // The sitter sees this name. A folder per file keeps it readable and still unique.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let title = snapshots.count == 1 ? snapshots[0].title : "Sitter sheet"
        let safe = title.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
        let url = folder.appendingPathComponent("\(safe).pdf")
        try data(snapshots).write(to: url, options: .atomic)
        return url
    }
}

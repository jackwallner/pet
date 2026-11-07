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
    let title: String
    let lines: [String]
    var photo: UIImage?
    static func build(pet: PetProfile, medications: [Medication], dueItems: [DueItem], events: [EventRecord],
                      lastSync: Date?, now: Date = .now, photo: UIImage? = nil) -> SitterSnapshot {
        var lines = ["Snapshot: \(now.formatted(date: .abbreviated, time: .shortened))",
                     "Last successful sync: \(lastSync?.formatted(date: .abbreviated, time: .shortened) ?? "Unavailable")",
                     "This PDF is a snapshot. Check with the household for updates.", "", "ABOUT"]
        lines += about(pet, now: now)
        lines += ["", "LAST LOGGED"]
        // A hidden button's entries still count: a sitter needs the last dose even if Meds is off Now.
        let hidden = EventKind.loggable.filter { !pet.shownLogKinds.contains($0) && NowSummary.last($0, petID: pet.id, events: events) != nil }
        for kind in pet.shownLogKinds + hidden {
            if let last = NowSummary.last(kind, petID: pet.id, events: events) {
                lines.append("\(kind.rawValue): \(last.occurredAt.formatted(date: .abbreviated, time: .shortened)), \(last.performedBy)\(last.doseStatus.map { ", \($0.rawValue)" } ?? "")")
            } else { lines.append("\(kind.rawValue): Nothing logged") }
        }
        let meds = medications.filter { $0.petID == pet.id && !$0.archived }
        if !meds.isEmpty { lines += ["", "MEDICATIONS"] }
        for med in meds {
            let times = med.asNeeded ? "As needed" : med.minutes.compactMap { ScheduleEngine.date(forMinutes: $0, onDayOf: now) }.map { $0.formatted(date: .omitted, time: .shortened) }.joined(separator: ", ")
            let weekdays = med.weekdays.isEmpty ? "Every day" : med.weekdays.map { Calendar.current.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", ")
            lines.append("\(med.name): \(times)\(med.asNeeded ? "" : ", " + weekdays)")
            lines.append("Reminder phone: \(med.reminderPhoneName)")
            if !med.instructions.isEmpty { lines.append(med.instructions) }
        }
        let items = dueItems.filter { $0.petID == pet.id && !$0.archived }
        if !items.isEmpty { lines += ["", "RECURRING ITEMS"] }
        for item in items {
            let time = ScheduleEngine.date(forMinutes: item.minutes, onDayOf: now)?.formatted(date: .omitted, time: .shortened) ?? ""
            lines.append("\(item.name): \(time), \(item.intervalDays == 1 ? "every day" : "every \(item.intervalDays) days")")
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
        case tooLong
        var errorDescription: String? { "This sitter sheet exceeds one page. Shorten the medication instructions, then try again." }
    }
    static func data(_ snapshot: SitterSnapshot) throws -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let text = snapshot.lines.joined(separator: "\n")
        let photoRect = CGRect(x: 472, y: 36, width: 100, height: 100)
        let bodyRect = snapshot.photo == nil ? CGRect(x: 40, y: 100, width: 532, height: 640) : CGRect(x: 40, y: 148, width: 532, height: 592)
        var size: CGFloat = 15
        func attributes(_ size: CGFloat) -> [NSAttributedString.Key: Any] {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            return [.font: UIFont.systemFont(ofSize: size), .foregroundColor: UIColor.black, .paragraphStyle: paragraph]
        }
        while size > 8 && (text as NSString).boundingRect(with: CGSize(width: bodyRect.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes(size), context: nil).height > bodyRect.height { size -= 0.5 }
        guard (text as NSString).boundingRect(with: CGSize(width: bodyRect.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes(size), context: nil).height <= bodyRect.height else { throw PDFError.tooLong }
        var titleSize: CGFloat = 25
        let titleRect = CGRect(x: 40, y: 40, width: snapshot.photo == nil ? 532 : 416, height: 52)
        while titleSize > 12 && (snapshot.title as NSString).boundingRect(with: CGSize(width: titleRect.width, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, attributes: [.font: UIFont.boldSystemFont(ofSize: titleSize)], context: nil).height > titleRect.height { titleSize -= 0.5 }
        guard (snapshot.title as NSString).boundingRect(with: CGSize(width: titleRect.width, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, attributes: [.font: UIFont.boldSystemFont(ofSize: titleSize)], context: nil).height <= titleRect.height else { throw PDFError.tooLong }
        return UIGraphicsPDFRenderer(bounds: page).pdfData { renderer in
            renderer.beginPage()
            (snapshot.title as NSString).draw(in: titleRect, withAttributes: [.font: UIFont.boldSystemFont(ofSize: titleSize), .foregroundColor: UIColor.black])
            (text as NSString).draw(in: bodyRect, withAttributes: attributes(size))
            if let photo = snapshot.photo { draw(photo, filling: photoRect, in: renderer.cgContext) }
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
    static func file(_ snapshot: SitterSnapshot) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(AppConfig.displayName)-sitter-sheet-\(UUID().uuidString.prefix(8)).pdf")
        try data(snapshot).write(to: url, options: .atomic)
        return url
    }
}

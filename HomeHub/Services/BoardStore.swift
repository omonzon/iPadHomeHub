import Foundation
import Combine

/// Chores and notes, saved as JSON in Application Support. No server, no
/// account — the hub is the source of truth and a backup is a file copy.
final class BoardStore: ObservableObject {
    @Published var chores: [Chore] = [] { didSet { save() } }
    @Published var notes: [StickyNote] = [] { didSet { save() } }

    private let fileURL: URL

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("board.json")
        load()
        resetRepeatingChores()
    }

    // MARK: - Chores

    func addChore(_ title: String, assignee: String, repeats: Chore.Repeat) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        chores.append(Chore(title: trimmed, assignee: assignee, repeats: repeats))
    }

    func toggleChore(_ chore: Chore) {
        guard let index = chores.firstIndex(where: { $0.id == chore.id }) else { return }
        chores[index].done.toggle()
    }

    func deleteChore(_ chore: Chore) {
        chores.removeAll { $0.id == chore.id }
    }

    /// Un-ticks daily/weekly chores once their period rolls over.
    func resetRepeatingChores() {
        let calendar = Calendar.current
        let now = Date()
        var changed = false

        for index in chores.indices where chores[index].repeats != .never {
            let last = chores[index].lastResetAt
            let due: Bool
            switch chores[index].repeats {
            case .daily:
                due = !calendar.isDate(last, inSameDayAs: now)
            case .weekly:
                due = !calendar.isDate(last, equalTo: now, toGranularity: .weekOfYear)
            case .never:
                due = false
            }
            if due {
                chores[index].done = false
                chores[index].lastResetAt = now
                changed = true
            }
        }
        if changed { save() }
    }

    // MARK: - Notes

    func addNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        notes.insert(StickyNote(text: trimmed, colorIndex: notes.count % 4), at: 0)
    }

    func deleteNote(_ note: StickyNote) {
        notes.removeAll { $0.id == note.id }
    }

    // MARK: - Persistence

    private struct Payload: Codable {
        var chores: [Chore]
        var notes: [StickyNote]
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return }
        chores = payload.chores
        notes = payload.notes
    }

    private func save() {
        let payload = Payload(chores: chores, notes: notes)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

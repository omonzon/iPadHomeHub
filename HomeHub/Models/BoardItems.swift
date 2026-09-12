import Foundation

struct Chore: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var assignee: String = ""
    var done: Bool = false
    var createdAt: Date = Date()
    /// Chores that repeat get un-ticked automatically at the start of the period.
    var repeats: Repeat = .never
    var lastResetAt: Date = .distantPast

    enum Repeat: String, Codable, CaseIterable, Identifiable {
        case never, daily, weekly
        var id: String { rawValue }
        var label: String {
            switch self {
            case .never: return "One-off"
            case .daily: return "Daily"
            case .weekly: return "Weekly"
            }
        }
    }
}

struct StickyNote: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var text: String
    var colorIndex: Int = 0
    var createdAt: Date = Date()
}

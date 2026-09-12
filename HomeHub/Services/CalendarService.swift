import Foundation
import EventKit
import SwiftUI
import UIKit

struct AgendaDay: Identifiable, Equatable {
    var id: Date { day }
    let day: Date
    let events: [AgendaEvent]
}

struct AgendaEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarColor: Color
    let location: String?
}

@MainActor
final class CalendarService: ObservableObject {
    @Published private(set) var events: [AgendaEvent] = []
    @Published private(set) var authorized = false
    @Published private(set) var denied = false

    private let store = EKEventStore()

    func requestAccessAndLoad(daysAhead: Int) async {
        let granted = await requestAccess()
        authorized = granted
        denied = !granted
        if granted { load(daysAhead: daysAhead) }
    }

    private func requestAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            return (try? await store.requestFullAccessToEvents()) ?? false
        } else {
            return await withCheckedContinuation { continuation in
                store.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func load(daysAhead: Int) {
        guard authorized else { return }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: max(1, daysAhead), to: start) else { return }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: predicate)
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
            .prefix(40)
            .map { event in
                AgendaEvent(id: event.eventIdentifier ?? UUID().uuidString,
                            title: event.title ?? "Untitled",
                            start: event.startDate ?? Date(),
                            end: event.endDate ?? Date(),
                            isAllDay: event.isAllDay,
                            calendarColor: Color(cgColor: event.calendar.cgColor ?? UIColor.systemBlue.cgColor),
                            location: event.location?.isEmpty == false ? event.location : nil)
            }
    }

    /// Events grouped by calendar day, so the agenda can show date headers.
    var grouped: [AgendaDay] {
        let calendar = Calendar.current
        let buckets = Dictionary(grouping: events) { calendar.startOfDay(for: $0.start) }
        return buckets.keys.sorted().map { AgendaDay(day: $0, events: buckets[$0] ?? []) }
    }
}

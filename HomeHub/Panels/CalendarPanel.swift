import SwiftUI

struct CalendarPanel: View {
    @ObservedObject var service: CalendarService

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PanelHeader(title: "Agenda",
                        systemImage: "calendar",
                        trailing: service.events.isEmpty ? nil : "\(service.events.count)")

            if service.denied {
                PanelPlaceholder(message: "Calendar access is off. Enable it in Settings › Privacy › Calendars › HomeHub.")
            } else if service.events.isEmpty {
                PanelPlaceholder(message: "Nothing scheduled.")
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(service.grouped) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(dayHeader(group.day))
                                    .font(.system(size: 13, weight: .semibold))
                                    .tracking(1.1)
                                    .foregroundColor(Theme.accent)

                                ForEach(group.events) { event in
                                    row(event)
                                }
                            }
                        }
                    }
                }
            }
        }
        .panel()
    }

    private func row(_ event: AgendaEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(event.calendarColor)
                .frame(width: 4)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Theme.primaryText)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(timeRange(event))
                        .foregroundColor(Theme.secondaryText)
                    if let location = event.location {
                        Text("· \(location)")
                            .foregroundColor(Theme.tertiaryText)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 13))
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func timeRange(_ event: AgendaEvent) -> String {
        if event.isAllDay { return "All day" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "\(formatter.string(from: event.start)) – \(formatter.string(from: event.end))"
    }

    private func dayHeader(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "TODAY" }
        if calendar.isDateInTomorrow(day) { return "TOMORROW" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMM"
        return formatter.string(from: day).uppercased()
    }
}

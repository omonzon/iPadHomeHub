import SwiftUI

struct ClockPanel: View {
    let use24Hour: Bool
    let showSeconds: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: showSeconds ? 1 : 30)) { context in
            VStack(alignment: .leading, spacing: 6) {
                Text(timeString(context.date))
                    .font(.system(size: 86, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(Theme.primaryText)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                Text(dateString(context.date))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Theme.secondaryText)
            }
        }
        .panel()
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        if use24Hour {
            formatter.dateFormat = showSeconds ? "HH:mm:ss" : "HH:mm"
        } else {
            formatter.dateFormat = showSeconds ? "h:mm:ss" : "h:mm"
        }
        return formatter.string(from: date)
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM"
        let base = formatter.string(from: date)
        if use24Hour { return base }

        let ampm = DateFormatter()
        ampm.dateFormat = "a"
        return "\(ampm.string(from: date))  ·  \(base)"
    }
}

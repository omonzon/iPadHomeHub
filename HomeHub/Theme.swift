import SwiftUI

/// Single place for the hub's look. Everything is dark-first: the iPad is
/// usually on a wall in a kitchen or hallway, and a bright white slab at
/// 6am is not what anyone wants.
enum Theme {
    static let background = Color(red: 0.05, green: 0.06, blue: 0.08)
    static let panel = Color(red: 0.11, green: 0.12, blue: 0.15)
    static let panelStroke = Color.white.opacity(0.07)
    static let accent = Color(red: 0.45, green: 0.72, blue: 1.0)
    static let warm = Color(red: 1.0, green: 0.72, blue: 0.35)
    static let good = Color(red: 0.44, green: 0.85, blue: 0.6)
    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.55)
    static let tertiaryText = Color.white.opacity(0.33)

    static let corner: CGFloat = 22
}

struct PanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .stroke(Theme.panelStroke, lineWidth: 1)
            )
    }
}

extension View {
    func panel() -> some View { modifier(PanelBackground()) }
}

struct PanelHeader: View {
    let title: String
    let systemImage: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.accent)
            Text(title.uppercased())
                .font(.system(size: 13, weight: .semibold))
                .tracking(1.4)
                .foregroundColor(Theme.secondaryText)
            Spacer()
            if let trailing = trailing {
                Text(trailing)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.tertiaryText)
            }
        }
    }
}

/// Small helper so panels can show "waiting on config" instead of an empty box.
struct PanelPlaceholder: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.system(size: 15))
            .foregroundColor(Theme.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
    }
}

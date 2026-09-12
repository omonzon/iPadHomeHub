import SwiftUI

struct NotesPanel: View {
    @EnvironmentObject private var board: BoardStore
    @State private var draft = ""

    private static let colors: [Color] = [
        Color(red: 1.0, green: 0.84, blue: 0.4),
        Color(red: 0.55, green: 0.85, blue: 1.0),
        Color(red: 0.72, green: 0.95, blue: 0.65),
        Color(red: 1.0, green: 0.66, blue: 0.72)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelHeader(title: "Notes", systemImage: "note.text")

            HStack(spacing: 10) {
                TextField("Leave a note…", text: $draft, onCommit: submit)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundColor(Theme.primaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )

                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(draft.isEmpty ? Theme.tertiaryText : Theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if board.notes.isEmpty {
                PanelPlaceholder(message: "No notes on the board.")
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(board.notes) { note in
                            noteCard(note)
                        }
                    }
                }
            }
        }
        .panel()
    }

    private func noteCard(_ note: StickyNote) -> some View {
        let tint = Self.colors[note.colorIndex % Self.colors.count]
        return VStack(alignment: .leading, spacing: 8) {
            Text(note.text)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text(note.createdAt, style: .date)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.tertiaryText)
                Spacer()
                Button {
                    board.deleteNote(note)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.3), lineWidth: 1)
        )
    }

    private func submit() {
        board.addNote(draft)
        draft = ""
    }
}

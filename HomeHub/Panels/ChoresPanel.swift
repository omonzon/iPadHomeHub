import SwiftUI

struct ChoresPanel: View {
    @EnvironmentObject private var board: BoardStore
    @State private var draft = ""
    @State private var assignee = ""
    @State private var repeats: Chore.Repeat = .never
    @State private var showAdd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                PanelHeader(title: "Chores",
                            systemImage: "checklist",
                            trailing: "\(remaining) left")
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Theme.accent)
                }
                .buttonStyle(.plain)
            }

            if board.chores.isEmpty {
                PanelPlaceholder(message: "Nothing on the list. Tap + to add one.")
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(board.chores) { chore in
                            row(chore)
                        }
                    }
                }
            }
        }
        .panel()
        .sheet(isPresented: $showAdd) {
            addSheet
        }
    }

    private var remaining: Int { board.chores.filter { !$0.done }.count }

    private func row(_ chore: Chore) -> some View {
        HStack(spacing: 12) {
            Button {
                board.toggleChore(chore)
            } label: {
                Image(systemName: chore.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(chore.done ? Theme.good : Theme.tertiaryText)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(chore.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(chore.done ? Theme.tertiaryText : Theme.primaryText)
                    .strikethrough(chore.done, color: Theme.tertiaryText)
                    .lineLimit(2)

                if !chore.assignee.isEmpty || chore.repeats != .never {
                    HStack(spacing: 6) {
                        if !chore.assignee.isEmpty {
                            Text(chore.assignee)
                        }
                        if chore.repeats != .never {
                            Text("· \(chore.repeats.label)")
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.accent.opacity(0.8))
                }
            }

            Spacer(minLength: 0)

            Button {
                board.deleteChore(chore)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.tertiaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private var addSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("Chore")) {
                    TextField("What needs doing?", text: $draft)
                    TextField("Who? (optional)", text: $assignee)
                    Picker("Repeats", selection: $repeats) {
                        ForEach(Chore.Repeat.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                }
            }
            .navigationTitle("New chore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { reset() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        board.addChore(draft, assignee: assignee, repeats: repeats)
                        reset()
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func reset() {
        draft = ""
        assignee = ""
        repeats = .never
        showAdd = false
    }
}

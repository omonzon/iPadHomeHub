import SwiftUI

/// Full-screen ask-anything panel backed by Gemini. It gets a short summary of
/// what is on the hub right now (weather, agenda, chores) so household
/// questions — "what should I wear?", "am I free Thursday?" — actually work.
@MainActor
struct AssistantView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var board: BoardStore
    @Environment(\.presentationMode) private var presentationMode

    let contextSummary: String

    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    private let suggestions = [
        "What should we have for dinner tonight?",
        "Summarise what's on today.",
        "Do I need a jacket?",
        "Give the kids a 10-minute science experiment."
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Theme.panelStroke)

            if messages.isEmpty {
                emptyState
            } else {
                transcript
            }

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.system(size: 14))
                    .foregroundColor(.red.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.top, 8)
            }

            composer
        }
        .background(Theme.background.ignoresSafeArea())
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 22))
                .foregroundColor(Theme.warm)
            VStack(alignment: .leading, spacing: 2) {
                Text("Assistant")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Theme.primaryText)
                Text(settings.settings.geminiModel)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.tertiaryText)
            }
            Spacer()
            if !messages.isEmpty {
                Button("Clear") { messages = []; errorMessage = nil }
                    .foregroundColor(Theme.secondaryText)
            }
            Button {
                presentationMode.wrappedValue.dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(Theme.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    private var emptyState: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 46))
                .foregroundColor(Theme.tertiaryText)
            Text(settings.assistantConfigured
                 ? "Ask anything."
                 : "Add a Gemini API key in Settings to use the assistant.")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(Theme.secondaryText)

            if settings.assistantConfigured {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            draft = suggestion
                            send()
                        } label: {
                            Text(suggestion)
                                .font(.system(size: 15))
                                .foregroundColor(Theme.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.white.opacity(0.05))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 700)
            }
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(messages) { message in
                        bubble(message).id(message.id)
                    }
                    if isSending {
                        HStack(spacing: 10) {
                            ProgressView().tint(Theme.secondaryText)
                            Text("Thinking…")
                                .font(.system(size: 15))
                                .foregroundColor(Theme.tertiaryText)
                        }
                        .id("thinking")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .onChange(of: messages.count) { _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
    }

    private func bubble(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message.role == .user ? "You" : "Gemini")
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.1)
                .foregroundColor(message.role == .user ? Theme.accent : Theme.warm)
            Text(message.text)
                .font(.system(size: 17))
                .foregroundColor(Theme.primaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 820, alignment: .leading)
    }

    private var composer: some View {
        HStack(spacing: 12) {
            TextField("Ask anything…", text: $draft, onCommit: send)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .foregroundColor(Theme.primaryText)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .disabled(!settings.assistantConfigured || isSending)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundColor(canSend ? Theme.accent : Theme.tertiaryText)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    private var canSend: Bool {
        settings.assistantConfigured
            && !isSending
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, settings.assistantConfigured, !isSending else { return }

        draft = ""
        errorMessage = nil
        messages.append(ChatMessage(role: .user, text: text))
        isSending = true

        let client = GeminiClient(apiKey: settings.geminiAPIKey,
                                  model: settings.settings.geminiModel)
        let history = messages
        let prompt = systemPrompt

        Task {
            do {
                let reply = try await client.send(history: history, systemPrompt: prompt)
                messages.append(ChatMessage(role: .model, text: reply))
            } catch {
                errorMessage = error.localizedDescription
            }
            isSending = false
        }
    }

    private var systemPrompt: String {
        var lines = [
            "You are the assistant on a family home hub tablet mounted in a shared room.",
            "Answer briefly and practically. Prefer short paragraphs or tight bullet lists.",
            "Do not use markdown headers or tables; the display renders plain text.",
            "",
            "Current context:"
        ]
        lines.append(contextSummary)

        let openChores = board.chores.filter { !$0.done }.map(\.title)
        if !openChores.isEmpty {
            lines.append("Open chores: " + openChores.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }
}

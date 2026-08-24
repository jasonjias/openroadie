import SwiftUI

/// Talk to Roadie — the on-device AI with tools over the drive.
struct AskView: View {
    let agent: RoadieAgent

    @State private var input = ""
    @State private var speech = SpeechRecognizer()
    @State private var speaker = SpeechSpeaker()
    @FocusState private var inputFocused: Bool

    private static let suggestions = [
        "Where am I?",
        "How fast am I going?",
        "What's the speed limit here?",
        "Any chargers nearby?",
        "Find me coffee",
        "How long have I been driving?",
        "Tell me about my recent trips",
    ]

    var body: some View {
        NavigationStack {
            Group {
                switch agent.state {
                case .checking:
                    ProgressView("Checking the on-device model…")
                case .unavailable(let why):
                    ContentUnavailableView {
                        Label("Roadie can't think yet", systemImage: "sparkles")
                    } description: {
                        Text(why)
                    } actions: {
                        Button("Check Again") { agent.start() }
                    }
                case .ready:
                    chat
                }
            }
            .navigationTitle("Roadie")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { agent.start() }
        .onAppear {
            // Spoken questions get spoken answers; typed ones stay silent.
            speech.onFinalTranscript = { question in
                input = ""
                Task {
                    if let reply = await agent.ask(question) {
                        speaker.speak(reply)
                    }
                }
            }
        }
        .onChange(of: speech.transcript) { _, transcript in
            if speech.isListening { input = transcript }
        }
    }

    private var chat: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if agent.messages.isEmpty {
                            emptyState
                        }
                        ForEach(agent.messages) { message in
                            bubble(for: message)
                                .id(message.id)
                        }
                        if agent.isThinking {
                            HStack {
                                ProgressView()
                                Text("Roadie is thinking…")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: agent.messages) { _, messages in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            inputBar
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .padding(.top, 30)
            Text("Ask about the drive")
                .font(.headline)
            Text("Everything runs on this iPhone. Your questions and your driving data never leave it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            FlowingChips(items: Self.suggestions) { suggestion in
                send(suggestion)
            }
            .padding(.horizontal)
            .padding(.top, 6)
        }
    }

    private func bubble(for message: RoadieAgent.Message) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    message.role == .user
                        ? AnyShapeStyle(.tint)
                        : AnyShapeStyle(.fill.secondary),
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .foregroundStyle(message.role == .user ? .white : .primary)
            if message.role == .roadie { Spacer(minLength: 40) }
        }
        .padding(.horizontal)
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            if speech.state == .denied {
                Text("Microphone or speech permission is off — enable both in Settings to talk to Roadie.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if speech.state == .unavailable {
                Text("On-device speech recognition isn't available right now.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button {
                    speaker.stop()
                    Task { await speech.toggle() }
                } label: {
                    Image(systemName: speech.isListening ? "waveform" : "mic.fill")
                        .symbolEffect(.variableColor.iterative, isActive: speech.isListening)
                        .font(.system(size: 21))
                        .foregroundStyle(speech.isListening ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
                        .frame(width: 34, height: 34)
                }
                TextField(speech.isListening ? "Listening…" : "Ask Roadie…", text: $input)
                    .textFieldStyle(.plain)
                    .focused($inputFocused)
                    .onSubmit { send(input) }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.fill.secondary, in: Capsule())
                Button {
                    send(input)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                }
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || agent.isThinking || speech.isListening)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        input = ""
        Task { await agent.ask(question) }
    }
}

/// Suggestion chips that wrap onto multiple lines.
private struct FlowingChips: View {
    let items: [String]
    let action: (String) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { item in
                        Button {
                            action(item)
                        } label: {
                            Text(item)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(.fill.secondary, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Two chips per row keeps everything tappable without measuring text.
    private var rows: [[String]] {
        stride(from: 0, to: items.count, by: 2).map {
            Array(items[$0..<min($0 + 2, items.count)])
        }
    }
}

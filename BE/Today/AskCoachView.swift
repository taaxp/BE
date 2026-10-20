import SwiftUI
import BECore

/// Greeting and BE score, the first widget on Home.
struct GreetingCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let g = model.greeting
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(g.hello).font(.largeTitle.weight(.bold))
                Text(g.line).font(.largeTitle.weight(.bold)).foregroundStyle(.secondary)
            }
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.08), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: Double(g.score) / 100)
                        .stroke(Theme.brand.gradient, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(duration: 1), value: g.score)
                    Text("\(g.score)").font(.metric(.title3)).contentTransition(.numericText())
                }
                .frame(width: 62, height: 62)
                Text("\(Text("BE score \(g.score). ").bold())\(Text(g.reason).foregroundStyle(.secondary))")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .widgetCard()
        }
        .accessibilityElement(children: .combine)
    }
}

/// The Ask coach entry on Home: a field and suggestion chips that open the chat.
struct AskCoachCard: View {
    @Environment(AppModel.self) private var model
    @Binding var openWith: String?
    @Binding var isOpen: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Ask your coach", systemImage: "sparkles").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.brand)
                Spacer()
                Text(engineLabel).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            Button {
                openWith = nil
                isOpen = true
            } label: {
                HStack {
                    Text("Ask anything about your health…").foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "arrow.up.circle.fill").font(.title2).foregroundStyle(.primary)
                }
                .padding(12)
                .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(CoachChat.suggestions, id: \.self) { s in
                        Button(s) { openWith = s; isOpen = true }
                            .font(.footnote.weight(.medium))
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                    }
                }
            }
        }
        .widgetCard()
    }

    private var engineLabel: String {
        switch model.chat.engine(model) {
        case .onDevice: "Apple Intelligence"
        case .cloud: "ChatGPT"
        case .offline: "Built-in coach"
        }
    }
}

/// The chat itself.
struct AskCoachView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var initialQuestion: String?
    @State private var draft = ""
    @State private var showConsent = false

    var body: some View {
        let chat = model.chat
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(chat.messages) { m in bubble(m).id(m.id) }
                            if chat.busy {
                                ProgressView().padding(.leading, 6).id("busy")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: chat.messages.count) {
                        withAnimation { proxy.scrollTo(chat.messages.last?.id, anchor: .bottom) }
                    }
                }
                if chat.engine(model) == .offline && !model.coach.isOnDeviceAvailable && !model.state.cloudCoachConsent {
                    Button("Use ChatGPT for smarter answers") { showConsent = true }
                        .font(.footnote.weight(.semibold))
                        .padding(.bottom, 6)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(CoachChat.suggestions, id: \.self) { s in
                            Button(s) { ask(s) }.font(.footnote).buttonStyle(.bordered).buttonBorderShape(.capsule)
                        }
                    }
                    .padding(.horizontal)
                }
                HStack(spacing: 8) {
                    TextField("Ask about your health…", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 20, style: .continuous))
                        .onSubmit { ask(draft) }
                    Button { ask(draft) } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 34))
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || chat.busy)
                    .accessibilityLabel("Send")
                }
                .padding()
                Text("General wellness information, not medical advice.")
                    .font(.caption2).foregroundStyle(.secondary).padding(.bottom, 6)
            }
            .navigationTitle("Ask your coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("New chat", systemImage: "square.and.pencil") { chat.reset(); chat.start(model) } }
            }
            .sheet(isPresented: $showConsent) { CoachConsentView { granted in model.setCloudCoachConsent(granted); showConsent = false } }
            .task {
                chat.start(model)
                if let q = initialQuestion { ask(q) }
            }
        }
    }

    private func ask(_ q: String) {
        let text = q
        draft = ""
        Task { await model.chat.send(text, model: model) }
    }

    @ViewBuilder private func bubble(_ m: CoachChat.Message) -> some View {
        if m.role == .me {
            HStack { Spacer(minLength: 40); Text(m.text).padding(12).foregroundStyle(Color(.systemBackground)).background(Color.primary, in: .rect(cornerRadius: 20, style: .continuous)) }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(m.text)
                if let insights = m.insights {
                    ForEach(insights) { i in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(i.title).font(.headline)
                            Text(i.detail).font(.subheadline)
                            Text("\(Text("Today: ").bold().foregroundStyle(Theme.brand))\(i.action)").font(.footnote)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16, style: .continuous))
                    }
                }
                if let s = m.source { Text(s).font(.caption2).foregroundStyle(.secondary) }
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20, style: .continuous))
            .padding(.trailing, m.insights == nil ? 40 : 0)
        }
    }
}

/// Explicit consent before any health summary is sent off the device.
struct CoachConsentView: View {
    var onDecision: (Bool) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "bubble.left.and.text.bubble.right").font(.system(size: 40)).foregroundStyle(Theme.brand)
                    Text("Use ChatGPT for coach answers?").font(.title2.weight(.bold))
                    Text("Apple Intelligence isn't available on this iPhone, so BE can use ChatGPT instead.").foregroundStyle(.secondary)
                    point("doc.text", "What's sent", "Your question and a summary of your numbers: daily totals, averages, your normal ranges, targets, and age, height, weight and sex if set in Apple Health. Never your name or raw Health records.")
                    point("server.rack", "Where it goes", "To BE's relay, then to OpenAI. This happens outside Australia, in the United States.")
                    point("trash", "What's kept", "BE's relay doesn't store your questions or data.")
                    point("switch.2", "Your choice", "Turn this off any time in Settings. Without it, BE's built-in coach still answers.")
                }
                .padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button { onDecision(true) } label: { Text("Allow").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.brand)
                    Button("Not now") { onDecision(false) }
                }
                .padding()
                .background(.bar)
            }
        }
    }

    private func point(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).frame(width: 28).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

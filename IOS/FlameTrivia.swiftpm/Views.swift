import SwiftUI

// MARK: - Theme

enum Theme {
    static let accent = Color(red: 0.91, green: 0.54, blue: 0.05)      // sodium flame
    static let good = Color(red: 0.12, green: 0.54, blue: 0.36)
    static let bad = Color(red: 0.76, green: 0.23, blue: 0.23)
    static let paper = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.055, green: 0.106, blue: 0.153, alpha: 1)
        : UIColor(red: 0.953, green: 0.965, blue: 0.973, alpha: 1) })
    static let grid = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.09, green: 0.165, blue: 0.227, alpha: 1)
        : UIColor(red: 0.859, green: 0.894, blue: 0.918, alpha: 1) })
    static let card = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.075, green: 0.141, blue: 0.2, alpha: 1) : .white })
    static let line = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.141, green: 0.224, blue: 0.294, alpha: 1)
        : UIColor(red: 0.788, green: 0.839, blue: 0.875, alpha: 1) })

    static func label(_ s: String) -> some View {
        Text(s.uppercased()).font(.system(size: 11, weight: .medium, design: .monospaced))
            .tracking(0.8).foregroundStyle(.secondary)
    }
}

struct GraphPaper: View {
    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            stride(from: 0, through: size.width, by: 24).forEach { x in p.move(to: .init(x: x, y: 0)); p.addLine(to: .init(x: x, y: size.height)) }
            stride(from: 0, through: size.height, by: 24).forEach { y in p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: size.width, y: y)) }
            ctx.stroke(p, with: .color(Theme.grid), lineWidth: 1)
        }
        .background(Theme.paper)
        .ignoresSafeArea()
    }
}

struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
    }
}

struct PrimaryButton: ButtonStyle {
    var enabled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.vertical, 12).padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(Theme.accent.opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.4),
                        in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject var game: Game
    @EnvironmentObject var store: ScoreStore
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                GraphPaper()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        StatsStrip(totals: store.totals)
                        switch game.phase {
                        case .setup: SetupView()
                        case .loading: LoadingView()
                        case .play: QuestionView()
                        case let .summary(correct, total, points, subject, level):
                            SummaryView(correct: correct, total: total, points: points, subject: subject, level: level)
                        }
                        HistoryView(history: store.history)
                    }
                    .padding(16)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
        .tint(Theme.accent)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            (Text("Flame Test ") + Text("Trivia").foregroundColor(Theme.accent))
                .font(.system(size: 34, weight: .heavy, design: .rounded))
            Theme.label("Pick a subject and difficulty · answers revealed after you guess")
        }
    }
}

struct StatsStrip: View {
    let totals: Totals
    var body: some View {
        let cells: [(String, String)] = [
            ("\(totals.points)", "Total points"),
            ("\(totals.correct)/\(totals.answered)", "Correct"),
            (totals.accuracy.map { "\($0)%" } ?? "—", "Accuracy"),
            ("\(totals.rounds) · \(totals.bestStreak)", "Rounds · streak")
        ]
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 1) {
            ForEach(cells.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    Text(cells[i].0).font(.system(size: 22, weight: .medium, design: .monospaced))
                        .foregroundStyle(i == 0 ? Theme.accent : .primary)
                        .monospacedDigit()
                    Theme.label(cells[i].1)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card)
            }
        }
        .background(Theme.line)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line))
    }
}

// MARK: - Setup

struct SetupView: View {
    @EnvironmentObject var game: Game
    @FocusState private var focused: Bool
    private let ideas = ["Astronomy", "Aviation weather", "Chemistry", "Human anatomy", "Geology", "Physics", "Computer science", "Oceanography"]

    var body: some View {
        Panel {
            Text("Start a round").font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Theme.label("Subject")
                TextField("e.g. Volcanoes, Jet engines, Genetics", text: $game.subject)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.go)
                    .focused($focused)
                    .onSubmit { game.start() }
                    .padding(12)
                    .background(Theme.paper, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(focused ? Theme.accent : Theme.line))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(ideas, id: \.self) { idea in
                            Button(idea) { game.subject = idea }
                                .font(.footnote)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .overlay(Capsule().strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [3])))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Theme.label("Difficulty · points per correct answer")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Level.allCases) { lv in
                        Button { game.level = lv } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lv.name).font(.body.weight(.semibold))
                                Text("\(lv.points) pt\(lv.points > 1 ? "s" : "")")
                                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(game.level == lv ? Theme.accent : Theme.line, lineWidth: game.level == lv ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Theme.label("Questions")
                Picker("Questions", selection: $game.count) {
                    Text("5").tag(5); Text("10").tag(10); Text("15").tag(15)
                }
                .pickerStyle(.segmented)
            }

            Button("Start round") { focused = false; game.start() }
                .buttonStyle(PrimaryButton())

            if let err = game.errorText {
                Text(err).font(.callout).foregroundStyle(Theme.bad)
            }
        }
    }
}

// MARK: - Loading

struct LoadingView: View {
    @EnvironmentObject var game: Game
    @State private var flicker = false

    var body: some View {
        Panel {
            VStack(spacing: 14) {
                Capsule()
                    .fill(LinearGradient(colors: [Theme.accent, Color(red: 1, green: 0.82, blue: 0.48)],
                                         startPoint: .bottom, endPoint: .top))
                    .frame(width: 18, height: 46)
                    .scaleEffect(y: flicker ? 1.08 : 0.88, anchor: .bottom)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: flicker)
                    .onAppear { flicker = true }
                Text("Writing \(game.count) \(game.level.name.lowercased()) questions").font(.headline)
                Theme.label(game.subject)
                Text(game.progress).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text("\(game.elapsed) s").font(.caption.monospaced()).foregroundStyle(.secondary)
                Button("Stop") { game.stop() }.buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Question

struct QuestionView: View {
    @EnvironmentObject var game: Game
    private let letters = ["A", "B", "C", "D"]

    var body: some View {
        if let r = game.round, r.current < r.questions.count {
            let q = r.questions[r.current]
            let ans = r.answers[r.current]
            Panel {
                ProgressBar(round: r)

                HStack(alignment: .top, spacing: 16) {
                    ElementTile(number: r.current + 1, points: r.level.points, symbol: q.symbol, category: q.category)
                    VStack(alignment: .leading, spacing: 6) {
                        Theme.label("\(r.subject) · \(r.level.name) · \(r.current + 1) of \(r.expectedCount)")
                        Text(q.text).font(.system(size: 21, weight: .medium, design: .rounded))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(spacing: 10) {
                    ForEach(q.choices.indices, id: \.self) { i in
                        ChoiceRow(letter: letters[i], text: q.choices[i],
                                  state: ans == nil ? .open : (i == q.answer ? .right : (i == ans?.choice ? .wrong : .dim)))
                        { game.choose(i) }
                    }
                }

                if let ans {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ans.correct ? "CORRECT · +\(r.level.points) PTS" : "NOT QUITE · ANSWER IS \(letters[q.answer])")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(ans.correct ? Theme.good : Theme.bad)
                        if !q.explanation.isEmpty {
                            Text(q.explanation).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.accent).frame(width: 3) }

                    let last = r.current >= r.questions.count - 1
                    Button(last ? (r.doneWriting ? "Finish round" : "Next question is being written…") : "Next question →") {
                        game.next()
                    }
                    .buttonStyle(PrimaryButton(enabled: game.canAdvance))
                    .disabled(!game.canAdvance)
                }
            }
        }
    }
}

struct ProgressBar: View {
    let round: Round
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<round.expectedCount, id: \.self) { i in
                let a = round.answers[i]
                RoundedRectangle(cornerRadius: 2)
                    .fill(a.map { $0.correct ? Theme.good : Theme.bad } ?? (i == round.current ? Theme.accent : (i < round.questions.count ? Theme.line : Color.clear)))
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(i >= round.questions.count ? Theme.line : .clear, style: StrokeStyle(lineWidth: 1, dash: [2])))
                    .frame(height: 8)
            }
        }
    }
}

struct ElementTile: View {
    let number: Int, points: Int, symbol: String, category: String
    var body: some View {
        VStack(alignment: .leading) {
            HStack { Text("\(number)"); Spacer(); Text("\(points)") }
                .font(.caption.monospaced())
            Spacer(minLength: 0)
            Text(symbol).font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(Theme.accent)
                .lineLimit(1).minimumScaleFactor(0.5)
            Spacer(minLength: 0)
            Text(category.uppercased()).font(.system(size: 8.5, design: .monospaced)).foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(6)
        .frame(width: 78, height: 78)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary, lineWidth: 2))
    }
}

struct ChoiceRow: View {
    enum ChoiceState { case open, right, wrong, dim }
    let letter: String, text: String, state: ChoiceState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(letter).font(.callout.monospaced().weight(.medium))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(state == .right || state == .wrong ? Color.white : Color.primary)
                    .background(Circle().fill(state == .right ? Theme.good : state == .wrong ? Theme.bad : Color.clear))
                    .overlay(Circle().stroke(state == .right ? Theme.good : state == .wrong ? Theme.bad : Theme.line))
                Text(text).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(fill, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(border))
            .opacity(state == .dim ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(state != .open)
    }

    private var fill: Color {
        switch state {
        case .right: return Theme.good.opacity(0.15)
        case .wrong: return Theme.bad.opacity(0.15)
        default: return Theme.paper
        }
    }
    private var border: Color {
        switch state {
        case .right: return Theme.good
        case .wrong: return Theme.bad
        default: return Theme.line
        }
    }
}

// MARK: - Summary & history

struct SummaryView: View {
    @EnvironmentObject var game: Game
    @EnvironmentObject var store: ScoreStore
    let correct: Int, total: Int, points: Int, subject: String, level: Level

    var body: some View {
        Panel {
            VStack(spacing: 8) {
                Theme.label("\(subject) · \(level.name)")
                Text("\(correct)/\(total)").font(.system(size: 56, weight: .heavy, design: .rounded)).foregroundStyle(Theme.accent)
                Text("+\(points) points this round · \(store.totals.points) total")
                Button("New round") { game.newRound() }.buttonStyle(PrimaryButton()).padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct HistoryView: View {
    let history: [RoundSummary]
    var body: some View {
        if !history.isEmpty {
            Panel {
                Text("Past rounds").font(.title3.weight(.semibold))
                VStack(spacing: 0) {
                    ForEach(history.prefix(40)) { h in
                        HStack(alignment: .firstTextBaseline) {
                            Text(h.subject).lineLimit(1)
                            Spacer()
                            Text(h.level.name.uppercased()).font(.caption.monospaced()).foregroundStyle(.secondary)
                            Text("\(h.correct)/\(h.total) · \(h.points) pts").font(.callout.monospaced()).monospacedDigit()
                        }
                        .padding(.vertical, 8)
                        Divider()
                    }
                }
            }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var store: ScoreStore
    @Environment(\.dismiss) private var dismiss
    @State private var key = Keychain.read() ?? ""
    @State private var model = ""
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-…", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: { Text("Anthropic API key") } footer: {
                    Text("Create one at platform.claude.com → Settings → API keys. Stored only in this iPhone's Keychain. Each round costs a few cents of API credit.")
                }
                Section {
                    TextField("claude-sonnet-5-5", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: { Text("Model") } footer: {
                    Text("Leave as claude-sonnet-5-5 unless you want a different model.")
                }
                Section {
                    Button("Erase all scores", role: .destructive) { confirmReset = true }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Keychain.write(key.trimmingCharacters(in: .whitespacesAndNewlines))
                        store.setModel(model.isEmpty ? "claude-sonnet-5-5" : model)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .confirmationDialog("Erase your cumulative score and history?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Erase", role: .destructive) { store.resetScores() }
            }
            .onAppear { model = store.file.model }
        }
    }
}

import Foundation
import SwiftUI

@MainActor
final class Game: ObservableObject {
    enum Phase: Equatable {
        case setup
        case loading
        case play
        case summary(correct: Int, total: Int, points: Int, subject: String, level: Level)
    }

    @Published var phase: Phase = .setup
    @Published var round: Round?
    @Published var subject = ""
    @Published var level: Level = .medium
    @Published var count = 10
    @Published var progress = ""
    @Published var errorText: String?
    @Published var elapsed = 0

    let store: ScoreStore
    private var genTask: Task<Void, Never>?
    private var ticker: Task<Void, Never>?

    init(store: ScoreStore) {
        self.store = store
        if let saved = store.file.round, !saved.questions.isEmpty {
            var r = saved
            r.doneWriting = true
            r.expected = r.questions.count
            round = r
            phase = .play
        }
    }

    // MARK: Start a round

    func start() {
        let subject = self.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.isEmpty else { errorText = "Type a subject to start."; return }
        guard let key = Keychain.read(), !key.isEmpty else { errorText = GenError.noKey.errorDescription; return }

        errorText = nil
        progress = "Waiting for Claude… usually 10–40 seconds"
        elapsed = 0
        phase = .loading
        startTicker()

        let level = self.level, count = self.count
        let prior = store.seen(for: subject)
        let prompt = Generator.prompt(subject: subject, level: level, count: min(count + 5, 20),
                                      seen: prior, calibration: store.calibration(subject: subject, level: level))
        let model = store.file.model

        genTask = Task { [weak self] in
            guard let self else { return }
            var seenObjects = 0
            var dupSkips = 0
            var built: Round?
            do {
                for try await text in Generator.stream(apiKey: key, model: model, prompt: prompt) {
                    if Task.isCancelled { break }
                    let objs = Generator.extractObjects(text)
                    let written = text.components(separatedBy: "\"q\"").count - 1
                    if built == nil { self.progress = written > 0 ? "\(min(written, count)) of \(count) written" : "Writing…" }

                    while seenObjects < objs.count {
                        defer { seenObjects += 1 }
                        guard let obj = objs[seenObjects],
                              let q = Generator.question(from: obj, subject: subject) else { continue }
                        if let fb = level.fanBand, let f = q.fanPercent {
                            if f < fb.lowerBound - 5 || f > fb.upperBound + 5 { continue }
                        } else if let p = q.estimatedPercent, p < level.band.lowerBound - 5 || p > level.band.upperBound + 5 {
                            continue
                        }
                        if Repeats.givesAway(q) { continue }
                        let pool = prior + (built?.questions.map(\.seenLine) ?? [])
                        if Repeats.isDuplicate(q, of: pool) { dupSkips += 1; continue }

                        if built == nil {
                            built = Round(subject: subject, level: level, questions: [q], expected: count)
                            self.round = built
                            self.phase = .play
                            self.stopTicker()
                            self.store.setRound(built)
                        } else if var r = built, r.questions.count < count {
                            r.questions.append(q)
                            built = r
                            self.round?.questions.append(q)
                        }
                    }
                    if Generator.isClosed(text) { break }
                }
                self.finishWriting(dupSkips: dupSkips)
            } catch {
                if self.round != nil { self.finishWriting(dupSkips: dupSkips); return }
                self.stopTicker()
                if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                    self.phase = .setup
                } else {
                    self.errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.phase = .setup
                }
            }
        }
    }

    private func finishWriting(dupSkips: Int) {
        stopTicker()
        guard round != nil else {
            errorText = (dupSkips > 0 ? GenError.allRepeats : GenError.nothingUsable).errorDescription
            phase = .setup
            return
        }
        round?.doneWriting = true
        round?.expected = round?.questions.count ?? 0
        store.setRound(round)
    }

    func stop() {
        genTask?.cancel()
        stopTicker()
        phase = .setup
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.elapsed += 1
                if self.elapsed == 60 { self.progress = "Still waiting on Claude after a minute. Check your connection, or tap Stop and try again." }
                if self.elapsed >= 180 { self.genTask?.cancel(); self.errorText = "Claude took longer than 3 minutes. Try again, or pick fewer questions."; self.phase = .setup; return }
            }
        }
    }

    private func stopTicker() { ticker?.cancel(); ticker = nil }

    // MARK: Playing

    func choose(_ index: Int) {
        guard var r = round, r.answers[r.current] == nil, r.current < r.questions.count else { return }
        let q = r.questions[r.current]
        let ok = index == q.answer
        r.answers[r.current] = Answer(choice: index, correct: ok)
        round = r
        store.add(AnswerRecord(roundID: r.id, subject: r.subject, key: Repeats.subjectKey(r.subject),
                               level: r.level, line: q.seenLine, correct: ok,
                               points: ok ? r.level.points : 0, at: Date()))
        store.setRound(r)
    }

    var canAdvance: Bool {
        guard let r = round else { return false }
        return r.current < r.questions.count - 1 || r.doneWriting
    }

    func next() {
        guard var r = round else { return }
        if r.current < r.questions.count - 1 {
            r.current += 1
            round = r
            store.setRound(r)
            return
        }
        guard r.doneWriting else { return }
        let answered = r.answers.values
        let correct = answered.filter(\.correct).count
        phase = .summary(correct: correct, total: answered.count, points: correct * r.level.points,
                         subject: r.subject, level: r.level)
        round = nil
        store.setRound(nil)
    }

    /// Back to a clean setup screen after a round.
    func newRound() {
        subject = ""
        level = .medium
        count = 10
        errorText = nil
        phase = .setup
    }
}

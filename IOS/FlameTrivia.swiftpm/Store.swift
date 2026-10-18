import Foundation
import Security

/// Everything the app saves, kept as one JSON file in the app's Documents folder.
/// Totals, history and the repeat list are all computed from `records`.
struct SaveFile: Codable {
    var records: [AnswerRecord] = []
    var resetAt: Date?
    var round: Round?
    var model: String = "claude-sonnet-5-5"
}

@MainActor
final class ScoreStore: ObservableObject {
    @Published private(set) var file = SaveFile()

    private let url: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("flame-test-trivia.json")
    }()

    init() { load() }

    // MARK: Disk

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let f = try? dec.decode(SaveFile.self, from: data) { file = f }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(file) { try? data.write(to: url, options: .atomic) }
    }

    // MARK: Changes

    func add(_ record: AnswerRecord) { file.records.append(record); save() }
    func setRound(_ round: Round?) { file.round = round; save() }
    func setModel(_ model: String) { file.model = model.trimmingCharacters(in: .whitespaces); save() }
    func resetScores() { file.resetAt = Date(); file.round = nil; save() }

    // MARK: Derived values

    var activeRecords: [AnswerRecord] {
        let r = file.records.sorted { $0.at < $1.at }
        guard let reset = file.resetAt else { return r }
        return r.filter { $0.at > reset }
    }

    var totals: Totals {
        var t = Totals()
        var run = 0
        for r in activeRecords {
            t.answered += 1
            if r.correct { t.correct += 1; t.points += r.points; run += 1; t.bestStreak = max(t.bestStreak, run) }
            else { run = 0 }
        }
        t.rounds = Set(activeRecords.map(\.roundID)).count
        return t
    }

    var history: [RoundSummary] {
        var byRound: [UUID: RoundSummary] = [:]
        for r in activeRecords {
            var s = byRound[r.roundID] ?? RoundSummary(id: r.roundID, subject: r.subject, level: r.level,
                                                       correct: 0, total: 0, points: 0, at: r.at)
            s.total += 1
            if r.correct { s.correct += 1; s.points += r.points }
            s.at = r.at
            byRound[r.roundID] = s
        }
        return byRound.values.sorted { $0.at > $1.at }
    }

    func seen(for subject: String) -> [String] {
        let key = Repeats.subjectKey(subject)
        return activeRecords.filter { Repeats.subjectKey($0.subject) == key }.map(\.line)
    }

    /// This player's recent results at a level, used to steer difficulty.
    func calibration(subject: String, level: Level) -> String {
        // Same subject only: doing well on Disney says nothing about History.
        let key = Repeats.subjectKey(subject)
        let recs = Array(activeRecords.filter { $0.level == level && Repeats.subjectKey($0.subject) == key }.suffix(30))
        let scope = "on this subject"
        guard recs.count >= 8 else { return "" }
        let pct = Int((Double(recs.filter(\.correct).count) / Double(recs.count) * 100).rounded())
        let got = recs.filter(\.correct).suffix(5).map { "  + " + $0.line }.joined(separator: "\n")
        let missed = recs.filter { !$0.correct }.suffix(5).map { "  - " + $0.line }.joined(separator: "\n")
        let verdict: String
        if pct > level.target + 12 {
            verdict = "a little easy for this player — make these slightly harder, while still passing the \(level.name) level test"
        } else if pct < level.target - 12 {
            verdict = "too hard for this player — make these noticeably easier"
        } else {
            verdict = "about right — keep the same difficulty"
        }
        return """
        Calibration from this player's own results at \(level.name) \(scope): \(pct)% correct over \(recs.count) questions (target \(level.target)%). That was \(verdict).
        Recent ones they got right:
        \(got.isEmpty ? "  (none)" : got)
        Recent ones they missed:
        \(missed.isEmpty ? "  (none)" : missed)

        """
    }
}

// MARK: - API key in the iOS Keychain

enum Keychain {
    private static let service = "com.linearair.flametesttrivia"
    private static let account = "anthropic-api-key"

    static func read() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ key: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard !key.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(key.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}

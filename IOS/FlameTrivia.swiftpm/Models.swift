import Foundation

// MARK: - Difficulty levels
// Calibrated against labeled trivia (Open Trivia DB easy/medium/hard science sets) and
// Jeopardy! solve rates by board row. "target" is the hit rate we aim for with this player.

enum Level: String, CaseIterable, Codable, Identifiable {
    case easy, medium, hard, expert
    var id: String { rawValue }

    var name: String { rawValue.capitalized }

    var points: Int {
        switch self {
        case .easy: return 1
        case .medium: return 2
        case .hard: return 3
        case .expert: return 5
        }
    }

    /// Share of ordinary adults expected to answer correctly (used for Easy and Medium).
    var band: ClosedRange<Double> {
        switch self {
        case .easy: return 82...100
        case .medium: return 65...85
        case .hard: return 38...64
        case .expert: return 0...40
        }
    }

    /// Share of fans of the subject expected to answer correctly (used for Hard and Expert).
    var fanBand: ClosedRange<Double>? {
        switch self {
        case .hard: return 45...70
        case .expert: return 25...50
        default: return nil
        }
    }

    /// Hit rate we aim for with this player.
    var target: Int {
        switch self {
        case .easy: return 88
        case .medium: return 75
        case .hard: return 55
        case .expert: return 38
        }
    }

    var describe: String {
        switch self {
        case .easy:
            return "About 85-95% of ordinary adults would get it right."
        case .medium:
            return "About 65-80% of ordinary adults would get it right. A small step up from Easy: still mainstream, famous material, just not the single most famous fact."
        case .hard:
            return "A real step up from Medium. Measured against fans of the subject: a casual fan gets about half; a dedicated fan gets most."
        case .expert:
            return "Hard, but winnable. A dedicated fan or someone who studied the subject gets about a third to half right; a casual fan rarely does."
        }
    }

    /// The rule that separates this level from the next.
    var test: String {
        switch self {
        case .easy:
            return "The answer is a household name or school-level fact most adults could say without seeing the choices."
        case .medium:
            return "Most adults have HEARD of the answer and would recognize it among the four choices, even if they couldn't recall it unprompted. If the answer is a name or term most adults have never heard (e.g. Peace of Westphalia, Zheng He, Justinian), it is NOT Medium. No exact years or numbers as the answer."
        case .hard:
            return "Not the famous main characters, places or headline facts of the subject (those are Easy/Medium even for a niche subject like a film series or a book series). Use secondary characters, specific events, causes, and well-known-to-fans details."
        case .expert:
            return "Deep knowledge of the subject's own core material: lesser-known characters and events from the books or films themselves, the deeper concepts a serious student learns. Everything must be findable in the main source material or a standard introduction to the field."
        }
    }

    /// Examples at this level, from subjects chosen so they don't pull a round off-topic.
    var anchors: [String] {
        switch self {
        case .easy:
            return ["Who was the first President of the United States? (George Washington)",
                    "What is the largest planet in the solar system? (Jupiter)",
                    "Which organ pumps blood through the body? (heart)",
                    "Which ship carried the Pilgrims to America in 1620? (Mayflower)"]
        case .medium:
            return ["Which country gave the Statue of Liberty to the United States? (France)",
                    "What disease paralyzed President Franklin D. Roosevelt? (polio)",
                    "The 1215 charter that limited King John's power is called what? (Magna Carta)",
                    "What is the name of Han Solo's ship in Star Wars? (Millennium Falcon)",
                    "Dry ice is the solid form of what? (carbon dioxide)",
                    "Which part of the brain coordinates balance? (cerebellum)"]
        case .hard:
            return ["What is Chewbacca's home planet in Star Wars? (Kashyyyk)",
                    "Whose 1919 eclipse observations supported general relativity? (Arthur Eddington)",
                    "Which 1648 agreement ended the Thirty Years' War? (Peace of Westphalia)",
                    "Which goblin helps Harry, Ron and Hermione break into Gringotts? (Griphook)"]
        case .expert:
            return ["Who taught Care of Magical Creatures before Hagrid? (Silvanus Kettleburn)",
                    "What is the ~1.4 solar-mass upper limit for a white dwarf called? (Chandrasekhar limit)",
                    "In The Lord of the Rings, what is Aragorn's reforged sword called? (Andúril)",
                    "Which English king faced the Peasants' Revolt of 1381? (Richard II)"]
        }
    }

    var tooEasy: [String] {
        guard self == .hard else { return [] }
        return ["Who is Luke Skywalker's father? (Darth Vader)",
                "What is Harry Potter's owl called? (Hedwig)",
                "Who is headmaster of Hogwarts for most of the series? (Dumbledore)"]
    }

    var tooHard: [String] {
        guard self == .expert else { return [] }
        return ["Who created the sound effects for the original Star Wars? (Ben Burtt)",
                "Which experiment showed space quantization with a beam of silver atoms? (Stern-Gerlach)",
                "What is the exact runtime in minutes of The Empire Strikes Back? (124)"]
    }

    var never: String? {
        guard self == .expert else { return nil }
        return "Never ask about behind-the-scenes production credits (animators, sequence directors, lyricists, software, studio technology), exact years or numbers, or one-line background names. Those make a question impossible, not expert."
    }

    var below: Level? {
        switch self {
        case .easy: return nil
        case .medium: return .easy
        case .hard: return .medium
        case .expert: return .hard
        }
    }

    var above: Level? {
        switch self {
        case .easy: return .medium
        case .medium: return .hard
        case .hard: return .expert
        case .expert: return nil
        }
    }
}

// MARK: - Game data

struct Question: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var choices: [String]
    var answer: Int
    var explanation: String
    var symbol: String
    var category: String
    var estimatedPercent: Double?
    var fanPercent: Double?

    var correctChoice: String { choices[answer] }

    /// Compact "question → answer" line used for repeat detection and in prompts.
    var seenLine: String {
        let q = text.replacingOccurrences(of: "\n", with: " ")
        return String(q.prefix(140)) + " → " + String(correctChoice.prefix(60))
    }

    func shuffled() -> Question {
        let order = Array(0..<choices.count).shuffled()
        var copy = self
        copy.choices = order.map { choices[$0] }
        copy.answer = order.firstIndex(of: answer) ?? 0
        return copy
    }
}

struct Answer: Codable, Equatable {
    var choice: Int
    var correct: Bool
}

struct Round: Codable, Identifiable {
    var id = UUID()
    var subject: String
    var level: Level
    var questions: [Question] = []
    var answers: [Int: Answer] = [:]
    var current = 0
    var expected: Int
    var doneWriting = false

    var expectedCount: Int { doneWriting ? questions.count : max(expected, questions.count) }
}

/// One saved record per answered question. Records are only ever added,
/// and every total in the app is computed from them.
struct AnswerRecord: Codable, Identifiable {
    var id = UUID()
    var roundID: UUID
    var subject: String
    var key: String
    var level: Level
    var line: String
    var correct: Bool
    var points: Int
    var at: Date
}

struct RoundSummary: Identifiable {
    var id: UUID
    var subject: String
    var level: Level
    var correct: Int
    var total: Int
    var points: Int
    var at: Date
}

struct Totals {
    var answered = 0
    var correct = 0
    var points = 0
    var rounds = 0
    var bestStreak = 0
    var accuracy: Int? { answered == 0 ? nil : Int((Double(correct) / Double(answered) * 100).rounded()) }
}

// MARK: - Subject keys and repeat detection

enum Repeats {
    static func singular(_ w: String) -> String {
        guard w.count >= 4 else { return w }
        if w.hasSuffix("sses") { return String(w.dropLast(2)) }
        if w.hasSuffix("ies") { return String(w.dropLast(3)) + "y" }
        for end in ["shes", "ches", "xes", "zes", "oes"] where w.hasSuffix(end) { return String(w.dropLast(2)) }
        for end in ["ss", "us", "is", "ics"] where w.hasSuffix(end) { return w }
        if w.hasSuffix("s") { return String(w.dropLast()) }
        return w
    }

    /// "Disney Princesses", "disney princess" and "Disney Princess trivia" all map to "disney princess".
    static func subjectKey(_ subject: String) -> String {
        let filler: Set<String> = ["try", "not", "to", "repeat", "please", "question", "questions",
                                   "trivia", "about", "the", "and", "of"]
        let cleaned = String(subject.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " })
        let words = cleaned.split(separator: " ").map(String.init)
            .filter { !filler.contains($0) }
            .map(singular)
        return words.isEmpty ? subject.lowercased() : words.joined(separator: " ")
    }

    /// True when the question text already contains its answer.
    static func givesAway(_ q: Question) -> Bool {
        func norm(_ s: String) -> String {
            String(s.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " })
                .split(separator: " ").joined(separator: " ")
        }
        var ans = norm(q.correctChoice)
        for article in ["the ", "a ", "an "] where ans.hasPrefix(article) { ans = String(ans.dropFirst(article.count)) }
        guard ans.count >= 4 else { return false }
        let text = " " + norm(q.text) + " "
        if text.contains(" " + ans + " ") { return true }
        let parts = ans.split(separator: " ").map(String.init)
        let generic: Set<String> = ["theorem", "effect", "number", "limit", "temperature", "experiment", "constant"]
        if parts.count > 1, let last = parts.last, last.count >= 5, !generic.contains(last), text.contains(" " + last + " ") {
            return true
        }
        return false
    }

    private static let stop: Set<String> = Set("a an the of in on at to for is are was were which what who whom whose how many much does do did by with from as that this these those its it be or and called known name".split(separator: " ").map(String.init))

    static func words(_ text: String) -> Set<String> {
        let cleaned = String(text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " })
        return Set(cleaned.split(separator: " ").map(String.init).filter { $0.count > 2 && !stop.contains($0) })
    }

    static func overlap(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(min(a.count, b.count))
    }

    /// True when the question repeats one already asked: near-identical wording,
    /// or the same answer to a similar question.
    static func isDuplicate(_ q: Question, of pool: [String]) -> Bool {
        let qa = q.correctChoice.lowercased().trimmingCharacters(in: .whitespaces)
        let qw = words(q.text)
        for line in pool {
            let parts = line.components(separatedBy: " → ")
            guard parts.count >= 2 else { continue }
            let ov = overlap(qw, words(parts[0]))
            let pa = parts[1].lowercased().trimmingCharacters(in: .whitespaces)
            if ov >= 0.7 || (pa == qa && ov >= 0.34) { return true }
        }
        return false
    }
}

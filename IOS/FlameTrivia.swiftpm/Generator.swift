import Foundation

enum GenError: LocalizedError {
    case noKey
    case api(Int, String)
    case nothingUsable
    case allRepeats

    var errorDescription: String? {
        switch self {
        case .noKey:
            return "Add your Anthropic API key in Settings (gear icon, top right) to start a round."
        case .api(let status, let message):
            switch status {
            case 401: return "Your API key was rejected. Check it in Settings. (\(message))"
            case 402, 400 where message.lowercased().contains("credit"):
                return "Your API account is out of credit. Add credits at platform.claude.com. (\(message))"
            case 404: return "The model name in Settings wasn't found. (\(message))"
            case 429: return "Too many requests right now. Wait a minute, then try again."
            case 529, 503: return "Claude is overloaded right now. Try again in a minute."
            default: return "Claude returned an error\(status > 0 ? " (\(status))" : ""): \(message)"
            }
        case .nothingUsable:
            return "The questions didn't come back cleanly. Try again, or reword the subject."
        case .allRepeats:
            return "Every question Claude wrote was one you've already had on this subject. Try again, or pick a narrower or different subject."
        }
    }
}

enum Generator {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    // MARK: Prompt

    static func prompt(subject: String, level: Level, count: Int, seen: [String], calibration: String) -> String {
        var p = """
        Write \(count) multiple-choice trivia questions.
        Subject: \(subject)
        Stay strictly on this exact subject. Every question must be about "\(subject)" itself, not the wider category it belongs to. For example, "Disney Princess" means the princesses themselves (their stories, songs, companions, villains and voices as they relate to the princess), not other Disney films, Pixar, or the studio's history; "Volcanoes" means volcanoes, not geology in general. If you can't write enough questions on the exact subject at this level, write fewer rather than drifting.
        Difficulty: \(level.name). \(level.describe)
        Level test: \(level.test)
        Examples at exactly this level, from unrelated subjects (they show difficulty only; do not take topics from them):
        \(level.anchors.map { "- " + $0 }.joined(separator: "\n"))

        """
        if let lower = level.below {
            p += "For comparison, the level BELOW (\(lower.name)) looks like: \(lower.anchors.prefix(2).joined(separator: "; ")). Stay close to that step; do not jump two levels.\n"
        }
        if let higher = level.above {
            p += "For comparison, the level ABOVE (\(higher.name)) looks like: \(higher.anchors.prefix(2).joined(separator: "; ")). Anything that hard does not belong here.\n"
        }
        if !level.tooEasy.isEmpty {
            p += "Too easy for \(level.name) (do NOT write questions like these): \(level.tooEasy.joined(separator: "; ")).\n"
        }
        if !level.tooHard.isEmpty {
            p += "Too hard even for \(level.name) (do NOT write questions like these): \(level.tooHard.joined(separator: "; ")).\n"
        }
        if let never = level.never { p += never + "\n" }
        p += calibration
        if let fb = level.fanBand {
            p += "Also estimate the percentage of fans of this subject (people who chose to play it) who would answer correctly, and only keep questions inside \(Int(fb.lowerBound))-\(Int(fb.upperBound))%. Put that in \"fan\".\n"
        }
        let caution = level == .expert
            ? "For Expert, the opposite risk matters more: if even dedicated fans would mostly miss it, it is too obscure, so drop it."
            : "so be conservative: if a question could fit this level or the harder one, it belongs to the harder one, so drop it."
        p += "Before writing each question, estimate the percentage of ordinary adults (a random person on the street, not a trivia fan) who would answer it correctly with four choices. Writers consistently overestimate what ordinary adults know, \(caution) Only keep questions inside \(Int(level.band.lowerBound))-\(Int(level.band.upperBound))%. Put that estimate in \"pct\".\n"
        if !seen.isEmpty {
            p += "The player has ALREADY been asked the questions below. Do not repeat any of these facts, answers, or near-rewordings of them; pick different sub-topics instead:\n"
            p += seen.suffix(150).map { "- " + $0 }.joined(separator: "\n") + "\n"
        }
        p += """
        Rules:
        - Every fact must be accurate and well established. Skip anything disputed, ambiguous, or likely to have changed recently.
        - The question text must not contain the correct answer or give it away. Check every question for this before including it.
        - Exactly one correct choice and three plausible wrong ones of the same kind. No "all of the above" or "none of the above".
        - Spread across different parts of the subject (still within "\(subject)"); no two questions about the same fact or with the same answer.
        - "sym": a 1-2 character tile label like a periodic-table symbol (e.g. "Ju" for Jupiter). "cat": a 1-2 word sub-topic.
        - "x": one or two sentences explaining why the answer is right, with a concrete detail.
        Return ONLY a JSON array, no prose, no code fences, in this shape:
        [{"q":"question","c":["choice","choice","choice","choice"],"a":0,"pct":65,"fan":80,"x":"explanation","sym":"Ab","cat":"Sub-topic"}]
        "a" is the 0-based index of the correct choice in "c".
        """
        return p
    }

    // MARK: Streaming request

    /// Streams the reply. Each yielded value is the whole text received so far.
    static func stream(apiKey: String, model: String, prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = URLRequest(url: endpoint)
                    req.httpMethod = "POST"
                    req.timeoutInterval = 180
                    req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    req.setValue("application/json", forHTTPHeaderField: "content-type")
                    let body: [String: Any] = [
                        "model": model,
                        "max_tokens": 8000,
                        "stream": true,
                        "messages": [["role": "user", "content": prompt]]
                    ]
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if status != 200 {
                        var data = Data()
                        for try await b in bytes { data.append(b) }
                        throw GenError.api(status, errorMessage(from: data))
                    }

                    var text = ""
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let d = json.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                              let type = obj["type"] as? String else { continue }
                        if type == "content_block_delta",
                           let delta = obj["delta"] as? [String: Any],
                           let piece = delta["text"] as? String {
                            text += piece
                            continuation.yield(text)
                        } else if type == "error" {
                            let err = obj["error"] as? [String: Any]
                            throw GenError.api(0, err?["message"] as? String ?? "Unknown error")
                        } else if type == "message_stop" {
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func errorMessage(from data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = obj["error"] as? [String: Any],
           let msg = err["message"] as? String { return msg }
        return String(data: data, encoding: .utf8)?.prefix(200).description ?? "No details"
    }

    // MARK: Parsing

    /// Every complete {...} object inside the array, even before the array closes.
    /// Objects that fail to parse come back as nil so indexes stay stable.
    static func extractObjects(_ text: String) -> [[String: Any]?] {
        var out: [[String: Any]?] = []
        let chars = Array(text)
        guard let start = chars.firstIndex(of: "[") else { return out }
        var depth = 0, inString = false, escaped = false, objStart = -1
        var i = start + 1
        while i < chars.count {
            let ch = chars[i]
            if inString {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
            } else if ch == "\"" {
                inString = true
            } else if ch == "{" {
                if depth == 0 { objStart = i }
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0, objStart >= 0 {
                    let slice = String(chars[objStart...i])
                    let obj = slice.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                    out.append(obj)
                    objStart = -1
                }
            } else if ch == "]" && depth == 0 {
                break
            }
            i += 1
        }
        return out
    }

    static func isClosed(_ text: String) -> Bool {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasSuffix("```") { t = String(t.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines) }
        return t.hasSuffix("]")
    }

    /// Accepts a few common shapes and validates: 4 distinct choices, one valid answer index.
    static func question(from obj: [String: Any], subject: String) -> Question? {
        guard let text = (obj["q"] ?? obj["question"]) as? String,
              let rawChoices = (obj["c"] ?? obj["choices"] ?? obj["options"]) as? [Any] else { return nil }
        let choices = rawChoices.map { "\($0)".trimmingCharacters(in: .whitespacesAndNewlines) }
        guard choices.count == 4, choices.allSatisfy({ !$0.isEmpty }),
              Set(choices.map { $0.lowercased() }).count == 4 else { return nil }

        var answer: Int?
        let rawA = obj["a"] ?? obj["answer"] ?? obj["correct"]
        if let n = rawA as? Int { answer = n }
        else if let n = rawA as? Double { answer = Int(n) }
        else if let s = rawA as? String {
            let t = s.trimmingCharacters(in: .whitespaces)
            if t.count == 1, let idx = "ABCD".firstIndex(of: Character(t.uppercased())) {
                answer = "ABCD".distance(from: "ABCD".startIndex, to: idx)
            } else {
                answer = choices.firstIndex { $0.lowercased() == t.lowercased() }
            }
        }
        guard let a = answer, (0..<4).contains(a) else { return nil }

        let sym = ((obj["sym"] as? String) ?? String(subject.prefix(2))).prefix(3)
        let cat = ((obj["cat"] as? String) ?? subject).prefix(24)
        func number(_ key: String) -> Double? {
            if let n = obj[key] as? Double { return n }
            if let n = obj[key] as? Int { return Double(n) }
            if let t = obj[key] as? String { return Double(t) }
            return nil
        }
        let pct = number("pct"), fan = number("fan")

        return Question(text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                        choices: choices, answer: a,
                        explanation: (obj["x"] ?? obj["explanation"]) as? String ?? "",
                        symbol: String(sym), category: String(cat),
                        estimatedPercent: pct, fanPercent: fan).shuffled()
    }
}

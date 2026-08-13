// VoiceIntentParser.swift
// Turns a spoken sentence into a draft chore or shopping item.
//
//   "add task due tomorrow to clean bathroom"
//     → chore "Clean bathroom", due tomorrow
//   "add milk to the shopping list for Sarah"
//     → shopping item "Milk", assigned to Sarah
//
// The rules-based implementation below is deliberate: it runs on-device,
// costs nothing, works offline, and — critically — works on every phone in
// the household. Apple's Foundation Models framework would parse more
// natural phrasing but requires Apple Intelligence hardware (iPhone 15 Pro
// or newer), which not every household device has. `VoiceIntentParsing`
// exists so a model-backed parser can be dropped in later without touching
// the capture UI or the confirmation screen.
//
// Nothing here creates a document directly: the result prefills a form the
// user confirms, so a misparse is a visible edit rather than bad data.

import Foundation

// ── Result ────────────────────────────────────────────────────────────────────

/// Which list the utterance is about.
enum VoiceIntentKind: Equatable {
    case chore
    case shopping
}

/// What we managed to extract. Everything except `kind` and `title` is a
/// best guess; the confirmation screen shows all of it before saving.
struct VoiceIntent: Equatable {
    var kind: VoiceIntentKind = .chore
    var title: String = ""
    /// Parsed due / need-by date, if the sentence mentioned one.
    var date: Date? = nil
    /// True when the sentence specified a time of day, not just a day.
    var hasTime: Bool = false
    /// Member indices mentioned by name ("for Sarah"). Empty = everyone.
    var assignedMembers: [Int] = []
    /// The original transcript, always kept so nothing is silently lost.
    var transcript: String = ""

    /// Human-readable summary of what was understood, for the confirm screen.
    func summary(memberName: (Int) -> String) -> String {
        var parts: [String] = []
        parts.append(kind == .chore ? "Chore" : "Shopping item")
        if let date {
            let cal = Calendar.current
            let dayPart: String
            if cal.isDateInToday(date)         { dayPart = "today" }
            else if cal.isDateInTomorrow(date) { dayPart = "tomorrow" }
            else { dayPart = date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) }
            parts.append(hasTime
                ? "\(dayPart) at \(date.formatted(date: .omitted, time: .shortened))"
                : dayPart)
        }
        if !assignedMembers.isEmpty {
            parts.append("for " + assignedMembers.map(memberName).joined(separator: " and "))
        }
        return parts.joined(separator: " · ")
    }
}

// ── Protocol ──────────────────────────────────────────────────────────────────

/// Seam for swapping in a model-backed parser (e.g. Apple Foundation
/// Models on supported hardware) without changing any UI.
protocol VoiceIntentParsing {
    /// - Parameters:
    ///   - transcript: what the user said.
    ///   - members: household member names, index-aligned with AppSettings.
    ///   - now: reference date (injected so this is testable).
    func parse(_ transcript: String, members: [String], now: Date) -> VoiceIntent
}

extension VoiceIntentParsing {
    func parse(_ transcript: String, members: [String]) -> VoiceIntent {
        parse(transcript, members: members, now: Date())
    }
}

// ── Rules-based implementation ────────────────────────────────────────────────

struct RuleBasedVoiceIntentParser: VoiceIntentParsing {

    func parse(_ transcript: String, members: [String], now: Date = Date()) -> VoiceIntent {
        var intent = VoiceIntent()
        intent.transcript = transcript

        var working = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !working.isEmpty else { return intent }

        intent.kind = detectKind(working)
        working = stripLeadIn(working, kind: intent.kind)

        // Order matters: pull the assignee and date out before whatever
        // remains becomes the title.
        let (afterMembers, foundMembers) = extractMembers(working, members: members)
        intent.assignedMembers = foundMembers
        working = afterMembers

        let (afterDate, date, hasTime) = extractDate(working, now: now)
        intent.date    = date
        intent.hasTime = hasTime
        working = afterDate

        intent.title = tidyTitle(working, fallback: transcript)
        return intent
    }

    // ── Kind ──────────────────────────────────────────────────────────────────

    private func detectKind(_ text: String) -> VoiceIntentKind {
        let lower = text.lowercased()
        let shoppingCues = ["shopping list", "grocery list", "groceries",
                            "shopping", "buy ", "pick up ", "get some "]
        let choreCues = ["task", "chore", "to do", "todo", "remind me to"]

        // Whichever cue appears earliest wins; chores are the default.
        let shoppingHit = shoppingCues.compactMap { lower.range(of: $0)?.lowerBound }.min()
        let choreHit    = choreCues.compactMap { lower.range(of: $0)?.lowerBound }.min()

        switch (shoppingHit, choreHit) {
        case let (s?, c?): return s < c ? .shopping : .chore
        case (_?, nil):    return .shopping
        default:           return .chore
        }
    }

    /// Removes conversational scaffolding: "add a task to…", "remind me to…",
    /// "put milk on the shopping list".
    private func stripLeadIn(_ text: String, kind: VoiceIntentKind) -> String {
        var out = text
        let leadIns = [
            "add a task to", "add a task", "add task to", "add task",
            "add a chore to", "add a chore", "add chore to", "add chore",
            "remind me to", "remind me",
            "i need to", "we need to", "need to",
            "put", "add", "create",
            "to the shopping list", "on the shopping list", "to the grocery list",
            "to shopping list", "to my shopping list",
            "to the list", "on the list",
            "shopping list", "grocery list", "groceries",
            "buy", "pick up", "get some", "get"
        ]
        for phrase in leadIns {
            out = removePhrase(phrase, from: out)
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;-"))
    }

    /// Case-insensitive whole-phrase removal, respecting word boundaries.
    private func removePhrase(_ phrase: String, from text: String) -> String {
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: phrase) + "\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
            .replacingOccurrences(of: "  ", with: " ")
    }

    // ── Members ───────────────────────────────────────────────────────────────

    /// Finds "for <name>" / "<name> should" references to household members.
    private func extractMembers(_ text: String, members: [String]) -> (String, [Int]) {
        var out = text
        var found: [Int] = []

        for (index, name) in members.enumerated() {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let escaped = NSRegularExpression.escapedPattern(for: trimmed)
            // "for Sarah", "to Sarah", or the bare name.
            let pattern = "\\b(?:for|to|by)?\\s*\\b\(escaped)\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            else { continue }
            let range = NSRange(out.startIndex..., in: out)
            if regex.firstMatch(in: out, range: range) != nil {
                found.append(index)
                out = regex.stringByReplacingMatches(in: out, range: range, withTemplate: " ")
            }
        }
        return (out.replacingOccurrences(of: "  ", with: " "), found.sorted())
    }

    // ── Dates ─────────────────────────────────────────────────────────────────

    /// Extracts a date phrase and removes it from the text. Handles the
    /// common spoken forms first, then falls back to NSDataDetector for
    /// things like "August 12" or "on the 3rd".
    private func extractDate(_ text: String, now: Date) -> (String, Date?, Bool) {
        let cal = Calendar.current
        var out = text
        var result: Date? = nil
        var hasTime = false

        // ── Explicit time of day: "at 5pm", "at 5:30" ──
        if let timeMatch = firstMatch(in: out, pattern: "\\bat\\s+(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)?\\b") {
            let hourRaw = Int(timeMatch.group(1) ?? "") ?? 0
            let minute  = Int(timeMatch.group(2) ?? "0") ?? 0
            let marker  = timeMatch.group(3)?.lowercased()
            var hour = hourRaw
            if marker == "pm", hour < 12 { hour += 12 }
            if marker == "am", hour == 12 { hour = 0 }
            // No am/pm and an ambiguous hour: assume the sensible daytime one.
            if marker == nil, hour < 8 { hour += 12 }
            if (0...23).contains(hour), (0...59).contains(minute) {
                result = cal.date(bySettingHour: hour, minute: minute, second: 0, of: now)
                hasTime = true
                out = out.replacingOccurrences(of: timeMatch.matched, with: " ")
            }
        }

        // ── Relative days ──
        let dayOffsets: [(String, Int)] = [
            ("day after tomorrow", 2), ("tomorrow", 1), ("today", 0), ("tonight", 0)
        ]
        for (phrase, offset) in dayOffsets where containsPhrase(phrase, in: out) {
            let base = cal.date(byAdding: .day, value: offset, to: now) ?? now
            result = merge(day: base, intoTimeOf: result, cal: cal, hasTime: hasTime)
            out = removePhrase(phrase, from: out)
            return (out, result, hasTime)
        }

        // ── "in N days/weeks" ──
        if let m = firstMatch(in: out, pattern: "\\bin\\s+(\\d+)\\s+(day|days|week|weeks)\\b"),
           let n = Int(m.group(1) ?? "") {
            let unit: Calendar.Component = (m.group(2) ?? "").hasPrefix("week") ? .weekOfYear : .day
            let base = cal.date(byAdding: unit, value: n, to: now) ?? now
            result = merge(day: base, intoTimeOf: result, cal: cal, hasTime: hasTime)
            out = out.replacingOccurrences(of: m.matched, with: " ")
            return (out, result, hasTime)
        }

        // ── Weekday names, optionally "next <weekday>" ──
        let symbols = cal.weekdaySymbols   // ["Sunday", … "Saturday"]
        for (idx, symbol) in symbols.enumerated() {
            guard containsPhrase(symbol, in: out) else { continue }
            let wantsNextWeek = containsPhrase("next \(symbol)", in: out)
            if let next = nextOccurrence(ofWeekday: idx + 1, after: now,
                                         skipAWeek: wantsNextWeek, cal: cal) {
                result = merge(day: next, intoTimeOf: result, cal: cal, hasTime: hasTime)
            }
            out = removePhrase("next \(symbol)", from: out)
            out = removePhrase(symbol, from: out)
            return (out, result, hasTime)
        }

        // ── Fallback: NSDataDetector for explicit dates ──
        if result == nil || !hasTime,
           let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let range = NSRange(out.startIndex..., in: out)
            if let match = detector.firstMatch(in: out, range: range), let detected = match.date {
                result = detected
                // Treat a detected midnight as "no time given".
                let comps = cal.dateComponents([.hour, .minute], from: detected)
                hasTime = !(comps.hour == 0 && comps.minute == 0)
                if let r = Range(match.range, in: out) {
                    out.removeSubrange(r)
                }
            }
        }

        return (out, result, hasTime)
    }

    /// Combines a day with an already-parsed time of day (or start of day).
    private func merge(day: Date, intoTimeOf timed: Date?, cal: Calendar, hasTime: Bool) -> Date {
        guard hasTime, let timed else { return cal.startOfDay(for: day) }
        let t = cal.dateComponents([.hour, .minute], from: timed)
        return cal.date(bySettingHour: t.hour ?? 9, minute: t.minute ?? 0, second: 0, of: day)
            ?? cal.startOfDay(for: day)
    }

    /// Next date falling on `weekday` (1 = Sunday). `skipAWeek` handles
    /// "next Friday" meaning the following week's Friday.
    private func nextOccurrence(ofWeekday weekday: Int, after date: Date,
                                skipAWeek: Bool, cal: Calendar) -> Date? {
        var comps = DateComponents()
        comps.weekday = weekday
        guard let next = cal.nextDate(after: date, matching: comps,
                                      matchingPolicy: .nextTime) else { return nil }
        return skipAWeek ? cal.date(byAdding: .weekOfYear, value: 1, to: next) : next
    }

    // ── Title ─────────────────────────────────────────────────────────────────

    /// Cleans leftover connective words from both ends and capitalizes.
    /// Removing a date or assignee mid-sentence commonly strands a
    /// preposition ("water the plants on", "cake by"), so both edges are
    /// trimmed repeatedly until stable. Falls back to the raw transcript if
    /// stripping left nothing usable — better to show the user their own
    /// words than an empty field.
    private func tidyTitle(_ text: String, fallback: String) -> String {
        let edgeWords = ["due", "by", "on", "at", "to the", "on the", "for the",
                         "to", "for", "and", "the", "a", "an", "some"]
        let punctuation = CharacterSet(charactersIn: " ,.:;-")

        var out = text.replacingOccurrences(of: "  ", with: " ")
                      .trimmingCharacters(in: punctuation)

        // Strip from both ends until nothing more is removable.
        var changed = true
        while changed {
            changed = false
            for word in edgeWords {
                if out.lowercased().hasPrefix(word + " ") {
                    out = String(out.dropFirst(word.count + 1)).trimmingCharacters(in: punctuation)
                    changed = true
                }
                if out.lowercased().hasSuffix(" " + word) {
                    out = String(out.dropLast(word.count + 1)).trimmingCharacters(in: punctuation)
                    changed = true
                }
                // A stranded connective can also be the entire remainder.
                if out.lowercased() == word {
                    out = ""
                    changed = true
                }
            }
        }

        out = out.replacingOccurrences(of: "  ", with: " ")
                 .trimmingCharacters(in: punctuation)
        guard !out.isEmpty else {
            return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return out.prefix(1).uppercased() + out.dropFirst()
    }

    // ── Regex helpers ─────────────────────────────────────────────────────────

    private struct Match {
        let matched: String
        private let groups: [String?]
        init(matched: String, groups: [String?]) {
            self.matched = matched
            self.groups = groups
        }
        func group(_ i: Int) -> String? {
            groups.indices.contains(i - 1) ? groups[i - 1] : nil
        }
    }

    private func firstMatch(in text: String, pattern: String) -> Match? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let full = Range(m.range, in: text) else { return nil }
        var groups: [String?] = []
        for i in 1..<m.numberOfRanges {
            if let r = Range(m.range(at: i), in: text) { groups.append(String(text[r])) }
            else { groups.append(nil) }
        }
        return Match(matched: String(text[full]), groups: groups)
    }

    private func containsPhrase(_ phrase: String, in text: String) -> Bool {
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: phrase) + "\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}

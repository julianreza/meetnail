import Foundation

struct NotulenActionItem: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var task: String
    var owner: String?
    var dueDate: String?

    enum CodingKeys: String, CodingKey {
        case id
        case task
        case owner
        case dueDate = "due_date"
    }

    init(
        id: String = UUID().uuidString,
        task: String,
        owner: String? = nil,
        dueDate: String? = nil
    ) {
        self.id = id
        self.task = task
        self.owner = owner
        self.dueDate = dueDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawId = try container.decodeIfPresent(String.self, forKey: .id)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = (rawId?.isEmpty == false) ? rawId! : UUID().uuidString

        let rawTask = try container.decode(String.self, forKey: .task)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.task = rawTask

        let rawOwner = try container.decodeIfPresent(String.self, forKey: .owner)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.owner = (rawOwner?.isEmpty == false) ? rawOwner : nil

        let rawDue = try container.decodeIfPresent(String.self, forKey: .dueDate)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.dueDate = (rawDue?.isEmpty == false) ? rawDue : nil
    }
}

struct NotulenSummary: Codable, Equatable, Sendable {
    var title: String
    var meetingDate: String?
    var meetingLink: String?
    var executiveSummary: String
    var keyPoints: [String]
    var decisions: [String]
    var actionItems: [NotulenActionItem]
    var participants: [String]
    var generatedAt: Date
    var modelUsed: String
    var sourceFileName: String

    func renderedMarkdown() -> String {
        var lines: [String] = ["## Ringkasan Rapat", ""]

        let summaryText = executiveSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summaryText.isEmpty {
            lines.append(summaryText)
            lines.append("")
        }

        if !keyPoints.isEmpty {
            lines.append("### Poin Utama")
            for point in keyPoints {
                lines.append("- \(point)")
            }
            lines.append("")
        }

        if !decisions.isEmpty {
            lines.append("### Keputusan")
            for decision in decisions {
                lines.append("- \(decision)")
            }
            lines.append("")
        }

        if !actionItems.isEmpty {
            lines.append("### Tindak Lanjut")
            for item in actionItems {
                var suffixParts: [String] = []
                if let owner = item.owner, !owner.isEmpty {
                    suffixParts.append("PIC: \(owner)")
                }
                if let dueDate = item.dueDate, !dueDate.isEmpty {
                    suffixParts.append("Target: \(dueDate)")
                }
                let suffix = suffixParts.isEmpty ? "" : " (\(suffixParts.joined(separator: " · ")))"
                lines.append("- [ ] \(item.task)\(suffix)")
            }
            lines.append("")
        }

        if !participants.isEmpty {
            lines.append("### Peserta")
            lines.append(participants.joined(separator: ", "))
            lines.append("")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }
}

enum NotulenSummaryError: LocalizedError, Equatable, Sendable {
    case emptyTranscript
    case cliExecutionFailed(String)
    case invalidSummaryResponse(String)

    var errorDescription: String? {
        switch self {
        case .emptyTranscript:
            "Transkrip notulen masih kosong sehingga belum dapat diringkas."
        case let .cliExecutionFailed(reason):
            reason.isEmpty
                ? "Gagal menjalankan mesin ringkasan Agy."
                : "Gagal menjalankan mesin ringkasan: \(reason)"
        case let .invalidSummaryResponse(detail):
            detail.isEmpty
                ? "Format ringkasan dari model tidak valid."
                : "Format ringkasan tidak valid: \(detail)"
        }
    }
}

enum NotulenSummaryService {
    private nonisolated static let summaryStartMarker = "<!-- NAIL_SUMMARY_START -->"
    private nonisolated static let summaryEndMarker = "<!-- NAIL_SUMMARY_END -->"
    private nonisolated static let transcriptHeading = "## Transkrip & Tanya Jawab"

    private struct RawSummaryJSON: Decodable {
        var executiveSummary: String?
        var summary: String?
        var keyPoints: [String]?
        var decisions: [String]?
        var actionItems: [NotulenActionItem]?
        var participants: [String]?

        enum CodingKeys: String, CodingKey {
            case executiveSummary = "executive_summary"
            case summary
            case keyPoints = "key_points"
            case decisions
            case actionItems = "action_items"
            case participants
        }
    }

    private struct ParsedMarkdownMetadata {
        var title: String
        var meetingDate: String?
        var meetingLink: String?
        var transcriptLines: [String]
        var speakers: [String]
        var bodyLines: [String]
    }

    nonisolated static func buildPrompt(title: String, markdown: String) -> String {
        let cleanedMarkdown = stripSummarySection(from: markdown)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let boundedMarkdown = cleanedMarkdown.count > 60_000
            ? String(cleanedMarkdown.prefix(60_000)) + "\n\n[...transkrip dipotong karena batas panjang...]"
            : cleanedMarkdown

        return """
        Kamu adalah asisten notulen rapat profesional berbahasa Indonesia.
        Tugasmu membaca catatan/transkrip rapat berikut lalu menghasilkan ringkasan terstruktur dalam SATU objek JSON valid (tanpa teks tambahan di luar JSON).

        Judul Rapat: \(title)

        Skema JSON wajib:
        {
          "executive_summary": "Ringkasan eksekutif padat 2-4 kalimat dalam Bahasa Indonesia.",
          "key_points": ["Poin pembahasan utama"],
          "decisions": ["Keputusan yang disepakati (isi [] jika belum ada keputusan eksplisit)"],
          "action_items": [
            {
              "task": "Langkah tindak lanjut konkret",
              "owner": "Nama penanggung jawab atau null",
              "due_date": "Tenggat waktu atau null"
            }
          ],
          "participants": ["Nama pembicara/peserta yang muncul di transkrip"]
        }

        Aturan penting:
        - Balas HANYA JSON valid sesuai skema di atas, tanpa pembuka, tanpa penutup, tanpa penjelasan.
        - Jangan mengarang fakta, keputusan, atau tenggat waktu yang tidak ada di catatan rapat.
        - Gunakan Bahasa Indonesia yang jelas, ringkas, dan profesional.

        Catatan Rapat:
        \(boundedMarkdown)
        """
    }

    nonisolated static func parseSummaryJSON(
        _ rawText: String,
        title: String,
        meetingDate: String?,
        meetingLink: String?,
        sourceFileName: String,
        modelUsed: String,
        generatedAt: Date = Date()
    ) throws -> NotulenSummary {
        guard let jsonString = extractOutermostJSONObject(from: rawText),
              let data = jsonString.data(using: .utf8) else {
            throw NotulenSummaryError.invalidSummaryResponse("Tidak ditemukan objek JSON pada respons model.")
        }

        let decoded: RawSummaryJSON
        do {
            decoded = try JSONDecoder().decode(RawSummaryJSON.self, from: data)
        } catch {
            throw NotulenSummaryError.invalidSummaryResponse(error.localizedDescription)
        }

        let keyPoints = cleanStringList(decoded.keyPoints ?? [])
        let decisions = cleanStringList(decoded.decisions ?? [])
        let actionItems = (decoded.actionItems ?? []).filter {
            !$0.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let participants = cleanStringList(decoded.participants ?? [])

        var executiveSummary = (decoded.executiveSummary ?? decoded.summary ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if executiveSummary.isEmpty {
            if !keyPoints.isEmpty {
                executiveSummary = keyPoints.prefix(2).joined(separator: " ")
            } else if !decisions.isEmpty {
                executiveSummary = decisions.prefix(2).joined(separator: " ")
            } else {
                throw NotulenSummaryError.invalidSummaryResponse("Field executive_summary dan poin utama kosong.")
            }
        }

        return NotulenSummary(
            title: title,
            meetingDate: meetingDate,
            meetingLink: meetingLink,
            executiveSummary: executiveSummary,
            keyPoints: keyPoints,
            decisions: decisions,
            actionItems: actionItems,
            participants: participants,
            generatedAt: generatedAt,
            modelUsed: modelUsed,
            sourceFileName: sourceFileName
        )
    }

    nonisolated static func extractiveFallback(
        title: String,
        markdown: String,
        sourceFileName: String,
        generatedAt: Date = Date()
    ) -> NotulenSummary {
        let parsed = parseMetadataAndLines(markdown: markdown, fallbackTitle: title)
        let lines = parsed.transcriptLines.isEmpty ? parsed.bodyLines : parsed.transcriptLines

        var keyPoints: [String] = []
        var decisions: [String] = []
        var actionItems: [NotulenActionItem] = []

        let decisionKeywords = [
            "sepakat", "disepakati", "diputuskan", "keputusan", "setuju",
            "final", "fix", "acc", "disetujui", "ditetapkan",
        ]
        let actionKeywords = [
            "akan ", "tolong", "perlu ", "tindak lanjut", "follow up", "follow-up",
            "followup", "kerjakan", "buatkan", "kirim", "cek ", "update ", "siapkan",
            "jadwal", "deadline", "target", "todo", "pic ", "besok", "lusa",
            "senin", "selasa", "rabu", "kamis", "jumat",
        ]

        for entry in lines {
            let (speaker, content) = splitSpeakerAndContent(from: entry)
            let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            let lower = normalized.lowercased()

            if decisionKeywords.contains(where: { lower.contains($0) }) && decisions.count < 5 {
                let candidate = speaker.map { "\($0): \(normalized)" } ?? normalized
                if !decisions.contains(candidate) {
                    decisions.append(candidate)
                }
            }

            if actionKeywords.contains(where: { lower.contains($0) }) && actionItems.count < 6 {
                let dueDate = extractHeuristicDueDate(from: normalized)
                if !actionItems.contains(where: { $0.task.caseInsensitiveCompare(normalized) == .orderedSame }) {
                    actionItems.append(
                        NotulenActionItem(
                            task: normalized,
                            owner: speaker,
                            dueDate: dueDate
                        )
                    )
                }
            }

            if keyPoints.count < 6 {
                let formatted = speaker.map { "\($0): \(normalized)" } ?? normalized
                if !keyPoints.contains(formatted) {
                    keyPoints.append(formatted)
                }
            }
        }

        let executiveSummary: String
        if keyPoints.isEmpty {
            executiveSummary = "Ringkasan lokal untuk rapat \"\(parsed.title)\"."
        } else {
            let speakerSummary = parsed.speakers.isEmpty
                ? ""
                : " dengan \(parsed.speakers.count) pembicara teridentifikasi (\(parsed.speakers.joined(separator: ", ")))"
            let leadPoints = keyPoints.prefix(2).joined(separator: " ")
            executiveSummary = "Rapat \"\(parsed.title)\" mencatat \(lines.count) baris transkrip\(speakerSummary). Pokok bahasan utama meliputi: \(leadPoints)"
        }

        return NotulenSummary(
            title: parsed.title,
            meetingDate: parsed.meetingDate,
            meetingLink: parsed.meetingLink,
            executiveSummary: executiveSummary,
            keyPoints: keyPoints,
            decisions: decisions,
            actionItems: actionItems,
            participants: parsed.speakers,
            generatedAt: generatedAt,
            modelUsed: "ringkasan-lokal",
            sourceFileName: sourceFileName
        )
    }

    nonisolated static func summarize(
        file: NotulenFile,
        markdown: String,
        model: String,
        runner: (@Sendable (_ prompt: String, _ model: String) async throws -> String)? = nil
    ) async throws -> NotulenSummary {
        let stripped = stripSummarySection(from: markdown)
        let parsed = parseMetadataAndLines(markdown: stripped, fallbackTitle: file.name)
        let hasTranscriptBody = !parsed.transcriptLines.isEmpty || !parsed.bodyLines.isEmpty
        guard !stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, hasTranscriptBody else {
            throw NotulenSummaryError.emptyTranscript
        }

        let prompt = buildPrompt(title: parsed.title, markdown: stripped)
        let sourceFileName = file.url.lastPathComponent

        if let runner {
            let rawResponse = try await runner(prompt, model)
            return try parseSummaryJSON(
                rawResponse,
                title: parsed.title,
                meetingDate: parsed.meetingDate,
                meetingLink: parsed.meetingLink,
                sourceFileName: sourceFileName,
                modelUsed: model
            )
        }

        let backend = VoiceSettings.summaryModelBackend(for: model)
        let rawResponse: String

        switch backend {
        case .local:
            return extractiveFallback(
                title: parsed.title,
                markdown: stripped,
                sourceFileName: sourceFileName
            )
        case .codex:
            guard let codexPath = findCodexExecutablePath() else {
                throw NotulenSummaryError.cliExecutionFailed(
                    "Codex CLI (ChatGPT) belum ditemukan di /opt/homebrew/bin/codex atau PATH."
                )
            }
            rawResponse = try await invokeCodexCLI(
                executablePath: codexPath,
                prompt: prompt,
                model: model
            )
        case .antigravity:
            guard let agyPath = findAgyExecutablePath() else {
                return extractiveFallback(
                    title: parsed.title,
                    markdown: stripped,
                    sourceFileName: sourceFileName
                )
            }
            rawResponse = try await invokeAgyCLI(
                executablePath: agyPath,
                prompt: prompt,
                model: model
            )
        }

        return try parseSummaryJSON(
            rawResponse,
            title: parsed.title,
            meetingDate: parsed.meetingDate,
            meetingLink: parsed.meetingLink,
            sourceFileName: sourceFileName,
            modelUsed: model
        )
    }

    // MARK: - Sidecar Persistence

    private nonisolated static func summariesDirectory(for notulenURL: URL) -> URL {
        notulenURL.deletingLastPathComponent().appendingPathComponent(".summaries", isDirectory: true)
    }

    nonisolated static func summarySidecarURL(for notulenURL: URL) -> URL {
        let stem = notulenURL.deletingPathExtension().lastPathComponent
        return summariesDirectory(for: notulenURL).appendingPathComponent("\(stem).summary.json")
    }

    nonisolated static func loadCachedSummary(for notulenURL: URL) -> NotulenSummary? {
        let url = summarySidecarURL(for: notulenURL)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(NotulenSummary.self, from: data)
    }

    nonisolated static func saveCachedSummary(_ summary: NotulenSummary, for notulenURL: URL) throws {
        let url = summarySidecarURL(for: notulenURL)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(summary)
        try data.write(to: url, options: .atomic)
    }

    nonisolated static func submissionRecordURL(for notulenURL: URL) -> URL {
        let stem = notulenURL.deletingPathExtension().lastPathComponent
        return summariesDirectory(for: notulenURL).appendingPathComponent("\(stem).submission.json")
    }

    nonisolated static func loadSubmissionRecord(for notulenURL: URL) -> NotulenSubmissionRecord? {
        let url = submissionRecordURL(for: notulenURL)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(NotulenSubmissionRecord.self, from: data)
    }

    nonisolated static func saveSubmissionRecord(_ record: NotulenSubmissionRecord, for notulenURL: URL) throws {
        let url = submissionRecordURL(for: notulenURL)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(record)
        try data.write(to: url, options: .atomic)
    }

    nonisolated static func upsertSummarySection(in notulenURL: URL, summary: NotulenSummary) throws {
        let existing = try String(contentsOf: notulenURL, encoding: .utf8)
        let block = """
        \(summaryStartMarker)
        \(summary.renderedMarkdown())
        \(summaryEndMarker)
        """

        let updated: String
        if let startRange = existing.range(of: summaryStartMarker),
           let endRange = existing.range(of: summaryEndMarker, range: startRange.upperBound..<existing.endIndex) {
            let before = existing[..<startRange.lowerBound].replacingOccurrences(
                of: #"\n+$"#,
                with: "",
                options: .regularExpression
            )
            let after = existing[endRange.upperBound...].replacingOccurrences(
                of: #"^\n+"#,
                with: "",
                options: .regularExpression
            )
            if after.isEmpty {
                updated = "\(before)\n\n\(block)\n"
            } else {
                updated = "\(before)\n\n\(block)\n\n\(after)"
            }
        } else if let headingRange = existing.range(of: transcriptHeading) {
            let before = existing[..<headingRange.lowerBound].replacingOccurrences(
                of: #"\n+$"#,
                with: "",
                options: .regularExpression
            )
            let after = existing[headingRange.lowerBound...]
            updated = before.isEmpty
                ? "\(block)\n\n\(after)"
                : "\(before)\n\n\(block)\n\n\(after)"
        } else {
            let trimmedExisting = existing.replacingOccurrences(
                of: #"\n+$"#,
                with: "",
                options: .regularExpression
            )
            updated = trimmedExisting.isEmpty ? "\(block)\n" : "\(trimmedExisting)\n\n\(block)\n"
        }

        try updated.write(to: notulenURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Helpers

    private nonisolated static func stripSummarySection(from markdown: String) -> String {
        guard let startRange = markdown.range(of: summaryStartMarker),
              let endRange = markdown.range(of: summaryEndMarker, range: startRange.upperBound..<markdown.endIndex) else {
            return markdown
        }
        let before = markdown[..<startRange.lowerBound]
        let after = markdown[endRange.upperBound...]
        return String(before + after)
    }

    private nonisolated static func cleanStringList(_ items: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in items {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    private nonisolated static func extractOutermostJSONObject(from rawText: String) -> String? {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // Strip common ```json ... ``` fences if present
        if text.hasPrefix("```") {
            let lines = text.components(separatedBy: .newlines)
            if lines.count >= 2 {
                let filtered = lines.dropFirst().reversed().drop(while: {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```")
                }).reversed()
                text = filtered.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        var startIndex: String.Index?
        var depth = 0
        var inString = false
        var escaped = false

        var idx = text.startIndex
        while idx < text.endIndex {
            let ch = text[idx]
            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
            } else {
                if ch == "\"" {
                    inString = true
                } else if ch == "{" {
                    if startIndex == nil {
                        startIndex = idx
                    }
                    depth += 1
                } else if ch == "}" {
                    if startIndex != nil {
                        depth -= 1
                        if depth == 0, let start = startIndex {
                            return String(text[start...idx])
                        }
                    }
                }
            }
            idx = text.index(after: idx)
        }

        return nil
    }

    private nonisolated static func parseMetadataAndLines(
        markdown: String,
        fallbackTitle: String
    ) -> ParsedMarkdownMetadata {
        let cleaned = stripSummarySection(from: markdown)
        var title = fallbackTitle
        var titleFound = false
        var meetingDate: String?
        var meetingLink: String?
        var transcriptLines: [String] = []
        var bodyLines: [String] = []
        var speakers: [String] = []
        var speakerSeen = Set<String>()

        func addSpeaker(_ raw: String?) {
            guard let raw else { return }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let key = trimmed.lowercased()
            if speakerSeen.insert(key).inserted {
                speakers.append(trimmed)
            }
        }

        for rawLine in cleaned.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("# ") && !titleFound {
                let candidate = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !candidate.isEmpty {
                    title = candidate
                }
                titleFound = true
                continue
            }
            if line.hasPrefix("- **Tanggal:**") {
                meetingDate = String(line.dropFirst("- **Tanggal:**".count)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix("- **Mulai:**") || line.hasPrefix("- **Status:**") {
                continue
            }
            if line.hasPrefix("- **Link Meet:**") {
                meetingLink = String(line.dropFirst("- **Link Meet:**".count)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix("- **Link Teams:**") {
                meetingLink = String(line.dropFirst("- **Link Teams:**".count)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix("## ") {
                let heading = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if heading.caseInsensitiveCompare("Transkrip & Tanya Jawab") == .orderedSame
                    || heading.lowercased().hasPrefix("sesi ") {
                    continue
                }
                bodyLines.append(heading)
                continue
            }

            if let match = line.wholeMatch(of: #/^- \[\d{2}:\d{2}:\d{2}\] \*\*(.+?):\*\* (.+)$/#) {
                let speaker = unescapeMarkdown(String(match.1))
                let text = String(match.2).trimmingCharacters(in: .whitespaces)
                addSpeaker(speaker)
                if !text.isEmpty {
                    transcriptLines.append("\(speaker): \(text)")
                }
                continue
            }

            if let match = line.wholeMatch(of: #/^- \[\d{2}:\d{2}:\d{2}\] (.+)$/#) {
                let text = String(match.1).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    transcriptLines.append(text)
                }
                continue
            }

            if let match = line.wholeMatch(of: #/^\*\*Dengar \([^)]+\):\*\* (.+)$/#) {
                let text = String(match.1).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    transcriptLines.append("Peserta: \(text)")
                }
                continue
            }

            if let match = line.wholeMatch(of: #/^\*\*Nail \([^)]+\):\*\* (.+)$/#) {
                let text = String(match.1).trimmingCharacters(in: .whitespaces)
                addSpeaker("Nail")
                if !text.isEmpty {
                    transcriptLines.append("Nail: \(text)")
                }
                continue
            }

            bodyLines.append(line)
        }

        return ParsedMarkdownMetadata(
            title: title,
            meetingDate: meetingDate,
            meetingLink: meetingLink,
            transcriptLines: transcriptLines,
            speakers: speakers,
            bodyLines: bodyLines
        )
    }

    private nonisolated static func splitSpeakerAndContent(from entry: String) -> (speaker: String?, content: String) {
        guard let colonRange = entry.range(of: ": ") else {
            return (nil, entry)
        }
        let candidateSpeaker = String(entry[..<colonRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let content = String(entry[colonRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if candidateSpeaker.isEmpty || candidateSpeaker.count > 40 {
            return (nil, entry)
        }
        return (candidateSpeaker, content)
    }

    private nonisolated static func extractHeuristicDueDate(from text: String) -> String? {
        let lower = text.lowercased()
        let markers = [
            "hari ini", "besok", "lusa", "minggu depan", "pekan depan",
            "senin", "selasa", "rabu", "kamis", "jumat", "sabtu", "minggu",
        ]
        for marker in markers where lower.contains(marker) {
            return marker.capitalized
        }
        return nil
    }

    private nonisolated static func unescapeMarkdown(_ raw: String) -> String {
        var result = ""
        var escaped = false
        for ch in raw {
            if escaped {
                result.append(ch)
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else {
                result.append(ch)
            }
        }
        return result
    }

    private nonisolated static func findAgyExecutablePath() -> String? {
        let fm = FileManager.default
        let homeBin = fm.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/agy").path
        var candidates = [
            homeBin,
            "/opt/homebrew/bin/agy",
            "/usr/local/bin/agy",
        ]
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") where !dir.isEmpty {
                candidates.append(URL(fileURLWithPath: String(dir)).appendingPathComponent("agy").path)
            }
        }
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }

    private nonisolated static func findCodexExecutablePath() -> String? {
        let fm = FileManager.default
        let homeBin = fm.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path
        var candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            homeBin,
        ]
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") where !dir.isEmpty {
                candidates.append(URL(fileURLWithPath: String(dir)).appendingPathComponent("codex").path)
            }
        }
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }

    private nonisolated static func invokeCodexCLI(
        executablePath: String,
        prompt: String,
        model: String,
        timeoutSeconds: TimeInterval = 90
    ) async throws -> String {
        let tmpDir = FileManager.default.temporaryDirectory
        let outputURL = tmpDir.appendingPathComponent("nail-codex-summary-\(UUID().uuidString).txt")
        let inputData = Data(prompt.utf8)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.currentDirectoryURL = tmpDir

                var env = ProcessInfo.processInfo.environment
                for key in ["OPENAI_API_KEY", "CODEX_API_KEY", "OPENAI_BASE_URL", "CODEX_BASE_URL"] {
                    env.removeValue(forKey: key)
                }
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                let existingPath = env["PATH"] ?? "/usr/bin:/bin"
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(home)/.local/bin:\(existingPath)"
                process.environment = env

                process.arguments = [
                    "exec",
                    "--ignore-user-config",
                    "--ephemeral",
                    "--skip-git-repo-check",
                    "-s", "read-only",
                    "-C", tmpDir.path,
                    "-m", model,
                    "-c", #"forced_login_method="chatgpt""#,
                    "-c", "features.shell_tool=false",
                    "-c", "features.unified_exec=false",
                    "-c", "features.plugins=false",
                    "-c", "features.code_mode=false",
                    "-c", #"web_search="disabled""#,
                    "--json",
                    "-o", outputURL.path,
                    "-",
                ]

                let stdinPipe = Pipe()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardInput = stdinPipe
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                let state = AgyStreamState()

                @Sendable func finish(_ result: Result<String, Error>) {
                    guard state.markFinishedIfNeeded() else { return }
                    if process.isRunning {
                        process.terminate()
                    }
                    try? FileManager.default.removeItem(at: outputURL)
                    continuation.resume(with: result)
                }

                let timeoutWorkItem = DispatchWorkItem {
                    finish(.failure(NotulenSummaryError.cliExecutionFailed("Waktu tunggu Codex CLI habis (\(Int(timeoutSeconds)) dtk).")))
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutWorkItem)

                process.terminationHandler = { proc in
                    timeoutWorkItem.cancel()
                    let fileText = (try? String(contentsOf: outputURL, encoding: .utf8))?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !fileText.isEmpty {
                        finish(.success(fileText))
                        return
                    }

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let parsed = parseCodexJSONLines(stdoutData)
                    if let message = parsed.agentText, !message.isEmpty {
                        finish(.success(message))
                        return
                    }
                    if let err = parsed.errorMessage, !err.isEmpty {
                        finish(.failure(NotulenSummaryError.cliExecutionFailed(err)))
                        return
                    }
                    let stderrText = String(decoding: stderrData, as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    finish(.failure(NotulenSummaryError.cliExecutionFailed(
                        stderrText.isEmpty
                            ? "Codex CLI (ChatGPT) keluar dengan kode \(proc.terminationStatus)."
                            : stderrText
                    )))
                }

                do {
                    try process.run()
                    stdinPipe.fileHandleForWriting.write(inputData)
                    try? stdinPipe.fileHandleForWriting.close()
                } catch {
                    timeoutWorkItem.cancel()
                    finish(.failure(NotulenSummaryError.cliExecutionFailed(error.localizedDescription)))
                }
            }
        }
    }

    private nonisolated static func parseCodexJSONLines(_ data: Data) -> (agentText: String?, errorMessage: String?) {
        let text = String(decoding: data, as: UTF8.self)
        var lastAgentText: String?
        var lastError: String?
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("{"),
                  let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }
            let type = json["type"] as? String
            if type == "item.completed",
               let item = json["item"] as? [String: Any],
               (item["type"] as? String) == "agent_message",
               let itemText = (item["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !itemText.isEmpty {
                lastAgentText = itemText
            } else if type == "turn.failed",
                      let err = json["error"] as? [String: Any],
                      let msg = (err["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !msg.isEmpty {
                lastError = msg
            } else if type == "error",
                      let msg = (json["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !msg.isEmpty {
                lastError = msg
            }
        }
        return (lastAgentText, lastError)
    }

    private final class AgyStreamState: @unchecked Sendable {
        private let lock = NSLock()
        private var finished = false
        private var buffer = Data()

        func appendAndExtractResult(_ chunk: Data) -> Result<String, Error>? {
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return nil }
            buffer.append(chunk)
            while let newlineRange = buffer.firstRange(of: Data([0x0A])) {
                let lineData = buffer[..<newlineRange.lowerBound]
                buffer.removeSubrange(...newlineRange.lowerBound)
                if let parsed = parseResultLine(lineData) {
                    return parsed
                }
            }
            return nil
        }

        func flushRemainingAndExtractResult(_ trailingChunk: Data) -> Result<String, Error>? {
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return nil }
            buffer.append(trailingChunk)
            while let newlineRange = buffer.firstRange(of: Data([0x0A])) {
                let lineData = buffer[..<newlineRange.lowerBound]
                buffer.removeSubrange(...newlineRange.lowerBound)
                if let parsed = parseResultLine(lineData) {
                    return parsed
                }
            }
            if !buffer.isEmpty {
                let lastLine = buffer
                buffer.removeAll()
                if let parsed = parseResultLine(lastLine) {
                    return parsed
                }
            }
            return nil
        }

        func markFinishedIfNeeded() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return false }
            finished = true
            return true
        }

        private func parseResultLine(_ lineData: Data) -> Result<String, Error>? {
            guard !lineData.isEmpty,
                  let event = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  (event["event"] as? String) == "result" else {
                return nil
            }
            let res = event["result"] as? [String: Any] ?? [:]
            if (res["status"] as? String) == "ERROR" {
                let errText = (res["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                return .failure(NotulenSummaryError.cliExecutionFailed(errText ?? "Agy mengembalikan error."))
            }
            let response = (res["response"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return .success(response)
        }
    }

    private nonisolated static func invokeAgyCLI(
        executablePath: String,
        prompt: String,
        model: String,
        timeoutSeconds: TimeInterval = 90
    ) async throws -> String {
        let payloadObject: [String: Any] = [
            "event": "user",
            "message": ["content": prompt],
        ]
        let inputData = try JSONSerialization.data(withJSONObject: payloadObject) + Data("\n".utf8)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.currentDirectoryURL = FileManager.default.temporaryDirectory
                process.arguments = [
                    "--input-format", "stream-json",
                    "--output-format", "stream-json",
                    "--disable-slash-commands",
                    "--model", model,
                    "--print=",
                ]

                let stdinPipe = Pipe()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardInput = stdinPipe
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                let state = AgyStreamState()

                @Sendable func finish(_ result: Result<String, Error>) {
                    guard state.markFinishedIfNeeded() else { return }
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    if process.isRunning {
                        process.terminate()
                    }
                    continuation.resume(with: result)
                }

                let timeoutWorkItem = DispatchWorkItem {
                    finish(.failure(NotulenSummaryError.cliExecutionFailed("Waktu tunggu CLI Agy habis (\(Int(timeoutSeconds)) dtk).")))
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutWorkItem)

                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    if chunk.isEmpty {
                        handle.readabilityHandler = nil
                        return
                    }
                    if let result = state.appendAndExtractResult(chunk) {
                        timeoutWorkItem.cancel()
                        finish(result)
                    }
                }

                process.terminationHandler = { proc in
                    timeoutWorkItem.cancel()
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    let remaining = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    if let result = state.flushRemainingAndExtractResult(remaining) {
                        finish(result)
                        return
                    }
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrText = String(decoding: stderrData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    if proc.terminationStatus != 0 {
                        finish(.failure(NotulenSummaryError.cliExecutionFailed(
                            stderrText.isEmpty ? "Proses agy keluar dengan kode \(proc.terminationStatus)." : stderrText
                        )))
                    } else {
                        finish(.failure(NotulenSummaryError.cliExecutionFailed("Stream agy berakhir sebelum mengirim hasil ringkasan.")))
                    }
                }

                do {
                    try process.run()
                    stdinPipe.fileHandleForWriting.write(inputData)
                    try? stdinPipe.fileHandleForWriting.close()
                } catch {
                    timeoutWorkItem.cancel()
                    finish(.failure(NotulenSummaryError.cliExecutionFailed(error.localizedDescription)))
                }
            }
        }
    }
}

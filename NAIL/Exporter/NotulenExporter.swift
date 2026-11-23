import AppKit
import Foundation

struct NotulenFile: Identifiable, Hashable, Sendable {
    var id: URL { url }
    var url: URL
    var name: String
    var modifiedAt: Date
}

enum NotulenExporter {
    nonisolated static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("NAIL/Notulen")
    }

    nonisolated static func listFiles(baseDir: URL = defaultDirectory()) -> [NotulenFile] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: baseDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .map { url in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                return NotulenFile(
                    url: url,
                    name: url.deletingPathExtension().lastPathComponent,
                    modifiedAt: values?.contentModificationDate ?? .distantPast
                )
            }
            .sorted { $0.name > $1.name }
    }

    nonisolated static func readContent(of url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    nonisolated static func deleteFile(at url: URL) throws {
        guard url.pathExtension.lowercased() == "md" else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    nonisolated static func meetCode(from link: String) -> String? {
        guard let match = link.trimmingCharacters(in: .whitespacesAndNewlines)
            .firstMatch(of: #/meet\.google\.com/([a-z]{3}-[a-z]{4}-[a-z]{3})/#) else {
            return nil
        }
        return String(match.1)
    }

    nonisolated static func meetingIdentifier(from link: String) -> String? {
        if let code = meetCode(from: link) { return code }
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let host = components.host?.lowercased(),
              host == "teams.microsoft.com" || host == "teams.live.com" || host == "teams.cloud.microsoft" else {
            return nil
        }
        if let match = components.path.firstMatch(of: #//meet/([A-Za-z0-9_-]+)/#) {
            return "teams-\(match.1)"
        }
        return "teams-rapat"
    }

    nonisolated static func slugify(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "rapat" }
        var out = ""
        var lastHyphen = false
        for ch in trimmed {
            if ch.isASCII && (ch.isLetter || ch.isNumber) {
                out.append(ch)
                lastHyphen = false
            } else if ch.isLetter || ch.isNumber {
                let folded = String(ch).folding(
                    options: [.diacriticInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                )
                for scalarChar in folded where scalarChar.isASCII && (scalarChar.isLetter || scalarChar.isNumber) {
                    out.append(scalarChar)
                    lastHyphen = false
                }
            } else if !lastHyphen && !out.isEmpty {
                out.append("-")
                lastHyphen = true
            }
            if out.count >= 48 { break }
        }
        let cleaned = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return cleaned.isEmpty ? "rapat" : cleaned
    }

    nonisolated static func sessionURL(
        title: String,
        meetLink: String,
        startedAt: Date = Date(),
        baseDir: URL = defaultDirectory()
    ) -> URL {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = trimmedTitle.isEmpty ? (meetingIdentifier(from: meetLink) ?? "rapat") : slugify(trimmedTitle)
        let stamp = filenameDateString(for: startedAt)
        return baseDir.appendingPathComponent("\(stamp)_\(slug).md")
    }

    nonisolated static func uniqueSessionURL(
        title: String,
        meetLink: String,
        startedAt: Date = Date(),
        baseDir: URL = defaultDirectory()
    ) -> URL {
        let baseURL = sessionURL(title: title, meetLink: meetLink, startedAt: startedAt, baseDir: baseDir)
        let fm = FileManager.default
        if !fm.fileExists(atPath: baseURL.path) { return baseURL }
        let stem = baseURL.deletingPathExtension().lastPathComponent
        var index = 2
        while true {
            let candidate = baseDir.appendingPathComponent("\(stem)-\(index).md")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }

    private nonisolated static func meetingLine(_ entry: TranscriptEntry, timestamp: String) -> String {
        guard let speaker = entry.speaker else { return "- [\(timestamp)] \(entry.text)" }
        let escaped = speaker.reduce(into: "") { result, char in
            if "\\`*_{}[]<>!&|~".contains(char) { result.append("\\") }
            result.append(char)
        }
        return "- [\(timestamp)] **\(escaped):** \(entry.text)"
    }

    nonisolated static func writeSession(
        to file: URL,
        title: String,
        meetLink: String,
        startedAt: Date,
        endedAt: Date? = nil,
        interrupted: Bool = false,
        entries: [TranscriptEntry]
    ) throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let isTeams = MeetSession.detectPlatform(meetLink) == .microsoftTeams
        let code = meetCode(from: meetLink)
        let heading = !trimmedTitle.isEmpty
            ? trimmedTitle
            : (isTeams ? "Rapat Microsoft Teams" : (code.map { "Rapat \($0)" } ?? "Rapat Google Meet"))

        var lines: [String] = [
            "# \(heading)",
            "",
            "- **Tanggal:** \(dateOnlyString(for: startedAt))",
            "- **Mulai:** \(TranscriptEntry.formatTime(startedAt))",
        ]
        let cleanLink = meetLink.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanLink.isEmpty {
            lines.append("- **\(isTeams ? "Link Teams" : "Link Meet"):** \(cleanLink)")
        }
        if let endedAt {
            let statusText = interrupted
                ? "Terputus (\(TranscriptEntry.formatTime(endedAt)))"
                : "Selesai (\(TranscriptEntry.formatTime(endedAt)))"
            lines.append("- **Status:** \(statusText)")
        } else {
            lines.append("- **Status:** Berlangsung")
        }

        lines.append("")
        lines.append("## Transkrip & Tanya Jawab")
        lines.append("")

        for entry in entries.sorted(by: { $0.timestamp < $1.timestamp }) {
            let ts = TranscriptEntry.formatTime(entry.timestamp)
            switch entry.kind {
            case .meeting:
                lines.append(meetingLine(entry, timestamp: ts))
            case .command:
                lines.append("")
                lines.append("**Dengar (\(ts)):** \(entry.text)")
            case .reply:
                let latencyTag = entry.latencySeconds.map { " · \(TranscriptEntry.formatLatency($0))" } ?? ""
                lines.append("**Nail (\(ts)\(latencyTag)):** \(entry.text)")
                lines.append("")
            }
        }

        let fm = FileManager.default
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    nonisolated static func todayURL(date: Date = Date(), baseDir: URL = defaultDirectory()) -> URL {
        baseDir.appendingPathComponent("\(dateOnlyString(for: date)).md")
    }

    nonisolated static func appendTurn(
        heard: String,
        reply: String,
        heardAt: Date? = nil,
        replyAt: Date? = nil,
        latencySeconds: Double? = nil,
        date: Date = Date(),
        baseDir: URL = defaultDirectory()
    ) throws {
        let file = todayURL(date: date, baseDir: baseDir)
        let header = headerString(for: date)
        let timeString = TranscriptEntry.formatTime(date)
        let heardTime = TranscriptEntry.formatTime(heardAt ?? date)
        let replyTime = TranscriptEntry.formatTime(replyAt ?? date)
        let latencyTag = latencySeconds.map { " · \(TranscriptEntry.formatLatency($0))" } ?? ""
        let block = "\n## \(timeString)\n\n**Dengar (\(heardTime)):** \(heard)\n\n**Nail (\(replyTime)\(latencyTag)):** \(reply)\n"
        try appendBlock(block, to: file, header: header)
    }

    nonisolated static func exportSession(
        entries: [TranscriptEntry],
        interrupted: Bool = false,
        date: Date = Date(),
        baseDir: URL = defaultDirectory()
    ) throws {
        guard !entries.isEmpty else { return }
        let file = todayURL(date: date, baseDir: baseDir)
        let header = headerString(for: date)
        let timeString = TranscriptEntry.formatTime(date)
        var lines: [String] = ["\n## Sesi \(timeString)\(interrupted ? " (terputus)" : "")\n"]
        for entry in entries.sorted(by: { $0.timestamp < $1.timestamp }) {
            let ts = TranscriptEntry.formatTime(entry.timestamp)
            switch entry.kind {
            case .meeting:
                lines.append(meetingLine(entry, timestamp: ts))
            case .command:
                lines.append("\n**Dengar (\(ts)):** \(entry.text)")
            case .reply:
                let latencyTag = entry.latencySeconds.map { " · \(TranscriptEntry.formatLatency($0))" } ?? ""
                lines.append("**Nail (\(ts)\(latencyTag)):** \(entry.text)\n")
            }
        }
        try appendBlock(lines.joined(separator: "\n") + "\n", to: file, header: header)
    }

    @MainActor static func openToday(baseDir: URL = defaultDirectory()) {
        openLatest(preferred: todayURL(baseDir: baseDir), baseDir: baseDir)
    }

    @MainActor static func openFolder(baseDir: URL = defaultDirectory()) {
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(baseDir)
    }

    @MainActor static func openLatest(preferred: URL? = nil, baseDir: URL = defaultDirectory()) {
        if let preferred, FileManager.default.fileExists(atPath: preferred.path) {
            NSWorkspace.shared.open(preferred)
            return
        }
        if let latest = listFiles(baseDir: baseDir).first {
            NSWorkspace.shared.open(latest.url)
            return
        }
        openFolder(baseDir: baseDir)
    }

    private nonisolated static func dateOnlyString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private nonisolated static func filenameDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        return formatter.string(from: date)
    }

    private nonisolated static func headerString(for date: Date) -> String {
        "# Notulen \(dateOnlyString(for: date))\n"
    }

    private nonisolated static func appendBlock(_ block: String, to file: URL, header: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: file.path) {
            try (header + block).write(to: file, atomically: true, encoding: .utf8)
            return
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(block.utf8))
    }
}

import Foundation
import Observation

struct TranscriptEntry: Identifiable, Codable, Equatable, Sendable {
    enum EntryKind: String, Codable, Sendable {
        case meeting
        case command
        case reply
    }

    var id: UUID
    var timestamp: Date
    var kind: EntryKind
    var text: String
    var speaker: String?
    var latencySeconds: Double?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        kind: EntryKind,
        text: String,
        speaker: String? = nil,
        latencySeconds: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.text = text
        self.speaker = speaker
        self.latencySeconds = latencySeconds
    }

    var formattedTime: String {
        Self.formatTime(timestamp)
    }

    nonisolated static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    nonisolated static func formatLatency(_ seconds: Double) -> String {
        String(format: "%.1f dtk", max(0, seconds))
    }
}

@MainActor @Observable
final class SessionTranscriptStore {
    private(set) var entries: [TranscriptEntry] = []

    var notulenLineCount: Int {
        entries.filter { $0.kind == .meeting || $0.kind == .command }.count
    }

    /// Mode Siaga discards ambient meeting chatter before "Nail" is called.
    func recordMeetingLine(_ text: String, mode: ListeningMode, speaker: String? = nil, timestamp: Date = Date()) {
        guard mode == .notulen else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let cleanSpeaker = speaker?.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        entries.append(TranscriptEntry(timestamp: timestamp, kind: .meeting, text: clean,
                                       speaker: cleanSpeaker?.isEmpty == false ? cleanSpeaker : nil))
    }

    func recordExchange(
        heard: String,
        reply: String,
        heardAt: Date = Date(),
        replyAt: Date = Date(),
        latencySeconds: Double? = nil
    ) {
        let cleanHeard = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanReply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanHeard.isEmpty {
            entries.append(TranscriptEntry(timestamp: heardAt, kind: .command, text: cleanHeard))
        }
        if !cleanReply.isEmpty {
            entries.append(TranscriptEntry(timestamp: replyAt, kind: .reply, text: cleanReply, latencySeconds: latencySeconds))
        }
    }

    func clear() {
        entries.removeAll()
    }
}

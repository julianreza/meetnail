import Foundation
import Observation

enum MeetVoiceProvider: String, CaseIterable {
    case codex, deepseek, antigravity

    var label: String {
        switch self {
        case .codex: "Codex Live Voice"
        case .deepseek: "DeepSeek"
        case .antigravity: "Antigravity (Google AI Pro)"
        }
    }
    var recipient: String {
        switch self {
        case .codex: "OpenAI (ChatGPT)"
        case .deepseek: "DeepSeek"
        case .antigravity: "Google (Antigravity)"
        }
    }
}

@MainActor @Observable
final class MeetSession {
    static let shared = MeetSession()
    private(set) var active = false
    private(set) var joiningMeeting = false
    private(set) var status = ""
    private(set) var voiceReady = false
    private(set) var voiceBusy = false
    private(set) var voiceTranscript = ""
    private(set) var voiceReply = ""
    private var voiceProvider: MeetVoiceProvider?
    private var input: FileHandle?

    nonisolated static func validLink(_ text: String) -> Bool {
        text.wholeMatch(of: #/https://meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}/#) != nil
    }

    func join(_ text: String, provider: MeetVoiceProvider? = nil) {
        guard !active else { return }
        let link = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.validLink(link) else {
            status = "Tempel link Google Meet yang valid."
            return
        }
        launch(link, provider: provider)
    }

    func signIn() { launch("--login") }

    func answerMeeting() {
        guard voiceReady, !voiceBusy, let input else { return }
        do {
            try input.write(contentsOf: Data("voice-turn\n".utf8))
            voiceBusy = true
            status = "Mulai menyimak audio Meet…"
        } catch {
            status = "Tidak dapat mengirim perintah suara ke Nail."
        }
    }

    func leave() {
        if let input {
            voiceReady = false
            status = "Menutup sesi Meet…"
            try? input.close()
            self.input = nil
        }
    }

    private func launch(_ target: String, provider: MeetVoiceProvider? = nil) {
        guard !active else { return }
        let bundle = Bundle.main.bundleURL
        let runtime = bundle.appendingPathComponent("Contents/Frameworks/Electron.app/Contents/MacOS/Electron")
        let worker = bundle.appendingPathComponent("Contents/Resources/meet.cjs")
        guard FileManager.default.isExecutableFile(atPath: runtime.path), FileManager.default.isReadableFile(atPath: worker.path) else {
            status = "Chromium tertanam belum terpasang di Nail."
            return
        }
        let profile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Nail/Meet Chromium")
        let process = Process()
        let pipe = Pipe()
        let commands = Pipe()
        process.executableURL = runtime
        process.arguments = [worker.path, target, profile.path]
        if let provider { process.arguments?.append(provider.rawValue) }
        if provider == .deepseek { process.arguments?.append(Pipeline.root.appendingPathComponent("spike/nail-loop.py").path) }
        if provider == .antigravity { process.arguments?.append(Pipeline.root.appendingPathComponent("spike/agy-voice.py").path) }
        process.standardInput = commands
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch {
            status = "Chromium Nail tidak bisa dijalankan."
            return
        }
        input = commands.fileHandleForWriting
        voiceProvider = provider
        voiceTranscript = ""
        voiceReply = ""
        active = true
        joiningMeeting = target != "--login"
        status = joiningMeeting ? "Membuka Google Meet…" : "Membuka login Google…"
        let reader = pipe.fileHandleForReading
        Task.detached { [weak self] in
            var pending = Data()
            while true {
                let data = reader.availableData
                if data.isEmpty { break }
                pending.append(data)
                while let newline = pending.firstIndex(of: 10) {
                    let event = String(decoding: pending[..<newline], as: UTF8.self)
                    pending.removeSubrange(...newline)
                    await self?.receive(event)
                }
            }
            process.waitUntilExit()
            await self?.finished(exitCode: process.terminationStatus)
        }
    }

    private func receive(_ event: String) {
        if CommandLine.arguments.contains("--join-meet"), !event.hasPrefix("voice-result ") {
            FileHandle.standardOutput.write(Data("MEET \(event)\n".utf8))
        }
        switch event {
        case "login-panel": status = "Selesaikan login di panel Nail."
        case "submitted": status = "Menunggu konfirmasi Meet…"
        case "waiting": status = "Menunggu host mengizinkan Nail."
        case "joined":
            voiceReady = voiceProvider != nil && input != nil
            status = voiceProvider.map { "Nail sudah masuk. Suara: \($0.label)." } ?? "Nail sudah masuk. Mic dan kamera diblokir."
        case "voice-standby":
            voiceBusy = false
            if !status.hasPrefix("Jawaban diputar") {
                status = "Siaga di Meet — menunggu panggilan 'Nail'…"
            }
        case "voice-recording": voiceBusy = true; status = "Menyimak audio Meet (maks 8 detik)…"
        case "voice-processing": voiceBusy = true; status = "Memproses audio dan menyiapkan jawaban…"
        case "voice-codex-connecting": status = "Menyambungkan suara ke Codex…"
        case "voice-codex-listening": status = "Codex terhubung. Menunggu ucapan terbaca…"
        case "voice-codex-heard": status = "Codex sudah menangkap ucapan. Menunggu jawabannya…"
        case "voice-sending": status = "Mengirim suara Nail ke Meet…"
        case "voice-no-audio": voiceBusy = false; status = "Tidak ada ucapan yang terbaca dari Meet."
        case "voice-no-mic": voiceBusy = false; status = "Meet belum memakai mic virtual Nail."
        case "voice-failed": voiceBusy = false; status = "Audio atau jawaban gagal diproses."
        case "voice-codex-quota": voiceBusy = false; status = "Kuota Codex habis. Tidak beralih ke API key."
        case "voice-codex-login": voiceBusy = false; status = "Login Codex lewat ChatGPT: jalankan codex login."
        case "voice-codex-missing": voiceBusy = false; status = "Codex CLI tidak ditemukan."
        case "voice-codex-timeout": voiceBusy = false; status = "Codex belum mengembalikan suara dalam 50 detik."
        case "voice-codex-connection": voiceBusy = false; status = "Koneksi suara ke Codex tidak terbentuk."
        case "voice-codex-no-transcript": voiceBusy = false; status = "Codex belum membaca ucapan. Coba bicara dengan mic Meet aktif setelah menekan tombol."
        case "voice-codex-error": voiceBusy = false; status = "Sesi Codex Live Voice gagal."
        case "voice-unavailable": status = "Mic virtual Nail gagal disiapkan."
        case "left": status = "Nail tidak lagi di rapat."
        case "login-required": status = "Login dulu lewat menu Nail → Login Google untuk Nail."
        case "rejected": status = "Google Meet menolak Nail masuk."
        case "admission-timeout": status = "Meet belum mengizinkan Nail masuk."
        case "lobby-timeout": status = "Tombol Gabung tidak aktif di lobi Meet."
        case "failed": status = "Nail tidak dapat membuka sesi Meet."
        default:
            if event.hasPrefix("voice-no-audio") {
                voiceBusy = false
                if event.count > 15,
                   let diag = try? JSONDecoder().decode([String: Double].self, from: Data(event.dropFirst(15).utf8)) {
                    let tracks = Int(diag["tracks"] ?? 0)
                    let live = Int(diag["live"] ?? 0)
                    let muted = Int(diag["muted"] ?? 0)
                    if let peak = diag["peak"] {
                        let rx = Int(diag["rxPackets"] ?? 0)
                        let energy = diag["rxEnergy"] ?? 0
                        status = energy < 0.001
                            ? "Meet hanya mengirim hening (\(rx) pkt, energi \(energy)). Cek mic peserta di Meet."
                            : "Tidak ada ucapan dari Meet (puncak \(Int(peak)) dBFS, \(live)/\(tracks) track, \(muted) mute, \(rx) pkt, energi \(energy))."
                    } else {
                        status = "Tidak ada ucapan dari Meet (\(live)/\(tracks) track audio peserta)."
                    }
                } else {
                    status = "Tidak ada ucapan yang terbaca dari Meet."
                }
                break
            }
            if event.hasPrefix("voice-wake ") {
                voiceBusy = true
                if let info = try? JSONDecoder().decode([String: String].self, from: Data(event.dropFirst(11).utf8)),
                   let heard = info["heard"], !heard.isEmpty {
                    voiceTranscript = heard
                }
                status = "Nail terpanggil — menyiapkan jawaban…"
                break
            }
            guard event.hasPrefix("voice-result "), input != nil else { break }
            voiceBusy = false
            if let result = try? JSONDecoder().decode([String: String].self, from: Data(event.dropFirst(13).utf8)) {
                voiceTranscript = result["heard"] ?? ""
                voiceReply = result["reply"] ?? ""
                status = "Jawaban diputar ke mic virtual Meet."
            }
        }
    }

    private func finished(exitCode: Int32) {
        try? input?.close()
        input = nil
        voiceReady = false
        voiceBusy = false
        if !joiningMeeting { status = "Panel login ditutup." }
        else if exitCode == 0 { status = "Nail tidak lagi di rapat." }
        else if status == "Membuka Google Meet…" || status == "Menunggu konfirmasi Meet…" ||
            status == "Nail sudah masuk. Mic dan kamera diblokir." || status == "Menunggu host mengizinkan Nail." {
            status = "Proses Chromium Nail berhenti sebelum sesi selesai."
        }
        active = false
        joiningMeeting = false
    }
}

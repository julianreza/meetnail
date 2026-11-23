import AppKit
import SwiftUI

/// Spike Fase 0/1: ikon menu bar + panel HUD + satu putaran dengar→jawab lewat pipeline DeepSeek.
@main
struct NailSpikeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Nail", systemImage: "waveform") {
            Button("Tampilkan HUD") { HUDPanel.shared.show() }
            Button("Sembunyikan HUD") { HUDPanel.shared.hide() }
            Button("Buka notulen hari ini") { Notulen.openToday() }
            Button("Login Google untuk Nail") { MeetSession.shared.signIn() }
                .disabled(MeetSession.shared.active)
            Divider()
            Button("Keluar") { NSApp.terminate(nil) }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        HUDPanel.shared.show()
        if CommandLine.arguments.contains("--google-login") {
            MeetSession.shared.signIn()
        }
        if let index = CommandLine.arguments.firstIndex(of: "--join-meet"),
           CommandLine.arguments.indices.contains(index + 1) {
            let provider: MeetVoiceProvider? = CommandLine.arguments.contains("--meet-voice") ? .codex : nil
            MeetSession.shared.join(CommandLine.arguments[index + 1], provider: provider)
        }

        if CommandLine.arguments.contains("--print-window") {
            let panel = HUDPanel.shared
            print("level=\(panel.level.rawValue)")
            print("collectionBehavior=\(panel.collectionBehavior.rawValue)")
            print("isVisible=\(panel.isVisible) frame=\(panel.frame)")
            NSApp.terminate(nil)
        }
        if CommandLine.arguments.contains("--print-notulen") {
            let file = Notulen.today()
            print("path=\(file.path) exists=\(FileManager.default.fileExists(atPath: file.path))")
            NSApp.terminate(nil)
        }
        if CommandLine.arguments.contains("--run-turn") {
            let pid = CommandLine.arguments.firstIndex(of: "--pid").flatMap { index -> Int? in
                CommandLine.arguments.count > index + 1 ? Int(CommandLine.arguments[index + 1]) : nil
            }
            let turns = CommandLine.arguments.firstIndex(of: "--turns").flatMap { index -> Int? in
                CommandLine.arguments.count > index + 1 ? Int(CommandLine.arguments[index + 1]) : nil
            } ?? 1
            let gate = !CommandLine.arguments.contains("--no-gate")
            for _ in 0..<turns {
                print(Pipeline.runTurn(microphone: pid == nil, pid: pid, requireTrigger: gate).output)
            }
            NSApp.terminate(nil)
        }
    }
}

enum Pipeline {
    static let root = URL(fileURLWithPath: "/Users/rezajulian/Documents/meetnail")

    struct Turn {
        var output: String
        var heard = ""
        var reply = ""
        var rms: Int? = nil
        var error: String? = nil

        static func failure(_ message: String) -> Turn {
            let data = (try? JSONEncoder().encode(["error": message])) ?? Data()
            return Turn(output: String(decoding: data, as: UTF8.self), error: message)
        }
    }

    /// PID audio aplikasi lain yang sedang berbunyi, mis. helper Arc saat Meet aktif.
    static func detectPlayingPID() -> Int? {
        let process = Process()
        process.executableURL = root.appendingPathComponent("spike/.build/debug/nail-spike")
        process.arguments = ["processes"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") where line.contains("output=1") {
            let fields = line.split(separator: " ")
            if let pidField = fields.first(where: { $0.hasPrefix("pid=") }),
               let pid = Int(pidField.dropFirst(4)),
               pid != Int(ProcessInfo.processInfo.processIdentifier) {
                return pid
            }
        }
        return nil
    }

    static func runTurn(microphone: Bool, pid: Int?, requireTrigger: Bool = true, shouldProcess: () -> Bool = { true }) -> Turn {
        let source: [String]
        if let pid {
            source = ["--pid", String(pid)]
        } else if microphone {
            source = ["--mic"]
        } else {
            return .failure("Belum ada audio aplikasi. Putar audio, lalu tekan Dengar terus.")
        }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("nail-\(UUID())")
        let wav = work.appendingPathComponent("turn.wav")
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        } catch {
            return .failure("Tidak bisa membuat file rekaman sementara.")
        }
        defer { try? FileManager.default.removeItem(at: work) }

        let recorder = Process()
        recorder.executableURL = root.appendingPathComponent("spike/.build/debug/nail-spike")
        recorder.arguments = ["record", "8", "--out", wav.path] + source
        recorder.standardOutput = FileHandle.nullDevice
        recorder.standardError = FileHandle.nullDevice
        guard shouldProcess() else { return .failure("Berhenti") }
        guard (try? recorder.run()) != nil else { return .failure("Perekam Nail tidak bisa dijalankan.") }
        recorder.waitUntilExit()
        guard shouldProcess() else { return .failure("Berhenti") }
        guard recorder.terminationStatus == 0, FileManager.default.fileExists(atPath: wav.path) else {
            return .failure(microphone
                ? "Perekaman gagal. Cek izin Mikrofon dan input headset."
                : "Perekaman gagal. Cek izin Perekaman Audio Sistem dan audio aplikasi.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        let arguments = [root.appendingPathComponent("spike/nail-loop.py").path, "--from-wav", wav.path]
            + (requireTrigger ? ["--require", "Nail"] : [])
        process.arguments = arguments
        process.currentDirectoryURL = root
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return .failure("Transkripsi Nail tidak bisa dijalankan.") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0, let lastLine = output.split(separator: "\n").last,
              let json = (try? JSONSerialization.jsonObject(with: Data(lastLine.utf8))) as? [String: Any],
              let heard = json["heard"] as? String else {
            return .failure("Transkripsi atau jawaban gagal. Cek koneksi dan akses DeepSeek.")
        }
        return Turn(output: output, heard: heard, reply: json["reply"] as? String ?? "",
                    rms: json["rms"] as? Int)
    }
}

enum Notulen {
    static func today() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let name = "\(formatter.string(from: Date())).md"
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("NAIL/Notulen")
            .appendingPathComponent(name)
    }

    static func openToday() {
        let file = today()
        if FileManager.default.fileExists(atPath: file.path) {
            NSWorkspace.shared.open(file)
        } else {
            NSWorkspace.shared.open(file.deletingLastPathComponent())
        }
    }
}

final class HUDPanel: NSPanel {
    static let shared = HUDPanel()

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 405),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: false
        )
        title = "HUD"
        titlebarAppearsTransparent = true
        isFloatingPanel = true
        level = .statusBar
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = NSHostingView(rootView: HUDContent())
        setFrameTopLeftPoint(NSPoint(x: 40, y: (NSScreen.main?.visibleFrame.maxY ?? 800) - 40))
    }

    func show() { orderFrontRegardless() }
    func hide() { orderOut(nil) }
}

final class LoopState: @unchecked Sendable {
    static let shared = LoopState()
    private let lock = NSLock()
    private var on = false
    var isOn: Bool { lock.lock(); defer { lock.unlock() }; return on }
    func set(_ value: Bool) { lock.lock(); on = value; lock.unlock() }
}

struct HUDContent: View {
    @State private var status = "Menunggu persetujuan"
    @State private var heard = ""
    @State private var reply = ""
    @State private var listening = false
    @State private var stopping = false
    @State private var meetingSource = false
    @State private var meetLink = ""
    @State private var meetVoice = false
    @AppStorage("meetVoiceProvider") private var meetProvider: MeetVoiceProvider = .codex
    @State private var attendeesInformed = false
    private let meet = MeetSession.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bukti Nail").font(.headline)
            Text(status).font(.callout.weight(.medium))
            Toggle("Dengar audio aplikasi (Meet/Zoom)", isOn: $meetingSource)
                .font(.callout)
                .disabled(listening)
            HStack {
                TextField("Link Google Meet", text: $meetLink)
                    .accessibilityLabel("Link Google Meet")
                    .disabled(meet.active)
                    .onSubmit { joinMeet() }
                if meet.joiningMeeting {
                    Button("Keluar Meet") { meet.leave() }
                } else {
                    Button("Gabung Meet") { joinMeet() }
                        .disabled(meet.active || meetLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            (meetVoice && !attendeesInformed))
                }
            }
            if !meet.active {
                Toggle("Dengar dan jawab di Meet", isOn: $meetVoice)
                    .font(.callout)
                Picker("Penyedia suara Meet", selection: $meetProvider) {
                    ForEach(MeetVoiceProvider.allCases, id: \.self) { provider in
                        Text(provider.label).tag(provider)
                    }
                }
                .onChange(of: meetProvider) { _, _ in attendeesInformed = false }
                if meetVoice {
                    Toggle("Peserta sudah diberi tahu audio dikirim ke \(meetProvider.recipient)", isOn: $attendeesInformed)
                        .font(.callout)
                }
            }
            if meet.voiceReady {
                Button("Dengar & jawab di Meet") { meet.answerMeeting() }
                    .disabled(meet.voiceBusy)
            }
            if !meet.status.isEmpty {
                Text(meet.status).font(.callout).lineLimit(2)
                    .onChange(of: meet.active) { _, active in
                        if !active { attendeesInformed = false }
                    }
            }
            Divider()
            let transcript = meet.voiceTranscript.isEmpty ? heard : meet.voiceTranscript
            let response = meet.voiceReply.isEmpty ? reply : meet.voiceReply
            Text(transcript.isEmpty ? "Belum ada transkrip." : "Dengar: \(transcript)")
                .font(.callout)
                .lineLimit(3)
            Text(response.isEmpty ? "" : "Nail: \(response)")
                .font(.callout)
                .lineLimit(3)
            Spacer()
            HStack {
                Button(stopping ? "Menghentikan…" : listening ? "Berhenti" : "Dengar terus") {
                    if listening {
                        stopping = true
                        LoopState.shared.set(false)
                        status = "Menghentikan…"
                    } else {
                        listening = true
                        LoopState.shared.set(true)
                        startLoop(meeting: meetingSource)
                    }
                }
                .disabled(stopping)
                Button("Dengar sekali") { startOneShot() }
                    .disabled(listening || stopping)
                Button("Approve") { status = "Disetujui" }
                Button("Reject") { status = "Ditolak" }
            }
        }
        .padding(16)
        .frame(width: 380, height: 405, alignment: .topLeading)
    }

    private func joinMeet() {
        guard !meetVoice || attendeesInformed else { return }
        meet.join(meetLink, provider: meetVoice ? meetProvider : nil)
    }

    private func startOneShot() {
        status = meetingSource ? "Merekam audio aplikasi…" : "Merekam mikrofon…"
        DispatchQueue.global(qos: .userInitiated).async {
            let pid = meetingSource ? Pipeline.detectPlayingPID() : nil
            let turn = Pipeline.runTurn(microphone: !meetingSource, pid: pid, requireTrigger: false)
            DispatchQueue.main.async {
                status = turn.error ?? (turn.rms == 0 ? "Tidak ada sinyal pada rekaman." : "Selesai")
                if !turn.heard.isEmpty {
                    heard = turn.heard
                    reply = turn.reply
                }
            }
        }
    }

    private func startLoop(meeting: Bool) {
        let activeStatus = meeting ? "Mendengarkan audio aplikasi…" : "Mendengarkan mikrofon…"
        status = activeStatus
        DispatchQueue.global(qos: .userInitiated).async {
            let pid = meeting ? Pipeline.detectPlayingPID() : nil
            var endStatus = "Berhenti"
            while LoopState.shared.isOn {
                let turn = Pipeline.runTurn(microphone: !meeting, pid: pid) { LoopState.shared.isOn }
                if let error = turn.error {
                    endStatus = error
                    break
                }
                DispatchQueue.main.async {
                    guard !stopping else { return }
                    if turn.rms == 0 {
                        status = meeting
                            ? "Tidak ada sinyal. Cek izin Perekaman Audio Sistem dan suara aplikasi."
                            : "Tidak ada sinyal. Cek izin Mikrofon dan input headset."
                    } else {
                        status = activeStatus
                    }
                    if !turn.heard.isEmpty {
                        heard = turn.heard
                        reply = turn.reply
                    }
                }
            }
            let finalStatus = endStatus
            DispatchQueue.main.async {
                status = stopping ? "Berhenti" : finalStatus
                LoopState.shared.set(false)
                listening = false
                stopping = false
            }
        }
    }
}

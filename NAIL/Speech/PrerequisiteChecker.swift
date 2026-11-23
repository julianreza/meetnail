import Foundation

struct PrerequisiteStatus: Equatable, Sendable {
    var agyInstalled: Bool
    var uvInstalled: Bool
    var ffmpegInstalled: Bool
    var whisperModelCached: Bool
    var meetProfileExists: Bool
    var electronBundled: Bool

    var allReady: Bool {
        agyInstalled && uvInstalled && ffmpegInstalled && whisperModelCached && meetProfileExists && electronBundled
    }

    var missingItems: [String] {
        var items: [String] = []
        if !electronBundled {
            items.append("Runtime Electron belum terpasang di Meet Nail.app/Contents/Frameworks/Electron.app.")
        }
        if !agyInstalled {
            items.append("Antigravity CLI (agy) belum ditemukan di ~/.local/bin/agy atau PATH.")
        }
        if !uvInstalled {
            items.append("uv belum terpasang (/opt/homebrew/bin/uv).")
        }
        if !ffmpegInstalled {
            items.append("ffmpeg belum terpasang (/opt/homebrew/bin/ffmpeg).")
        }
        if !whisperModelCached {
            items.append("Bobot Whisper lokal belum terunduh di ~/.cache/huggingface/hub.")
        }
        if !meetProfileExists {
            items.append("Belum ada profil login Google Meet — buka menu Nail → Login Google untuk Nail.")
        }
        return items
    }
}

enum PrerequisiteChecker {
    nonisolated static func check(whisperModel: String = "small", bundleURL: URL = Bundle.main.bundleURL) -> PrerequisiteStatus {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        let agyCandidates = [
            home.appendingPathComponent(".local/bin/agy").path,
            "/opt/homebrew/bin/agy",
            "/usr/local/bin/agy",
        ]
        let uvCandidates = ["/opt/homebrew/bin/uv", "/usr/local/bin/uv"]
        let ffmpegCandidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]

        let agyInstalled = agyCandidates.contains { fm.isExecutableFile(atPath: $0) }
        let uvInstalled = uvCandidates.contains { fm.isExecutableFile(atPath: $0) }
        let ffmpegInstalled = ffmpegCandidates.contains { fm.isExecutableFile(atPath: $0) }

        let modelDir = home
            .appendingPathComponent(".cache/huggingface/hub/models--Systran--faster-whisper-\(whisperModel)")
        let whisperModelCached = fm.fileExists(atPath: modelDir.path)

        let meetProfile = home
            .appendingPathComponent("Library/Application Support/Nail/Meet Chromium")
        let meetProfileExists = fm.fileExists(atPath: meetProfile.path)

        let electronExecutable = bundleURL
            .appendingPathComponent("Contents/Frameworks/Electron.app/Contents/MacOS/Electron")
        let electronBundled = fm.isExecutableFile(atPath: electronExecutable.path)

        return PrerequisiteStatus(
            agyInstalled: agyInstalled,
            uvInstalled: uvInstalled,
            ffmpegInstalled: ffmpegInstalled,
            whisperModelCached: whisperModelCached,
            meetProfileExists: meetProfileExists,
            electronBundled: electronBundled
        )
    }
}

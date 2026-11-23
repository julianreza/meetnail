import AppKit
import SwiftUI

@MainActor
final class AppNavigator {
    static let shared = AppNavigator()
    var openMainAction: (() -> Void)?

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openMainAction?()
    }
}

@main
struct NailApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Meet Nail", id: "main") {
            MainWindowView()
                .preferredColorScheme(VoiceSettings.shared.appAppearance.colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1160, height: 760)

        MenuBarExtra {
            Text(menuStatusLabel)
            Divider()
            Button("Buka Meet Nail") {
                AppNavigator.shared.openMainAction = { openWindow(id: "main") }
                AppNavigator.shared.showMainWindow()
            }
            Button(HUDPanel.shared.metrics.isVisible ? "Sembunyikan HUD" : "Tampilkan HUD") {
                HUDPanel.shared.toggle()
            }
            Button("Panic Mute (⌘⇧M)") { MeetSession.shared.interrupt() }
                .disabled(!MeetSession.shared.active)
            Divider()
            Button("Buka notulen terbaru") {
                NotulenExporter.openLatest(preferred: MeetSession.shared.currentNotulenURL)
            }
            Button("Login Google untuk Nail") { MeetSession.shared.signIn() }
                .disabled(MeetSession.shared.active)
            Divider()
            Button("Keluar") { NSApp.terminate(nil) }
        } label: {
            Image(nsImage: NailBrandLogo.menuBarTemplateImage(isActive: MeetSession.shared.active))
                .accessibilityLabel("Meet Nail")
        }
    }

    private var menuStatusLabel: String {
        MeetSession.shared.presentation.label
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKeyManager: HotKeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotKeyManager = HotKeyManager {
            MeetSession.shared.interrupt()
        }

        if CommandLine.arguments.contains("--print-window") {
            let panel = HUDPanel.shared
            panel.show()
            print("level=\(panel.level.rawValue)")
            print("collectionBehavior=\(panel.collectionBehavior.rawValue)")
            print("isVisible=\(panel.isVisible) frame=\(panel.frame)")
            NSApp.terminate(nil)
        }
        if CommandLine.arguments.contains("--print-notulen") {
            let file = NotulenExporter.todayURL()
            print("path=\(file.path) exists=\(FileManager.default.fileExists(atPath: file.path))")
            NSApp.terminate(nil)
        }
    }
}

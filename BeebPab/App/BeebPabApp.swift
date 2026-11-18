import AppKit
import SwiftUI

@main
struct BeebPabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var presets = PresetStore()

    var body: some Scene {
        Window("BeebPab", id: "main") {
            ContentView()
                .environment(model)
                .environment(presets)
                .task {
                    // Check GitHub for new platform sizes at launch, then every hour
                    // (PresetStore itself only downloads when 24 hours have passed).
                    while !Task.isCancelled {
                        await presets.refreshIfNeeded()
                        try? await Task.sleep(for: .seconds(3600))
                    }
                }
        }
        .defaultSize(width: 1040, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("เพิ่มภาพหรือโฟลเดอร์…") { model.chooseFiles() }
                    .keyboardShortcut("o")
            }
        }

        Settings {
            SettingsView()
                .environment(presets)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

import AppKit
import SwiftUI

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private let client: MediaRemoteWizardClient = .init()

    private lazy var mainWindowController = MainWindowController(client: client)

    @AppStorage("showMainWindowOnLaunch")
    private var showMainWindowOnLaunch: Bool = true

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        _ = MainStatusItemController.shared
        if showMainWindowOnLaunch {
            showMainWindow()
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {}

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    @objc func showMainWindow() {
        mainWindowController.showWindow(nil)
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

import AppKit

final class MainWindowController: NSWindowController, NSWindowDelegate {
    
    let client: MediaRemoteWizardClient
    
    lazy var mainViewController = MainViewController {
        MainView()
            .environmentObject(client)
    }

    override var windowNibName: NSNib.Name? { "" }

    init(client: MediaRemoteWizardClient) {
        self.client = client
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadWindow() {
        window = NSWindow(contentViewController: mainViewController)
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        window?.title = "MediaRemoteWizard"
        window?.center()
        window?.styleMask.remove(.resizable)
        window?.titlebarAppearsTransparent = true
        window?.setFrameAutosaveName("Main Window")
        window?.delegate = self
    }
    
    
    func windowWillClose(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}


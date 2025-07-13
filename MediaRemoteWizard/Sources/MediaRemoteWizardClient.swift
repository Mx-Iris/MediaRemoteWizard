import OSLog
import Foundation
import Observation
import HelperClient
import HelperCommunication
import InjectionService
import MediaRemoteWizardShared

@Observable
final class MediaRemoteWizardClient: ObservableObject {
    private let processMonitor = ProcessMonitor(processName: "mediaremoted")

    private static let logger = Logger(subsystem: "com.JH.MediaRemoteWizard", category: "ViewModel")

    public private(set) var isHelperConnected: Bool = false

    private let helperClient = HelperClient()

    private var logger: Logger { Self.logger }

    public init() {
        Task {
            do {
                try await connectToHelper()
            } catch {
                print(error)
            }
        }
    }

    public func installHelper() async throws {
        try await helperClient.installTool(name: MediaRemoteWizardDaemonBundleIdentifier)
        try await connectToHelper()
    }

    public func connectToHelper() async throws {
        try await helperClient.connectToTool(machServiceName: MediaRemoteWizardDaemonBundleIdentifier, isPrivilegedHelperTool: true)
        isHelperConnected = await helperClient.isConnectedToTool
        processMonitor.onProcessStarted = { [weak self] pid in
            guard let self else { return }
            Task {
                do {
                    guard let dylib = Bundle.main.url(forResource: "MediaRemoteDaemonInjection", withExtension: "framework") else {
                        self.logger.error("Failed to get dylib URL")
                        return
                    }
                    guard let dylibURL = Bundle(url: dylib)?.executableURL else {
                        self.logger.error("Failed to get dylib executable URL")
                        return
                    }

                    try await self.helperClient.sendToTool(request: InjectApplicationRequest(pid: pid, dylibURL: dylibURL))
                    self.logger.debug("Injected into process with PID: \(pid)")
                } catch {
                    print(error)
                }
            }
        }
        processMonitor.startMonitoring(interval: 0.5)
    }
}

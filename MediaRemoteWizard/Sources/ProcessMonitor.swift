import Foundation
import Darwin
import os.log

class ProcessMonitor {
    let targetProcessName: String
    private var monitoredPIDs: Set<pid_t> = []
    private let pidsQueue = DispatchQueue(label: "com.example.ProcessMonitor.pidsQueue")

    private var kqueueFD: Int32 = -1
    private var keventThread: Thread?
    private var timer: Timer?

    // Logger
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.JH.ProcessMonitor", category: "ProcessMonitor")

    // Callbacks
    var onProcessStarted: ((pid_t) -> Void)?
    var onProcessStopped: ((pid_t) -> Void)?

    init(processName: String) {
        self.targetProcessName = processName
    }

    func startMonitoring(interval: TimeInterval = 2.0) {
        guard kqueueFD == -1 else { return } // Already monitoring

        kqueueFD = kqueue()
        guard kqueueFD != -1 else {
            let error = String(cString: strerror(errno))
            Self.logger.error("kqueue creation failed: \(error, privacy: .public)")
            return
        }

        // Start kqueue event listening thread
        keventThread = Thread { [weak self] in
            self?.listenForKevents()
        }
        keventThread?.name = "Kevent Listener Thread"
        keventThread?.start()

        // Start polling timer
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.pollProcesses()
        }
        RunLoop.current.add(timer!, forMode: .common)
        // Initial poll
        pollProcesses()

        Self.logger.log("Started monitoring for process: \(self.targetProcessName, privacy: .public)")
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil

        // Signal kevent thread to stop
        if kqueueFD != -1 {
            close(kqueueFD)
            kqueueFD = -1
        }
        keventThread?.cancel()
        keventThread = nil

        pidsQueue.sync {
            monitoredPIDs.removeAll()
        }
        Self.logger.log("Stopped monitoring for process: \(self.targetProcessName, privacy: .public)")
    }

    private func pollProcesses() {
        var currentPIDs: Set<pid_t> = []
        let pids = allPIDs() // This can be slow, keep it outside the synchronized block.

        for pid in pids {
            // Getting process name can also be slow.
            if let processName = processName(for: pid), processName == targetProcessName {
                currentPIDs.insert(pid)
            }
        }

        pidsQueue.sync {
            let previouslyMonitored = self.monitoredPIDs

            // New processes: found in current scan but not monitored before.
            let newPIDs = currentPIDs.subtracting(previouslyMonitored)
            for pid in newPIDs {
                Self.logger.log("Detected start of \(self.targetProcessName, privacy: .public) with PID: \(pid)")
                self.monitoredPIDs.insert(pid)
                self.addKeventWatch(for: pid) // Must be called inside sync block
                // Dispatch callback to the main thread for UI safety
                DispatchQueue.main.async {
                    self.onProcessStarted?(pid)
                }
            }

            // Stopped processes: were monitored before but not found in current scan.
            let stoppedPIDs = previouslyMonitored.subtracting(currentPIDs)
            for pid in stoppedPIDs {
                // The kqueue event might have already handled this, but we double-check.
                if self.monitoredPIDs.contains(pid) {
                    Self.logger.log("Detected stop (via polling) of \(self.targetProcessName, privacy: .public) with PID: \(pid)")
                    self.monitoredPIDs.remove(pid)
                    // Dispatch callback to the main thread for UI safety
                    DispatchQueue.main.async {
                        self.onProcessStopped?(pid)
                    }
                }
            }
        }
    }

    private func listenForKevents() {
        var eventList: [kevent] = .init(repeating: .init(), count: 1)

        while kqueueFD != -1, !Thread.current.isCancelled {
            // Check kqueueFD validity before blocking
            guard fcntl(kqueueFD, F_GETFL) != -1 || errno != EBADF else {
                Self.logger.warning("kqueue FD became invalid, stopping listener.")
                break
            }

            let nev = kevent(kqueueFD, nil, 0, &eventList, 1, nil) // Blocking call

            if nev == -1 {
                // Interrupted by signal (e.g., closing FD from another thread) or real error
                if errno == EINTR { continue } // Interrupted, just retry
                if errno == EBADF && kqueueFD == -1 { break } // FD closed intentionally
                let error = String(cString: strerror(errno))
                Self.logger.error("kevent wait error: \(error, privacy: .public)")
                break
            } else if nev > 0 {
                let event = eventList[0]
                let pid = pid_t(event.ident)

                if event.fflags & NOTE_EXIT != 0 {
                    pidsQueue.sync {
                        // Ensure we remove it from the set *before* calling the callback
                        // to prevent race conditions with polling.
                        if monitoredPIDs.contains(pid) {
                            Self.logger.log("Detected stop (via kqueue) of \(self.targetProcessName, privacy: .public) with PID: \(pid)")
                            monitoredPIDs.remove(pid)
                            // Dispatch callback to the main thread for UI safety
                            DispatchQueue.main.async {
                                self.onProcessStopped?(pid)
                            }
                        } else {
                            Self.logger.log("Received exit for untracked PID \(pid), possibly due to race condition or late event.")
                        }
                    }
                }
            }
        }
        Self.logger.log("Kevent listener thread finished.")
        // Ensure FD is closed if loop exited unexpectedly
        if kqueueFD != -1 {
            close(kqueueFD)
            kqueueFD = -1
        }
    }

    private func addKeventWatch(for pid: pid_t) {
        // NOTE: This method must be called from within a pidsQueue.sync block.
        guard kqueueFD != -1 else { return }
        var kev = kevent(ident: UInt(pid), filter: Int16(EVFILT_PROC), flags: UInt16(EV_ADD | EV_ENABLE), fflags: NOTE_EXIT, data: 0, udata: nil)

        let result = kevent(kqueueFD, &kev, 1, nil, 0, nil)
        if result == -1 {
            let error = String(cString: strerror(errno))
            Self.logger.error("Failed to add kqueue watch for PID \(pid): \(error, privacy: .public)")
            // If adding fails, remove from monitored set since we can't watch it.
            monitoredPIDs.remove(pid)
        } else {
            Self.logger.log("Successfully watching PID \(pid) for exit.")
        }
    }

    /// --- Helper functions ---
    private func allPIDs() -> [pid_t] {
        var numberOfPIDs: Int32
        var bufferSize: Int

        // First call to get the required buffer size
        numberOfPIDs = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard numberOfPIDs > 0 else { return [] }

        bufferSize = Int(numberOfPIDs) * MemoryLayout<pid_t>.size
        var pids: [pid_t] = .init(repeating: 0, count: Int(numberOfPIDs))

        // Second call to get the actual PIDs
        numberOfPIDs = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(bufferSize))
        guard numberOfPIDs > 0 else { return [] }

        // Adjust array size to actual number of PIDs returned
        return Array(pids.prefix(Int(numberOfPIDs)))
    }

    private func processName(for pid: pid_t) -> String? {
        var pathBuffer: [CChar] = .init(repeating: 0, count: Int(4 * MAXPATHLEN))
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))

        if pathLength > 0 {
            let path = String(cString: pathBuffer)
            // Use URL(fileURLWithPath:) for correct path handling
            let url = URL(fileURLWithPath: path)
            let processName = url.lastPathComponent
            if !processName.isEmpty {
                return processName
            }
        }
        return nil
    }

    deinit {
        stopMonitoring()
    }
}

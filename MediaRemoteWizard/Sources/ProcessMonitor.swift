import Foundation
import Darwin

class ProcessMonitor {
    let targetProcessName: String
    private var monitoredPIDs: Set<pid_t> = []
    private var kqueueFD: Int32 = -1
    private var keventThread: Thread?
    private var timer: Timer?

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
            perror("kqueue creation failed")
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
        // Initial poll
        pollProcesses()

        print("Started monitoring for process: \(targetProcessName)")
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil

        // Signal kevent thread to stop (e.g., by closing kqueueFD or using a flag)
        if kqueueFD != -1 {
            close(kqueueFD)
            kqueueFD = -1
        }
        keventThread?.cancel() // Or use a more robust stopping mechanism
        keventThread = nil

        monitoredPIDs.removeAll()
        print("Stopped monitoring for process: \(targetProcessName)")
    }

    private func pollProcesses() {
        var currentPIDs: Set<pid_t> = []
        let pids = allPIDs() // Implement using proc_listpids

        for pid in pids {
            if let processName = processName(for: pid) { // Implement using proc_pidpath or proc_name
                if processName == targetProcessName {
                    currentPIDs.insert(pid)
                    if !monitoredPIDs.contains(pid) {
                        // New process found
                        print("Detected start of \(targetProcessName) with PID: \(pid)")
                        monitoredPIDs.insert(pid)
                        addKeventWatch(for: pid)
                        onProcessStarted?(pid)
                    }
                }
            }
        }

        // Check for processes that stopped but maybe missed kqueue event
        let stoppedPIDs = monitoredPIDs.subtracting(currentPIDs)
        for pid in stoppedPIDs {
            if monitoredPIDs.contains(pid) { // Double check it was being monitored
                print("Detected stop (via polling) of \(targetProcessName) with PID: \(pid)")
                monitoredPIDs.remove(pid)
                // No need to remove kevent watch here, it should trigger/fail anyway
                onProcessStopped?(pid)
            }
        }
    }

    private func listenForKevents() {
        var eventList: [kevent] = .init(repeating: .init(), count: 1)

        while kqueueFD != -1, !Thread.current.isCancelled {
            // Check kqueueFD validity before blocking
            guard fcntl(kqueueFD, F_GETFL) != -1 || errno != EBADF else {
                print("kqueue FD became invalid, stopping listener.")
                break
            }

            let nev = kevent(kqueueFD, nil, 0, &eventList, 1, nil) // Blocking call

            if nev == -1 {
                // Interrupted by signal (e.g., closing FD from another thread) or real error
                if errno == EINTR { continue } // Interrupted, just retry
                if errno == EBADF, kqueueFD == -1 { break } // FD closed intentionally
                perror("kevent wait error")
                break
            } else if nev > 0 {
                let event = eventList[0]
                let pid = pid_t(event.ident)

                if event.fflags & NOTE_EXIT != 0 {
                    print("Detected stop (via kqueue) of \(targetProcessName) with PID: \(pid)")
                    // Ensure we remove it from the set *before* calling the callback
                    // to prevent race conditions with polling
                    if monitoredPIDs.contains(pid) {
                        monitoredPIDs.remove(pid)
                        // No need to explicitly remove the watch, NOTE_EXIT is often oneshot or implicitly removed on exit
                        onProcessStopped?(pid)
                    } else {
                        print("Received exit for untracked PID \(pid), possibly due to race condition or late event.")
                    }
                }
            }
        }
        print("Kevent listener thread finished.")
        // Ensure FD is closed if loop exited unexpectedly
        if kqueueFD != -1 {
            close(kqueueFD)
            kqueueFD = -1
        }
    }

    private func addKeventWatch(for pid: pid_t) {
        guard kqueueFD != -1 else { return }
        var kev = kevent(ident: UInt(pid), filter: Int16(EVFILT_PROC), flags: UInt16(EV_ADD | EV_ENABLE /* | EV_CLEAR */ ), fflags: NOTE_EXIT, data: 0, udata: nil)

        // EV_SET(&kev, ident, filter, flags, fflags, data, udata);
        // EV_CLEAR makes it oneshot after delivery (optional, depends on exact needs)

        let result = kevent(kqueueFD, &kev, 1, nil, 0, nil)
        if result == -1 {
            perror("Failed to add kqueue watch for PID \(pid)")
            // If adding fails, remove from monitored set? Or rely on polling?
            monitoredPIDs.remove(pid)
        } else {
            print("Successfully watching PID \(pid) for exit.")
        }
    }

    /// --- Helper functions to implement ---
    private func allPIDs() -> [pid_t] {
        // Implementation using proc_listpids
        // ... (see examples online for proc_listpids usage) ...
        var numberOfPIDs: Int32 = 0
        var pids: [pid_t] = []
        var bufferSize = 0

        // First call to get the required buffer size
        numberOfPIDs = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        if numberOfPIDs <= 0 { return [] }

        bufferSize = Int(numberOfPIDs) * MemoryLayout<pid_t>.size
        pids = [pid_t](repeating: 0, count: Int(numberOfPIDs)) // Allocate buffer

        // Second call to get the actual PIDs
        numberOfPIDs = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(bufferSize))
        if numberOfPIDs <= 0 { return [] }

        // Adjust array size to actual number of PIDs returned
        return Array(pids.prefix(Int(numberOfPIDs)))
    }

    private func processName(for pid: pid_t) -> String? {
        // Implementation using proc_pidpath
        var pathBuffer: [CChar] = .init(repeating: 0, count: Int(4 * MAXPATHLEN))
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))

        if pathLength > 0 {
            let path = String(cString: pathBuffer)
            // Extract name from path (e.g., last component)
            if let url = URL(string: path), !url.lastPathComponent.isEmpty {
                return url.lastPathComponent
            } else {
                // Fallback or handle cases where path isn't a typical file path
                let components = path.split(separator: "/")
                if let last = components.last { return String(last) }
            }
        }
        // Optional: Fallback using proc_name if proc_pidpath fails
        // var nameBuffer = [CChar](repeating: 0, count: Int(MAXCOMLEN + 1))
        // if proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)) > 0 {
        //     return String(cString: nameBuffer)
        // }

        return nil
    }

    deinit {
        stopMonitoring()
    }
}

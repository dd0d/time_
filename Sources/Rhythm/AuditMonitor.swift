#if DEBUG
import AppKit
import Darwin

/// Opt-in instrumentation for isolated QA bundles only; absent from release builds.
@MainActor
final class AuditMonitor {
    private var timer: Timer?
    private let url: URL
    private var previousTime = ProcessInfo.processInfo.systemUptime
    private var previousCPU = 0.0

    init(url: URL) {
        self.url = url
        try? Data().write(to: url, options: .atomic)
        record()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.record() }
        }
        timer?.tolerance = 0.5
    }

    deinit { timer?.invalidate() }

    private func record() {
        var memory = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &memory) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        let now = ProcessInfo.processInfo.systemUptime
        let sample: [String: Any] = ["at": Date().timeIntervalSince1970,
                                   "footprint": status == KERN_SUCCESS ? memory.phys_footprint : 0,
                                   "cpu_percent": previousCPU == 0 ? 0 : (cpu - previousCPU) / max(0.001, now - previousTime) * 100,
                                   "windows": NSApplication.shared.windows.count]
        previousCPU = cpu
        previousTime = now
        guard let data = try? JSONSerialization.data(withJSONObject: sample, options: [.sortedKeys]),
              let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        do { try handle.seekToEnd(); try handle.write(contentsOf: data + Data([10])) } catch { }
    }
}
#endif

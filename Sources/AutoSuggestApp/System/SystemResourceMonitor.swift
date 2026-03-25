import Foundation
import Darwin.Mach

struct MemorySnapshot {
    let totalBytes: UInt64
    let availableBytes: UInt64?

    var totalGB: Double {
        Double(totalBytes) / 1_073_741_824.0
    }

    var availableGB: Double? {
        guard let availableBytes else { return nil }
        return Double(availableBytes) / 1_073_741_824.0
    }
}

struct SystemResourceMonitor {
    func memorySnapshot() -> MemorySnapshot {
        MemorySnapshot(
            totalBytes: ProcessInfo.processInfo.physicalMemory,
            availableBytes: availableMemoryBytes()
        )
    }

    func hasSufficientMemoryForPrimaryRuntime() -> Bool {
        let snapshot = memorySnapshot()
        guard let available = snapshot.availableBytes else {
            return snapshot.totalBytes >= 8 * 1024 * 1024 * 1024
        }
        return available >= 2 * 1024 * 1024 * 1024
    }

    private func availableMemoryBytes() -> UInt64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result: kern_return_t = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let freePageCount = UInt64(stats.free_count + stats.inactive_count + stats.speculative_count)
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else {
            return nil
        }
        return freePageCount * UInt64(pageSize)
    }
}

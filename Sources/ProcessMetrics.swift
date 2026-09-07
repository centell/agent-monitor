import Darwin
import Foundation

// MARK: - 값

struct SessionMetrics {
    /// 세션 프로세스 **트리 전체**의 상주 메모리.
    ///
    /// claude 프로세스 하나만 재면 크게 틀린다. MCP 서버와 자식들이 따라붙어
    /// 실측에서 단독 541MB 인 세션의 트리 합계가 2790MB 였다.
    let memoryBytes: UInt64

    /// 직전 표본 이후의 CPU 사용률. 첫 표본에는 없다.
    let cpuPercent: Double?

    /// 딸린 자손 프로세스 수. 왜 이만큼 먹는지 설명해 준다.
    let descendantCount: Int
}

struct SystemMemory {
    let usedBytes: UInt64
    let totalBytes: UInt64
    let swapUsedBytes: UInt64
    let compressedBytes: UInt64
}

// MARK: - 표본 수집

/// 프로세스 트리를 훑어 세션마다 메모리와 CPU 를 잰다.
///
/// CPU 사용률은 순간값을 읽을 수 없고 **두 표본의 차이**로만 구할 수 있으므로
/// 이 객체가 직전 값을 들고 있는다.
final class MetricsSampler {

    private var previousCPUSeconds: [Int32: Double] = [:]
    private var previousSampleTime: Date?

    /// 세션 pid 들에 대해 한 번에 잰다.
    ///
    /// 프로세스 목록은 `sysctl` **한 번**으로 통째로 가져온다. 세션마다 따로
    /// 훑으면 같은 일을 여러 번 하게 된다.
    func sample(pids: [Int32], now: Date = Date()) -> [Int32: SessionMetrics] {
        let processes = Self.allProcesses()
        guard !processes.isEmpty else { return [:] }

        var children: [Int32: [Int32]] = [:]
        for entry in processes { children[entry.ppid, default: []].append(entry.pid) }

        let elapsed = previousSampleTime.map { now.timeIntervalSince($0) }
        var out: [Int32: SessionMetrics] = [:]
        var freshCPU: [Int32: Double] = [:]

        for pid in pids {
            let tree = Self.descendants(of: pid, in: children)
            var memory: UInt64 = 0
            var cpuSeconds: Double = 0
            for member in tree {
                guard let info = Self.info(of: member) else { continue }
                memory += info.residentBytes
                cpuSeconds += info.cpuSeconds
            }
            freshCPU[pid] = cpuSeconds

            var percent: Double?
            if let elapsed, elapsed > 0.1, let before = previousCPUSeconds[pid] {
                percent = max(0, (cpuSeconds - before) / elapsed * 100)
            }
            out[pid] = SessionMetrics(memoryBytes: memory,
                                      cpuPercent: percent,
                                      descendantCount: tree.count - 1)
        }

        previousCPUSeconds = freshCPU
        previousSampleTime = now
        return out
    }

    // MARK: 커널에서 읽기

    /// 살아있는 모든 프로세스의 `pid` 와 `ppid`.
    static func allProcesses() -> [(pid: Int32, ppid: Int32)] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        let capacity = size / MemoryLayout<kinfo_proc>.stride + 16   // 훑는 사이 늘어날 여유
        var buffer = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
        size = capacity * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &buffer, &size, nil, 0) == 0 else { return [] }
        let count = size / MemoryLayout<kinfo_proc>.stride
        return (0..<count).map { (buffer[$0].kp_proc.p_pid, buffer[$0].kp_eproc.e_ppid) }
    }

    private static func descendants(of root: Int32, in children: [Int32: [Int32]]) -> [Int32] {
        var out = [root]
        var stack = [root]
        while let pid = stack.popLast() {
            for child in children[pid] ?? [] {
                out.append(child)
                stack.append(child)
            }
        }
        return out
    }

    private static func info(of pid: Int32) -> (residentBytes: UInt64, cpuSeconds: Double)? {
        var info = proc_taskallinfo()
        let size = Int32(MemoryLayout<proc_taskallinfo>.size)
        let rc = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, $0, size)
        }
        guard rc == size else { return nil }
        let cpu = Double(info.ptinfo.pti_total_user + info.ptinfo.pti_total_system) / 1_000_000_000
        return (info.ptinfo.pti_resident_size, cpu)
    }

    // MARK: 시스템 전체

    /// 맥 전체의 메모리 사정. 「지금 쪼들리나」에 답하는 값이다.
    ///
    /// 스왑과 압축이 함께 있어야 뜻이 통한다. 사용량만 보면 늘 가득 차 보인다.
    static func systemMemory() -> SystemMemory? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let rc = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard rc == KERN_SUCCESS else { return nil }

        let page = UInt64(vm_kernel_page_size)
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count)
                    + UInt64(stats.compressor_page_count)) * page

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        var swapMib: [Int32] = [CTL_VM, VM_SWAPUSAGE]
        let swapUsed = sysctl(&swapMib, 2, &swap, &swapSize, nil, 0) == 0 ? swap.xsu_used : 0

        return SystemMemory(usedBytes: used,
                            totalBytes: ProcessInfo.processInfo.physicalMemory,
                            swapUsedBytes: swapUsed,
                            compressedBytes: UInt64(stats.compressor_page_count) * page)
    }
}

// MARK: - 보여주기

enum MetricFormat {

    /// 막대 한 칸이 뜻하는 양. 눈금을 고정해 두는 것이 중요하다.
    ///
    /// 처음에는 「그 순간 가장 많이 쓰는 세션」을 만점으로 삼았는데, 큰 세션이 사라지자
    /// 0.6GB 짜리들이 전부 꽉 찬 막대로 보였다. **「다들 비슷하다」가 「다들 한계다」로
    /// 읽히는** 거짓말이었다. 눈금이 고정돼야 막대가 같은 뜻을 유지한다.
    static let bytesPerCell: Double = 500_000_000

    /// 부분 블록으로 그린 가로 막대.
    ///
    /// 눈은 숫자를 읽는 것보다 모양을 훑는 것이 빠르다. 여덟 개 줄에서 「누가 먹나」를
    /// 찾을 때 숫자를 하나씩 비교하는 대신 튀어나온 막대 하나를 보면 된다.
    /// 눈금을 넘으면 `+` 를 붙여 **잘렸다는 사실을 숨기지 않는다.**
    static func bar(bytes: UInt64, cells: Int = 5) -> String {
        let partials = ["", "▏", "▎", "▍", "▌", "▋", "▊", "▉"]
        let scaled = Double(bytes) / bytesPerCell
        if scaled >= Double(cells) { return String(repeating: "█", count: cells) + "+" }
        let full = Int(scaled)
        let remainder = Int((scaled - Double(full)) * 8)
        var out = String(repeating: "█", count: full)
        if remainder > 0 { out += partials[remainder] }
        if out.isEmpty { out = partials[1] }   // 0 이 아니면 최소 한 칸은 보인다
        return out
    }

    static func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.1fG", Double(bytes) / 1_000_000_000)
    }

    /// 시스템 요약 한 줄.
    static func systemSummary(_ memory: SystemMemory, agentBytes: UInt64) -> String {
        let gb = { (v: UInt64) in Double(v) / 1_000_000_000 }
        return String(format: "메모리 %.1f/%.1fGB · 스왑 %.1fGB · 에이전트 %.1fGB",
                      gb(memory.usedBytes), gb(memory.totalBytes),
                      gb(memory.swapUsedBytes), gb(agentBytes))
    }
}

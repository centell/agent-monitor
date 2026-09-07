import Darwin
import Foundation

/// 「이 맥의 메모리를 누가 먹고 있나」를 한 장으로 만든다.
///
/// 세션 목록만으로는 답이 안 나온다. 세션 트리 밖에도 메모리를 쓰는 것이 많고,
/// 세션이 띄운 개발 서버나 컨테이너는 트리에서 떨어져 나가 **우리 합계에 안 잡힌다.**
struct MemoryReport {

    struct Entry: Identifiable {
        let name: String
        let bytes: UInt64
        let processCount: Int
        /// 세션이 띄운 것으로 **보이는** 경우 그 세션 이름. 확정이 아니라 추정이다.
        let suspectedOwner: String?
        var id: String { name }
    }

    let system: SystemMemory?
    let agentBytes: UInt64
    let agentProcessCount: Int
    /// 세션 트리 밖에서 메모리를 쓰는 것들. 많이 쓰는 순.
    let others: [Entry]
    /// 그중 세션이 띄운 것으로 보이는 것들.
    let suspected: [Entry]

    // MARK: 만들기

    /// 30MB 미만은 묶지 않는다. 목록이 잡음으로 덮인다.
    private static let floor: UInt64 = 30_000_000

    static func build(sessions: [Session]) -> MemoryReport {
        let processes = MetricsSampler.allProcesses()
        var children: [Int32: [Int32]] = [:]
        for entry in processes { children[entry.ppid, default: []].append(entry.pid) }

        // 세션이 거느린 pid 를 모두 모은다.
        var owned = Set<Int32>()
        for session in sessions {
            var stack = [session.pid]
            owned.insert(session.pid)
            while let pid = stack.popLast() {
                for child in children[pid] ?? [] where !owned.contains(child) {
                    owned.insert(child)
                    stack.append(child)
                }
            }
        }

        var agentBytes: UInt64 = 0
        var grouped: [String: (bytes: UInt64, count: Int, owner: String?)] = [:]

        for entry in processes {
            guard let info = MetricsSampler.info(of: entry.pid) else { continue }
            if owned.contains(entry.pid) {
                agentBytes += info.residentBytes
                continue
            }
            guard info.residentBytes >= floor else { continue }
            let name = executableName(of: entry.pid) ?? "(알 수 없음)"
            let owner = suspectedOwner(of: entry.pid, sessions: sessions)
            let previous = grouped[name]
            grouped[name] = (
                bytes: (previous?.bytes ?? 0) + info.residentBytes,
                count: (previous?.count ?? 0) + 1,
                owner: previous?.owner ?? owner
            )
        }

        let entries = grouped
            .map { Entry(name: $0.key, bytes: $0.value.bytes,
                         processCount: $0.value.count, suspectedOwner: $0.value.owner) }
            .sorted { $0.bytes > $1.bytes }

        return MemoryReport(
            system: MetricsSampler.systemMemory(),
            agentBytes: agentBytes,
            agentProcessCount: owned.count,
            others: entries.filter { $0.suspectedOwner == nil },
            suspected: entries.filter { $0.suspectedOwner != nil }
        )
    }

    // MARK: 커널에서 읽기

    private static func executableName(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer)).lastPathComponent
    }

    private static func workingDirectory(of pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let rc = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, $0, size)
        }
        guard rc == size else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
    }

    /// 작업 디렉터리가 어느 세션의 폴더 아래인가.
    ///
    /// `⚠` 이것은 **추정**이다. 한 프로젝트에 세션이 여럿이면 누가 띄웠는지 갈리지 않는다.
    /// 실측에서 `payments-api` 아래 개발 서버 하나에 세션 넷이 후보로 걸렸다.
    /// 그래서 갈리지 않을 때는 이름을 고르지 않고 「여러 세션」이라고 적는다.
    private static func suspectedOwner(of pid: Int32, sessions: [Session]) -> String? {
        guard let cwd = workingDirectory(of: pid), cwd != "/" else { return nil }
        var best = 0
        var names: [String] = []
        for session in sessions where !session.cwd.isEmpty {
            guard cwd == session.cwd || cwd.hasPrefix(session.cwd + "/") else { continue }
            if session.cwd.count > best {
                best = session.cwd.count
                names = [session.name]
            } else if session.cwd.count == best {
                names.append(session.name)
            }
        }
        guard !names.isEmpty else { return nil }
        return names.count == 1 ? names[0] : "여러 세션 (\(names.count))"
    }
}

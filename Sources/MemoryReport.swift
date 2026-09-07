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
            let name = label(of: entry.pid) ?? S.unknownProcess
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

    /// 스크립트를 실행할 뿐이라 이름만으로는 정체를 알 수 없는 것들.
    private static let runtimes: Set<String> = [
        "node", "python", "python3", "ruby", "deno", "bun", "java", "perl", "php",
    ]

    /// 목록에 적을 이름.
    ///
    /// 실행 파일 이름만 쓰면 `next-server` 도 `node`, MCP 서버도 `node` 로 뭉쳐진다.
    /// 「무엇이 먹고 있나」를 알려는 화면에서 그건 절반쯤 실패다. 그래서
    /// `argv[0]`(스스로 바꿔 단 이름)과 실행 스크립트 이름까지 본다.
    private static func label(of pid: Int32) -> String? {
        let executable = executableName(of: pid)
        guard let args = arguments(of: pid), let first = args.first, !first.isEmpty else {
            return executable
        }
        let titled = URL(fileURLWithPath: first).lastPathComponent

        // next-server 처럼 제 이름을 고쳐 단 프로세스는 그 이름이 곧 정체다.
        if let executable, titled != executable, !titled.isEmpty { return titled }

        // node·python 처럼 남의 코드를 돌리는 것이면 무엇을 돌리는지 덧붙인다.
        if let executable, runtimes.contains(executable),
           let script = args.dropFirst().first(where: { !$0.hasPrefix("-") }) {
            return "\(executable) (\(URL(fileURLWithPath: script).lastPathComponent))"
        }
        return executable
    }

    /// `KERN_PROCARGS2` 배치: `[argc(4)][실행 경로\0][정렬용 \0…][argv0\0][argv1\0]…`
    private static func arguments(of pid: Int32) -> [String]? {
        var size = 0
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }

        let count = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard count > 0 else { return nil }

        var index = 4
        while index < size, buffer[index] != 0 { index += 1 }   // 실행 경로
        while index < size, buffer[index] == 0 { index += 1 }   // 정렬용 널

        var out: [String] = []
        while index < size, out.count < Int(count) {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            out.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return out
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
        return names.count == 1 ? names[0] : S.multipleSessions(names.count)
    }
}

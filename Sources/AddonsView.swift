import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 꽂힌 애드온을 보여 주고, 넣고 빼는 자리.
///
/// **못 꽂은 것도 함께 보여 준다.** 판이 안 맞는 번들은 앱이 안 부르므로 아무 일도 안
/// 일어나는데, 여기 안 적으면 그 사람은 제가 산 것이 왜 안 보이는지 알 길이 없다 —
/// 조용히 실패한 것과 같아진다.
///
/// 이 탭은 **애드온이 하나도 없어도 선다.** 다른 애드온 탭들은 그 애드온이 있을 때만
/// 생기지만, 여기는 「없다」를 말하고 「넣는 길」을 여는 자리라 비었을 때가 오히려 쓸모 있다.
struct AddonsView: View {

    /// 지웠거나 넣은 것을 화면에 바로 비추기 위한 것. 번들은 한 번 꽂으면 못 빼므로
    /// **목록만 다시 그리고 실제 반영은 다시 켤 때** 이뤄진다.
    @State private var entries: [AddonLoader.Entry] = AddonLoader.entries
    @State private var notice: String?

    /// 지금 들여다보고 있는 애드온. `nil` 이면 목록이다.
    ///
    /// 애드온이 낸 화면을 **탭이 아니라 이 안에서** 편다. 최상위 탭으로 내주면 탭 줄이
    /// 애드온 수만큼 자라는데, 탭 줄은 앱이 정하는 것이지 남이 늘리는 것이 아니다.
    @State private var opened: AddonLoader.Entry?

    /// **뿌리를 하나로 둔다.** `if` 를 그대로 `body` 에 두면 목록과 상세가 서로 다른
    /// 타입이 되어, 안으로 들어가고 나올 때마다 탭 내용의 «정체» 가 바뀐다. 선택을 따로
    /// 안 묶어 둔 `TabView` 는 그때 첫 탭으로 되돌아간다 — 실제로 「설정」을 눌러도,
    /// 돌아오는 단추를 눌러도 Display 탭으로 튕겼다.
    ///
    /// 겉을 `ZStack` 하나로 감싸면 타입이 늘 같아 그 일이 안 일어난다.
    var body: some View {
        ZStack {
            if let opened {
                detail(opened)
            } else {
                list
            }
        }
    }

    // MARK: 들여다보기

    @ViewBuilder
    private func detail(_ entry: AddonLoader.Entry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                // 돌아오는 길. **여기 말고는 없다** — 탭으로 빠져나갈 수 없으므로
                // 이 단추가 막히면 설정창을 닫았다 여는 수밖에 없다.
                Button {
                    opened = nil
                } label: {
                    Label(S.tabAddons, systemImage: "chevron.left")
                }
                .buttonStyle(.link)
                Text(entry.name).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            Divider()

            // 애드온이 낸 화면 그대로. 이 저장소는 안에 무엇이 그려지는지 모른다.
            //
            // 애드온이 설정을 여럿 냈으면 **이어서 편다.** 하나가 흔한 경우이고,
            // 여럿일 때 또 한 겹을 파는 것보다 이어 붙이는 쪽이 읽기 쉽다.
            ForEach(Array(entry.settingsTabs.enumerated()), id: \.offset) { _, tab in
                tab.content()
            }
        }
    }

    // MARK: 목록

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                if entries.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(S.addonNone).foregroundStyle(.secondary)
                        Text(AddonLoader.directory.path)
                            .font(.caption).foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                } else {
                    Form {
                        ForEach(entries, id: \.id) { entry in
                            row(entry)
                        }
                    }
                    .formStyle(.grouped)
                }

                HStack(spacing: 8) {
                    Button(S.addonInstallButton) { pickAndInstall() }
                    Button(S.addonFolder) {
                        try? FileManager.default.createDirectory(
                            at: AddonLoader.directory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(AddonLoader.directory)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)

                if let notice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                }
            }
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private func row(_ entry: AddonLoader.Entry) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name)
                    if let version = entry.version {
                        Text(version).font(.caption).foregroundStyle(.tertiary)
                    }
                }
                Text(describe(entry.state))
                    .font(.caption)
                    .foregroundStyle(isLoaded(entry.state) ? .secondary : Color.orange)
            }
            Spacer()
            // 설정을 안 낸 애드온에는 안 생긴다. 눌러도 빈 화면인 단추를 두면
            // 그 애드온이 무언가를 숨기고 있는 것처럼 보인다.
            if !entry.settingsTabs.isEmpty {
                Button(S.addonSettings) { opened = entry }
            }
            Button(S.addonRemove) { remove(entry) }
        }
    }

    private func isLoaded(_ state: AddonLoader.Entry.State) -> Bool {
        if case .loaded = state { return true }
        return false
    }

    private func describe(_ state: AddonLoader.Entry.State) -> String {
        switch state {
        case .loaded:                  return S.addonLoaded
        case .contractMismatch(let v): return S.addonContractMismatch(v, Addon.contractVersion)
        case .notAnAddon:              return S.addonNotAnAddon
        case .unreadable(let why):     return why
        case .pendingRestart:          return S.addonPendingRestart
        }
    }

    // MARK: 넣고 빼기

    private func pickAndInstall() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true      // `.bundle` 은 폴더다
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "bundle"), .zip].compactMap { $0 }
        panel.prompt = S.addonInstallButton
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let id = try AddonLoader.install(from: url)
            notice = "\(id) — \(S.addonRestartNeeded)"
        } catch {
            notice = S.addonInstallFailed(url.lastPathComponent)
        }
        refresh()
    }

    private func remove(_ entry: AddonLoader.Entry) {
        // **묻고 지운다.** 산 것을 한 번의 헛손질로 잃지 않게. 자료를 안 지운다는 것도
        // 여기서 말한다 — 지우고 난 뒤에 말하면 이미 놀란 뒤다.
        let alert = NSAlert()
        alert.messageText = S.addonRemoveConfirm(entry.name)
        alert.informativeText = S.addonDataKept
        alert.addButton(withTitle: S.addonRemove)
        alert.addButton(withTitle: S.addonCancel)
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if AddonLoader.remove(entry.id) {
            notice = "\(entry.name) — \(S.addonRestartNeeded)"
        }
        // 지운 것을 들여다보고 있었으면 목록으로 나온다. 안 그러면 없는 애드온의
        // 설정 화면을 계속 보고 있게 된다.
        if opened?.id == entry.id { opened = nil }
        refresh()
    }

    /// 폴더를 다시 훑되 **꽂지는 않는다.** 이미 꽂힌 번들을 또 부르면 같은 것이 두 번
    /// 등록되고, 뺀 번들은 어차피 못 내린다.
    ///
    /// 그래서 이 목록은 «지금 폴더에 있는 것» 이고, 상태는 켤 때 알아낸 것을 쓴다.
    /// 켤 때 없었던 것은 **아직 안 꽂혔다고 적는다** — 방금 넣은 것이 목록에서 통째로
    /// 사라지면 넣은 사람은 실패한 줄 안다.
    private func refresh() {
        let known = Dictionary(uniqueKeysWithValues: AddonLoader.entries.map {
            ($0.url.lastPathComponent, $0)
        })
        entries = AddonLoader.onDisk().map {
            known[$0.lastPathComponent] ?? AddonLoader.describe($0, state: .pendingRestart)
        }
    }
}

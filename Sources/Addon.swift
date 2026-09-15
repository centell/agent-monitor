import Foundation
// 탭 등록부가 `AnyView` 를 받으므로 여기까지 SwiftUI 가 따라온다. 이 앱은 어차피 GUI
// 번들이고 배포 대상이 macOS 13 이라 더 드는 값은 없다.
import SwiftUI

/// 이 저장소에 없는 애드온이 스스로를 꽂는 자리.
///
/// 이 파일은 **MIT 다.** 여기 있는 것은 «자리» 뿐이고 «내용» 은 애드온 번들 안에 있다.
/// 그래서 clone 해 온 사람이 받는 것은 빈 자리뿐이고, 빌드하면 애드온 없는 판이 나온다.
///
/// **비어 있는 것이 정상이다.** 애드온 없는 판은 덜 만든 앱이 아니라 그것으로 온전한
/// 앱이다. 이 등록부가 비었다고 화면에 «없음» 이나 «잠김» 을 그리지 않는다 — 없는 것을
/// 보여 주면 그 판을 쓰는 사람이 매번 제 앱이 모자란다는 말을 듣게 된다.
///
/// ## 왜 컴파일이 아니라 실행 중에 꽂는가
///
/// 전에는 애드온 소스를 실행 파일에 **함께 컴파일**했다. 가를 곳을 조건문이 아니라 파일로
/// 둔다는 뜻이었고, 애드온이 하나이고 그것을 짓는 사람도 하나일 때는 그것으로 깨끗했다.
///
/// 애드온이 여럿이 되고 사람마다 가진 것이 다르면 그 셈이 뒤집힌다 — 애드온 셋이면
/// 조합이 여덟이고, 앱을 한 번 고칠 때마다 여덟 판을 지어야 한다. 그래서 가르는 자리를
/// **실행 파일 안에서 파일 옆으로** 옮겼다. 애드온은 이제 따로 지은 번들이고, 앱은 그것을
/// 켤 때 찾아 읽는다 (`AddonLoader`).
///
/// 소스를 안 준다는 경계는 그대로다. 번들에 들어가는 것은 컴파일된 것뿐이다.
public enum Addon {

    /// 이 앱이 애드온과 맺은 계약의 판.
    ///
    /// **번들을 부르기 전에 이것부터 맞춰 본다.** 아래 등록부가 받는 타입(`Session` ·
    /// `SessionSource`)이 바뀌면, 옛 판에 대고 지은 번들은 **아무 말 없이 앱을 죽인다** —
    /// 실측에서 SIGBUS 로 끝났고 오류 한 줄 안 남았다. 기본 구현을 달아 줘도 마찬가지였다.
    ///
    /// 그래서 이 숫자는 **타입이 바뀔 때마다 올린다.** 자리(아래 등록부)를 늘리기만 하는
    /// 것은 옛 번들이 그 자리를 안 채울 뿐 안전하므로 올리지 않아도 된다.
    ///
    /// 조용한 죽음을 소리 나는 거절로 바꾸는 것이 이 숫자가 하는 일의 전부다.
    public static let contractVersion: Int32 = 1

    // MARK: 값을 받는 자리

    /// 애드온이 더하는 세션 출처.
    ///
    /// `CompositeSource` 가 배열을 받으므로 여기 꽂힌 것은 **화면 코드를 한 줄도 고치지
    /// 않고** 목록에 섞인다. 출처를 늘릴 생각으로 만들어 둔 자리가 그대로 경계가 되었다.
    public static var extraSources: [SessionSource] = []

    /// 애드온이 명령줄을 가로채는 자리.
    ///
    /// `main.swift` 가 아는 명령을 모두 지나온 뒤에 차례로 물어본다. 처리한 쪽이 `true` 를
    /// 내면 거기서 끝난다.
    ///
    /// **이 저장소는 무슨 명령이 오는지 모른다.** 알면 그 이름이 곧 애드온이 무엇을 하는지가
    /// 되므로, 가로챌 수 있다는 사실만 두고 내용은 번들 안에 둔다.
    public static var extraCommands: [([String]) -> Bool] = []

    /// 애드온이 줄에 덧붙이는 글 한 조각. `nil` 을 내면 그 애드온은 아무것도 안 붙인다.
    ///
    /// 줄을 짜는 쪽은 이 글이 무엇인지 모르고 자리만 내준다. 칸을 새로 만들지 않고
    /// 한 조각으로 받는 것도 같은 이유다 — 칸 이름이 늘면 그 이름이 말을 한다.
    ///
    /// **폭을 정하지 않는다.** 정해 두면 글이 없는 목록에서도 그 폭만큼 자리를 지켜,
    /// 애드온이 없는 판의 줄이 까닭 없이 벌어진다.
    ///
    /// 여럿이 붙으면 가운뎃점으로 이어 붙인다 (`annotation(for:)`). 한 칸이라 길어지면
    /// 곧 못 읽게 되지만, **자르는 자리는 줄을 짜는 쪽이지 여기가 아니다.**
    public static var rowAnnotations: [(Session) -> String?] = []

    /// 애드온이 툴팁에 보태는 글. 여러 줄이어도 되고 `nil` 이면 아무것도 안 붙는다.
    ///
    /// 줄에 붙이는 `rowAnnotations` 와 **자리가 다르다.** 줄은 한 칸이라 한 조각만 들어가고,
    /// 툴팁은 마우스를 올린 한 줄에만 뜨므로 길어도 된다. 곁눈으로 보는 것과 자세히 보는
    /// 것을 한 등록부로 받으면 둘 중 하나는 반드시 맞지 않는다.
    ///
    /// **메뉴와 상시 창이 같은 글을 쓴다** — 둘 다 `SessionRowStyle.tooltip` 을 거친다.
    public static var rowDetails: [(Session) -> String?] = []

    // MARK: 화면을 받는 자리

    /// 애드온이 설정창에 두는 제 탭.
    ///
    /// 앞의 등록부들은 **값**을 받았는데 이것만 **화면**을 받는다. `AnyView` 로 감싸므로
    /// 이 저장소는 그 안에 무엇이 그려지는지 끝까지 모른다 — 탭 이름조차 애드온이 내놓는다.
    ///
    /// 애드온이 늘면 각자 제 방이 필요하다. 남의 탭에 한 줄씩 끼어들면 그 탭이 곧
    /// 아무의 것도 아니게 된다. 그래서 이름과 화면을 **한 짝으로** 받는다 — 전에는 둘을
    /// 따로 두었는데, 애드온이 여럿이 되면 어느 이름이 어느 화면의 것인지 알 수가 없다.
    public struct SettingsTab {
        public let label: String
        public let content: () -> AnyView

        public init(label: String, content: @escaping () -> AnyView) {
            self.label = label
            self.content = content
        }
    }

    public static var settingsTabs: [SettingsTab] = []

    /// 애드온이 여는 제 창.
    ///
    /// 설정 탭과 나란한 자리이나 **창을 따로 내는 데는 까닭이 있다.** 설정은 고치고 닫는
    /// 자리라, 켜 두고 보는 것을 거기 밀어 넣으면 그것을 보는 내내 설정창을 붙잡고 있어야
    /// 한다. 무엇을 켜 두고 보는지는 이 저장소가 알 바가 아니다.
    ///
    /// **지금 세션을 당겨 읽는 손을 함께 건넨다.** 애드온이 스스로 훑지 못하게 하려는
    /// 것이다 — 이 앱은 이미 몇 초마다 훑고 있고, 한 번 더 훑으면 재는 값이 두 배로 들
    /// 뿐 아니라 쓰임새 기록이 **표본 사이 간격을 시간의 단위로 쓰기 때문에** 그 단위가
    /// 뒤틀린다 (`StatsRecorder`). 설정창이 이미 같은 손을 받아 쓰고 있다.
    public struct Window {
        /// 메뉴 항목의 글이자 창 제목이 된다.
        ///
        /// 이름을 이 저장소에 박아 두지 않는 것은 탭과 같은 까닭이다 — 박아 두는 순간
        /// 그 글이 곧 애드온이 무엇을 하는지가 된다.
        public let label: String

        /// 창을 다시 찾을 이름. 사람에게 안 보이고 **자리를 기억하는 데만 쓴다.**
        /// 창마다 달라야 한다 — 같으면 두 창이 서로의 자리를 덮어쓴다.
        public let key: String

        public let content: (@escaping () -> [Session]) -> AnyView

        public init(label: String, key: String,
                    content: @escaping (@escaping () -> [Session]) -> AnyView) {
            self.label = label
            self.key = key
            self.content = content
        }
    }

    public static var windows: [Window] = []

    // MARK: 여럿을 하나로

    /// 줄에 붙일 글을 모아 한 조각으로 만든다. 붙일 것이 없으면 `nil`.
    public static func annotation(for session: Session) -> String? {
        let parts = rowAnnotations.compactMap { $0(session) }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 툴팁에 보탤 글을 모은다. 애드온마다 여러 줄이라 줄바꿈으로 잇는다.
    public static func detail(for session: Session) -> String? {
        let parts = rowDetails.compactMap { $0(session) }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    /// 애드온이 하나라도 꽂혔는가.
    ///
    /// **표시를 가르는 데만 쓴다.** 기능을 막는 데 쓰지 않는다 — 막을 기능은 애초에
    /// 이 판에 들어 있지 않다. 이 값으로 무언가를 잠그기 시작하면 그 순간
    /// 「번들이 없으면 없다」는 경계가 「스위치 하나」로 내려앉는다.
    ///
    /// **애드온이 아니라 앱이 정한다.** 전에는 애드온이 스스로 켰는데, 이제 꽂는 쪽이
    /// 앱이라 (`AddonLoader`) 꽂힌 것을 아는 쪽도 앱이다.
    public static var isActive = false
}

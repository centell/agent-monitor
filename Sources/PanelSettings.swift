import SwiftUI

/// 상시 창의 손잡이만 모은 탭.
///
/// 「표시」 안에 섞여 있을 때는 **어디까지가 창에만 영향인지** 보이지 않았다. 같은 화면에
/// 메뉴에 걸리는 손잡이와 창에만 걸리는 손잡이가 섞여 있으면, 하나를 만질 때마다
/// 「이게 메뉴도 바꾸나」를 매번 생각해야 한다. 탭으로 가르면 그 물음이 사라진다.
struct PanelSettingsView: View {

    @ObservedObject private var settings = Settings.shared

    /// 진하기가 이보다 낮으면 바탕이 사실상 없다. 안내를 띄우는 문턱이자
    /// `FloatingPanel` 이 그림자를 끄는 문턱과 같은 뜻이다.
    private let bareBelow = 0.15

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 이 탭에 있는 것이 전부 창에만 걸린다는 것을 맨 위에서 한 번 말한다.
                Text(S.panelTabNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                Form {
                    Toggle(S.panelShowToggle, isOn: $settings.panelOpen)
                    Toggle(S.panelAlwaysOnTop, isOn: $settings.panelAlwaysOnTop)
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle(S.panelWaitingOnly, isOn: $settings.panelWaitingOnly)
                        Text(S.panelWaitingOnlyNote)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Picker(S.backdropStyle, selection: $settings.panelBackdropStyle) {
                        ForEach(PanelBackdropStyle.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 2) {
                        LabeledContent(S.backdropAlpha) {
                            HStack(spacing: 10) {
                                Slider(value: $settings.panelBackdropAlpha, in: 0...1, step: 0.05)
                                // 숫자를 함께 둔다. 손잡이만 있으면 「지금 몇 %인가」를
                                // 눈대중해야 하고, 같은 값으로 돌아오지도 못한다.
                                Text("\(Int((settings.panelBackdropAlpha * 100).rounded()))%")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 46, alignment: .trailing)
                            }
                        }
                        // 0% 의 대가를 **그 값일 때만** 적는다. 늘 띄워 두면 경고가 배경이 된다.
                        if settings.panelBackdropAlpha < bareBelow {
                            Text(S.backdropNote)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Picker(S.panelTextSize, selection: $settings.panelFontSize) {
                        Text(S.textSmall).tag(11.0)
                        Text(S.textNormal).tag(12.0)
                        Text(S.textLarge).tag(14.0)
                    }
                    .pickerStyle(.segmented)

                    Picker(S.panelDensityLabel, selection: $settings.panelDensity) {
                        Text(S.densityTight).tag(1.0)
                        Text(S.densityNormal).tag(3.0)
                        Text(S.densityLoose).tag(6.0)
                    }
                    .pickerStyle(.segmented)
                }
                .formStyle(.grouped)
                // 손잡이를 더할 때는 이 값도 한 줄만큼 올린다. 모자라면 마지막 줄이 잘린다.
                .frame(height: 400)

                // 미리보기를 따로 그리지 않는다. **창 자체가 미리보기**다 —
                // 띄워 두고 만지면 바뀌는 것이 그 자리에서 보인다. 흉내 낸 그림을 옆에
                // 두면 실제와 어긋날 자리만 하나 더 생긴다.
                Text(settings.panelOpen ? S.panelLivePreview : S.panelOpenToSee)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

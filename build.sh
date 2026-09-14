#!/usr/bin/env bash
# agent-monitor 빌드. 의존성 없음 — swiftc 만 있으면 된다.
#
# 빌드가 곧 설치다. 앱은 언제나 ~/Applications/AgentMonitor.app 에 놓이므로
# Spotlight 로 띄울 수 있고, 「나중에 어디 둘까」를 따로 정할 필요가 없다.
#
#   ./build.sh               빌드 · 설치 · (돌고 있었으면) 다시 띄움
#   ./build.sh --no-run      빌드 · 설치 · 띄우지 않음 (돌고 있었으면 내려간 채로 둔다)
#   ./build.sh --no-install  빌드만. **도는 앱을 건드리지 않는다** — 그 앱은 이전 판이다
set -euo pipefail
cd "$(dirname "$0")"

VERSION="0.6.1"
APP_NAME="AgentMonitor"
DEST="$HOME/Applications/${APP_NAME}.app"
DEPLOYMENT_TARGET="13.0"

# 돌고 있었는지 먼저 기억해 둔다. 빌드 때문에 조용히 꺼져 있으면 안 된다.
WAS_RUNNING=0
pgrep -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" >/dev/null 2>&1 && WAS_RUNNING=1

mkdir -p build

# 별도 애드온 소스가 있으면 함께 빌드한다. 없으면 그냥 없는 채로 빌드되고, clone 해 온
# 사람에게는 그쪽이 기본이며 그것으로 온전하다. `Addon/` 은 .gitignore 라 따라오지 않는다.
#
# 빈 배열을 `"${ARR[@]}"` 로 펼치면 **맥 기본 bash 3.2 는 `set -u` 아래서 죽는다.**
# 그래서 `${ARR[@]+...}` 로 «있을 때만 펼치기» 를 쓴다. 이 맥에는 Addon/ 이 있으니
# 이 줄이 틀려도 여기서는 안 드러난다 — 안 겪는 사람이 고쳐야 하는 자리다.
ADDON_ARGS=()
EDITION="기본"
if [[ -d Addon/Sources ]]; then
    ADDON_ARGS=(-D ADDON Addon/Sources/*.swift)
    EDITION="애드온 포함"
    echo "  · 애드온 소스를 함께 빌드합니다"
fi

# Apple Silicon 과 Intel 양쪽에서 도는 하나의 실행 파일을 만든다.
# 한쪽 아키텍처를 못 만드는 환경에서도 빌드가 막히지 않도록, 되는 것만 모아 합친다.
SLICES=()
for arch in arm64 x86_64; do
    if swiftc -O -target "${arch}-apple-macos${DEPLOYMENT_TARGET}" \
        Sources/*.swift ${ADDON_ARGS[@]+"${ADDON_ARGS[@]}"} \
        -o "build/slice-${arch}" 2>/dev/null; then
        SLICES+=("build/slice-${arch}")
    else
        echo "  · ${arch} 는 건너뜁니다 (이 환경에서 못 만듦)"
    fi
done

if [[ ${#SLICES[@]} -eq 0 ]]; then
    # 둘 다 실패하면 대상 지정 없이 이 맥용으로만 만든다. 그래야 최소한 손에 남는다.
    echo "  · 지정한 대상으로 못 만들어 이 맥용으로만 빌드합니다"
    swiftc -O Sources/*.swift ${ADDON_ARGS[@]+"${ADDON_ARGS[@]}"} -o build/agent-monitor
else
    lipo -create "${SLICES[@]}" -output build/agent-monitor
    rm -f "${SLICES[@]}"
fi

# **도는 앱을 건드리지 않는 길.**
#
# 앱을 내리는 것은 번들을 통째로 갈아끼우기 때문이지(`rm -rf "$DEST"`) 빌드 자체가
# 그것을 요구해서가 아니다. 그러니 설치를 건너뛰면 내릴 까닭도 없다.
#
# 고치는 사람이 「컴파일이 되는가」만 보려고 빌드하는 일이 잦은데, 그때마다 앱이 꺼지면
# 그 앱을 쓰고 있던 사람의 창과 보던 자리가 함께 날아간다. 실제로 하루에 열몇 번 그랬다.
if [[ "${1:-}" == "--no-install" ]]; then
    echo "빌드 완료  ${EDITION}  ($(lipo -archs build/agent-monitor 2>/dev/null || echo native))"
    echo "  CLI : build/agent-monitor"
    echo "  → 앱은 그대로 둡니다 — 지금 도는 앱은 이전 판입니다"
    exit 0
fi

# 돌고 있으면 먼저 내린다. 실행 중인 번들을 덮어쓰면 상태가 어긋난다.
if [[ $WAS_RUNNING -eq 1 ]]; then
    pkill -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
    sleep 0.4
fi

mkdir -p "$HOME/Applications"
rm -rf "$DEST"
mkdir -p "$DEST/Contents/MacOS"
cp build/agent-monitor "$DEST/Contents/MacOS/${APP_NAME}"

# 아이콘. Resources/AppIcon.png 하나에서 필요한 크기를 전부 만들어 .icns 로 묶는다.
# 아이콘이 없어도 빌드는 계속된다 — 앱이 도는 데 아이콘이 필요하진 않으니까.
if [[ -f Resources/AppIcon.png ]]; then
    ICONSET="build/${APP_NAME}.iconset"
    rm -rf "$ICONSET"
    mkdir -p "$ICONSET" "$DEST/Contents/Resources"
    for sz in 16 32 128 256 512; do
        sips -s format png -z "$sz" "$sz" Resources/AppIcon.png \
            --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
        sips -s format png -z "$((sz * 2))" "$((sz * 2))" Resources/AppIcon.png \
            --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$DEST/Contents/Resources/${APP_NAME}.icns"
    rm -rf "$ICONSET"
else
    echo "  · Resources/AppIcon.png 이 없어 아이콘 없이 만듭니다"
fi

# LSUIElement 로 Dock 아이콘 없이 메뉴바에만 산다.
cat > "$DEST/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>me.centell.agent-monitor</string>
    <key>CFBundleIconFile</key><string>${APP_NAME}</string>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>${DEPLOYMENT_TARGET}</string>
    <key>LSUIElement</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>세션을 누르면 그 세션이 도는 터미널 창으로 이동하기 위해 Terminal 제어 권한이 필요합니다.</string>
    <key>NSHumanReadableCopyright</key><string>MIT</string>
</dict>
</plist>
PLIST

echo "빌드 완료  ${EDITION}  ($(lipo -archs build/agent-monitor 2>/dev/null || echo native))"
echo "  앱  : $DEST"
echo "  CLI : build/agent-monitor   (--list · --json · --memory · --roots)"

if [[ "${1:-}" == "--no-run" ]]; then
    [[ $WAS_RUNNING -eq 1 ]] && echo "  → 내려둔 채로 두었습니다 (--no-run)"
    exit 0
fi

open "$DEST"
echo "  → 띄웠습니다$([[ $WAS_RUNNING -eq 1 ]] && echo " (쓰고 계셔서 다시 올렸습니다)")"

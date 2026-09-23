#!/usr/bin/env bash
# agent-monitor 빌드. 의존성 없음 — swiftc 만 있으면 된다.
#
# 빌드가 곧 설치다. 앱은 언제나 ~/Applications/AgentMonitor.app 에 놓이므로
# Spotlight 로 띄울 수 있고, 「나중에 어디 둘까」를 따로 정할 필요가 없다.
#
#   ./build.sh               빌드 · 설치 · (돌고 있었으면) 다시 띄움
#   ./build.sh --no-run      빌드 · 설치 · 띄우지 않음 (돌고 있었으면 내려간 채로 둔다)
#   ./build.sh --no-install  빌드만. **도는 앱을 건드리지 않는다** — 그 앱은 이전 판이다
#   ./build.sh --release     올릴 판. 애드온 자리를 빼고 build/release 에 짓고 zip 으로 묶는다.
#                            도는 앱도 ~/Applications 도 건드리지 않는다
set -euo pipefail
cd "$(dirname "$0")"

VERSION="0.7.0"
APP_NAME="AgentMonitor"
DEST="$HOME/Applications/${APP_NAME}.app"
RELEASE=0
[[ "${1:-}" == "--release" ]] && RELEASE=1 && DEST="build/release/${APP_NAME}.app"
DEPLOYMENT_TARGET="13.0"

# 돌고 있었는지 먼저 기억해 둔다. 빌드 때문에 조용히 꺼져 있으면 안 된다.
WAS_RUNNING=0
pgrep -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" >/dev/null 2>&1 && WAS_RUNNING=1

mkdir -p build

# 애드온은 **더 이상 여기서 함께 컴파일하지 않는다.** 따로 지은 번들이 되어 앱이 켤 때
# 찾아 읽는다 (`Sources/AddonLoader.swift`). 애드온이 여럿이 되면 조합마다 다른 판을 지어야
# 하는데, 셋이면 여덟 판이라 그 셈이 안 선다.
#
# 대신 여기서 **애드온이 대고 지을 것**을 함께 내놓는다 (아래 build/sdk). 애드온은 이 앱의
# 타입에 직접 대고 지어지므로, 모듈(무엇이 있는지)과 실행 파일(어디 있는지) 둘 다 필요하다.
EDITION="기본"
MODULE_NAME="AgentMonitor"

# 애드온을 **받는 자리**(로더·설정창 칸·`addon` 명령)를 켤지. 애드온 소스가 옆에 있는
# 맥에서만 켜고, clone 해 온 판과 릴리즈판에서는 끈다 — 아직 남에게 내놓을 자리가 아니다.
# 애드온마다 가르는 것이 아니라 자리 전체 하나라, 판은 켬·끔 둘뿐이다.
SWIFT_FLAGS=()
if [[ $RELEASE -eq 0 && -d Addon/Sources && -x Addon/build.sh ]]; then
    SWIFT_FLAGS=(-D ADDONS)
fi

rm -rf build/sdk

# Apple Silicon 과 Intel 양쪽에서 도는 하나의 실행 파일을 만든다.
# 한쪽 아키텍처를 못 만드는 환경에서도 빌드가 막히지 않도록, 되는 것만 모아 합친다.
#
# 슬라이스를 **안 지운다.** 애드온을 지을 때 `-bundle_loader` 가 제 아키텍처의 실행 파일을
# 가리켜야 하고, 모듈도 아키텍처마다 따로 나온다.
SLICES=()
for arch in arm64 x86_64; do
    mkdir -p "build/sdk/${arch}"
    if swiftc -O -target "${arch}-apple-macos${DEPLOYMENT_TARGET}" \
        ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"} \
        -module-name "$MODULE_NAME" \
        -emit-module -emit-module-path "build/sdk/${arch}/${MODULE_NAME}.swiftmodule" \
        -emit-executable \
        Sources/*.swift \
        -o "build/sdk/${arch}/host" 2>"build/sdk/${arch}.log"; then
        SLICES+=("build/sdk/${arch}/host")
    else
        # **까닭을 함께 내놓는다.** 전에는 stderr 를 통째로 버려서, 정말 못 만드는
        # 아키텍처인지 내가 코드를 틀린 것인지 구분할 수가 없었다 (실제로 걸렸다).
        echo "  · ${arch} 는 건너뜁니다 — build/sdk/${arch}.log"
        grep -m3 "error:" "build/sdk/${arch}.log" 2>/dev/null || true
        rm -rf "build/sdk/${arch}"
    fi
done

if [[ ${#SLICES[@]} -eq 0 ]]; then
    # 둘 다 실패하면 대상 지정 없이 이 맥용으로만 만든다. 그래야 최소한 손에 남는다.
    echo "  · 지정한 대상으로 못 만들어 이 맥용으로만 빌드합니다"
    mkdir -p build/sdk/native
    swiftc -O ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"} -module-name "$MODULE_NAME" \
        -emit-module -emit-module-path "build/sdk/native/${MODULE_NAME}.swiftmodule" \
        -emit-executable Sources/*.swift -o build/sdk/native/host
    cp build/sdk/native/host build/agent-monitor
else
    lipo -create "${SLICES[@]}" -output build/agent-monitor
fi

# 애드온 소스가 옆에 있으면 이어서 번들로 짓는다. 없으면 그냥 없는 채로 끝나고, clone 해 온
# 사람에게는 그쪽이 기본이며 그것으로 온전하다. `Addon/` 은 .gitignore 라 따라오지 않는다.
if [[ ${#SWIFT_FLAGS[@]} -gt 0 ]]; then
    echo "  · 애드온을 번들로 짓습니다"
    # `--no-install` 을 그대로 넘긴다. 도는 앱을 안 건드리겠다고 한 사람에게 애드온만
    # 몰래 갈아 끼우면 그 말이 반만 지켜진다.
    if Addon/build.sh ${1:+"$1"}; then
        EDITION="애드온 포함"
    else
        # **여기서 멈추지 않는다.** 애드온이 안 지어져도 앱은 온전하다.
        echo "  · 애드온을 못 지었습니다 — 앱은 그대로 이어서 만듭니다"
    fi
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
# 릴리즈판은 build/ 안에 지으므로 도는 앱과 부딪히지 않는다.
if [[ $WAS_RUNNING -eq 1 && $RELEASE -eq 0 ]]; then
    pkill -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
    sleep 0.4
fi

mkdir -p "$(dirname "$DEST")"
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

# 릴리즈판은 여기서 묶고 끝낸다. 앱의 업데이트가 릴리즈에 붙은 .zip 을 받아 풀므로,
# 번들 하나를 맨 위에 둔 채로 묶는다 (`--keepParent`).
if [[ $RELEASE -eq 1 ]]; then
    ZIP="build/${APP_NAME}-v${VERSION}.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$DEST" "$ZIP"
    echo "빌드 완료  릴리즈판 ${VERSION}  ($(lipo -archs build/agent-monitor 2>/dev/null || echo native))"
    echo "  앱  : $DEST"
    echo "  zip : $ZIP"
    exit 0
fi

# 이름을 PATH 에 건다.
#
# 훅도 README 도 `agent-monitor` 를 치라고 적는데, **여기서 걸어 주지 않으면 그 이름은
# 어디에도 없다.** 실제로 그랬다 — 훅을 읽고 그대로 친 세션이 command not found 를 맞았고,
# 판이 비어 있던 것이 「안 쓴 것」이 아니라 「못 쓴 것」이었다. 앱만 놓고 이름을 안 걸면
# 도구는 설치된 것처럼 보이면서 손에는 안 잡힌다.
#
# sudo 가 필요한 /usr/local/bin 대신 ~/.local/bin 에 건다 — 빌드가 암호를 묻지 않아야 한다.
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
ln -sf "$DEST/Contents/MacOS/${APP_NAME}" "$BIN_DIR/agent-monitor"

echo "빌드 완료  ${EDITION}  ($(lipo -archs build/agent-monitor 2>/dev/null || echo native))"
echo "  앱  : $DEST"
echo "  CLI : $BIN_DIR/agent-monitor   (--list · --json · --memory · --roots · ticket · plan · step · board)"

# 건 이름이 **잡히는지**까지 본다. 안 잡히면 조용히 실패해 이 버그가 그대로 돌아온다.
case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo "  ⚠ $BIN_DIR 이 PATH 에 없습니다 — 셸 설정에 넣어야 이 이름이 잡힙니다" ;;
esac

if [[ "${1:-}" == "--no-run" ]]; then
    [[ $WAS_RUNNING -eq 1 ]] && echo "  → 내려둔 채로 두었습니다 (--no-run)"
    exit 0
fi

open "$DEST"
echo "  → 띄웠습니다$([[ $WAS_RUNNING -eq 1 ]] && echo " (쓰고 계셔서 다시 올렸습니다)")"

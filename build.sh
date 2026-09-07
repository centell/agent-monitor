#!/usr/bin/env bash
# agent-monitor 빌드. 의존성 없음 — swiftc 만 있으면 된다.
#
#   ./build.sh          바이너리 + AgentMonitor.app
#   ./build.sh --run    빌드하고 바로 띄운다
set -euo pipefail
cd "$(dirname "$0")"

VERSION="0.1.0"
APP="build/AgentMonitor.app"

mkdir -p build
swiftc -O Sources/*.swift -o build/agent-monitor

# .app 번들 — LSUIElement 로 Dock 아이콘 없이 메뉴바에만 산다.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp build/agent-monitor "$APP/Contents/MacOS/AgentMonitor"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>AgentMonitor</string>
    <key>CFBundleIdentifier</key><string>me.centell.agent-monitor</string>
    <key>CFBundleName</key><string>AgentMonitor</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT</string>
</dict>
</plist>
PLIST

echo "빌드 완료"
echo "  CLI : build/agent-monitor   (--list · --json · --roots)"
echo "  앱  : $APP"

if [[ "${1:-}" == "--run" ]]; then
    pkill -f "AgentMonitor" 2>/dev/null || true
    sleep 0.5
    open "$APP"
    echo "  → 띄웠습니다"
fi

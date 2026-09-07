#!/usr/bin/env bash
# agent-monitor 빌드. 의존성 없음 — swiftc 만 있으면 된다.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
swiftc -O Sources/*.swift -o build/agent-monitor
echo "빌드 완료: build/agent-monitor"

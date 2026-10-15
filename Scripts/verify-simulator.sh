#!/bin/bash
# 在模拟器上安装并启动 ClassFlow，确认进程存活，并留一张截图。
#
# 用法: Scripts/verify-simulator.sh [输出截图路径]
set -uo pipefail

PROJECT_DIR="${CLASSFLOW_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
XCODEPROJ="$PROJECT_DIR/ClassFlow/ClassFlow.xcodeproj"
DERIVED="${CLASSFLOW_DERIVED:-$PROJECT_DIR/.build}"
BUNDLE_ID="com.wuhanbingyanonlinetechnologycoltd.ClassFlow"
# 用 UDID 而不是名字：同名设备在不同 runtime 下会重复，name= 会报 "ambiguous"。
# 默认 iPhone 17 (iOS 26.2)。可用 CLASSFLOW_SIM_UDID 覆盖。
SIM_UDID="${CLASSFLOW_SIM_UDID:-9C9F620E-E9DE-45A4-826E-15E69D2EE7E7}"
SHOT="${1:-$DERIVED/classflow-simulator.png}"

echo "== 构建 =="
xcodebuild -project "$XCODEPROJ" -scheme ClassFlow \
  -destination "id=$SIM_UDID" \
  -derivedDataPath "$DERIVED" \
  -configuration Debug build > "$DERIVED/verify-build.log" 2>&1 || {
    echo "构建失败，见 $DERIVED/verify-build.log"; tail -20 "$DERIVED/verify-build.log"; exit 1; }

APP="$(find "$DERIVED/Build/Products" -maxdepth 2 -name 'ClassFlow.app' -type d | head -1)"
[ -n "$APP" ] || { echo "找不到 ClassFlow.app"; exit 1; }

ACTUAL_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist" 2>/dev/null || echo "$BUNDLE_ID")"
echo "== 应用: $APP ($ACTUAL_ID) =="

echo "== 启动模拟器 =="
xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
xcrun simctl bootstatus "$SIM_UDID" -b > /dev/null 2>&1 || true

echo "== 安装 =="
xcrun simctl uninstall "$SIM_UDID" "$ACTUAL_ID" > /dev/null 2>&1 || true
xcrun simctl install "$SIM_UDID" "$APP" || { echo "安装失败"; exit 1; }

echo "== 启动 =="
xcrun simctl launch "$SIM_UDID" "$ACTUAL_ID" || { echo "启动失败"; exit 1; }
sleep 5

PID="$(xcrun simctl spawn "$SIM_UDID" launchctl list 2>/dev/null | grep -i classflow | head -1 || true)"
if [ -n "$PID" ]; then
  echo "进程存活: $PID"
else
  echo "失败: 启动后进程不在了（可能启动即崩溃）"; exit 1
fi

xcrun simctl io "$SIM_UDID" screenshot "$SHOT" > /dev/null 2>&1 && echo "截图: $SHOT"
echo "== 模拟器验证完成 =="

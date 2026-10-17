#!/bin/bash
# 在模拟器上安装并启动 ClassFlow，确认进程存活，并留一张截图。
# 用法: Scripts/verify-simulator.sh [输出截图路径]
set -uo pipefail

PROJECT_DIR="${CLASSFLOW_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
XCODEPROJ="$PROJECT_DIR/apps/ios/ClassFlow.xcodeproj"
DERIVED="${CLASSFLOW_DERIVED:-$PROJECT_DIR/.build}"
BUNDLE_ID="com.wuhanbingyanonlinetechnologycoltd.ClassFlow"
# 须用 UDID：同名设备在不同 runtime 下会重复，name= 报 "ambiguous"。
# 默认 iPhone 17 (iOS 26.2)，可覆盖：CLASSFLOW_SIM_UDID。
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

# 小组件扩展必须被嵌进 App，否则桌面组件根本装不上。
APPEX="$APP/PlugIns/ClassFlowWidget.appex"
if [ -d "$APPEX" ]; then
  echo "== 小组件扩展: 已嵌入 ($(du -sh "$APPEX" | cut -f1)) =="
  [ -d "$APPEX/Metadata.appintents" ] && echo "   App Intent 元数据: 有（组件里的按钮才有得跑）"
else
  echo "失败: 找不到 $APPEX"; exit 1
fi

# 深链 scheme 必须写进 Info.plist，否则组件点回来会「没有 App 能打开这个链接」。
SCHEMES="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' "$APP/Info.plist" 2>/dev/null || true)"
if [ "$SCHEMES" = "classflow" ]; then
  echo "== 深链 scheme: classflow:// 已注册 =="
else
  echo "失败: Info.plist 里没有注册 classflow scheme（读到 '${SCHEMES:-空}'）"; exit 1
fi

echo "== 启动模拟器 =="
xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
xcrun simctl bootstatus "$SIM_UDID" -b > /dev/null 2>&1 || true

echo "== 安装 =="
xcrun simctl uninstall "$SIM_UDID" "$ACTUAL_ID" > /dev/null 2>&1 || true
xcrun simctl install "$SIM_UDID" "$APP" || { echo "安装失败"; exit 1; }

# App Group 容器：主 App 与组件共用；simctl 只支持 `groups` 子命令，
# 直接传 group id 会以 117 退出。
GROUP_ID="group.com.wuhanbingyanonlinetechnologycoltd.ClassFlow"
GROUP_PATH="$(xcrun simctl get_app_container "$SIM_UDID" "$ACTUAL_ID" groups 2>/dev/null \
  | awk -v id="$GROUP_ID" '$1 == id { print $2 }' || true)"
if [ -n "$GROUP_PATH" ]; then
  echo "== App Group 容器: $GROUP_PATH =="
else
  echo "失败: 拿不到 App Group 容器（检查两端的 entitlements）"; exit 1
fi

echo "== 启动 =="
xcrun simctl launch "$SIM_UDID" "$ACTUAL_ID" || { echo "启动失败"; exit 1; }
sleep 5

PID="$(xcrun simctl spawn "$SIM_UDID" launchctl list 2>/dev/null | grep -i classflow | head -1 || true)"
if [ -n "$PID" ]; then
  echo "进程存活: $PID"
else
  echo "失败: 启动后进程不在了（可能启动即崩溃）"; exit 1
fi

# 只验证 URL 回跳路径（onOpenURL），App Intent 那条由单元测试覆盖。
for link in "classflow://schedule/today" "classflow://tasks" "classflow://notes" "classflow://settings/period-times"; do
  if xcrun simctl openurl "$SIM_UDID" "$link" > /dev/null 2>&1; then
    echo "深链已交给系统: $link"
  else
    echo "失败: 系统打不开 $link（scheme 没注册？）"; exit 1
  fi
done

sleep 3
if xcrun simctl spawn "$SIM_UDID" launchctl list 2>/dev/null | grep -qi classflow; then
  echo "深链处理之后进程仍然存活"
else
  echo "失败: 处理深链之后 App 不在了（可能崩在路由里）"; exit 1
fi

# 共享容器里的文件（第一次保存课表之后才会出现，这里只做信息性输出）
echo "== 共享容器内容 =="
ls -la "$GROUP_PATH" 2>/dev/null || true

xcrun simctl io "$SIM_UDID" screenshot "$SHOT" > /dev/null 2>&1 && echo "截图: $SHOT"
echo "== 模拟器验证完成 =="

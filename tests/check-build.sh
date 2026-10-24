#!/bin/bash
# 第一层：检查编译产物的配置文件、签名和沙盒设置。需先执行 ./build.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/CopyPathSync.app
EXT=$APP/Contents/PlugIns/CopyPathExtension.appex

plutil -lint host/Info.plist extension/Info.plist extension/*.entitlements
codesign --verify --deep --strict --verbose=2 "$APP"

# Finder 扩展必须开启沙盒，否则系统不会加载
codesign -d --entitlements - "$EXT" 2>&1 | grep -q com.apple.security.app-sandbox \
    || { echo "扩展没有开启沙盒"; exit 1; }

point=$(plutil -extract NSExtension.NSExtensionPointIdentifier raw "$EXT/Contents/Info.plist")
[[ "$point" == com.apple.FinderSync ]] || { echo "扩展类型不对：$point"; exit 1; }

echo "第一层通过"

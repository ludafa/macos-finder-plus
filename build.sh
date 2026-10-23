#!/bin/bash
# 编译 Finder 扩展试用版；加 install 参数会装到 ~/Applications 并注册扩展。
#   ./build.sh           只编译到 build/
#   ./build.sh install   编译并安装
set -euo pipefail
cd "$(dirname "$0")"

BUILD=build
# 按当前电脑的芯片编译（arm64 或 x86_64）
TARGET="$(uname -m)-apple-macos14.0"
rm -rf "$BUILD"
mkdir -p "$BUILD"

echo "==> 生成图标"
swift make-icon.swift "$BUILD/icon-1024.png"
ICONSET="$BUILD/AppIcon.iconset"
mkdir "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s "$BUILD/icon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$BUILD/icon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$BUILD/AppIcon.icns"

echo "==> Finder Sync 扩展 (CopyPathSync.app)"
HOST="$BUILD/CopyPathSync.app"
EXT="$HOST/Contents/PlugIns/CopyPathExtension.appex"
mkdir -p "$HOST/Contents/MacOS" "$HOST/Contents/Resources" "$EXT/Contents/MacOS"
swiftc -O -target $TARGET \
    -module-name CopyPathExtension -parse-as-library -application-extension \
    -Xlinker -e -Xlinker _NSExtensionMain \
    extension/CopyPathExtension.swift \
    -o "$EXT/Contents/MacOS/CopyPathExtension"
cp extension/Info.plist "$EXT/Contents/"
swiftc -O -target $TARGET host/main.swift -o "$HOST/Contents/MacOS/CopyPathSync"
cp host/Info.plist "$HOST/Contents/"
cp "$BUILD/AppIcon.icns" "$HOST/Contents/Resources/"
# 先签内层扩展（必须沙盒），再签外层 App
codesign --force --sign - --entitlements extension/Extension.entitlements "$EXT"
codesign --force --sign - "$HOST"

if [[ "${1:-}" == "install" ]]; then
    echo "==> 安装到 ~/Applications"
    mkdir -p ~/Applications
    rm -rf ~/Applications/CopyPathSync.app
    cp -R "$HOST" ~/Applications/
    # 让 LaunchServices 认识新 App，并打开一次宿主 App，扩展才会被注册
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -f -R ~/Applications/CopyPathSync.app
    open ~/Applications/CopyPathSync.app
    sleep 2
    pluginkit -e use -i com.ludafa.finderplus.extension
    # 结束旧的扩展进程，Finder 会按需启动新版本
    pkill -x CopyPathExtension || true
fi

echo "==> 完成"

#!/bin/bash
# 第二层：确认扩展已注册、已启用，并且 Finder 真的启动了扩展进程。需先执行 ./build.sh install
set -euo pipefail

ID=com.ludafa.finderplus.extension

if ! pluginkit -m -i "$ID" | grep -q '^+'; then
    echo "扩展没有启用："
    pluginkit -m -v -i "$ID"
    exit 1
fi

# 扩展进程由 Finder 启动；Finder 没有打开窗口时可能不会马上启动，等一会儿再开个窗口
for i in $(seq 30); do
    if pgrep -x CopyPathExtension >/dev/null; then
        echo "第二层通过"
        exit 0
    fi
    [[ $i == 15 ]] && open "$HOME"
    sleep 1
done

echo "30 秒内 Finder 没有启动扩展进程"
exit 1

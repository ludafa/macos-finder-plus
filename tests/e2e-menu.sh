#!/bin/bash
# 第三层：在 Finder 里真的打开菜单、点击菜单项，再检查剪贴板内容。需先执行 ./build.sh install
# 会打开 Finder 窗口和菜单，需要辅助功能权限，并要求 Finder 使用列表视图，适合在 CI 上运行。
# 某个用例失败时会当场截屏到 $RUNNER_TEMP，然后继续跑后面的用例，最后统一报告。
set -euo pipefail
cd "$(dirname "$0")/.."

swiftc -O tests/MenuClicker.swift -o build/MenuClicker

if [[ -n "${CI:-}" ]]; then
    # CI 机器是全新的，直接把 Finder 默认视图改成列表视图并重启 Finder
    defaults write com.apple.finder FXPreferredViewStyle -string Nlsv
    killall Finder || true
    sleep 3
    for _ in $(seq 30); do pgrep -x CopyPathExtension >/dev/null && break; sleep 1; done
fi

build/MenuClicker --check-trust

ROOT="$(mktemp -d "${RUNNER_TEMP:-$HOME}/finder-plus-e2e.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT
DIR="$ROOT/带 空格 的目录"
mkdir -p "$DIR"
touch "$DIR/a.txt" "$DIR/b c.txt"

FAILED=()

record_failure() {
    FAILED+=("$1")
    screencapture -x "${RUNNER_TEMP:-$ROOT}/failed-${#FAILED[@]}.png" || true
}

# 跑一个用例：清空剪贴板 → 用 MenuClicker 操作菜单 → 比较剪贴板与期望值（多个路径时不要求顺序）。
# 期望为空表示剪贴板不应被改动。
# 用法：check <用例名> <期望的剪贴板内容> <MenuClicker 参数...>
check() {
    local name="$1" expected="$2" actual=""
    shift 2
    echo "==> $name"
    pbcopy </dev/null
    if ! build/MenuClicker "$@"; then
        record_failure "$name"
        return
    fi
    if [[ -z "$expected" ]]; then
        sleep 1
        actual="$(pbpaste)"
    else
        for _ in $(seq 50); do
            actual="$(pbpaste)"
            [[ -n "$actual" ]] && break
            sleep 0.1
        done
    fi
    if [[ "$(sort <<<"$actual")" != "$(sort <<<"$expected")" ]]; then
        printf '剪贴板内容不符\n期望：\n%s\n实际：\n%s\n' "$expected" "$actual"
        record_failure "$name"
        return
    fi
    echo "剪贴板符合预期"
}

# 打开测试目录的窗口并选中 a.txt
open -R "$DIR/a.txt"
sleep 2

check "右键单个文件" "$DIR/a.txt" "拷贝路径"
check "全选后右键" "$DIR/a.txt
$DIR/b c.txt" --select-all "拷贝 2 个项目的路径"
check "右键窗口空白处" "$DIR" --select-none "拷贝当前路径"
check "没有选中项时点工具栏按钮" "$DIR" --toolbar --select-none "拷贝当前路径"
check "有选中项时点工具栏按钮" "$DIR/a.txt" --toolbar --select a.txt "拷贝 1 个选中项的路径"
# 侧边栏不提供我们的菜单项（扩展对侧边栏菜单返回 nil）
check "右键侧边栏" "" --sidebar --expect-absent "拷贝路径"

# 「最近使用」没有真实路径：点了菜单项也不应该改动剪贴板
open /System/Library/CoreServices/Finder.app/Contents/Resources/MyLibraries/myDocuments.cannedSearch
sleep 2
check "在「最近使用」里点工具栏按钮" "" --toolbar "拷贝当前路径"

if (( ${#FAILED[@]} )); then
    echo "失败的用例（${#FAILED[@]} 个）："
    printf '  %s\n' "${FAILED[@]}"
    exit 1
fi
echo "第三层通过"

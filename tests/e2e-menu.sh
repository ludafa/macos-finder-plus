#!/bin/bash
# 第三层：在 Finder 里真的打开右键菜单、点击菜单项，再检查剪贴板内容。需先执行 ./build.sh install
# 会打开 Finder 窗口和右键菜单，需要辅助功能权限，并要求 Finder 使用列表视图，适合在 CI 上运行。
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

# 等剪贴板出现内容，与期望值比较（多个路径时不要求顺序）
expect_clipboard() {
    local expected="$1" actual=""
    for _ in $(seq 50); do
        actual="$(pbpaste)"
        [[ -n "$actual" ]] && break
        sleep 0.1
    done
    if [[ "$(sort <<<"$actual")" != "$(sort <<<"$expected")" ]]; then
        printf '剪贴板内容不符\n期望：\n%s\n实际：\n%s\n' "$expected" "$actual"
        exit 1
    fi
    echo "剪贴板正确"
}

run_case() {
    echo "==> $1"
    shift
    pbcopy </dev/null
    build/MenuClicker "$@"
}

# 打开测试目录的窗口并选中 a.txt
open -R "$DIR/a.txt"
sleep 2

run_case "右键单个文件" "拷贝路径"
expect_clipboard "$DIR/a.txt"

run_case "全选后右键" --select-all "拷贝 2 个项目的路径"
expect_clipboard "$DIR/a.txt
$DIR/b c.txt"

run_case "右键窗口空白处" --select-none "拷贝当前路径"
expect_clipboard "$DIR"

run_case "有选中项时点工具栏按钮" --toolbar --select-first "拷贝 1 个选中项的路径"
expect_clipboard "$DIR/a.txt"

run_case "没有选中项时点工具栏按钮" --toolbar --select-none "拷贝当前路径"
expect_clipboard "$DIR"

# 侧边栏不提供我们的菜单项（扩展对侧边栏菜单返回 nil）
run_case "右键侧边栏" --sidebar --expect-absent "拷贝路径"

# 「最近使用」没有真实路径：点了菜单项也不应该改动剪贴板
open /System/Library/CoreServices/Finder.app/Contents/Resources/MyLibraries/myDocuments.cannedSearch
sleep 2
run_case "在「最近使用」里点工具栏按钮" --toolbar "拷贝当前路径"
sleep 1
[[ -z "$(pbpaste)" ]] || { echo "剪贴板不应该被改动，实际：$(pbpaste)"; exit 1; }
echo "剪贴板没有被改动，符合预期"

echo "第三层通过"

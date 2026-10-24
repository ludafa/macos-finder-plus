#!/bin/bash
# 汇总端到端测试和单元测试的覆盖率数据，生成报告到 build/coverage/。
# 需先用 COVERAGE=1 ./build.sh install 安装覆盖率版本并跑完 tests/e2e-menu.sh；
# 如果也跑了 COVERAGE=1 tests/unit-tests.sh，会把单元测试的数据一起算进去
set -euo pipefail
cd "$(dirname "$0")/.."

E2E_DATA=/private/tmp/finderplus-coverage
UNIT_DATA=/private/tmp/finderplus-unit
BIN=build/CopyPathSync.app/Contents/PlugIns/CopyPathExtension.appex/Contents/MacOS/CopyPathExtension
OUT=build/coverage

shopt -s nullglob
e2e_files=("$E2E_DATA"/*.profraw)
unit_files=("$UNIT_DATA"/*.profraw)
if (( ${#e2e_files[@]} == 0 )); then
    echo "没有找到端到端测试的覆盖率数据（$E2E_DATA/*.profraw）"
    exit 1
fi
echo "合并 ${#e2e_files[@]} 个端到端测试、${#unit_files[@]} 个单元测试的覆盖率数据文件"

rm -rf "$OUT"
mkdir -p "$OUT"
xcrun llvm-profdata merge -sparse "${e2e_files[@]}" "${unit_files[@]}" -o "$OUT/coverage.profdata"
# 两个程序编译自同一份扩展源码，一起交给 llvm-cov 才能合并统计；测试代码本身不计入
COV_ARGS=("$BIN" -instr-profile="$OUT/coverage.profdata" -ignore-filename-regex='/tests/')
if (( ${#unit_files[@]} )); then
    COV_ARGS+=(-object "$UNIT_DATA/UnitTests")
fi

xcrun llvm-cov report "${COV_ARGS[@]}" | tee "$OUT/report.txt"
xcrun llvm-cov show "${COV_ARGS[@]}" -format=html -output-dir="$OUT/html"
xcrun llvm-cov export "${COV_ARGS[@]}" -format=lcov >"$OUT/coverage.lcov"

# 列出没执行到的代码块（行:列  代码）。某一行执行过、但其中一个分支没走到时，只看行覆盖率是发现不了的
xcrun llvm-cov export "${COV_ARGS[@]}" -format=text | python3 -I -c '
import json, sys
seen = set()
for function in json.load(sys.stdin)["data"][0]["functions"]:
    for line, column, _, _, count, file_id, _, kind in function["regions"]:
        path = function["filenames"][file_id]
        # kind 0 是普通代码块；同一份源码被两个程序各统计一次，去重
        if count or kind != 0 or (path, line, column) in seen:
            continue
        seen.add((path, line, column))
        print(f"{line}:{column}  {open(path).read().splitlines()[line - 1].strip()}")
' >"$OUT/uncovered.txt"
echo "未覆盖的代码块："
cat "$OUT/uncovered.txt"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
        echo "## 覆盖率（端到端测试 + 单元测试）"
        echo '```'
        cat "$OUT/report.txt"
        echo '```'
        echo "### 未覆盖的代码块（行:列）"
        echo '```swift'
        cat "$OUT/uncovered.txt"
        echo '```'
        echo "逐行的 HTML 报告见本次运行的附件 coverage-*。"
    } >>"$GITHUB_STEP_SUMMARY"
fi

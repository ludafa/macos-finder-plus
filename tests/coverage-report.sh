#!/bin/bash
# 汇总端到端测试中扩展写出的覆盖率数据，生成报告到 build/coverage/。
# 需先用 COVERAGE=1 ./build.sh install 安装覆盖率版本，再跑完 tests/e2e-menu.sh
set -euo pipefail
cd "$(dirname "$0")/.."

DATA=/private/tmp/finderplus-coverage
BIN=build/CopyPathSync.app/Contents/PlugIns/CopyPathExtension.appex/Contents/MacOS/CopyPathExtension
OUT=build/coverage

shopt -s nullglob
files=("$DATA"/*.profraw)
if (( ${#files[@]} == 0 )); then
    echo "没有找到覆盖率数据（$DATA/*.profraw）"
    exit 1
fi
echo "合并 ${#files[@]} 个覆盖率数据文件"

rm -rf "$OUT"
mkdir -p "$OUT"
xcrun llvm-profdata merge -sparse "${files[@]}" -o "$OUT/coverage.profdata"
COV_ARGS=("$BIN" -instr-profile="$OUT/coverage.profdata")

xcrun llvm-cov report "${COV_ARGS[@]}" | tee "$OUT/report.txt"
xcrun llvm-cov show "${COV_ARGS[@]}" -format=html -output-dir="$OUT/html"
xcrun llvm-cov export "${COV_ARGS[@]}" -format=lcov >"$OUT/coverage.lcov"

# 列出没被执行到的代码行（行号 | 执行次数 0 | 代码）
xcrun llvm-cov show "${COV_ARGS[@]}" -format=text \
    | grep -E '^ *[0-9]+\| +0\|' >"$OUT/uncovered.txt" || true
echo "未覆盖的行："
cat "$OUT/uncovered.txt"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
        echo "## 端到端测试覆盖率"
        echo '```'
        cat "$OUT/report.txt"
        echo '```'
        echo "### 未覆盖的行"
        echo '```swift'
        cat "$OUT/uncovered.txt"
        echo '```'
        echo "逐行的 HTML 报告见本次运行的附件 coverage-*。"
    } >>"$GITHUB_STEP_SUMMARY"
fi

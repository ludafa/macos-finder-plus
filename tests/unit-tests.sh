#!/bin/bash
# 单元测试：把扩展代码和 tests/UnitTests.swift 编译成命令行程序运行。
# 加 COVERAGE=1 时带覆盖率统计，程序和数据放在 /private/tmp/finderplus-unit/
# （不放 build/，因为 build.sh 每次会清空它），由 tests/coverage-report.sh 和端到端测试的数据一起汇总。
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=/private/tmp/finderplus-unit
rm -rf "$OUT"
mkdir -p "$OUT"

FLAGS=(-Onone)
if [[ -n "${COVERAGE:-}" ]]; then
    # 与 build.sh 的覆盖率版本保持相同的模块名、目标平台和编译参数，两边的数据才能合并到同一份源码上
    FLAGS=(-Onone -profile-generate -profile-coverage-mapping -D COVERAGE)
fi
swiftc "${FLAGS[@]}" -target "$(uname -m)-apple-macos14.0" \
    -module-name CopyPathExtension -parse-as-library \
    extension/CopyPathExtension.swift tests/UnitTests.swift \
    -o "$OUT/UnitTests"

LLVM_PROFILE_FILE="$OUT/unit-%p.profraw" "$OUT/UnitTests"

#!/usr/bin/env bash
set -euo pipefail

# Reproduce the compiler listings used by compiler_baseline_diff.md.
# Run this on Apple Silicon: the checked-in O2 executables are arm64 Mach-O,
# while clang's -arch option supplies the x86-64 instruction-selection view.

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
out_dir=${1:-"$repo_root/results/compiler_baseline"}
c_dir="$repo_root/benchmarks/c_portable"

mkdir -p "$out_dir"

for binary in fib_O2 matmul_c_O2; do
    binary_path="$c_dir/$binary"
    if [[ ! -x "$binary_path" ]]; then
        echo "missing executable: $binary_path" >&2
        exit 1
    fi
    if ! file "$binary_path" | rg -q 'Mach-O 64-bit executable arm64'; then
        echo "expected an arm64 Mach-O executable: $binary_path" >&2
        exit 1
    fi
    otool -tvV "$binary_path" > "$out_dir/${binary}_aarch64.disasm"
done

clang -O2 -S -arch x86_64 "$c_dir/fib.c" \
    -o "$out_dir/fib_O2_x86_64.s"
clang -O2 -S -arch x86_64 "$c_dir/matmul.c" \
    -o "$out_dir/matmul_c_O2_x86_64.s"

{
    clang --version
    echo
    file "$c_dir/fib_O2" "$c_dir/matmul_c_O2"
} > "$out_dir/toolchain.txt"

echo "compiler baselines written to $out_dir"

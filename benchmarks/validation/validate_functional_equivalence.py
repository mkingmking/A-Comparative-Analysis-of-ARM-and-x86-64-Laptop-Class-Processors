#!/usr/bin/env python3
"""Validate the assembly kernels against platform-independent references.

The script creates temporary validation-only source variants.  It does not
modify the benchmark sources or the binaries used for timing/energy results.

Run on macOS/AArch64:
    python3 benchmarks/validation/validate_functional_equivalence.py arm64-macos

Run on Linux/x86-64 (requires nasm and gcc):
    python3 benchmarks/validation/validate_functional_equivalence.py x86_64-linux
"""

from __future__ import annotations

import argparse
import json
import math
import re
import struct
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
FIB_CASES = (0, 1, 2, 5, 10, 20, 30, 40)
MATRIX_CASES = tuple((n, modulus) for n in (4, 8, 16, 32) for modulus in (7, 31, 100)) + (
    (256, 100),
)


def run(command: list[str], *, capture: bool = False) -> bytes:
    completed = subprocess.run(
        command,
        check=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE,
    )
    return completed.stdout if capture else b""


def fib_reference(n: int) -> int:
    if n <= 1:
        return n
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return a


def i32(value: int) -> int:
    value &= 0xFFFFFFFF
    return value - 0x100000000 if value >= 0x80000000 else value


def matrix_reference(n: int, modulus: int) -> list[int]:
    values = [i % modulus for i in range(n * n)]
    result: list[int] = []
    for row in range(n):
        for column in range(n):
            total = 0
            for k in range(n):
                total = i32(total + i32(values[row * n + k] * values[k * n + column]))
            result.append(total)
    return result


def arm_fib_source(source: str, n: int) -> str:
    return source.replace("mov     w0, #40", f"mov     w0, #{n}", 1)


def x86_fib_source(source: str, n: int) -> str:
    return re.sub(r"N_VAL:\s+equ 40", f"N_VAL:      equ {n}", source, count=1)


def arm_matrix_source(source: str, n: int, modulus: int) -> str:
    matrix_bytes = n * n * 4
    source = re.sub(r"\.equ N, 256", f".equ N, {n}", source, count=1)
    source = re.sub(r"\.equ N_SQUARED, 65536", f".equ N_SQUARED, {n * n}", source, count=1)
    source = re.sub(r"\.equ MATRIX_BYTES, 262144", f".equ MATRIX_BYTES, {matrix_bytes}", source, count=1)
    source = source.replace("mov     w11, #100", f"mov     w11, #{modulus}", 1)
    old = """    ldr     w9, [x21]
    str     x9, [sp]
    adrp    x0, _fmt_result@PAGE
    add     x0, x0, _fmt_result@PAGEOFF
    bl      _printf"""
    new = f"""    // Validation-only: emit every int32 element of C as raw bytes.
    mov     x0, #1
    mov     x1, x21
    mov     x2, #{matrix_bytes}
    bl      _write"""
    if old not in source:
        raise RuntimeError("AArch64 matrix output block no longer matches validator")
    source = source.replace(old, new, 1)
    source = re.sub(
        r"\.zerofill __DATA,__bss,_mat_[ABC],262144,4",
        lambda match: match.group(0).replace("262144", str(matrix_bytes)),
        source,
    )
    return source


def x86_matrix_source(source: str, n: int, modulus: int) -> str:
    if n & (n - 1):
        raise ValueError("x86 validation dimensions must be powers of two")
    log2_n = int(math.log2(n))
    matrix_bytes = n * n * 4
    source = re.sub(r"N:\s+equ 256", f"N:          equ {n}", source, count=1)
    source = re.sub(r"N_SQ:\s+equ 65536[^\n]*", f"N_SQ:       equ {n * n}", source, count=1)
    source = re.sub(r"MAT_BYTES:\s+equ 262144[^\n]*", f"MAT_BYTES:  equ {matrix_bytes}", source, count=1)
    source = source.replace("shl     r8, 10", f"shl     r8, {log2_n + 2}", 1)
    source = source.replace("shl     eax, 8", f"shl     eax, {log2_n}", 1)
    source = source.replace("mov     ebx, 100", f"mov     ebx, {modulus}", 1)
    source = source.replace("extern printf", "extern printf\nextern write", 1)
    old = """    ; Print result
    lea     rdi, [rel fmt_done]
    lea     rax, [rel mat_C]
    mov     esi, [rax]              ; C[0]
    xor     eax, eax
    call    printf wrt ..plt"""
    new = f"""    ; Validation-only: emit every int32 element of C as raw bytes.
    mov     edi, 1
    lea     rsi, [rel mat_C]
    mov     edx, {matrix_bytes}
    call    write wrt ..plt"""
    if old not in source:
        raise RuntimeError("x86-64 matrix output block no longer matches validator")
    return source.replace(old, new, 1)


def build(platform: str, source_path: Path, executable: Path) -> None:
    if platform == "arm64-macos":
        run(["clang", str(source_path), "-o", str(executable)])
    else:
        object_path = executable.with_suffix(".o")
        run(["nasm", "-f", "elf64", "-o", str(object_path), str(source_path)])
        run(["gcc", "-o", str(executable), str(object_path), "-no-pie"])


def validate(platform: str) -> dict[str, object]:
    is_arm = platform == "arm64-macos"
    source_dir = ROOT / "benchmarks" / ("asm_aarch64" if is_arm else "asm_x86_64")
    fib_path = source_dir / ("fib_arm.s" if is_arm else "fib_x86.asm")
    matrix_path = source_dir / ("matmul_arm.s" if is_arm else "matmul_x86.asm")
    fib_original = fib_path.read_text()
    matrix_original = matrix_path.read_text()
    fib_results = []
    matrix_results = []

    with tempfile.TemporaryDirectory(prefix="assembly-validation-") as temp_name:
        temp = Path(temp_name)
        extension = ".s" if is_arm else ".asm"
        for n in FIB_CASES:
            source = arm_fib_source(fib_original, n) if is_arm else x86_fib_source(fib_original, n)
            variant = temp / f"fib_{n}{extension}"
            executable = temp / f"fib_{n}"
            variant.write_text(source)
            build(platform, variant, executable)
            output = run([str(executable)], capture=True).decode("utf-8")
            match = re.search(r"=\s*(-?\d+)\s*$", output)
            if not match:
                raise RuntimeError(f"could not parse Fibonacci output: {output!r}")
            actual = int(match.group(1))
            expected = fib_reference(n)
            if actual != expected:
                raise AssertionError(f"fib({n}): assembly={actual}, reference={expected}")
            fib_results.append({"n": n, "result": actual, "status": "pass"})

        for n, modulus in MATRIX_CASES:
            source = (
                arm_matrix_source(matrix_original, n, modulus)
                if is_arm
                else x86_matrix_source(matrix_original, n, modulus)
            )
            variant = temp / f"matrix_{n}_{modulus}{extension}"
            executable = temp / f"matrix_{n}_{modulus}"
            variant.write_text(source)
            build(platform, variant, executable)
            raw = run([str(executable)], capture=True)
            expected = matrix_reference(n, modulus)
            expected_bytes = struct.pack(f"<{len(expected)}i", *expected)
            if raw != expected_bytes:
                actual = list(struct.unpack(f"<{len(raw) // 4}i", raw)) if len(raw) % 4 == 0 else []
                first_difference = next(
                    (index for index, pair in enumerate(zip(actual, expected)) if pair[0] != pair[1]),
                    None,
                )
                raise AssertionError(
                    f"matrix n={n}, modulus={modulus}: byte length {len(raw)} "
                    f"(expected {len(expected_bytes)}), first difference {first_difference}"
                )
            matrix_results.append(
                {
                    "dimension": n,
                    "input_rule": f"A[i]=B[i]=i mod {modulus}",
                    "elements_compared": n * n,
                    "status": "pass",
                }
            )

    return {
        "platform": platform,
        "source_files": [str(fib_path.relative_to(ROOT)), str(matrix_path.relative_to(ROOT))],
        "fibonacci": fib_results,
        "matrix": matrix_results,
        "summary": {
            "fibonacci_cases": len(fib_results),
            "matrix_cases": len(matrix_results),
            "matrix_elements_compared": sum(item["elements_compared"] for item in matrix_results),
            "status": "pass",
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("platform", choices=("arm64-macos", "x86_64-linux"))
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = validate(args.platform)
    rendered = json.dumps(report, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered)
    print(rendered, end="")


if __name__ == "__main__":
    main()

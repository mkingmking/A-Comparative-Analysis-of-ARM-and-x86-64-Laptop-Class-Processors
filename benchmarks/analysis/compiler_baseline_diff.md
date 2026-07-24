# Compiler-baseline instruction-selection diff

This note compares the hot kernels in the hand-written assembly with Clang
`-O2` output from the corresponding portable C. It is an instruction-selection
comparison, not a performance result: static loop instructions have different
costs, and the two programs do not use identical allocation, initialization,
or output code.

## Baselines and method

- **AArch64:** disassembly of the supplied arm64 Mach-O executables
  `benchmarks/c_portable/fib_O2` and `matmul_c_O2` using `otool -tvV`.
- **x86-64:** Apple Clang 16.0.0 output from the same C sources with
  `clang -O2 -S -arch x86_64`. This isolates x86-64 instruction selection, but
  uses the Darwin ABI rather than the Linux ABI used by the NASM programs.
- **Scope:** `_fib` and the steady-state `k` loop only. The compiler inlines
  `matmul` into `main`, so symbol-size comparisons would mix the kernel with
  allocation, random initialization, timing, and printing.
- **Dynamic loop count:** instructions executed per original `k` iteration,
  including the loop back-edge and excluding entry, exit, and odd-`N` cleanup.
  Since the compiler loops are unrolled by two, their static loop-body counts
  are divided by two.

Recreate all compiler listings from the repository root with:

```sh
bash benchmarks/analysis/generate_compiler_baselines.sh
```

The script records the toolchain version alongside the listings. The existing
Mach-O files do not embed enough information to identify their original Clang
version, so the AArch64 findings below are based on their actual machine code,
not on a recompilation.

## Quantitative summary

| Kernel | ISA | Hand-written | Clang `-O2` | Difference |
| --- | --- | ---: | ---: | ---: |
| Fibonacci | AArch64 | 2 recursive call sites | 1 recursive call site + loop | 50% fewer dynamic calls at `n=40` |
| Fibonacci | x86-64 | 2 recursive call sites | 1 recursive call site + loop | 50% fewer dynamic calls at `n=40` |
| Matmul `k` loop | AArch64 | 9 instructions / `k` | 9 / 2 = 4.5 instructions / `k` | 50.0% fewer |
| Matmul `k` loop | x86-64 | 9 instructions / `k` | 10 / 2 = 5.0 instructions / `k` | 44.4% fewer |

For naive Fibonacci, the hand-written recurrence executes
`2*F(n+1)-1` function entries. At `n=40` that is **331,160,281 entries** and
**331,160,280 call/return edges**. Clang's loop-converted recurrence executes
`F(n+1)` entries: **165,580,141 entries** and **165,580,140 call/return
edges**. Thus it removes exactly **165,580,140 calls and matching returns**,
or 50% of the hand-written edge count. It does not replace Fibonacci with a
closed form or an iterative linear-time algorithm; the workload remains
exponential.

For `N=256`, each matmul runs `N^3 = 16,777,216` original `k` iterations.
Ignoring loop entry/exit and cleanup, the hot-loop totals are therefore:

| ISA | Hand-written | Clang `-O2` | Instructions removed |
| --- | ---: | ---: | ---: |
| AArch64 | 150,994,944 | 75,497,472 | 75,497,472 |
| x86-64 | 150,994,944 | 83,886,080 | 67,108,864 |

These are modeled dynamic instruction counts from the shown loop bodies, not
hardware retired-instruction measurements.

## Fibonacci diff

Both compiler back ends perform the same structural optimization. The hand
code computes `fib(n-1)`, calls `fib(n-2)`, and adds the two results. Clang
retains the `fib(n-1)` call but turns the second recursion into a loop over
`n-2`, accumulating partial results in a callee-saved register.

On AArch64, the important compiler sequence is:

```asm
sub  w0, w20, #1
bl   _fib
mov  x8, x0
sub  w0, w20, #2
add  x19, x8, x19
cmp  w20, #4
mov  x20, x0
b.hs <loop>
```

The hand-written AArch64 instead has a second `bl _fib`. Clang also uses one
32-byte frame per surviving invocation, the same frame size as the hand code,
so the gain is fewer dynamically created frames rather than a smaller frame.
Its combined `add x0, x19, w0, sxtw` also folds sign extension of the base-case
value into the addition; the hand code uses a separate `uxtw` on the base path.

The x86-64 result is analogous: Clang replaces the second `callq _fib` with a
back-edge and uses `addq %rbx, %rax` when leaving the loop. The compiler frame
saves three registers (`rbp`, `r14`, and `rbx`) and is entered even for the base
case, whereas the hand code saves `rbx` and `r12` only on recursive cases.
That makes the hand base case leaner, but it does not compensate for twice as
many calls over `fib(40)`.

## Matrix-multiply diff

### AArch64

The hand-written loop executes nine instructions for every `k`: compare,
conditional branch, two address-generating `madd`s, two scalar loads, one
accumulating `madd`, increment, and an unconditional back-edge.

Clang unrolls by two and executes nine instructions per pair:

```asm
ldp  w5, w6, [x2, #-4]
ldr  w7, [x3, x12]
ldr  w19, [x3]
madd w0, w19, w5, w0
madd w1, w7, w6, w1
add  x3, x3, x13
add  x2, x2, #8
subs x4, x4, #2
b.ne <loop>
```

This removes per-element index multiplication, uses pointer induction, folds
the compare into `subs`, halves branch frequency, and maintains two independent
accumulators before combining them. It also uses `ldp` to fetch two adjacent A
elements. There is no NEON vectorization; B is accessed down a column and the
compiler has no non-aliasing guarantee for the three pointers.

### x86-64

The hand-written loop also has nine instructions per `k`: two explicit loads,
register-register `imul`, accumulator add, two loop-control comparisons/branches,
and pointer/counter updates.

Clang's two-way-unrolled loop has ten instructions per pair:

```asm
movl  (%r10), %r8d
imull -4(%rdx,%rbx,4), %r8d
addl  %r12d, %r8d
movl  (%r10,%rsi), %r12d
imull (%rdx,%rbx,4), %r12d
addl  %r8d, %r12d
addq  $2, %rbx
addq  %rdi, %r10
cmpq  %rbx, %rcx
jne   <loop>
```

It folds each B load into an `imul` memory operand, advances pointers instead
of recalculating both indices, and halves branch frequency. Unlike AArch64,
this particular schedule preserves one serial accumulator chain rather than
using two independent accumulators. It is still scalar—no SSE/AVX multiply is
selected.

## Distance from the compiler baseline

The handwritten Fibonacci implementations are structurally far from `-O2`:
their direct source-shaped recursion doubles dynamic call/return traffic. The
matrix implementations are also materially behind the compiler baseline in
instruction count (44-50%), chiefly because they recompute indices and branch
for every scalar element. The gap is not due to exotic ISA features: the main
compiler choices are recursion-to-loop conversion, two-way unrolling, pointer
induction, fused addressing/compare forms, and—on AArch64—two accumulators.

The comparison also sets a limit on the conclusion: these C kernels accept a
runtime `N`, while the assembly fixes `N=256`, and the x86 compiler listing is
Darwin rather than Linux. A native GCC/Clang build on the Ryzen host should be
captured before attributing code-generation differences to the measured Linux
toolchain, but neither issue changes the supplied AArch64-binary result.

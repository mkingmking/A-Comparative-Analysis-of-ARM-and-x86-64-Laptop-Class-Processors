// fib_arm.s - Recursive Fibonacci in AArch64 Assembly (with timing)
// Target: Apple Silicon (M3) running macOS
//
// Build:
//   as -o fib_arm.o fib_arm.s
//   ld -o fib_arm fib_arm.o -lSystem -syslibroot $(xcrun --sdk macosx --show-sdk-path) -e _main
//
// Run:
//   ./fib_arm
//   OR with external timing:
//   hyperfine --warmup 5 --runs 30 './fib_arm'

.global _main
.align 4

// -------------------------------------------------------
// fib(n): recursive Fibonacci
//   Input:  x0 = n (use 64-bit throughout to avoid overflow issues)
//   Output: x0 = fib(n)
// -------------------------------------------------------
_fib:
    cmp     x0, #1
    b.le    .Lfib_base

    // Save frame
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    stp     x19, x20, [sp, #-16]!

    mov     x19, x0                  // x19 = n

    // fib(n-1)
    sub     x0, x19, #1
    bl      _fib
    mov     x20, x0                  // x20 = fib(n-1)

    // fib(n-2)
    sub     x0, x19, #2
    bl      _fib

    // result = fib(n-1) + fib(n-2)
    add     x0, x20, x0

    // Restore
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

.Lfib_base:
    // n <= 1: return n (already in x0)
    ret

// -------------------------------------------------------
// main
// -------------------------------------------------------
_main:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!

    // ---- Get start time ----
    // Call clock_gettime(CLOCK_MONOTONIC, &timespec)
    // On macOS/ARM64: CLOCK_MONOTONIC = 6
    sub     sp, sp, #32              // space for two timespec structs (16 bytes each)
    mov     x0, #6                   // CLOCK_MONOTONIC
    mov     x1, sp                   // &start_time (at sp)
    bl      _clock_gettime

    // ---- Compute fib(40) ----
    mov     x0, #40
    bl      _fib
    mov     x19, x0                  // x19 = result

    // ---- Get end time ----
    mov     x0, #6
    add     x1, sp, #16              // &end_time (at sp+16)
    bl      _clock_gettime

    // ---- Calculate elapsed nanoseconds ----
    // elapsed = (end.tv_sec - start.tv_sec) * 1e9 + (end.tv_nsec - start.tv_nsec)
    ldr     x20, [sp, #16]           // end.tv_sec
    ldr     x21, [sp, #24]           // end.tv_nsec
    ldr     x22, [sp]                // start.tv_sec
    ldr     x9,  [sp, #8]            // start.tv_nsec

    sub     x20, x20, x22            // delta_sec
    sub     x21, x21, x9             // delta_nsec

    // Convert to milliseconds: ms = delta_sec * 1000 + delta_nsec / 1000000
    mov     x10, #1000
    mul     x20, x20, x10            // delta_sec * 1000
    mov     x10, #16960
    movk    x10, #15, lsl #16        // x10 = 1000000 (0xF4240)
    udiv    x21, x21, x10           
    add     x20, x20, x21            // total ms

    add     sp, sp, #32              // restore stack

    // ---- Print results ----
    // Print: "fib(40) = <result>"
    adrp    x0, _fmt_result@PAGE
    add     x0, x0, _fmt_result@PAGEOFF
    mov     x1, x19
    bl      _printf

    // Print: "Time: <ms> ms"
    adrp    x0, _fmt_time@PAGE
    add     x0, x0, _fmt_time@PAGEOFF
    mov     x1, x20
    bl      _printf

    // Exit
    mov     x0, #0
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

.section __DATA,__data
_fmt_result:
    .asciz "fib(40) = %lld\n"
_fmt_time:
    .asciz "Time: %lld ms\n"

// matmul_arm.s - Matrix Multiplication in AArch64 Assembly (with timing)
// Target: Apple Silicon (M3) running macOS
//
// Build:
//   as -o matmul_arm.o matmul_arm.s
//   ld -o matmul_arm matmul_arm.o -lSystem -syslibroot $(xcrun --sdk macosx --show-sdk-path) -e _main
//
// Run:
//   ./matmul_arm
//   OR: hyperfine --warmup 5 --runs 30 './matmul_arm'

.global _main
.align 4

.equ N, 256
.equ N_SQUARED, 65536
.equ MATRIX_BYTES, 262144

// -------------------------------------------------------
// matmul: C = A × B (256×256 integers)
//   x0 = A, x1 = B, x2 = C
// -------------------------------------------------------
_matmul:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    stp     x23, x24, [sp, #-16]!
    stp     x25, x26, [sp, #-16]!

    mov     x19, x0                 // A
    mov     x20, x1                 // B
    mov     x21, x2                 // C
    mov     w22, #N

    mov     w23, #0                 // i = 0
.Li:
    cmp     w23, w22
    b.ge    .Li_done

    mov     w24, #0                 // j = 0
.Lj:
    cmp     w24, w22
    b.ge    .Lj_done

    mov     w26, #0                 // sum = 0
    mov     w25, #0                 // k = 0
.Lk:
    cmp     w25, w22
    b.ge    .Lk_done

    // A[i*N + k]
    madd    w9, w23, w22, w25
    ldr     w10, [x19, w9, UXTW #2]

    // B[k*N + j]
    madd    w11, w25, w22, w24
    ldr     w12, [x20, w11, UXTW #2]

    // sum += A[i][k] * B[k][j]
    madd    w26, w10, w12, w26

    add     w25, w25, #1
    b       .Lk

.Lk_done:
    // C[i*N + j] = sum
    madd    w9, w23, w22, w24
    str     w26, [x21, w9, UXTW #2]

    add     w24, w24, #1
    b       .Lj

.Lj_done:
    add     w23, w23, #1
    b       .Li

.Li_done:
    ldp     x25, x26, [sp], #16
    ldp     x23, x24, [sp], #16
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

// -------------------------------------------------------
// main
// -------------------------------------------------------
_main:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    stp     x23, x24, [sp, #-16]!

    // Allocate A, B, C
    mov     x0, #MATRIX_BYTES
    bl      _malloc
    mov     x19, x0                 // A

    mov     x0, #MATRIX_BYTES
    bl      _malloc
    mov     x20, x0                 // B

    mov     x0, #MATRIX_BYTES
    bl      _malloc
    mov     x21, x0                 // C

    // Fill A and B with (i % 100)
    mov     w9, #0
    mov     w10, #N_SQUARED
.Lfill:
    cmp     w9, w10
    b.ge    .Lfill_done
    mov     w11, #100
    udiv    w12, w9, w11
    msub    w12, w12, w11, w9       // w12 = i % 100
    str     w12, [x19, w9, UXTW #2]
    str     w12, [x20, w9, UXTW #2]
    add     w9, w9, #1
    b       .Lfill
.Lfill_done:

    // Zero C
    mov     x0, x21
    mov     x1, #0
    mov     x2, #MATRIX_BYTES
    bl      _memset

    // Print header
    adrp    x0, _fmt_header@PAGE
    add     x0, x0, _fmt_header@PAGEOFF
    bl      _printf

    // ---- Start timing ----
    sub     sp, sp, #32
    mov     x0, #6                   // CLOCK_MONOTONIC
    mov     x1, sp
    bl      _clock_gettime

    // ---- Matrix multiply ----
    mov     x0, x19
    mov     x1, x20
    mov     x2, x21
    bl      _matmul

    // ---- End timing ----
    mov     x0, #6
    add     x1, sp, #16
    bl      _clock_gettime

    // Calculate elapsed ms
    ldr     x22, [sp, #16]           // end.tv_sec
    ldr     x23, [sp, #24]           // end.tv_nsec
    ldr     x24, [sp]                // start.tv_sec
    ldr     x9,  [sp, #8]            // start.tv_nsec

    sub     x22, x22, x24            // delta_sec
    sub     x23, x23, x9             // delta_nsec

    mov     x10, #1000
    mul     x22, x22, x10
    mov     x10, #1000000
    sdiv    x23, x23, x10
    add     x22, x22, x23            // total ms

    add     sp, sp, #32

    // Print result
    ldr     w1, [x21]                // C[0]
    adrp    x0, _fmt_result@PAGE
    add     x0, x0, _fmt_result@PAGEOFF
    bl      _printf

    // Print time
    adrp    x0, _fmt_time@PAGE
    add     x0, x0, _fmt_time@PAGEOFF
    mov     x1, x22
    bl      _printf

    // Print total operations
    // 256^3 * 2 = 33,554,432 ops
    adrp    x0, _fmt_ops@PAGE
    add     x0, x0, _fmt_ops@PAGEOFF
    mov     x1, #33554432
    bl      _printf

    // Free
    mov     x0, x19
    bl      _free
    mov     x0, x20
    bl      _free
    mov     x0, x21
    bl      _free

    mov     x0, #0
    ldp     x23, x24, [sp], #16
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

.section __DATA,__data
_fmt_header:
    .asciz "Matrix Multiplication (256x256) - AArch64 Assembly\n"
_fmt_result:
    .asciz "C[0] = %d\n"
_fmt_time:
    .asciz "Time: %lld ms\n"
_fmt_ops:
    .asciz "Operations: %lld multiply-add\n"

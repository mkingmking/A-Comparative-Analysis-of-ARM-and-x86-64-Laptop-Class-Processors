// matmul_arm_profile.s - Long-running profiling wrapper around the
// unmodified hand-written _matmul from matmul_arm.s.
//
// _matmul below is copied byte-for-byte from matmul_arm.s. Only _main
// differs: A/B are filled once (as in matmul_arm.s), then _matmul(A,B,C) is
// called REPETITIONS times in a loop instead of once, so the process runs
// long enough (~36s at the measured 15ms/run single-shot time) for
// Instruments' CPU Counters template to capture a steady-state PMU sampling
// window. This measures the actual hand-written assembly kernel directly,
// unlike matmul_profile.c / Table tab:uarch, which profile a portable-C
// proxy.
//
// Build: as -o matmul_arm_profile.o matmul_arm_profile.s && ld -o matmul_arm_profile \
//        matmul_arm_profile.o -lSystem -syslibroot "$(xcrun --sdk macosx --show-sdk-path)" -e _main
// Run:   ./matmul_arm_profile   (256x256 matmul x 2400 reps, prints summed checksum)

.global _main
.align 4

.equ N, 256
.equ N_SQUARED, 65536
.equ MATRIX_BYTES, 262144
.equ REPETITIONS, 2400

_matmul:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    stp     x23, x24, [sp, #-16]!
    stp     x25, x26, [sp, #-16]!
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     w22, #N
    mov     w23, #0
.Lloop_i:
    cmp     w23, w22
    b.ge    .Ldone_i
    mov     w24, #0
.Lloop_j:
    cmp     w24, w22
    b.ge    .Ldone_j
    mov     w26, #0
    mov     w25, #0
.Lloop_k:
    cmp     w25, w22
    b.ge    .Ldone_k
    madd    w9, w23, w22, w25
    ldr     w10, [x19, w9, uxtw #2]
    madd    w11, w25, w22, w24
    ldr     w12, [x20, w11, uxtw #2]
    madd    w26, w10, w12, w26
    add     w25, w25, #1
    b       .Lloop_k
.Ldone_k:
    madd    w9, w23, w22, w24
    str     w26, [x21, w9, uxtw #2]
    add     w24, w24, #1
    b       .Lloop_j
.Ldone_j:
    add     w23, w23, #1
    b       .Lloop_i
.Ldone_i:
    ldp     x25, x26, [sp], #16
    ldp     x23, x24, [sp], #16
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

_main:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    stp     x23, x24, [sp, #-16]!
    sub     sp, sp, #16             // Apple arm64 variadic argument area

    adrp    x19, _mat_A@PAGE
    add     x19, x19, _mat_A@PAGEOFF
    adrp    x20, _mat_B@PAGE
    add     x20, x20, _mat_B@PAGEOFF
    adrp    x21, _mat_C@PAGE
    add     x21, x21, _mat_C@PAGEOFF

    // Fill A and B once, exactly as matmul_arm.s does (C is zero BSS).
    mov     w9, #0
    mov     w10, #N_SQUARED
.Lfill:
    cmp     w9, w10
    b.ge    .Lfill_done
    mov     w11, #100
    udiv    w12, w9, w11
    msub    w12, w12, w11, w9
    str     w12, [x19, w9, uxtw #2]
    str     w12, [x20, w9, uxtw #2]
    add     w9, w9, #1
    b       .Lfill
.Lfill_done:

    mov     x23, #0                 // checksum accumulator
    mov     w24, #REPETITIONS       // remaining reps

.Lrep_loop:
    cbz     w24, .Lrep_done
    mov     x0, x19
    mov     x1, x20
    mov     x2, x21
    bl      _matmul
    ldr     w9, [x21]               // C[0]
    add     x23, x23, x9
    sub     w24, w24, #1
    b       .Lrep_loop
.Lrep_done:

    adrp    x0, _fmt_result@PAGE
    add     x0, x0, _fmt_result@PAGEOFF
    str     x23, [sp]
    bl      _printf

    mov     x0, #0
    add     sp, sp, #16
    ldp     x23, x24, [sp], #16
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

.section __DATA,__data
_fmt_result:
    .asciz "matmul checksum over 2400 reps = %lld\n"

.zerofill __DATA,__bss,_mat_A,262144,4
.zerofill __DATA,__bss,_mat_B,262144,4
.zerofill __DATA,__bss,_mat_C,262144,4

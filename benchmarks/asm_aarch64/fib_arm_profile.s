// fib_arm_profile.s - Long-running profiling wrapper around the unmodified
// hand-written _fib from fib_arm.s.
//
// _fib below is copied byte-for-byte from fib_arm.s. Only _main differs: it
// calls _fib(40) REPETITIONS times in a loop instead of once, so the process
// runs long enough (~35s at the measured 346ms/run single-shot time) for
// Instruments' CPU Counters template to capture a steady-state PMU sampling
// window. This measures the actual hand-written assembly kernel directly,
// unlike fib_profile.c / Table tab:uarch, which profile a portable-C proxy.
//
// Build: as -o fib_arm_profile.o fib_arm_profile.s && ld -o fib_arm_profile \
//        fib_arm_profile.o -lSystem -syslibroot "$(xcrun --sdk macosx --show-sdk-path)" -e _main
// Run:   ./fib_arm_profile   (fib(40) x 100 reps, prints the summed checksum)

.global _main
.align 4

.equ N_VAL, 40
.equ REPETITIONS, 100

_fib:
    cmp     w0, #1
    b.le    .Lfib_base

    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    stp     x19, x20, [sp, #-16]!
    mov     w19, w0

    sub     w0, w19, #1
    bl      _fib
    mov     x20, x0
    sub     w0, w19, #2
    bl      _fib
    add     x0, x20, x0

    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

.Lfib_base:
    uxtw    x0, w0
    ret

_main:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    stp     x19, x20, [sp, #-16]!
    sub     sp, sp, #16             // Apple arm64 variadic argument area

    mov     x19, #0                 // checksum accumulator
    mov     w20, #REPETITIONS       // remaining reps

.Lrep_loop:
    cbz     w20, .Lrep_done
    mov     w0, #N_VAL
    bl      _fib
    add     x19, x19, x0
    sub     w20, w20, #1
    b       .Lrep_loop
.Lrep_done:

    adrp    x0, _fmt_result@PAGE
    add     x0, x0, _fmt_result@PAGEOFF
    str     x19, [sp]
    bl      _printf

    mov     x0, #0
    add     sp, sp, #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

.section __DATA,__data
_fmt_result:
    .asciz "fib(40) checksum over 100 reps = %lld\n"

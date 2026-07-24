// fib_arm.s - Recursive Fibonacci, normalized with fib_x86.asm
// Build: as -o fib_arm.o fib_arm.s && ld -o fib_arm fib_arm.o -lSystem \
//        -syslibroot "$(xcrun --sdk macosx --show-sdk-path)" -e _main

.global _main
.align 4

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
    sub     sp, sp, #16
    mov     w0, #40
    bl      _fib
    mov     x19, x0

    adrp    x0, _fmt_result@PAGE
    add     x0, x0, _fmt_result@PAGEOFF
    str     x19, [sp]               // Apple arm64 variadic argument area
    bl      _printf

    mov     x0, #0
    add     sp, sp, #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

.section __DATA,__data
_fmt_result:
    .asciz "fib(40) = %lld\n"

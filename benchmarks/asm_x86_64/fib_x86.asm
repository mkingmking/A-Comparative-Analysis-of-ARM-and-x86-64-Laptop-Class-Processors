; fib_x86.asm - Recursive Fibonacci in x86-64 Assembly
; Target: AMD Ryzen 7 running Linux
;
; Demonstrates: x86-64 calling convention (System V AMD64 ABI),
;               complex instructions (CALL/RET with implicit stack ops),
;               CISC characteristics.
;
; Build (Linux):
;   nasm -f elf64 -o fib_x86.o fib_x86.asm
;   gcc -o fib_x86 fib_x86.o -no-pie -nostartfiles
;   OR link with libc:
;   gcc -o fib_x86 fib_x86.o -no-pie
;
; Run:
;   ./fib_x86            (computes fib(40))
;   perf stat -r 30 ./fib_x86

section .data
    fmt_result: db "fib(40) = %lld", 10, 0
    N_VAL:      equ 40

section .text
global main
extern printf

; -------------------------------------------------------
; fib(n): recursive Fibonacci
;   Input:  edi = n
;   Output: rax = fib(n)
;
; Note how x86-64 CALL implicitly pushes RIP onto stack,
; and RET implicitly pops it — a CISC characteristic that
; ARM's BL/RET with explicit LR register does not share.
; -------------------------------------------------------
fib:
    ; Base case: if n <= 1, return n
    cmp     edi, 1
    jle     .fib_base

    ; Save callee-saved registers
    push    rbx
    push    r12

    mov     ebx, edi                ; ebx = n (preserved across calls)

    ; Compute fib(n-1)
    lea     edi, [ebx - 1]          ; edi = n - 1
    call    fib                     ; rax = fib(n-1)
    mov     r12, rax                ; r12 = fib(n-1) (preserved)

    ; Compute fib(n-2)
    lea     edi, [ebx - 2]          ; edi = n - 2
    call    fib                     ; rax = fib(n-2)

    ; Result = fib(n-1) + fib(n-2)
    add     rax, r12

    ; Restore
    pop     r12
    pop     rbx
    ret

.fib_base:
    ; n <= 1: return n
    movsx   rax, edi                ; sign-extend edi to rax
    ret

; -------------------------------------------------------
; main
; -------------------------------------------------------
main:
    push    rbp
    mov     rbp, rsp

    ; Compute fib(40)
    mov     edi, N_VAL
    call    fib

    ; Print result: printf("fib(40) = %lld\n", rax)
    mov     rsi, rax                ; second arg = result
    lea     rdi, [rel fmt_result]   ; first arg = format string
    xor     eax, eax                ; no float args
    call    printf wrt ..plt

    ; Exit with 0
    xor     eax, eax
    pop     rbp
    ret

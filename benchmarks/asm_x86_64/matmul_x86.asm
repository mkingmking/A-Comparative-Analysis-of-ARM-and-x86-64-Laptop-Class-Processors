; matmul_x86.asm - Matrix Multiplication in x86-64 Assembly
; Target: AMD Ryzen 7 running Linux
;
; Computes C = A × B for 256×256 integer matrices.
; Demonstrates: x86 complex addressing modes, IMUL, memory operands,
;               CISC-style instructions that combine load+compute.
;
; Build (Linux):
;   nasm -f elf64 -o matmul_x86.o matmul_x86.asm
;   gcc -o matmul_x86 matmul_x86.o -no-pie
;
; Run:
;   ./matmul_x86
;   perf stat -e cycles,instructions,cache-misses ./matmul_x86

section .data
    fmt_done:   db "Matrix multiplication complete. C[0] = %d", 10, 0
    N:          equ 256
    N_SQ:       equ 65536           ; 256 * 256
    MAT_BYTES:  equ 262144          ; 256 * 256 * 4

section .bss
    align 16
    mat_A:  resd N_SQ               ; 256 KB
    mat_B:  resd N_SQ
    mat_C:  resd N_SQ

section .text
global main
extern printf

; -------------------------------------------------------
; matmul: triple nested loop
;   Uses static BSS arrays (mat_A, mat_B, mat_C)
;
; Key x86-64 difference from ARM:
;   - Can do memory operands directly in arithmetic: 
;     e.g., imul reg, [memory] (load + multiply in one instruction)
;   - Complex addressing: [base + index*scale + disp]
;   - ARM must always load to register first (load/store architecture)
; -------------------------------------------------------
matmul:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    xor     r12d, r12d              ; r12 = i = 0

.loop_i:
    cmp     r12d, N
    jge     .done_i

    xor     r13d, r13d              ; r13 = j = 0

.loop_j:
    cmp     r13d, N
    jge     .done_j

    xor     r15d, r15d              ; r15 = sum = 0
    xor     r14d, r14d              ; r14 = k = 0

.loop_k:
    cmp     r14d, N
    jge     .done_k

    ; Calculate A[i*N + k]
    mov     eax, r12d
    imul    eax, N                  ; eax = i * N
    add     eax, r14d               ; eax = i * N + k
    ; x86 can use complex addressing: load from [base + index*4]
    lea     rbx, [rel mat_A]
    mov     ecx, [rbx + rax*4]      ; ecx = A[i*N + k]

    ; Calculate B[k*N + j]
    mov     eax, r14d
    imul    eax, N                  ; eax = k * N
    add     eax, r13d               ; eax = k * N + j
    lea     rbx, [rel mat_B]
    ; x86 IMUL can multiply register by memory operand directly
    imul    ecx, [rbx + rax*4]      ; ecx = A[i][k] * B[k][j]

    add     r15d, ecx               ; sum += product

    inc     r14d                    ; k++
    jmp     .loop_k

.done_k:
    ; Store C[i*N + j] = sum
    mov     eax, r12d
    imul    eax, N
    add     eax, r13d
    lea     rbx, [rel mat_C]
    mov     [rbx + rax*4], r15d

    inc     r13d                    ; j++
    jmp     .loop_j

.done_j:
    inc     r12d                    ; i++
    jmp     .loop_i

.done_i:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; -------------------------------------------------------
; main
; -------------------------------------------------------
main:
    push    rbp
    mov     rbp, rsp

    ; Initialize A and B: A[i] = B[i] = i % 100
    lea     rdi, [rel mat_A]
    lea     rsi, [rel mat_B]
    xor     ecx, ecx                ; i = 0

.init_loop:
    cmp     ecx, N_SQ
    jge     .init_done

    mov     eax, ecx
    xor     edx, edx
    mov     ebx, 100
    div     ebx                     ; edx = i % 100

    mov     [rdi + rcx*4], edx      ; A[i] = i % 100
    mov     [rsi + rcx*4], edx      ; B[i] = i % 100

    inc     ecx
    jmp     .init_loop

.init_done:
    ; Zero C
    lea     rdi, [rel mat_C]
    xor     eax, eax
    mov     ecx, N_SQ
    rep stosd                       ; x86-specific: REP STOSD fills memory
                                    ; (no ARM equivalent — ARM uses loop or NEON)

    ; Run matrix multiplication
    call    matmul

    ; Print result
    lea     rdi, [rel fmt_done]
    lea     rax, [rel mat_C]
    mov     esi, [rax]              ; C[0]
    xor     eax, eax
    call    printf wrt ..plt

    xor     eax, eax
    pop     rbp
    ret

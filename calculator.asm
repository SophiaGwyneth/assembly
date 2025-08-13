; calc_fixed_ops.asm
; NASM 32-bit (Linux int 0x80)
; Simple 2-Digit Calculator (0-99), supports + - * / correctly
; Helpers preserve EBX/ESI/EDI so main values are not clobbered.

section .data
    title       db "Simple 2-Digit Calculator", 10, 0
    divider     db "===========================", 10, 0
    prompt1     db "Enter first number (0-99): ", 0
    prompt2     db "Enter second number (0-99): ", 0
    prompt_op   db "Enter operation (+, -, *, /): ", 0
    result_lbl  db "Result: ", 0
    prompt_more db "Press Enter to continue or q+Enter to quit: ", 0
    err_input   db "Invalid input!", 10, 0
    err_divzero db "Error: division by zero!", 10, 0
    newline     db 10, 0

section .bss
    buf1    resb 16
    buf2    resb 16
    opbuf   resb 8
    tmp     resb 8
    outbuf  resb 64

section .text
    global _start

_start:
MAIN_LOOP:
    ; print header
    mov ecx, title
    call print_str
    mov ecx, divider
    call print_str

    ; read first number
    mov ecx, prompt1
    call print_str
    mov ecx, buf1
    mov edx, 15
    call read_line
    mov ecx, buf1
    call parse_two_digits      ; EAX = 0..99 or -1
    cmp eax, -1
    je BAD_INPUT
    mov ebx, eax               ; n1 -> EBX

    ; read second number
    mov ecx, prompt2
    call print_str
    mov ecx, buf2
    mov edx, 15
    call read_line
    mov ecx, buf2
    call parse_two_digits
    cmp eax, -1
    je BAD_INPUT
    mov esi, eax               ; n2 -> ESI

    ; read operator
    mov ecx, prompt_op
    call print_str
    mov ecx, opbuf
    mov edx, 7
    call read_line
    mov al, [opbuf]            ; operator char

    cmp al, '+'
    je OP_ADD
    cmp al, '-'
    je OP_SUB
    cmp al, '*'
    je OP_MUL
    cmp al, '/'
    je OP_DIV
    jmp BAD_INPUT

OP_ADD:
    mov eax, ebx
    add eax, esi
    jmp PRINT_RESULT

OP_SUB:
    mov eax, ebx
    sub eax, esi
    jmp PRINT_RESULT

OP_MUL:
    mov eax, ebx
    imul eax, esi              ; 32-bit signed multiply
    jmp PRINT_RESULT

OP_DIV:
    cmp esi, 0
    je DIV_ZERO
    mov eax, ebx
    cdq                        ; sign-extend EAX into EDX:EAX
    idiv esi                   ; quotient in EAX
    jmp PRINT_RESULT

DIV_ZERO:
    mov ecx, err_divzero
    call print_str
    call WAIT_MORE
    jmp MAIN_LOOP

BAD_INPUT:
    mov ecx, err_input
    call print_str
    call WAIT_MORE
    jmp MAIN_LOOP

PRINT_RESULT:
    ; Convert signed EAX -> NUL string at outbuf (ECX = outbuf)
    mov ecx, outbuf
    call int_to_str

    mov ecx, result_lbl
    call print_str
    mov ecx, outbuf
    call print_str
    mov ecx, newline
    call print_str

    call WAIT_MORE
    jmp MAIN_LOOP

; -----------------------
; Helpers (preserve EBX/ESI/EDI)
; -----------------------

; print_str: ECX -> zero-terminated string to stdout
print_str:
    push ebx
    push esi
    push edi

    mov edi, ecx
    xor edx, edx
.ps_len_loop:
    mov al, [edi+edx]
    cmp al, 0
    je .ps_len_done
    inc edx
    jmp .ps_len_loop
.ps_len_done:
    mov eax, 4
    mov ebx, 1
    mov ecx, edi
    int 0x80

    pop edi
    pop esi
    pop ebx
    ret

; read_line: ECX=buffer, EDX=maxbytes
; returns NUL-terminated buffer (CR or LF -> NUL)
read_line:
    push ebx
    push esi
    push edi

    mov eax, 3
    mov ebx, 0
    int 0x80            ; eax = bytes read
    cmp eax, 0
    jle .rl_no_bytes
    mov esi, eax
    mov edi, ecx
    xor ebx, ebx
.rl_scan:
    cmp ebx, esi
    jge .rl_no_nl
    mov al, [edi+ebx]
    cmp al, 10          ; LF
    je .rl_found_nl
    cmp al, 13          ; CR
    je .rl_found_nl
    inc ebx
    jmp .rl_scan
.rl_found_nl:
    mov byte [edi+ebx], 0
    jmp .rl_done
.rl_no_nl:
    mov byte [edi+esi], 0
    jmp .rl_done
.rl_no_bytes:
    mov byte [ecx], 0
.rl_done:
    pop edi
    pop esi
    pop ebx
    ret

; parse_two_digits: ECX -> buffer (NUL-terminated)
; returns EAX = 0..99 or -1 on error; skips leading spaces/tabs
parse_two_digits:
    push ebx
    push esi

    mov esi, ecx           ; pointer into buffer

    ; skip leading spaces/tabs
.pt_skip:
    mov al, [esi]
    cmp al, ' '
    je .pt_inc
    cmp al, 9
    je .pt_inc
    jmp .pt_start
.pt_inc:
    inc esi
    jmp .pt_skip

.pt_start:
    mov al, [esi]
    cmp al, 0
    je .pt_fail
    cmp al, '0'
    jb .pt_fail
    cmp al, '9'
    ja .pt_fail
    sub al, '0'
    movzx eax, al         ; eax = first digit
    inc esi

    ; second char?
    mov bl, [esi]
    cmp bl, '0'
    jb .pt_single
    cmp bl, '9'
    ja .pt_single
    sub bl, '0'
    imul eax, 10
    add eax, ebx
    jmp .pt_done

.pt_single:
    ; single-digit in eax
.pt_done:
    pop esi
    pop ebx
    ret

.pt_fail:
    pop esi
    pop ebx
    mov eax, -1
    ret

; int_to_str: signed EAX -> NUL string at ECX (outbuf)
int_to_str:
    push ebx
    push ecx
    push edx
    push esi
    push edi

    mov edi, ecx        ; dest
    mov esi, ecx
    add esi, 63         ; work from end
    mov byte [esi], 0
    dec esi

    mov ebx, 0          ; sign flag
    cmp eax, 0
    jge .it_abs_ok
    neg eax
    mov ebx, 1
.it_abs_ok:
.it_conv:
    xor edx, edx
    mov ecx, 10
    div ecx             ; EAX/=10, EDX=remainder
    add dl, '0'
    mov [esi], dl
    dec esi
    test eax, eax
    jnz .it_conv

    cmp ebx, 1
    jne .it_copy
    mov byte [esi], '-'
    dec esi
.it_copy:
    inc esi
.it_copy_loop:
    mov al, [esi]
    mov [edi], al
    inc esi
    inc edi
    cmp al, 0
    jne .it_copy_loop

    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; WAIT_MORE: prompt and read tmp; q/Q quits
WAIT_MORE:
    mov ecx, prompt_more
    call print_str
    mov ecx, tmp
    mov edx, 7
    call read_line
    mov al, [tmp]
    cmp al, 'q'
    je WM_QUIT
    cmp al, 'Q'
    je WM_QUIT
    ret
WM_QUIT:
    mov eax, 1
    xor ebx, ebx
    int 0x80

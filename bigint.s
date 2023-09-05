; We are seeking n>1 that divides 2^n-3
; Equivalently we are seeking n>1 that divides 2^n with a remainder of 3
; Spoiler alert: there aren't many solutions.
; The first solution is very large but is known.
; See https://proofwiki.org/wiki/Smallest_n_for_which_2%5En-3_is_Divisible_by_n
; There are few solutions for remainders of 5 or 7.
; The first solution of 2^n mod n = 7 is n=25
; The first solution of 2^n mod n = 5 is n=19147
; The first solution of 2^n mod n = 3 is rather more than 4G and won't fit into 32 bits
; See ~/c/bigint.c ...
;                       exponent=25 (0x19) result=7
;                       exponent=1727 (0x6bf) result=7
;                       exponent=19147 (0x4acb) result=5
;                       exponent=3830879 (0x3a745f) result=7
;                       exponent=33554425 (0x1fffff9) result=7
;
; Language: x86-64 assembly ... syntax: nasm ... uses 128-bit unsigned integer arithmetic
; Generally, see https://www.cs.uaf.edu/2017/fall/cs301/reference/x86_64.html
; and perhaps https://cs.lmu.edu/~ray/notes/nasmtutorial/
; Short-cut: there is no need to test powers of 2 with even exponents because their remainders will always be even

; Inputs:
;     min: the starting exponent, the lowest that will be tested
;     max: the stopping exponent, the highest that will be tested
;     cutoff: odd remainders lower than this will be reported

; Outputs:
;     Report lines of the format "X: deadbeefdodecade" [printhex] or "X: 9999" [printdec]
;      where X is one of B, S, M, P, E, r, t or z.
;      B: demonstration of DIV instruction using Creel's example - see below
;      m: min, the starting exponent
;      M: max, the stopping exponent
;      P: progress report, handy for restarts
;      E: reporting an exponent value
;      r: remainder for that exponent
;      t: seconds since unix epoch
;      z: at stop, the next exponent that would have been tested

; x86-64 mul instruction:
;   multiplicand is in rax
;   multiplier is in the register named in the instruction
;   product goes into rdx:rax

; x86-64 div instruction: 
;   dividend is in rdx:rax
;   divisor is in the register named in the instruction
;   quotient goes into rax
;   remainder goes into rdx
;   see Creel "Modern x86 Assembler" #11 https://youtube.com/watch?v=vwTYM0oSwjg&t=6m41s

section .data
    min        dq 4000000000                ; only odd values will be tested
    max        dq 5000000000                ; cannot go beyond 18446744073709551615 = 2^64 - 1
    cutoff     dq 8                         ; remainders less than this are reported.
    one        dq 1                         ; constant which is used extensively
    two        dq 2                         ; increment for main loop; we work with odd exponents only
    chkptmask  dq 0x00000001fffffffe        ; mask for periodic progress reports
    hex_chars  db "0123456789ABCDEF"        ; table of printed chars
    reportline db "?: "                     ; start of printed line
    quadstuff  db "deadbeefdodecade"        ; formatted contents of 64-bit register
    nl         db 10                        ;  at least one "\n" to finish printed line
    linelength equ $-reportline             ; how many chars are to be printed in each line
    nlnl       db 10                        ; extra newline ready for double-spacing
; the next field gets written from the right. The contents illustrate the maximum possible.
    decstuff   db "M: 18446744073709551615" ; placeholder for printdec outline
    nl_10      db 10
    nl_nl_10   db 10

section .bss
    exponent   resq 1                   ; steps through odd numbers up to max
    save_rbx   resq 1                   ; offstack save for rbx
    time_struc resb 16                  ; Reserve space for timespec structure (tv_sec, tv_nsec)

; register allocations  ... rcx, rsi, rdi, r8, r9, r10, r11 (and perhaps r12, r13, r14, r15)
; see ~/c/bigint.c
  ; rcx - exponent
  ; rsi - mask
  ; rdi - remainingbits
  ; r8  - sqsq
  ; r9  - result
  ; r10 - two
  ; r11 - cutoff
  ; r12 - max
  ; r13 - n (only needs 1 byte)
  ; r14
  ; r15 - values passed to printhex or printdec

section .text
    global _start

; subroutine printdec .........................................
printdec:     ; formats r15 from right to left into decstuff and prints the whole line.
              ; needs rdx and rax for division. rdx must be zeroed before each division
              ; we need a register with 10 in it to be the divisor
              ; we need a register pointing to decstuff, stepping back from nl_10 - 1.
    mov     rax, r15       ; put value in rax
    xor     rdx, rdx       ; clear rdx ready for 1st division
    mov     r15, 10        ; put 10 in r15
    mov     r14, nl_10     ; point r14 at the end of the printline
printdecloop:
    dec     r14            ; move left 1 position
    div     r15            ; divide by 10.
    add     rdx, '0'       ; char for remainder
    mov     [r14], dl      ; now store dl in the print line
    xor     rdx, rdx       ; clear rdx ready for next division
    test    rax, rax       ; are we finished?
    jnz     printdecloop   ; otherwise loop back


; todo - put 3 chars in front of the number
    lea     ebx, reportline+2
    dec     r14
    mov     dl, [ebx]
    mov     [r14], dl
    dec     ebx
    dec     r14
    mov     dl, [ebx]
    mov     [r14], dl
    dec     ebx
    dec     r14
    mov     dl, [ebx]
    mov     [r14], dl

    mov     eax, 4                         ; sys_write
    mov     ebx, 1                         ; fd for stdout
    mov     rcx, r14                       ; ecx points to start of print
    lea     edx, nl_nl_10                  ; how many chars to print
    sub     edx, ecx
    int     0x80                           ; syscall
    ret                                    ; end of printdec

; subroutine printhex .........................................
printhex:     ; formats r15 into quadstuff and prints the whole line. r15 is destroyed.
             ; r14 and edi are used for scratch
             ; Presumes that first char of reportline has been set to indicate what is being displayed.
    mov     [save_rbx], rbx ; save rbx into save_rbx ??????????????????
    mov     edi, 16   ; counter, decrements from 16 to zero as we work from R to L
.printhexloop:
    ; Extract the lowest 4 bits of the surviving value in r15 and use them as an index to the hex characters
    mov     r14, r15
    and     r14, 0xF                       ; Extract the lowest 4 bits 
    movzx   r14d, byte [hex_chars + r14d]  ; Look up the corresponding hex character
    dec     edi                            ; Move the destination index one step back
    mov     [quadstuff+edi], r14b          ; Store the hex character in the buffer
    shr     r15, 4                         ; Shift r15 to the right by 4 bits
    test    edi, edi
    jnz     .printhexloop                     ; If di is not zero, repeat the loop
                                           ; else print the whole line
    mov     eax, 4                         ; sys_write
    mov     ebx, 1                         ; fd for stdout
    lea     ecx, reportline                ; load effective addr of line
    mov     edx, linelength                ; how many chars to print
    int     0x80                           ; syscall
    lea     r15, [save_rbx]
    mov     rbx, [r15]                     ; restore rbx from save_rbx
    ret                                    ; end of printhex

_start:
    ; example fron Creel video:
    mov     rax, 79871
    mov     rdx, 4     ; make huge dividend 4*2^64 + 79871 = 73786976294838286335
    mov     rcx, 1238  ; divisor
    div     rcx        ; quotient rax is 59601757911824140 (D3BF7BA852B70C), remainder rdx is 1015 (3F7)
    mov     r15, rax   ; value-to-be-displayed is copied to r15, rax will be the quotient
    mov     al, 'B'
    mov     [reportline], al
    call    printdec    ; print 'B' and the quotient

    ;  display the current time
    mov rax, 201               ; syscall number to time
    lea rdi, [time_struc]      ; load address of hi-res time struct
    syscall                    ; will put time into rax and success code into rdx
    mov     r15, rax
    mov     al, 't'
    mov     [reportline], al
    call    printdec            ; print 't' and the time

    ;  display min (the starting exponent) as 'm'
    mov     r15, [min]       ; load min and ...
    or      r15, 0x01        ;  ... we must start from an odd number
    mov     [exponent], r15  ; start exponent = min .or. 1
    mov     al, 'm'
    mov     [reportline], al
    call    printdec          ; print 'S' and the exponent

    ; display max as 'M'
    mov     r15, [max]       ; load max
    mov     al, 'M'
    mov     [reportline], al
    call    printdec          ; print 'M' and the value

    ; load some registers ...
    mov     r11, [cutoff]    ; cutoff lives in r11
    mov     rcx, [min]       ; exponent lives in rcx
    or      rcx, 0x01        ; we must start from an odd number
    mov     r12, [max]
    mov     r10, [two]
; start of bigloop ...
bigloop:
    mov     rdi, rcx   ; remaining bits lives in rdi
    mov     rsi, [one] ; mask lives in rsi and moves leftwards in medium loop
    mov     r8, r10    ; sqsq lives in r8
                       ; sqsq starts at 2 then is squared to 4 then 16 then 256 then 65536 etc. HOWEVER,
                       ; after every squaring it is reduced modulo rcx (the exponent)
    mov     r9, [one]  ; result builds up in r9
mediumloop:
    test    rcx, rsi   ; and(mask, exponent)
    jz      nomult
yesmult:
    mov     rax, r9    ; multiply result
    mul     r8         ; by sqsq
    div     rcx        ; divide by exponent
    mov     r9, rdx    ; and store the remainder in result.
    xor     rdi, rsi   ; mask out mask from remainingbits so we know when we've finished this exponent

; register allocations 
  ; rcx - exponent
  ; rsi - mask
  ; rdi - remainingbits
  ; r8  - sqsq
  ; r9  - result
  ; r10 - two
  ; r11 - cutoff
  ; r12 - max
  ; r13 - n (only needs 1 byte)

nomult:
    test    rdi, rdi   ; test remainingbits
    jz      endmediumloop
    shl     rsi, 1     ; shift mask leftwards one bit
pre:
    mov     rax, r8    ; get sqsq ...
    mul     r8         ;   ... and square it again
    div     rcx        ; and divide it by exponent
    mov     r8, rdx    ; and store the remainder in sqsq
    jmp     mediumloop
endmediumloop:
    cmp     r9, r11    ; compare result with cutoff
    jg      noprint    ; don't print exponents with large result
    mov     rsi, [one] ; mask = 1
    test    r9, rsi
    jpe     noprint    ; don't print unless result is odd

    push rcx           ; save the registers ...
    push rsi           ; save the registers ...
    push rdi           ; save the registers ...
    push r8            ; save the registers ...
    push r9            ; save the registers ...
    push r10           ; save the registers ...
    push r11           ; save the registers ...
    push r12           ; save the registers ...
    push r13           ; save the registers ...

    push r9            ; save the result again ..
    mov     r15, rcx  ; print the exponent
    mov     rdi, reportline
    mov     al, 'E'         ; display 'E' to show it's an exponent
    mov     [reportline], al
    call    printdec

    pop  r9            ; restore the result

    mov     r15,  r9   ; print the result
    mov     rdi, reportline
    mov     al, 'r'         ; display 'r' to show it's the result
    mov     [reportline], al
    call    printdec

    pop  r13           ; restore the registers ...
    pop  r12           ; restore the registers ...
    pop  r11           ; restore the registers ...
    pop  r10           ; restore the registers ...
    pop  r9            ; restore the registers ...
    pop  r8            ; restore the registers ...
    pop  rdi           ; restore the registers ...
    pop  rsi           ; restore the registers ...
    pop  rcx           ; restore the registers ...

noprint:
    mov  r15, [chkptmask]
    test  r15, rcx     ; do we need to print a checkpoint pulse line?
    jnz     nocheckpoint


    push rcx           ; save the registers ...
    push rsi           ; save the registers ...
    push rdi           ; save the registers ...
    push r8            ; save the registers ...
    push r9            ; save the registers ...
    push r10           ; save the registers ...
    push r11           ; save the registers ...
    push r12           ; save the registers ...
    push r13           ; save the registers ...

    mov     r15, rcx  ; print the exponent
    mov     rdi, reportline
    mov     al, 'P'         ; display 'P' to show it's a checkpoint pulse
    mov     [reportline], al
    call    printdec

    ;  display the current time
    mov rax, 201           ; syscall number to time
    lea rdi, [time_struc]  ; load address of hires time struct
    syscall                ; will put time into rax and success code into rdx
    mov     r15, rax
    mov     al, 't'
    mov     [reportline], al
    call    printdec        ; print 't' and the time


    pop  r13           ; restore the registers ...
    pop  r12           ; restore the registers ...
    pop  r11           ; restore the registers ...
    pop  r10           ; restore the registers ...
    pop  r9            ; restore the registers ...
    pop  r8            ; restore the registers ...
    pop  rdi           ; restore the registers ...
    pop  rsi           ; restore the registers ...
    pop  rcx           ; restore the registers ...

nocheckpoint:
    add     rcx, [two] ; increment exponent ready for next trip around the big loop
    cmp     rcx, r12   ; compare exponent with max .. are we finished?
    jle     bigloop      ; loop if not finished ************************** end of bigloop

;;;;;;;;;;;;;;;;;;;;;;; we've finished

    mov     r15, rcx  ; print the next exponent we might have done
    mov     rdi, reportline
    mov     al, 'z'         ; display 'z' to show we're at the end
    mov     [reportline], al
    call    printdec

    ;  display the current time
    mov rax, 201           ; syscall number to time
    lea rdi, [time_struc]  ; load address of hires time struct
    syscall                ; will put time into rax and success code into rdx
    mov     r15, rax
    mov     al, 't'
    mov     [reportline], al
    call    printdec        ; print 't' and the time

    ; Tidy-up the output
    mov     eax, 4           ; syscall number for sys_write
    mov     ebx, 1           ; file descriptor 1 (stdout)
    lea     ecx, [nl]        ; \n
    mov     edx, 1
    int     0x80

    ; Exit the program
quit:
    mov     eax, 1           ; syscall number for sys_exit
    xor     ebx, ebx         ; exit status 0
    int     0x80             ; interrupt to invoke the syscall

abort:    ; debugging - put something in r15 then jump here ...
    mov     rdi, reportline
    mov     al, 'x'         ; display 'x' to show we've aborted
    mov     [reportline], al
    call    printhex
    mov     eax, 1           ; syscall number for sys_exit
    xor     ebx, ebx         ; exit status 0
    int     0x80             ; interrupt to invoke the syscall
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    mov     r15, r9    ; this value will be printed at abort   MMMMMMMMMMMMMMWWWWWWWWWMMMMMMMMMMMMMM
    jmp     abort      ;                                       WWWWWWWWWWWWWWMMMMMMMMMWWWWWWWWWWWWWW

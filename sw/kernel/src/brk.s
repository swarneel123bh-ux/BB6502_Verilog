; Kernel BRK handler
.setcpu "65C02"
.export _brk_handler
.import _syscall_dispatch
.import do_yield
.include "../devices.s"

; Syscall Application Binary Inteface (ABI)
ZP_SYS_NUM_PTR = $30        ; Pointer to (PC+2)-1 so that we can retrieve syscall number from inline
ZP_SYS_NUM     = $32        ; Syscall number to trigger
ZP_SYS_RET     = $33        ; Syscall return value stored here
ZP_CURR_PROC_MMU_PPN0 = $53
ZP_BRK_SP      = $55        ; user SP captured at entry (for yield_rti txs)
ZP_SAVE_PPN1   = $56        ; scratch save of MMU_PPN1 during frame read
ZP_SAVE_PPN7   = $57        ; scratch save of MMU_PPN7 around C dispatch

; yield_rti lives in ROM ($FFF8 vector). We exit through it so the
; page-0 remap + register pulls + rti all run from ROM (which bypasses
; the MMU) instead of from kernel page 0 (which we are about to unmap).
yield_rti = $FFF8

.segment "CODE"
; ================
; brk_handler: distinguishes hardware IRQ from software BRK.
;
; Stack on entry (top down):
;                                       <- sp
;   status register (B set => BRK)      <- sp + 4 (after trampoline's A/X/Y pushes)
;   PCL                                 <- sp + 5
;   PCH                                 <- sp + 6
;
; The running process's stack lives in *its* page 0. The handler lives in
; the *kernel's* page 0. We must NOT remap MMU_PPN0 while executing here,
; or the very next instruction fetch vanishes. So we view the user stack
; through virtual page 1 (MMU_PPN1) for the frame read, keeping PPN0 = kernel.
; ================
_brk_handler:
                tsx
                stx ZP_BRK_SP               ; remember user SP for the exit

                ; Map user's page 0 (its stack) into virtual page 1, read frame.
                lda MMU_PPN1
                sta ZP_SAVE_PPN1
                lda ZP_CURR_PROC_MMU_PPN0
                sta MMU_PPN1               ; vpage1 -> user stack page

                lda $1104,x                ; saved status (vpage1 mirror of $0104,x)
                and #$10                   ; B flag set => software BRK
                bne @brk_path

                ; ---- IRQ PATH ----
                lda ZP_SAVE_PPN1
                sta MMU_PPN1               ; restore vpage1
                jmp irq_path

@brk_path:
                ; ptr to syscall number = (saved PC) - 1, read from vpage1 mirror
                lda $1105,x                ; PCL
                sec
                sbc #1
                sta ZP_SYS_NUM_PTR
                lda $1106,x                ; PCH
                sbc #0
                sta ZP_SYS_NUM_PTR+1

                ; Syscall args are passed in the *user's* zero page ($34-$3f),
                ; but zero page is page-0-private. During dispatch PPN0 = kernel,
                ; so the C handlers would read the kernel's ZP, not the user's.
                ; Copy the user arg block (read via the vpage1=user-page-0 mirror
                ; at $1134-$113f) into the kernel ZP now, before remapping vpage1.
                ldy #$0b                    ; $34..$3f = 12 bytes (ARG0..ARG2 + spare)
@cpargs:
                lda $1034,y                 ; user ZP mirror: $0034+y via vpage1
                sta $34,y                   ; kernel ZP
                dey
                bpl @cpargs

                ; restore vpage1 -> user code page before dereferencing syscall num
                lda ZP_SAVE_PPN1
                sta MMU_PPN1

                ldy #0
                lda (ZP_SYS_NUM_PTR),y     ; syscall number (lives in user code page)
                sta ZP_SYS_NUM

                cmp #0                     ; SYS_YIELD (0)?
                bne @not_do_yield
                jmp do_yield               ; far branch via JMP

@not_do_yield:
                ; The kernel cc65 C-stack lives in virtual page 7 (sp=$7eff).
                ; During a syscall MMU_PPN7 still maps the *user's* page, so any
                ; C code (k_print, locals, args) would read/write garbage.
                ; Map kernel phys page 7 into vpage7 for the duration of the C
                ; call, then restore the user's ppn7 before returning to it.
                lda MMU_PPN7
                sta ZP_SAVE_PPN7
                lda #7
                sta MMU_PPN7

                jsr _syscall_dispatch

                lda ZP_SAVE_PPN7
                sta MMU_PPN7               ; vpage7 -> user page again

                ; Return to user through the ROM stub.
                ldx ZP_BRK_SP              ; X = user SP -> yield_rti does txs
                jmp (yield_rti)

irq_path:       ; NOT YET IMPLEMENTED (routed through ROM exit too)
                ldx ZP_BRK_SP
                jmp (yield_rti)

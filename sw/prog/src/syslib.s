.export _sys_yield
.export _sys_exit
.export _sys_putc
.export _sys_getc
.export _sys_puts
.export _sys_block_read
.export _sys_block_write

; These are STILL in program zp (user mode, not in real hardware zp)
SYS_NUM_PTR   = $30
SYS_NUM				= $32
SYS_RET       = $33
SYS_ARG0_LO   = $34
SYS_ARG0_HI   = $35
SYS_ARG1_LO   = $36
SYS_ARG1_HI   = $37
SYS_ARG2_LO   = $38
SYS_ARG2_HI   = $39
SYS_A_REG     = $40   ; for syscalls returning a byte

.segment "CODE"

; ------------------------------------------------------------
; void sys_exit(uint8_t code)
; ------------------------------------------------------------
_sys_exit:
    sta SYS_A_REG
    pha
    phx
    phy
    brk
    .byte 1
    ; No need to retrieve registers before a hang
@hang:
    jmp @hang

; ------------------------------------------------------------
; void sys_yield(void)
; ------------------------------------------------------------
_sys_yield:
		pha
		phx
		phy
		brk
		.byte 0
		ply
		plx
		pla
		rts
@hang:
		jmp @hang

; ------------------------------------------------------------
; void sys_putc(uint8_t c)
; ------------------------------------------------------------
_sys_putc:
    sta SYS_A_REG
    pha
		phx
		phy
		brk
		.byte 2
		ply
		plx
		pla
    rts

; ------------------------------------------------------------
; uint8_t sys_getc(void)
; ------------------------------------------------------------
_sys_getc:
			pha
			phx
			phy
			brk
    	.byte 3
     	ply
      plx
      pla
    	lda SYS_A_REG
      rts

; ------------------------------------------------------------
; void sys_puts(const char* s)
; cc65 passes pointer in A/X
; ------------------------------------------------------------
_sys_puts:
    sta SYS_ARG0_LO
    stx SYS_ARG0_HI
    pha
    phx
    phy
    brk
    .byte 4
    ply
    plx
    pla
    rts

; ------------------------------------------------------------
; uint8_t sys_block_read(uint16_t lba, uint8_t* buf)
;
; cc65 stack layout on entry:
;   sp+0  return lo
;   sp+1  return hi
;   sp+2  lba lo
;   sp+3  lba hi
;   sp+4  buf lo
;   sp+5  buf hi
; ------------------------------------------------------------
_sys_block_read:
    ; get C stack pointer
    tsx

    ; lba
    lda $0102,x
    sta SYS_ARG0_LO

    lda $0103,x
    sta SYS_ARG0_HI

    ; buf pointer
    lda $0104,x
    sta SYS_ARG1_LO

    lda $0105,x
    sta SYS_ARG1_HI

    pha
    phx
    phy
    brk
    .byte 5
    ply
    plx
    pla

    lda SYS_RET
    ldx #0
    rts


; ------------------------------------------------------------
; uint8_t sys_block_write(uint16_t lba, uint8_t* buf)
; ------------------------------------------------------------
_sys_block_write:
    tsx
    ; lba
    lda $0102,x
    sta SYS_ARG0_LO

    lda $0103,x
    sta SYS_ARG0_HI

    ; buf pointer
    lda $0104,x
    sta SYS_ARG1_LO

    lda $0105,x
    sta SYS_ARG1_HI

    pha
    phx
    phy
    brk
    .byte 6
    ply
    plx
    pla

    lda SYS_RET
    ldx #0
    rts

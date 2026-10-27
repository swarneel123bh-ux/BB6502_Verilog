; ==========================================================================
; syslib.s — user-side syscall stubs (sys_putc, sys_puts, sys_yield, ...)
;
; Syscall ABI (see docs/syscalls.md):
;   arguments in the program's own zero page (the ABI block, see below),
;   then PHA/PHX/PHY, BRK, .byte <syscall number>.
;   The kernel returns to the instruction after the number byte; the
;   stub restores Y/X/A and reads the result from SYS_RET / SYS_A_REG.
; ==========================================================================
.export _sys_yield
.export _sys_exit
.export _sys_putc
.export _sys_getc
.export _sys_puts
.export _sys_block_read
.export _sys_block_write

; These are STILL in program zp (user mode, not in real hardware zp).
; SYS_ABI_BASE / SYS_ABI_SIZE come from common.mk (ca65 -D); the offsets
; must match the OFF_* defines in sw/kernel/src/syscalls.c.
SYS_NUM_PTR   = SYS_ABI_BASE + $00   ; (unused on the user side)
SYS_NUM				= SYS_ABI_BASE + $02   ; (unused on the user side)
SYS_RET       = SYS_ABI_BASE + $03
SYS_ARG0_LO   = SYS_ABI_BASE + $04
SYS_ARG0_HI   = SYS_ABI_BASE + $05
SYS_ARG1_LO   = SYS_ABI_BASE + $06
SYS_ARG1_HI   = SYS_ABI_BASE + $07
SYS_ARG2_LO   = SYS_ABI_BASE + $08
SYS_ARG2_HI   = SYS_ABI_BASE + $09
SYS_A_REG     = SYS_ABI_BASE + $10   ; for syscalls returning a byte

; Build-time checks: every slot inside the block, block inside zero page
.assert SYS_A_REG < SYS_ABI_BASE + SYS_ABI_SIZE, error, "syslib.s: ABI slot outside SYS_ABI_SIZE, grow it in common.mk"
.assert SYS_ABI_BASE + SYS_ABI_SIZE <= $100, error, "syslib.s: syscall ABI block does not fit in zero page"

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

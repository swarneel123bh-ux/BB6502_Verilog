.import _main        ; Tell the assembler 'main' is in another file
.export __STARTUP__ : abs = 1
.include "zeropage.inc"

.segment "STARTUP"
reset:
    sei
    cld
    ldx #$ff
    txs

    ; Initialize cc65 software stack pointer
    ; We'll put it at the top of our 32KB RAM ($7FFF)
    lda #$ff
    sta sp
    lda #$7f
    sta sp+1

    jsr _main   ; Jump to your C main()
    bra *				; Trap if main ever returns

.segment "VECTORS"
		.word 0         ; NMI
		.word reset     ; Reset
		.word 0         ; IRQ

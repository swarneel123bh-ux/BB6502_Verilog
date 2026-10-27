; ==========================================================================
; crt0.s — kernel start-up and BBX header
;
; HDR emits the 6-byte BBX header at $0200 ('BX', load address, entry
; point). The boot ROM jumps to kentry, which resets the hardware stack,
; points the cc65 software stack (zero page `sp`) at $7EFF and calls main.
; ==========================================================================
.setcpu "65C02"
.include "zeropage.inc"

.import _main
.export __STARTUP__ : abs = 1

.segment "HDR"
        .byte $42, $58            ; 'B','X'
        .word $0200               ; load address
        .word kentry              ; entry point (kentry, $0206: first byte after HDR)

.segment "STARTUP"
kentry:
        sei
        ldx #$ff
        txs
        cld
        ; Init cc65 software stack at $7EFF, the top of the kernel's high page
        lda #$ff
        sta sp
        lda #$7e
        sta sp+1
        jsr _main
forever:
        bra forever

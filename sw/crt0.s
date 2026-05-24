.setcpu "65C02"
.include "zeropage.inc"

.import _main
.export __STARTUP__ : abs = 1

.segment "HDR"
        .byte $42, $58            ; 'B','X'
        .word $0200               ; load address
        .word kentry              ; entry point ($0206 presumably)

.segment "STARTUP"
kentry:
        sei
        ldx #$ff
        txs
        cld
        ; Init cc65 software stack to top of usable RAM
        lda #$ff
        sta sp
        lda #$7e
        sta sp+1
        jsr _main
forever:
        bra forever

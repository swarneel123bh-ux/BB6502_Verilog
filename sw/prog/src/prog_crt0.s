.setcpu "65C02"

.import _main
.export __STARTUP__ : abs = 1
.include "zeropage.inc"

.segment "HDR"
        .byte $42, $58              ; 'B','X' magic
        .word $1000                 ; load address
        .word entry                 ; entry point

.segment "CODE"
entry:
        ldx #$ff
        txs                         ; init hw stack
        ; init cc65 software stack at top of program area
        lda #$ff
        sta sp
        lda #$7e
        sta sp+1
        cld
        jsr _main
forever:
        bra forever                 ; trap (no return-to-kernel yet)

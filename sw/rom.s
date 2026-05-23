; echo.s — read a char from ACIA, write it back. Loop forever.
.setcpu "65C02"

ACIA_DATA    = $8000
ACIA_STATUS  = $8001
RX_READY     = $01

GPU_DATA    = $8002
GPU_STATUS  = $8003
GPU_READY   = $01

.segment "CODE"

reset:
        sei
        ldx #$ff
        txs                     ; init stack
        cld                     ; clear decimal mode

        ; print banner
        ldx #0
banner_loop:
        lda banner,x
        beq main
        jsr putc
        inx
        bra banner_loop

main:
        jsr getc
        jsr putc        ; echo to terminal
        jsr gputc       ; and to graphical monitor
        bra main

; ---- getc: block until ACIA has a byte; return it in A ----
getc:
        lda ACIA_STATUS
        and #RX_READY
        beq getc
        lda ACIA_DATA
        rts

; ---- putc: send A to ACIA TX (always ready in sim) ----
putc:
        sta ACIA_DATA
        rts

gputc:
        pha
gputc_wait:
        lda GPU_STATUS
        and #GPU_READY
        beq gputc_wait
        pla
        sta GPU_DATA
        rts


banner: .byte "BB6502 sim ready. type:", $0d, $0a, 0

nmi:
irq:
        rti

.segment "VECTORS"
        .word nmi               ; $FFFA
        .word reset             ; $FFFC
        .word irq               ; $FFFE

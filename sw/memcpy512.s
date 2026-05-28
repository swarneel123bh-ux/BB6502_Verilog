
.importzp ptr1, ptr2   ; Use CC65's built-in zero-page pointers
.import popax         ; CC65 runtime routine to pop Ax from software stack

.export _memcpy512

_memcpy512:
    ; CC65 passes the last argument (src) in registers A (low) and X (high)
    ; First, save 'src' into ptr1
    sta ptr1
    stx ptr1+1

    ; The previous argument (dst) is on top of the CC65 software stack.
    ; Call 'popax' to pull 'dst' into A (low) and X (high).
    jsr popax
    sta ptr2
    stx ptr2+1

    ; Now perform the 512-byte copy (2 pages)
    ldx #2
    ldy #0
@copy_loop:
    lda (ptr1),y
    sta (ptr2),y
    iny
    bne @copy_loop

    inc ptr1+1        ; Move to next page
    inc ptr2+1
    dex
    bne @copy_loop    ; Loop back for the second page

    ; Return safely. The CC65 stack is perfectly cleaned up.
    rts

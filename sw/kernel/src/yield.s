.import _plist
.import _plist_idx
.import _schedule_process
.import yield_rti
.include "../devices.s"

; Process states
PROC_STATE_EXITED   = $00
PROC_STATE_WAITING  = $01
PROC_STATE_RUNNING  = $02


; Struct field offsets (PROCESS padded to 32 bytes)
PROC_OFF_STATE      = 0
PROC_OFF_SP         = 13
PROC_OFF_PPN0       = 14    ; ppn_table[0..7] -> 14..21

; TODO: move all explicit ZP pointers into a shared include
ZP_CURR_PROC_PTR    	= $51
ZP_CURR_PROC_MMU_PPN0 = $53

.segment "CODE"
.export do_yield

; ================================================================
; do_yield
; Entered from brk_handler when syscall number == 0 (SYS_YIELD).
; Saves the running process (plist[plist_idx]), runs the scheduler
; (which updates plist_idx), then restores the newly selected
; process and rti's into it.
;
; Saves ONLY SP and the PPN table. A/X/Y/status were already pushed
; onto the *running* process's stack by brk_handler, so they ride
; along with that process's stack page and are restored by rti once
; we switch SP + PPN back to it on a later dispatch.
; ================================================================
do_yield:
  ; --- &plist[plist_idx] -> ZP_CURR_PROC_PTR (running process) ---
  jsr calc_proc_ptr

  ; mark running process WAITING
  ldy #PROC_OFF_STATE
  lda #PROC_STATE_WAITING
  sta (ZP_CURR_PROC_PTR),y

  ; save current SP at offset 13
  tsx
  txa
  ldy #PROC_OFF_SP
  sta (ZP_CURR_PROC_PTR),y

  ; save PPN table at offsets 14..21
  ldy #PROC_OFF_PPN0
  lda MMU_PPN0
  sta (ZP_CURR_PROC_PTR),y
  iny
  lda MMU_PPN1
  sta (ZP_CURR_PROC_PTR),y
  iny
  lda MMU_PPN2
  sta (ZP_CURR_PROC_PTR),y
  iny
  lda MMU_PPN3
  sta (ZP_CURR_PROC_PTR),y
  iny
  lda MMU_PPN4
  sta (ZP_CURR_PROC_PTR),y
  iny
  lda MMU_PPN5
  sta (ZP_CURR_PROC_PTR),y
  iny
  lda MMU_PPN6
  sta (ZP_CURR_PROC_PTR),y
  iny
  lda MMU_PPN7
  sta (ZP_CURR_PROC_PTR),y

  ; --- pick next process (updates _plist_idx) ---
  jsr _schedule_process

  ; --- &plist[plist_idx] -> ZP_CURR_PROC_PTR (selected process) ---
  jsr calc_proc_ptr	; <- This JSR happens on the last process's stack frame

  ; mark selected process RUNNING
  ldy #PROC_OFF_STATE
  lda #PROC_STATE_RUNNING
  sta (ZP_CURR_PROC_PTR),y

  ; load saved SP into X (do NOT txs yet)
  ldy #PROC_OFF_SP
  lda (ZP_CURR_PROC_PTR),y
  tax

  ; restore PPN table (offsets 14..21)
  ; NOTE: once these execute, the address space is the selected
  ; process's. No stack ops are allowed between here and txs/rti
  ; because SP still points into the OLD process's stack page.
  ; MUST STALL LOADING MMU_PPN0
  ; Instead, we jump to yield_rti to do that for us
  ; This is necessary to stay in kernel's page
  iny
  lda (ZP_CURR_PROC_PTR),y
  sta MMU_PPN1
  iny
  lda (ZP_CURR_PROC_PTR),y
  sta MMU_PPN2
  iny
  lda (ZP_CURR_PROC_PTR),y
  sta MMU_PPN3
  iny
  lda (ZP_CURR_PROC_PTR),y
  sta MMU_PPN4
  iny
  lda (ZP_CURR_PROC_PTR),y
  sta MMU_PPN5
  iny
  lda (ZP_CURR_PROC_PTR),y
  sta MMU_PPN6
  iny
  lda (ZP_CURR_PROC_PTR),y
  sta MMU_PPN7

  jmp yield_rti

  ; switch to selected process's stack LAST, then return into it

; ----------------------------------------------------------------
; calc_proc_ptr: ZP_CURR_PROC_PTR = &_plist + (_plist_idx * 32)
; Clobbers A. plist_idx < 8 so idx*32 < 256 (no high-byte carry
; from the shift; adc #<_plist may still carry, handled below).
; ----------------------------------------------------------------
calc_proc_ptr:
  lda _plist_idx
  asl
  asl
  asl
  asl
  asl                 ; A = plist_idx * 32
  clc
  adc #<_plist
  sta ZP_CURR_PROC_PTR
  lda #>_plist
  adc #0              ; propagate carry from low-byte add
  sta ZP_CURR_PROC_PTR+1
  rts

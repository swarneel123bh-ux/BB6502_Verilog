; ==========================================================================
; yield.s — context switch (SYS_YIELD) and scheduler start
;
; do_yield saves the running process's SP and MMU page table into its
; plist entry, calls schedule_process, restores the next process's SP
; and page table and leaves through ret_user_mode ($FFF8), whose RTI
; pops the status/PC that BRK pushed on that process's own stack.
; sched_start does the restore half for plist[0].
; ==========================================================================
.import _plist
.import _plist_idx
.import _schedule_process

.export save_process
.export restore_process
.export calc_proc_ptr
.export do_preempt

; .import yield_rti
.include "include/devices.s"
.include "include/zp.s"

; Process states
PROC_STATE_EXITED   = $00
PROC_STATE_WAITING  = $01
PROC_STATE_RUNNING  = $02


; Struct field offsets (PROCESS padded to 64 bytes, see include/proc.h)
PROC_OFF_STATE      = 0
PROC_OFF_SP         = 13
PROC_OFF_PPN0       = 14    ; ppn_table[0..31] -> 14..45
PROC_SIZE_SHIFT     = 6     ; sizeof(PROCESS) = 1 << 6 = 64
PROC_OFF_A					= 46
PROC_OFF_X					= 47
PROC_OFF_Y					= 48

; yield_rti address, so that we can simply jump (is in ROM)
yield_rti = $FFF8

; ----------------------------------------------------------------
; SAVE_PPN: copy ppn_table[0..31] of MMU to *ZP_CURR_PROC_PTR.
; A macro, not a subroutine: it runs after TXS has switched SP to the
; next process, and a JSR there would push onto the kernel's physical
; stack page at that process's SP. Clobbers A, X, Y.
; ----------------------------------------------------------------
.macro SAVE_PPN
				.local loop
				ldy #PROC_OFF_PPN0
				ldx #0
loop:
				lda MMU_PPN0,x
				sta (ZP_CURR_PROC_PTR),y
				iny
				inx
				cpx #MMU_NPAGES
				bne loop
.endmacro


; ----------------------------------------------------------------
; RESTORE_PPN: copy ppn_table[0..31] of *ZP_CURR_PROC_PTR into the MMU.
; A macro, not a subroutine: it runs after TXS has switched SP to the
; next process, and a JSR there would push onto the kernel's physical
; stack page at that process's SP. Clobbers A, X, Y.
; ----------------------------------------------------------------
.macro RESTORE_PPN
  .local loop
  ldy #PROC_OFF_PPN0
  ldx #0
loop:
  lda (ZP_CURR_PROC_PTR),y
  sta MMU_PPN0,x
  iny
  inx
  cpx #MMU_NPAGES
  bne loop
.endmacro

.segment "CODE"
.export do_yield


save_process:
				; save A
				lda ZP_IRQ_A
				ldy #PROC_OFF_A
				sta (ZP_CURR_PROC_PTR),y

				; Save X
				lda ZP_IRQ_X
				ldy #PROC_OFF_X
				sta (ZP_CURR_PROC_PTR),y

				; Save Y
				lda ZP_IRQ_Y
				ldy #PROC_OFF_Y
				sta (ZP_CURR_PROC_PTR),y

				tsx	; save current CORRECT SP at offset 13
				inx
				inx
				txa
				ldy #PROC_OFF_SP
				sta (ZP_CURR_PROC_PTR),y

				SAVE_PPN	; Save the process page table

				rts


restore_process:
				ldy #PROC_OFF_SP ; load saved SP into X
				lda (ZP_CURR_PROC_PTR),y
				tax
				txs

				RESTORE_PPN		; restore PPN table (offsets 14..45)

				; Restore A
				ldy #PROC_OFF_A
				lda (ZP_CURR_PROC_PTR),y
				sta ZP_IRQ_A

				; Restore X
				ldy #PROC_OFF_X
				lda (ZP_CURR_PROC_PTR),y
				sta ZP_IRQ_X

				; Restore Y
				ldy #PROC_OFF_Y
				lda (ZP_CURR_PROC_PTR),y
				sta ZP_IRQ_Y

				; Store into registers before exiting
				lda ZP_IRQ_A
				ldx ZP_IRQ_X
				ldy ZP_IRQ_Y

				jmp (RET_USER_MODE)

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

  jsr save_process

  ; --- pick next process (updates _plist_idx) ---
  jsr _schedule_process

  ; --- &plist[plist_idx] -> ZP_CURR_PROC_PTR (selected process) ---
  jsr calc_proc_ptr	; <- This JSR happens on the last process's stack frame

  ; mark selected process RUNNING
  ldy #PROC_OFF_STATE
  lda #PROC_STATE_RUNNING
  sta (ZP_CURR_PROC_PTR),y

  jmp restore_process


do_preempt:
				; --- &plist[plist_idx] -> ZP_CURR_PROC_PTR (running process) ---
				jsr calc_proc_ptr

				; mark running process WAITING
				ldy #PROC_OFF_STATE
				lda #PROC_STATE_WAITING
				sta (ZP_CURR_PROC_PTR),y

				jsr save_process	; Save SP and Page table
				jsr _schedule_process ; pick next process (updates _plist_idx)

				jsr calc_proc_ptr	; &plist[plist_idx] -> ZP_CURR_PROC_PTR (selected process)
													; This JSR happens on the last process's stack frame

				; mark selected process RUNNING
				ldy #PROC_OFF_STATE
				lda #PROC_STATE_RUNNING
				sta (ZP_CURR_PROC_PTR),y

				jmp restore_process




; ----------------------------------------------------------------
; calc_proc_ptr: ZP_CURR_PROC_PTR = &_plist + (_plist_idx * 64)
; Clobbers A. plist_idx < 4 so idx*64 < 256 (no high-byte carry
; from the shift; adc #<_plist may still carry, handled below).
; ----------------------------------------------------------------
calc_proc_ptr:
  lda _plist_idx
  .repeat PROC_SIZE_SHIFT
  asl
  .endrepeat          ; A = plist_idx * 64
  clc
  adc #<_plist
  sta ZP_CURR_PROC_PTR
  lda #>_plist
  adc #0              ; propagate carry from low-byte add
  sta ZP_CURR_PROC_PTR+1
  rts

; Starts proc0 for test
; Later will start the main shell
.export _sched_start
_sched_start:
  stz _plist_idx
  ; let user reach all 32 virtual pages (4 permission bytes each)
  lda #$ff
  ldx #3
@open_all:
  sta MMU_UBITS,x
  sta MMU_WBITS,x
  dex
  bpl @open_all

  jsr calc_proc_ptr       ; ZP_CURR_PROC_PTR = &plist[0]

  ldy #PROC_OFF_STATE
  lda #PROC_STATE_RUNNING
  sta (ZP_CURR_PROC_PTR),y
  ldy #PROC_OFF_SP
  lda (ZP_CURR_PROC_PTR),y
  tax
  txs

  ; Load the mmu ppns
  RESTORE_PPN
  jmp (RET_USER_MODE)

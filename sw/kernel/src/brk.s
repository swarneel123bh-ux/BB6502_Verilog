; ==========================================================================
; brk.s — BRK (syscall) / IRQ entry point, installed at $FE/$FF by main
; ==========================================================================
; Kernel BRK handler
.setcpu "65C02"
.export _brk_handler
.import _syscall_dispatch
.import do_yield
.import save_process
.import restore_process
.import do_preempt
.import calc_proc_ptr
.include "include/devices.s"
.include "include/zp.s"

.segment "CODE"

; ================
; brk_handler is the same as our generic interrupt handler but can distinguish
; hardware interrupts fro software interrupts
;
; brk_handler: brk is an interrupt(irq) => cpu fetches the vector at $FFFE, which
; points at brk_trampoline in the boot ROM => JMP ($00FE) => here
;
; Stack on entry (top down):
; 																														<- sp
; 	status register (with B flag set indicating BRK, not IRQ) <- sp + 1
;   PCL  (low byte of PC+2 after BRK instruction)							<- sp + 2
;   PCH  (high byte of PC+2 after BRK instruction) 						<- sp + 3
;
; 6502 BRK instruction is 2 bytes only (not 3)
; so PC 			-> BRK
; 	 PC + 1   -> SYSCALL NUMBER
; 	 PC + 2		-> NEXT INSTRUCTION
;
; NOTE : These things are pushed to the USER stac and we cannot use the stack to preserve
; A, X ad Y registers anymore due to a stack split which may cause us to overwrite kernel stack area
; Thus, the syscall ITSELF must push it to its own stack before brk, then pull it before rts
;
; Thus stack looks like : -
;																<- sp
; 	Status	<- rti pulls from 	<- (sp + 1)
; 	PCL													<- (sp + 2)
; 	PCH <- to here							<- (sp + 3)
; 	Y		<- syscaller pulls this
; 	X
; 	A
;
; Meaning the programmer must define the syscall number after the brk instruction
; (just like puts_inline)
;
; 		brk
; 		.byte SYSCALL_NUMBER
; 		; <exec resumes from here>
; ================
_brk_handler:
				sta ZP_IRQ_A				; Push A,X and Y to kernel stack because we cannot lose these
				stx ZP_IRQ_X				; registers while calculating the stack address
				sty ZP_IRQ_Y

				tsx									; X = SP: BRK's frame is at user $0100+SP+1..3. We are in kernel
														; mode now (no translation), so reach it through the user's page

				lda MMU_PPN0				; Load the page number to get stack access
				asl
				asl									; Shift left into the a14 to a10 range (1 KB pages)
				ora #$01						; Get the stack ($0100 is in virtual page 0)
				sta ZP_MEM_PTR+1		; Store in high byte
				stx ZP_MEM_PTR			; Store stack pointer data in low byte to get full indirect addr
				ldy #1
				lda (ZP_MEM_PTR),y	; saved status register (MMU_PPN0 << 10 | $01(sp))
				and #$10						; Get the B flag of the status register (if set then brk)
				bne @brk_path
				jmp irq_path				; B clear: a hardware IRQ, not BRK

@brk_path:
				; ---- BRK PATH ----
				; Saved PCL is at $0100+sp+2, PCH at $0100+sp+3 (BRK pushed PC+2)
				; Restore
				iny
				lda (ZP_MEM_PTR),y						; Load PCL (Still in process stack)
				sec														; Set carry
				sbc #1												; PC+2 - 1 = address of the syscall-number byte
				sta ZP_SYS_NUM_PTR		; Store the syscall_number_pointer's low byte

				iny
				lda (ZP_MEM_PTR),y						; Load PCH
				sbc #0												; Subtract 0 (if borrow was used)
				sta ZP_SYS_NUM_PTR+1					; Store the syscall_number_pointer's high byte

				; ---- translate that USER VA to a physical address ----
				; The inline byte is in the user's CODE page, not the stack page, so
				; select the PPN by the pointer's OWN virtual page (VA[14:10]).
				lda ZP_SYS_NUM_PTR+1
				lsr
				lsr
				and #$1f                    ; X = vpage of the syscall-number pointer
				tax
				lda ZP_SYS_NUM_PTR+1
				and #$03                    ; keep VA[9:8] (offset bits within the page)
				sta ZP_SYS_NUM_PTR+1
				lda MMU_PPN0,x              ; $8080,x : physical page mapped to that vpage
				asl
				asl
				ora ZP_SYS_NUM_PTR+1
				sta ZP_SYS_NUM_PTR+1        ; high byte now physical; low byte untouched

				; Now we have realptr to syscall number, derefernce it
				ldy #0
				lda (ZP_SYS_NUM_PTR),y 	; Read the syscall number through ZP_SYS_NUM_PTR
				sta ZP_SYS_NUM					; now ZP_SYS_NUM has signature syscall number

				; Check if this was a yield syscall (SYS_YIELD (0))
				cmp #0
				bne @not_do_yield
				jmp do_yield					; BRANCH WITHOUT RTS using JMP because DO_YIELD IS FAR AWAY
@not_do_yield:
				jsr _syscall_dispatch	; Handle syscall
				jmp (RET_USER_MODE)						; back to the process (ret_user_mode, $FFF8)




				; ---- IRQ PATH -----
irq_path:
				sei
				jsr calc_proc_ptr
				jsr save_process

				; Find out what device caused the irq (right now only a timer can cause one
				lda TIMER_ST        ; one read: snapshot the flags
    		and #$0F            ; drop ST[4] (BUSY), keep the four channel flags
    		tay 								; keep a copy for the acknowledge write

    		lsr                 ; bit 0 -> carry
    		bcc @not_timer0
    		jmp handle_timer0
@not_timer0:
    		lsr                 ; bit 1 -> carry
    		bcc @not_timer1
      	jmp handle_timer1
@not_timer1:
      	lsr                 ; bit 2 -> carry
      	bcc @not_timer2
      	jmp handle_timer2
@not_timer2:
      	lsr                 ; bit 3 -> carry
      	bcc @not_timer3
      	jmp handle_timer3
@not_timer3:										; The int was not due to a timer, nothing else is there, so just return
				jmp restore_process


; --------- IRQ HANDLERS ------------

; Handle the correct timer's interrpt
; Later, we jump to a subroutine the kernel registers
handle_timer0:
				pha
				lda #$01									; Writing status register with the correct bit set should clear the int
				sta TIMER_ST
				inc ZP_TIMER_INT_COUNT0
				pla
				jmp do_preempt						; This is the timer-preemption subroutine

handle_timer1:
				pha
				lda #$02									; Writing status register with the correct bit set should clear the int
				sta TIMER_ST
				inc ZP_TIMER_INT_COUNT1
				pla
				jmp restore_process

handle_timer2:
				pha
				lda #$04									; Writing status register with the correct bit set should clear the int
				sta TIMER_ST
				inc ZP_TIMER_INT_COUNT2
				pla
				jmp restore_process

handle_timer3:
				pha
				lda #$08									; Writing status register with the correct bit set should clear the int
				sta TIMER_ST
				inc ZP_TIMER_INT_COUNT3
				pla
				jmp restore_process

; Kernel BRK handler
.setcpu "65C02"
.export _brk_handler
.import _syscall_dispatch
.import do_yield
.include "../devices.s"

; Syscall Application Binary Inteface (ABI)
ZP_SYS_NUM_PTR = 	$30				; Pointer to (PC+2)-1 so that we can retrieve syscall number from inline
ZP_SYS_NUM = 			$32				; Syscall number to trigger
ZP_SYS_RET = 			$33				; Syscall return value stored here
ZP_CURR_PROC_MMU_PPN0 = $53

.segment "CODE"
; ================
; brk_handler is the same as our generic interrupt handler but can distinguish
; hardware interrupts fro software interrupts
;
; brk_handler: brk is an interrupt(irq) => cpu jumps to $FFFE => $FFFE has a jump instr
; to addres at ($00FE) [instr JMP ($00FE)]
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
; Meaning the programmer must define the syscall number after the brk instruction
; (just like puts_inline)
;
; 		brk
; 		.byte SYSCALL_NUMBER
; 		; <exec resumes from here>
; ================
_brk_handler:
				tsx

				lda ZP_CURR_PROC_MMU_PPN0		; Load the page number to get stack access
				sta MMU_PPN0

				lda $0104,x				; (saved status register will be at $0100(hardware stack) + sp)
				and #$10					; Get the B flag of the status register (if set then brk)
				bne @brk_path

				lda #0
				sta MMU_PPN0
				jmp irq_path			; Interrupt was a software one, treat as irq

@brk_path:
				; ---- BRK PATH ----
				; Saved PCH/PCL is at ($0100 + sp + (3 / 2))
				; Restore
				lda $0105,x						; Load PCL (Still in process stack)
				sec										; Set carry
				sbc #1								; Subtract with carry to get previous byte
				tay

				lda #0
				sta MMU_PPN0
				sty ZP_SYS_NUM_PTR		; Store the syscall_number_pointer's low byte

				lda ZP_CURR_PROC_MMU_PPN0	; Padding necessary to retrive from program stack
				sta MMU_PPN0
				lda $0106,x						; Load PCH
				sbc #0								; Subtract 0 (if borrow was used)
				tay
				lda #0
				sta MMU_PPN0
				sty ZP_SYS_NUM_PTR+1	; Store the syscall_number_pointer's high byte
				; Now we have ptr to syscall number, derefernce it

				ldy #0
				lda (ZP_SYS_NUM_PTR),y 	; Read syscall signature from ZP_SYS_NUM
				sta ZP_SYS_NUM					; now ZP_SYS_NUM has signature syscall number

				; Check if this was a yield syscall (SYS_YIELD (0))
				cmp #0
				bne @not_do_yield
				jmp do_yield			; BRANCH WITHOUT RTS using JMP because DO_YIELD IS FAR AWAY
@not_do_yield:
				jsr _syscall_dispatch	; Handle syscall

				; Need to reload ppn0 before we can pull from stack
				; the regsters that the brk_trampoline pushed
				lda ZP_CURR_PROC_MMU_PPN0
				sta MMU_PPN0

				; restore user mode before returning from interrupt
				lda #0
				sta MMU_CTRL
				pla
				tay
				pla
				tax
				pla
				rti

				; ---- IRQ PATH -----
irq_path:	; NOT YET IMPLEMENTED
				; Need to re-set ppn0 before we can pull from process stack
				lda ZP_CURR_PROC_MMU_PPN0
				sta MMU_PPN0
				lda #0
				sta MMU_CTRL
				ply
				plx
				pla
				rti

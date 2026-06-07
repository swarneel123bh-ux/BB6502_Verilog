; Kernel BRK handler
.setcpu "65C02"
.export _brk_handler
.import _syscall_dispatch
.import do_yield
.include "include/devices.s"
.include "include/zp.s"

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

				tsx									; Note, stack pointer doesnt matter because we are in kernel stack now

				lda MMU_PPN0				; Load the page number to get stack access
				asl
				asl
				asl
				asl									; Shift left to move into the a14 to a12 range
				ora #$01						; Get the stack
				sta ZP_MEM_PTR+1		; Store in high byte
				stx ZP_MEM_PTR			; Store stack pointer data in low byte to get full indirect addr
				ldy #1
				lda (ZP_MEM_PTR),y	; saved status register (MMU_PPN0 << 12 | $01(sp))
				and #$10						; Get the B flag of the status register (if set then brk)
				bne @brk_path
				jmp irq_path				; Interrupt was a software one, treat as irq

@brk_path:
				; ---- BRK PATH ----
				; Saved PCH/PCL is at ($0100 + sp + (3 / 2))
				; Restore
				iny
				lda (ZP_MEM_PTR),y						; Load PCL (Still in process stack)
				sec														; Set carry
				sbc #1												; Subtract with carry to get previous byte
				sta ZP_SYS_NUM_PTR		; Store the syscall_number_pointer's low byte

				iny
				lda (ZP_MEM_PTR),y						; Load PCH
				sbc #0												; Subtract 0 (if borrow was used)
				sta ZP_SYS_NUM_PTR+1					; Store the syscall_number_pointer's high byte

				; ---- translate that USER VA to a physical address ----
				; The inline byte is in the user's CODE page, not the stack page, so
				; select the PPN by the pointer's OWN virtual page (VA[14:12]).
				lda ZP_SYS_NUM_PTR+1
				lsr
				lsr
				lsr
				lsr
				and #$07                    ; X = vpage of the syscall-number pointer
				tax
				lda ZP_SYS_NUM_PTR+1
				and #$0f                    ; keep VA[11:8] (offset bits within the page)
				sta ZP_SYS_NUM_PTR+1
				lda MMU_PPN0,x              ; $80F0,x : physical page mapped to that vpage
				asl
				asl
				asl
				asl
				ora ZP_SYS_NUM_PTR+1
				sta ZP_SYS_NUM_PTR+1        ; high byte now physical; low byte untouched

				; Now we have realptr to syscall number, derefernce it
				ldy #0
				lda (ZP_SYS_NUM_PTR),y 	; Read syscall signature from ZP_SYS_NUM
				sta ZP_SYS_NUM					; now ZP_SYS_NUM has signature syscall number

				; Check if this was a yield syscall (SYS_YIELD (0))
				cmp #0
				bne @not_do_yield
				jmp do_yield					; BRANCH WITHOUT RTS using JMP because DO_YIELD IS FAR AWAY
@not_do_yield:
				jsr _syscall_dispatch	; Handle syscall
				jmp (RET_USER_MODE)						; return code here

				; ---- IRQ PATH -----
irq_path:
				jmp (RET_USER_MODE)						; ret_user_mode code here

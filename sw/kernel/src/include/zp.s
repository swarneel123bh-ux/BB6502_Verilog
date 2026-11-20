; ==========================================================================
; zp.s — zero-page locations shared by the kernel's assembly files
; ==========================================================================
; Kernel-side syscall scratch, in the KERNEL's zero page (physical page 0).
; Not the same as the process ABI block (SYS_ABI_BASE in common.mk), which
; lives in each process's own zero page.
ZP_SYS_NUM_PTR 				=	$30				; Pointer to (PC+2)-1 so that we can retrieve syscall number from inline
ZP_SYS_NUM 						=	$32				; Syscall number to trigger
ZP_SYS_RET 						=	$33				; Syscall return value stored here (currently unused)

ZP_IRQ_A							= $40				; Save-point for A when IRQ happens
ZP_IRQ_X							= $41				; Save-point for A when IRQ happens
ZP_IRQ_Y							= $42				; Save-point for A when IRQ happens

; Process control zero page vars
ZP_CURR_PROC_PTR    	= $51				; Points to the current running proces struct
ZP_MEM_PTR						= $54


ZP_TIMER_INT_COUNT0	 	= $60				; How many interrupts have happend, i dont think its necessary to track this
ZP_TIMER_INT_COUNT1	 	= $62				; but i need to test the timers out too so im using this temporarily
ZP_TIMER_INT_COUNT2	 	= $64				; later on, the kernel defines how to handle, and brk.s simply points to that
ZP_TIMER_INT_COUNT3	 	= $67				; subroutine

RET_USER_MODE					= $FFF8

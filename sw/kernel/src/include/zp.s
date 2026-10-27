; ==========================================================================
; zp.s — zero-page locations shared by the kernel's assembly files
; ==========================================================================
; Kernel-side syscall scratch, in the KERNEL's zero page (physical page 0).
; Not the same as the process ABI block (SYS_ABI_BASE in common.mk), which
; lives in each process's own zero page.
ZP_SYS_NUM_PTR 				=	$30				; Pointer to (PC+2)-1 so that we can retrieve syscall number from inline
ZP_SYS_NUM 						=	$32				; Syscall number to trigger
ZP_SYS_RET 						=	$33				; Syscall return value stored here (currently unused)

; Process control zero page vars
ZP_CURR_PROC_PTR    	= $51				; Points to the current running proces struct
ZP_MEM_PTR						= $54

RET_USER_MODE					= $FFF8

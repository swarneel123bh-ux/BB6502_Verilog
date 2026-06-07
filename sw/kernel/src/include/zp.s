; Syscall Application Binary Inteface (ABI)
ZP_SYS_NUM_PTR 				=	$30				; Pointer to (PC+2)-1 so that we can retrieve syscall number from inline
ZP_SYS_NUM 						=	$32				; Syscall number to trigger
ZP_SYS_RET 						=	$33				; Syscall return value stored here

; Process control zero page vars
ZP_CURR_PROC_PTR    	= $51				; Points to the current running proces struct
ZP_MEM_PTR						= $54

RET_USER_MODE					= $FFF8

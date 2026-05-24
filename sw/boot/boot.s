.setcpu "65C02"

; ---- Required Hardware Addresses ----
; ACIA (UART)
ACIA_DATA    	= $8000
ACIA_STATUS  	= $8001
; GPU (COPROCESSOR)
GPU_DATA			= $8002
GPU_STATUS		= $8003
; DISK (SDCARD MODULE)
DISK_LBA0    	= $80E0
DISK_LBA1    	= $80E1
DISK_LBA2    	= $80E2
DISK_LBA3    	= $80E3
DISK_CMD     	= $80E4
DISK_STATUS  	= $80E5
DISK_DATA    	= $80E6
DISK_DPTR    	= $80E7

; ------ Commands ------
CMD_READ 		= $01
STATUS_BUSY 	= $01


; ZERO PAGE WORKSPACE
; BOOTLOADER ALLOWED FREE ACCESS OF HIGH SPEED ZERO PAGE
; KERNEL WILL RE-INIT ZERO PAGE LATER
ZP_PTR 				= $00			; 2 bytes
ZP_COUNT 			= $02			; 2 bytes
ZP_LBA 				= $04			; 4 bytes

BOOT_REC_LBA 	= 100			; BOOT RECORD MUST BE AT LBA100 ON THE DISK
STAGE_ADDR		= $0200		; KERNEL MUST BE LOADED AT THIS ADDRESS

.segment "VECTORS"
				.word nmi_handler		; $FFFA
				.word reset					; $FFFC
				.word irq_handler		; $FFFE

.segment "CODE"
nmi_handler:
irq_handler:
				rti

reset:
				sei
				cld
				ldx #$ff
				txs

				jsr puts_inline
				.byte "BB6502 boot ROM", $0d, $0a, 0

				; Read boot record
				lda #<BOOT_REC_LBA
				sta DISK_LBA0
				lda #>BOOT_REC_LBA
				sta DISK_LBA1
				stz DISK_LBA2
				stz DISK_LBA3
				jsr disk_read_to_stage	; Reads into STAGE_ADDR

				; Validate Boot Record Header
				lda STAGE_ADDR+0
				cmp #66								; B
				beq :+
				jmp bad_boot_record
:
				lda STAGE_ADDR+1
				cmp #66								; B
				beq :+
				jmp bad_boot_record
:
				lda STAGE_ADDR+2
				cmp #66								; B
				beq :+
				jmp bad_boot_record
:
				lda STAGE_ADDR+3
				cmp #82								; R
				beq :+
				jmp bad_boot_record
:

				; Load kernel_lba into ZP_LBA
				lda STAGE_ADDR+4
				sta ZP_LBA+0
				lda STAGE_ADDR+5
				sta ZP_LBA+1
				lda STAGE_ADDR+6
				sta ZP_LBA+2
				lda STAGE_ADDR+7
				sta ZP_LBA+3

				; Load number of sectors into ZP_COUNT
				lda STAGE_ADDR+8
				sta ZP_COUNT+0
				lda STAGE_ADDR+9
				sta ZP_COUNT+1

				jsr puts_inline
				.byte "Loading kernel", $0d, $0a, 0

				; Set ZP_PTR to STAGE_ADDR
				lda #<STAGE_ADDR
				sta ZP_PTR
				lda #>STAGE_ADDR
				sta ZP_PTR+1


@load_loop:
				; Check count for 0
				lda ZP_COUNT+0
				ora ZP_COUNT+1
				beq load_done

				; Set disk lba from ZP_LBA
				lda ZP_LBA+0
				sta DISK_LBA0
				lda ZP_LBA+1
				sta DISK_LBA1
				lda ZP_LBA+2
				sta DISK_LBA2
				lda ZP_LBA+3
				sta DISK_LBA3
				jsr disk_read_to_ptr ; Load wherever ZP_PTR points to

				; Advance ZP_PTR by 1 sector size (512 bytes)
				clc
				lda ZP_PTR+1
				adc #2				; Adding 2 to high byte = +512
				sta ZP_PTR+1

				; Advance ZP_LBA by 1 (propagate carry)
				inc ZP_LBA+0
				bne @zp_lba_inc_done
				inc ZP_LBA+1
				bne @zp_lba_inc_done
				inc ZP_LBA+2
				bne @zp_lba_inc_done
				inc ZP_LBA+3
@zp_lba_inc_done:

				; Decrement ZP_COUNT
				lda ZP_COUNT+0
				bne @zp_count_dec_low_byte_only
				dec ZP_COUNT+1
@zp_count_dec_low_byte_only:
				dec ZP_COUNT+0

				; Load next
				bra @load_loop

load_done:
				; Parese BBX header at STAGE_ADDR
				lda STAGE_ADDR+0
				cmp #$42						; B
				beq :+
				bne bad_bbx
:

				lda STAGE_ADDR+1
				cmp #$58						; X
				beq :+
				jmp bad_bbx
:

				jsr puts_inline
				.byte "Jumping to Kernel", $0d, $0a, 0

				; Entry point is at STAGE_ADDR+5/STAGE_ADDR+4 (litte endian)
				lda STAGE_ADDR+4
				sta ZP_PTR
				lda STAGE_ADDR+5
				sta ZP_PTR+1
				jmp (ZP_PTR)	; Indirect jump to kernel entry point by dereferenceing ZP_PTR as an address

bad_bbx:
				jsr puts_inline
				.byte "[ERROR] BAD BBX HEADER (HALTING)", $0d, $0a, 0
				jmp halt

bad_boot_record:
				jsr puts_inline
				.byte "[ERROR] BAD BOOT RECORD (HALTING)", $0d, $0a, 0
				jmp halt

; ============================================================
;  disk_read_to_stage: read sector at current LBA registers
;  to STAGE_ADDR (512 bytes).
; ============================================================
disk_read_to_stage:
				lda #<STAGE_ADDR
				sta ZP_PTR+0
				lda #>STAGE_ADDR
				sta ZP_PTR+1
				; Fall thrhough since all disk reads
				; need ZP_PTR anyways
disk_read_to_ptr:
				lda #CMD_READ
				sta DISK_CMD

@disk_busy_wait:
				lda DISK_STATUS
				and #STATUS_BUSY
				bne @disk_busy_wait
				; TODO: CHECK FOR ERRORS ON STATUS SINCE
				; REAL SD CARD HARDWARE MAY ERROR OUT
				stz DISK_DPTR
				ldy #0
				ldx #2
				; Outer count: 2 pages of 256 bytes since disk has 512 bytes per sector
@pg_loop:
				; NOTE: The verilog model of the disk controller
				; has a buffer. In real hardware, we have to
				; bit bang SPI to get each byte, so this code needs to change
				lda DISK_DATA
				sta (ZP_PTR),y
				iny
				bne @pg_loop
				; Next page
				inc ZP_PTR+1
				dex
				bne @pg_loop	; More pages remain so more bytes remain
				; Restore ZP_PTR as we incremented it twice if we reach here
				dec ZP_PTR+1
				dec ZP_PTR+1
				rts


; ============================================================
;  puts_inline: prints null-terminated string that follows the
;  JSR, then returns to the byte after the null.
; ============================================================
puts_inline:
				pla
				sta ZP_PTR+0
				pla
				sta ZP_PTR+1
				ldy #1
@loop:
				lda (ZP_PTR),y
				beq @done
				pha
@acia_wait:
				lda ACIA_STATUS
				and #$01
				beq @acia_wait
				pla
				sta ACIA_DATA
				pha
@gpu_wait:
				lda GPU_STATUS
				and #$01
				beq @gpu_wait
				pla
				sta GPU_DATA
				iny
				bne @loop
				inc ZP_PTR+1			; Increment high byte in case string longer than 256 bytes
				bra @loop
@done:
				; Push return address correectly
				; (ZP_PTR + Y)
				clc
				tya
				adc ZP_PTR+0
				tax						; Save low
				lda ZP_PTR+1
				adc #0				; Add the carry if generated
				pha						; Restore return address to stack
				txa
				pha
				rts


halt:
				bra halt

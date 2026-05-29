; ---- Required Hardware Addresses ----

; ACIA (UART) - 6850 Style
ACIA_DATA       = $8000
ACIA_STATUS     = $8001

; GPU (COPROCESSOR)
GPU_DATA        = $8002
GPU_STATUS      = $8003

; DISK (SDCARD MODULE)
DISK_LBA0       = $80E0
DISK_LBA1       = $80E1
DISK_LBA2       = $80E2
DISK_LBA3       = $80E3
DISK_CMD        = $80E4
DISK_STATUS     = $80E5
DISK_DATA       = $80E6
DISK_DPTR       = $80E7

; MMU REGISTERS ($80F0 - $80FF)
; PPN Entries (Virtual Pages 0-7)
MMU_PPN0        = $80F0
MMU_PPN1        = $80F1
MMU_PPN2        = $80F2
MMU_PPN3        = $80F3
MMU_PPN4        = $80F4
MMU_PPN5        = $80F5
MMU_PPN6        = $80F6
MMU_PPN7        = $80F7

; Control & Permissions
MMU_WBITS       = $80F8  ; Write permissions per page
MMU_UBITS       = $80F9  ; User-access permissions per page
MMU_CTRL        = $80FA  ; LSB = 1 (Kernel), 0 (User)

; Export for use in other files
.export ACIA_DATA, ACIA_STATUS, GPU_DATA, GPU_STATUS
.export DISK_LBA0, DISK_LBA1, DISK_LBA2, DISK_LBA3, DISK_CMD, DISK_STATUS, DISK_DATA, DISK_DPTR
.export MMU_PPN0, MMU_PPN1, MMU_PPN2, MMU_PPN3, MMU_PPN4, MMU_PPN5, MMU_PPN6, MMU_PPN7
.export MMU_WBITS, MMU_UBITS, MMU_CTRL

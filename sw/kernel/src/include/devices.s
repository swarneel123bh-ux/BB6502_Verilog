; ==========================================================================
; devices.s — I/O register addresses (assembly side)
;
; There are three identical copies of this file: sw/boot/devices.s,
; sw/kernel/devices.s and sw/kernel/src/include/devices.s. Keep them in
; sync (the C side is sw/kernel/src/include/devices.h). The decode itself
; lives in rtl/tb.v; see docs/hardware.md for what each register does.
; ==========================================================================
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

; MMU REGISTERS ($8080 - $80BF), 1 KB pages: VPN = VA[14:10]
; Page table: one entry per virtual page, MMU_PPN0+n = ppn[n] (n = 0..31)
MMU_PPN0        = $8080
MMU_NPAGES      = 32
MMU_PAGE_SHIFT  = 10     ; page size = 1 << 10 = 1 KB

; Control & Permissions (4 bytes each: byte k bit n = virtual page 8k+n)
MMU_UBITS       = $80A0  ; User-access permissions, $80A0-$80A3
MMU_WBITS       = $80A4  ; Write permissions,       $80A4-$80A7
MMU_CTRL        = $80A8  ; LSB = 1 (Kernel), 0 (User)

; Export for use in other files
; // .export ACIA_DATA, ACIA_STATUS, GPU_DATA, GPU_STATUS
; // .export DISK_LBA0, DISK_LBA1, DISK_LBA2, DISK_LBA3, DISK_CMD, DISK_STATUS, DISK_DATA, DISK_DPTR
; // .export MMU_PPN0, MMU_NPAGES, MMU_PAGE_SHIFT
; // .export MMU_WBITS, MMU_UBITS, MMU_CTRL

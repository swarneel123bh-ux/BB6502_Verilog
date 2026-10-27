// ==========================================================================
// devices.h — I/O register addresses (C side; asm side is devices.s)
// ==========================================================================
#ifndef  DEVICES_H
#define DEVICES_H

#include <stdint.h>

// ---- Required Hardware Addresses ----
// ACIA (UART)
#define ACIA_DATA    	((volatile uint8_t*)0x8000)
#define ACIA_STATUS  	((volatile uint8_t*)0x8001)
// GPU (COPROCESSOR)
#define GPU_DATA			((volatile uint8_t*)0x8002)
#define GPU_STATUS		((volatile uint8_t*)0x8003)
// DISK (SDCARD MODULE)
#define DISK_LBA0    	((volatile uint8_t*)0x80E0)
#define DISK_LBA1    	((volatile uint8_t*)0x80E1)
#define DISK_LBA2    	((volatile uint8_t*)0x80E2)
#define DISK_LBA3    	((volatile uint8_t*)0x80E3)
#define DISK_CMD     	((volatile uint8_t*)0x80E4)
#define DISK_STATUS  	((volatile uint8_t*)0x80E5)
#define DISK_DATA    	((volatile uint8_t*)0x80E6)
#define DISK_DPTR    	((volatile uint8_t*)0x80E7)
// MMU — 1 KB pages, VPN = VA[14:10]
// Page table: MMU_PPN0[n] = physical page for virtual page n (n = 0..31)
#define MMU_PPN0        ((volatile uint8_t*)0x8080)
#define MMU_NPAGES      32
#define MMU_PAGE_SHIFT  10                            // page size = 1 KB
#define MMU_PAGE_MASK   0x03FF                        // offset within a page
// Control & Permissions Registers (4 bytes each: byte k bit n = vpage 8k+n)
#define MMU_UBITS       ((volatile uint8_t*)0x80A0)  // User-access permissions, $80A0-$80A3
#define MMU_WBITS       ((volatile uint8_t*)0x80A4)  // Write permissions, $80A4-$80A7
#define MMU_CTRL        ((volatile uint8_t*)0x80A8)  // LSB = 1 (Kernel), 0 (User)


#endif		// DEVICES_H

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
// MMU
// PPN Entries (Virtual Pages 0-7)
#define MMU_PPN0        ((volatile uint8_t*)0x80F0)
#define MMU_PPN1        ((volatile uint8_t*)0x80F1)
#define MMU_PPN2        ((volatile uint8_t*)0x80F2)
#define MMU_PPN3        ((volatile uint8_t*)0x80F3)
#define MMU_PPN4        ((volatile uint8_t*)0x80F4)
#define MMU_PPN5        ((volatile uint8_t*)0x80F5)
#define MMU_PPN6        ((volatile uint8_t*)0x80F6)
#define MMU_PPN7        ((volatile uint8_t*)0x80F7)
// Control & Permissions Registers
#define MMU_WBITS       ((volatile uint8_t*)0x80F8)  // Write permissions per page
#define MMU_UBITS       ((volatile uint8_t*)0x80F9)  // User-access permissions per page
#define MMU_CTRL        ((volatile uint8_t*)0x80FA)  // LSB = 1 (Kernel), 0 (User)


#endif		// DEVICES_H

// ==========================================================================
// kernel.c — kernel console output
//
// Every string goes to both the ACIA (vvp's terminal / debugger pane) and
// the GPU stream (SDL window).
//
// Status bits: ACIA bit 1 = TX ready (bit 0 is RX valid); GPU bit 0 = ready.
// ==========================================================================
#include "include/kernel.h"
#include "include/devices.h"

void k_putc(char c) {
  while (!(*ACIA_STATUS & 0x02)); // Wait for ACIA TX ready
  *ACIA_DATA = c;
}

void k_gputc(char c) {
  while (!(*GPU_STATUS & 0x01)); // Wait for GPU TX ready
  *GPU_DATA = c;
}

void k_print(char* str) {
  while (*str) {
	 	k_putc(*str);
	  k_gputc(*str);
	  str++;
  }
}

void k_puthex(uint8_t b) {
	const char *alphabet = "0123456789ABCDEF";
	k_putc(alphabet[b >> 4]);			// High nibble
	k_gputc(alphabet[b >> 4]);		// High nibble
	k_putc(alphabet[b & 0x0F]); 	// Low nibble
	k_gputc(alphabet[b & 0x0F]); 	// Low nibble
}

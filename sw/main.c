// Registers
#define ACIA_DATA   	((volatile unsigned char*)0x8000)
#define ACIA_STATUS 	((volatile unsigned char*)0x8001)
#define GPU_DATA    	((volatile unsigned char*)0x8002)
#define GPU_STATUS    ((volatile unsigned char*)0x8003)

// MMU Registers
#define MMU_PPN0     ((volatile unsigned char*)0x80F0)
#define MMU_PPN1     ((volatile unsigned char*)0x80F1)
#define MMU_W        ((volatile unsigned char*)0x80F8)
#define MMU_U        ((volatile unsigned char*)0x80F9)

// KERNEL SPACE VARIABLE
#define MMU_KERNEL   ((volatile unsigned char*)0x80FA)

void k_putc(char c) {
  while (!(*ACIA_STATUS & 0x01)); // Wait for ACIA TX ready
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

int main() {
  k_print("Kernel Booting...\n");

  // Identity map Page 1 to PPN 1 via MMU
  *MMU_PPN1 = 0x01;

  k_print("MMU Initialized. System Ready.\n");

  while(1);
  return 0;
}

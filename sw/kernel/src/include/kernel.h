#ifndef KERNEL_H
#define KERNEL_H

#include <stdint.h>

void k_putc(char c);
void k_gputc(char c);
void k_print(char* str);
void k_puthex(uint8_t b);

#endif

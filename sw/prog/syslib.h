#ifndef SYSLIB_H
#define SYSLIB_H

#include <stdint.h>

#define SYS_EXIT         1
#define SYS_PUTC         2
#define SYS_GETC         3
#define SYS_PUTS         4
#define SYS_BLOCK_READ   5
#define SYS_BLOCK_WRITE  6
#define SYS_EXEC         7
#define SYS_GETC_NB      8

void    sys_exit(uint8_t code);
void    sys_putc(uint8_t c);
uint8_t sys_getc(void);
void    sys_puts(const char* s);
uint8_t sys_block_read(uint16_t lba, uint8_t* buf);
uint8_t sys_block_write(uint16_t lba, uint8_t* buf);

#endif

#ifndef BLOCK_H
#define BLOCK_H

#include <stdint.h>

#define BLOCK_SIZE 512

// Returns 0 on success, nonzero on error.
uint8_t block_read(uint32_t lba, uint8_t* buf);
uint8_t block_write(uint32_t lba, const uint8_t* buf);

#endif

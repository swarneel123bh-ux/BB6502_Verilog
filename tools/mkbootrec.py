#!/usr/bin/env python3
# Boot record format (LBA 100, read by sw/boot/boot.s):
#   +0  'BBBR'           magic
#   +4  kernel_lba       u32 little-endian
#   +8  kernel_nsec      u16 little-endian (sectors to load to $0200)
#   +10 zero padding to 512 bytes
# Usage: mkbootrec.py <kernel_lba> <kernel_nsec> <out.bin>
"""Generate a 512-byte boot record for BB6502."""
import sys, struct

if len(sys.argv) != 4:
    print("usage: mkbootrec.py <kernel_lba> <kernel_nsec> <out.bin>")
    sys.exit(1)

kernel_lba   = int(sys.argv[1])
kernel_nsec  = int(sys.argv[2])
out          = sys.argv[3]

# Boot record: 'BBBR' magic, kernel_lba (u32 LE), kernel_nsec (u16 LE), pad
record = struct.pack("<4sIH", b"BBBR", kernel_lba, kernel_nsec)
record += b"\x00" * (512 - len(record))

with open(out, "wb") as f:
    f.write(record)

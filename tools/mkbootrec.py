#!/usr/bin/env python3
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

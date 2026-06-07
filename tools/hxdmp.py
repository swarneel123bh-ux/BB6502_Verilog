#!/usr/bin/env python3

import sys
from pathlib import Path


def hexdump(data: bytes, width: int = 16):
    for offset in range(0, len(data), width):
        chunk = data[offset : offset + width]

        hex_bytes = " ".join(f"{b:02x}" for b in chunk)

        # Add extra spacing like hexdump -C
        if len(chunk) > 8:
            hex_bytes = (
                " ".join(f"{b:02x}" for b in chunk[:8])
                + "  "
                + " ".join(f"{b:02x}" for b in chunk[8:])
            )

        hex_bytes = hex_bytes.ljust(49)

        ascii_part = "".join(chr(b) if 32 <= b <= 126 else "." for b in chunk)

        print(f"{offset:08x}  {hex_bytes}  |{ascii_part}|")

    print(f"{len(data):08x}")


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <file>")
        sys.exit(1)

    path = Path(sys.argv[1])

    if not path.exists():
        print(f"File not found: {path}")
        sys.exit(1)

    with open(path, "rb") as f:
        data = f.read()

    hexdump(data)


if __name__ == "__main__":
    main()

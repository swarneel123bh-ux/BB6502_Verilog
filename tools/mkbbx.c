// mkbbx: wrap a raw .bin with a BBX header
//
// Verifies logical correctness of a BBX file
//
// Usage: mkbbx <input.bin> <load_addr_hex> <entry_addr_hex> <output.bbx>
//
// Actually: the program's prog_crt0.s already emits the header as the first
// 6 bytes via the HDR segment. So this tool just copies the binary as-is
// if your linker config places HDR first. It exists as a sanity check
// and for cases where you want to wrap externally.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char** argv) {
  if (argc != 2) {
    fprintf(stderr, "Usage: %s <file.bbx>\n", argv[0]);
    fprintf(stderr, "Verifies BBX header on stdin/file.\n");
    return 1;
  }
  FILE* f = fopen(argv[1], "rb");
  if (!f) { perror("open"); return 1; }

  unsigned char hdr[6];
  if (fread(hdr, 1, 6, f) != 6) {
    fprintf(stderr, "file too short\n"); return 1;
  }
  fclose(f);

  if (hdr[0] != 0x42 || hdr[1] != 0x58) {
    fprintf(stderr, "bad magic: %02x %02x (expected 42 58)\n", hdr[0], hdr[1]);
    return 1;
  }
  unsigned load  = hdr[2] | (hdr[3] << 8);
  unsigned entry = hdr[4] | (hdr[5] << 8);
  printf("BBX valid:  load=$%04X  entry=$%04X\n", load, entry);
  return 0;
}

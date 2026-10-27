// ============================================================================
// tb.v — the BB6502 machine (top level, simulated with Icarus Verilog)
//
// Not just a testbench: this is the whole computer.
//   CPU     Arlet Ottens' 65C02 (verilog-65C02-microcode/generic, with a VPB
//           output added for the MMU), 100 MHz simulated clock, AD registered
//           into AB as Arlet's README describes for asynchronous memory.
//   MMU     mmu6502.v: 32 x 1 KB virtual pages -> 32 physical pages (32 KB RAM).
//           Faults are routed to NMI.
//   Memory  ram[0:32767] physical RAM, rom[0:32511] = CPU $8100-$FFFF loaded
//           from build/bootrom.hex.
//   I/O     decoded below in the $8000-$80FF window:
//             $8000 ACIA data   W: byte to vvp's stdout   R: last RX byte
//             $8001 ACIA status bit0 = RX byte valid (cleared by reading $8000)
//                               bit1 = TX ready (6850 TDRE; busy for
//                                      ACIA_TX_CYCLES after each write)
//             $8002 GPU data    W: byte to /tmp/bb6502_gpu (tools/gpu.c)
//             $8003 GPU status  always $01 (ready)
//             $80E0-$80E3  disk LBA (32-bit LE)
//             $80E4 disk CMD    1 = read sector into buffer, 2 = write buffer
//             $80E5 disk STATUS bit7 = error, bit0 = busy
//             $80E6 disk DATA   buffer byte at DPTR, DPTR auto-increments
//             $80E7 disk DPTR   any write resets the buffer pointer to 0
//             $8080-$80BF MMU registers (handled inside mmu6502)
//           Unmapped I/O reads return $FF.
//   Files   build/disk.img (the disk), /tmp/bb6502_in (keyboard input, a
//           regular file polled every 200 clocks; a FIFO here would block
//           the simulation), /tmp/bb6502_gpu (GPU output stream, a FIFO).
//
// Built twice by rtl/rtl.mk: build/sim.vvp (normal) and build/sim_dbg.vvp
// with -DBBDBG, which adds the debugger hooks near the end of this file.
// Run from the project root (file paths here are relative to it).
// ============================================================================
`timescale 1ns/1ps

module tb;
  reg clk = 0;
  reg reset = 1;
  always #5 clk = ~clk;

  // CPU interface
  wire [15:0] AD;
  wire        WE;
  wire [7:0]  DO;
  reg  [7:0]  DI;
  reg         IRQ = 0;
  reg         NMI = 1;          // active low — high when no interrupt
  reg         RDY = 1;
  wire        sync;
  wire        VPB;

  cpu dut(
    .clk   (clk),
    .RST   (reset),
    .AD    (AD),
    .sync  (sync),
    .DI    (DI),
    .DO    (DO),
    .WE    (WE),
    .IRQ   (IRQ),
    .NMI   (NMI),
    .RDY   (RDY),
    .VPB   (VPB),
    .debug (1'b0)
  );

  // Register AD -> AB
  reg [15:0] AB;
  always @(posedge clk)
    if (RDY) AB <= AD;

  // ---- MMU ----
  localparam PPN_W = 5;                  // 32 physical pages of 1 KB = 32KB
  wire [7:0]            mmu_data_out;
  wire                  mmu_data_oe;
  wire [9+PPN_W:0]      ram_paddr;       // physical address out of MMU (10-bit page offset)
  wire                  faultb;


  mmu6502 #(.PPN_WIDTH(PPN_W)) mmu (
    .phi2     (clk),
    .resetb   (~reset),
    .rwb      (~WE),
    .vpb      (VPB),
    .addr     (AB),
    .data_in  (DO),
    .data_out (mmu_data_out),
    .data_oe  (mmu_data_oe),
    .ram_addr (ram_paddr),
    .faultb    (faultb)
  );

  // Connect fault -> NMI (active low; NMI=0 means "interrupt pending")
  always @(posedge clk)
    NMI <= ~faultb;	// NOTE: artlet's nmi is POSEDGE Triggered so we need to bar the bar again

  // ---- Memory ----
  reg [7:0] ram [0:32767];        // physical, 32KB
  reg [7:0] rom [0:32511];        // $8100-$FFFF

  // ---- ACIA + GPU state ----
  reg [7:0] acia_rx_data = 0;
  reg       acia_rx_valid = 0;
  reg				acia_tx_ready = 1;

  // ---- Disk peripheral state ----
  reg [31:0] disk_lba   = 0;
  reg [7:0]  disk_buf [0:511];
  reg [8:0]  disk_dptr = 0;      // 0..511 byte pointer into disk_buf
  reg        disk_busy = 0;
  reg        disk_err  = 0;
  integer    disk_fd;

  // Reset data pointer & buffer index helpers
  task automatic disk_do_read;
    integer i, n;
    begin
      if (disk_fd == 0) begin
        disk_err <= 1;
      end else begin
        // Seek to LBA * 512
        $fseek(disk_fd, disk_lba * 512, 0);   // SEEK_SET = 0
        for (i = 0; i < 512; i = i + 1) begin
          n = $fgetc(disk_fd);
          if (n == -1) disk_buf[i] <= 8'h00;  // past EOF -> zeros
          else         disk_buf[i] <= n[7:0];
        end
        disk_err  <= 0;
      end
      disk_busy <= 0;
      disk_dptr <= 0;
    end
  endtask

  task automatic disk_do_write;
    integer i;
    begin
      if (disk_fd == 0) begin
        disk_err <= 1;
      end else begin
        $fseek(disk_fd, disk_lba * 512, 0);
        for (i = 0; i < 512; i = i + 1)
          $fwrite(disk_fd, "%c", disk_buf[i]);
        $fflush(disk_fd);
        disk_err <= 0;
      end
      disk_busy <= 0;
    end
  endtask

  // Array reads as continuous assignments. Indexing an array inside
  // always @(*) makes icarus put every word of the array in the block's
  // sensitivity list (~65K words here): ~15 s to compile and a slower
  // simulation. A continuous assign is tracked per word instead.
  wire [7:0] ram_q  = ram[ram_paddr];
  wire [7:0] rom_q  = rom[AB - 16'h8100];   // only selected when AB >= $8100
  wire [7:0] dbuf_q = disk_buf[disk_dptr];

  // Combinational read mux (async memory model)
  always @(*) begin
    if (AB[15] == 1'b0) DI = ram_q;                                   // translated by MMU
    else if ((AB & 16'hFFC0) == 16'h8080) DI = mmu_data_out;          // MMU control regs $8080-$80BF
    else if (AB == 16'h8000) DI = acia_rx_data;
    else if (AB == 16'h8001) DI = {6'b0, acia_tx_ready, acia_rx_valid};
    else if (AB == 16'h8003) DI = 8'h01;                             	// GPU TX always ready
    else if (AB == 16'h80E0) DI = disk_lba[7:0];
    else if (AB == 16'h80E1) DI = disk_lba[15:8];
    else if (AB == 16'h80E2) DI = disk_lba[23:16];
    else if (AB == 16'h80E3) DI = disk_lba[31:24];
    else if (AB == 16'h80E5) DI = {disk_err, 6'b0, disk_busy};
    else if (AB == 16'h80E6) DI = dbuf_q;
    else if (AB >= 16'h8100) DI = rom_q;
    else DI = 8'hFF;
  end

  // Tx behaviour
  localparam ACIA_TX_CYCLES = 87;     // 115200 baud, 10 bits/char, 1 MHz CPU
  reg [15:0] acia_tx_count = 0;
  always @(posedge clk) begin
    if (reset) begin
    	acia_tx_ready <= 1;							// Start ready
     	acia_tx_count <= 0;
    end else if (WE & RDY & (AB == 16'h8000)) begin
    	if (!acia_tx_ready) begin
     		$display("[acia] TX overrun: byte %02x at t=%0t", DO, $time);
     	end
    	acia_tx_count <= ACIA_TX_CYCLES - 1;	// Set counter to corrent count
     	acia_tx_ready <= 0;								// Reset ready flag
    end else if (!acia_tx_ready) begin
      if (acia_tx_count == 0) begin			// If count finished, set ready flag
      	acia_tx_ready <= 1;
       	acia_tx_count <= 0;
      end else begin										// If not finished, recude count by 1
      	acia_tx_count <= acia_tx_count - 1;
      end
    end
  end

  // Writes (clocked)
  integer gpu_fd, stdin_fd;
  always @(posedge clk) begin
    if (WE & RDY & ~reset) begin
      if (AB[15] == 1'b0)
        ram[ram_paddr] <= DO;                       // translated
      else if (AB == 16'h8000)
`ifdef BBDBG
        $bbdbg_tx(DO);                              // debugger terminal pane
`else
        $write("%c", DO);
`endif
      else if (AB == 16'h8002) begin
        $fwrite(gpu_fd, "%c", DO);
        $fflush(gpu_fd);
      end
      else if (AB == 16'h80E0) disk_lba[7:0]   <= DO;
      else if (AB == 16'h80E1) disk_lba[15:8]  <= DO;
      else if (AB == 16'h80E2) disk_lba[23:16] <= DO;
      else if (AB == 16'h80E3) disk_lba[31:24] <= DO;
      else if (AB == 16'h80E4) begin
        disk_busy <= 1;
        if      (DO == 8'h01) disk_do_read;
        else if (DO == 8'h02) disk_do_write;
        else                  disk_busy <= 0;       // unknown cmd, no-op
      end
      else if (AB == 16'h80E6) disk_buf[disk_dptr] <= DO;
      else if (AB == 16'h80E7) disk_dptr <= 0;
      // MMU control writes are consumed inside the MMU itself
    end
  end

  // Auto increment the data pointer after any data access
  always @(posedge clk) begin
    if (RDY & ~reset & (AB == 16'h80E6) && disk_dptr < 511)
      disk_dptr <= disk_dptr + 1;
  end

  // Clear RX-valid after CPU reads data register
  always @(posedge clk) begin
    if (~WE && AB == 16'h8000 && acia_rx_valid) acia_rx_valid <= 0;
  end

  // stdin polling: /tmp/bb6502_in is a regular file that gpu.c (and the
  // debugger) append keys to; we re-seek to the next unread byte each poll
  integer stdin_pos = 0;
  integer ch;
  integer poll_counter = 0;
  always @(posedge clk) begin
    poll_counter <= poll_counter + 1;
    if (poll_counter >= 200) begin
      poll_counter <= 0;
      if (!acia_rx_valid && stdin_fd != 0) begin
        $fseek(stdin_fd, stdin_pos, 0);  // SEEK_SET = 0; also clears EOF flag
        ch = $fgetc(stdin_fd);
        if (ch != -1) begin
          acia_rx_data  <= ch[7:0];
          acia_rx_valid <= 1;
          stdin_pos = stdin_pos + 1;
        end
      end
    end
  end

  // ---- Optional: log faults so we can see when the MMU traps ----
  always @(posedge clk)
    if (~faultb)
`ifdef BBDBG
      $bbdbg_fault(AB, WE, ram_paddr);              // shown in the debugger console
`else
      $display("[mmu] FAULT  AB=%04x  WE=%b  paddr=%05x",
               AB, WE, ram_paddr);
`endif

`ifdef BBDBG
  // ---- Debugger hooks (only in sim_dbg.vvp, built with -DBBDBG) ----
  // The debugger is a VPI module (rtl/dbg/) that gets control once per
  // instruction. At the posedge that ends an opcode-fetch (sync) cycle we
  // latch the opcode's address and value; at the following negedge the
  // previous instruction's register write-back (done on that posedge) is
  // visible, so $bbdbg_fetch sees a consistent "about to execute dbg_pc"
  // state. While $bbdbg_fetch has not returned, simulation time is frozen.
  reg  [15:0] dbg_pc    = 0;
  reg  [7:0]  dbg_op    = 0;
  reg         dbg_fetch = 0;
  // Software reset requested by the debugger (written through VPI):
  // hold `reset` for 16 cycles, like the power-on reset in the initial block.
  reg         dbg_reset_req = 0;
  integer     dbg_rst_cnt   = 0;

  always @(posedge clk) begin
    dbg_fetch <= sync & RDY & ~reset & ~dbg_reset_req & (dbg_rst_cnt == 0);
    if (sync & RDY) begin
      dbg_pc <= AB;
      dbg_op <= DI;
    end
  end

  always @(negedge clk)
    if (dbg_fetch) $bbdbg_fetch(dbg_pc, dbg_op);

  always @(posedge clk) begin
    if (dbg_reset_req) begin
      dbg_reset_req <= 0;
      dbg_rst_cnt   <= 16;
      reset         <= 1;
    end else if (dbg_rst_cnt == 1) begin
      dbg_rst_cnt   <= 0;
      reset         <= 0;
    end else if (dbg_rst_cnt > 1)
      dbg_rst_cnt   <= dbg_rst_cnt - 1;
  end
`endif

  initial begin
  	// Traces
  	// $dumpfile("trace.vcd");
    // $dumpvars(0, tb);

    // Rom Loading
    $readmemh("build/bootrom.hex", rom);

    // I/O files loading
    stdin_fd = $fopen("/tmp/bb6502_in", "r");
    gpu_fd   = $fopen("/tmp/bb6502_gpu", "w");
    if (stdin_fd == 0 || gpu_fd == 0) begin
      $display("[tb] FIFO open failed");
      $finish;
    end

    // Disk image loading
    disk_fd = $fopen("build/disk.img", "r+b");
    if (disk_fd == 0) $display("[tb] WARNING: build/disk.img not found");

    // Reset
    reset = 1;
    repeat (16) @(posedge clk);
    reset = 0;

    // Keep looping
  end
endmodule

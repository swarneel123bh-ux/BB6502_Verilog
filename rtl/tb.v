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
  localparam PPN_W = 3;                  // 8 physical pages = 32KB
  wire [7:0]            mmu_data_out;
  wire                  mmu_data_oe;
  wire [11+PPN_W:0]     ram_paddr;       // physical address out of MMU
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

  // Combinational read mux (async memory model)
  always @(*) begin
    if (AB[15] == 1'b0) DI = ram[ram_paddr];                          // translated by MMU
    else if ((AB & 16'hFFF0) == 16'h80F0) DI = mmu_data_out;          // MMU control regs
    else if (AB == 16'h8000) DI = acia_rx_data;
    else if (AB == 16'h8001) DI = {7'b0, acia_rx_valid};
    else if (AB == 16'h8003) DI = 8'h01;                             	// GPU TX always ready
    else if (AB == 16'h80E0) DI = disk_lba[7:0];
    else if (AB == 16'h80E1) DI = disk_lba[15:8];
    else if (AB == 16'h80E2) DI = disk_lba[23:16];
    else if (AB == 16'h80E3) DI = disk_lba[31:24];
    else if (AB == 16'h80E5) DI = {disk_err, 6'b0, disk_busy};
    else if (AB == 16'h80E6) DI = disk_buf[disk_dptr];
    else if (AB >= 16'h8100) DI = rom[AB - 16'h8100];
    else DI = 8'hFF;
  end

  // Writes (clocked)
  integer gpu_fd, stdin_fd;
  always @(posedge clk) begin
    if (WE & RDY & ~reset) begin
      if (AB[15] == 1'b0)
        ram[ram_paddr] <= DO;                       // translated
      else if (AB == 16'h8000)
        $write("%c", DO);
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
  always @(posedge clk)
    if (~WE && AB == 16'h8000 && acia_rx_valid)
      acia_rx_valid <= 0;

  // stdin polling via FIFO
  integer stdin_pos = 0;
  integer ch;
  integer poll_counter = 0;
  /*always @(posedge clk) begin
    poll_counter <= poll_counter + 1;
    if (poll_counter >= 200) begin
      poll_counter <= 0;
      if (!acia_rx_valid) begin
        ch = $fgetc(stdin_fd);
        if (ch != -1) begin
          acia_rx_data  <= ch[7:0];
          acia_rx_valid <= 1;
        end
      end
    end
    end*/
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
      $display("[mmu] FAULT  AB=%04x  WE=%b  paddr=%05x",
               AB, WE, ram_paddr);

  initial begin
  	// Traces
  	// $dumpfile("trace.vcd");
    // $dumpvars(0, tb);

    // Rom Loading
    $readmemh("build/rom.hex", rom);

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

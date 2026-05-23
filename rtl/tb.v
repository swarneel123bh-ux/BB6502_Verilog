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

  // Combinational read mux (async memory model)
  always @(*) begin
    if (AB[15] == 1'b0)
      DI = ram[ram_paddr];                          // translated by MMU
    else if ((AB & 16'hFFF0) == 16'h80F0)
      DI = mmu_data_out;                            // MMU control regs
    else if (AB == 16'h8000)
      DI = acia_rx_data;
    else if (AB == 16'h8001)
      DI = {7'b0, acia_rx_valid};
    else if (AB == 16'h8003)
      DI = 8'h01;                                   // GPU TX always ready
    else if (AB >= 16'h8100)
      DI = rom[AB - 16'h8100];
    else
      DI = 8'hFF;
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
      // MMU control writes are consumed inside the MMU itself
    end
  end

  // Clear RX-valid after CPU reads data register
  always @(posedge clk)
    if (~WE && AB == 16'h8000 && acia_rx_valid)
      acia_rx_valid <= 0;

  // stdin polling via FIFO
  integer ch;
  integer poll_counter = 0;
  always @(posedge clk) begin
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
  end

  // ---- Optional: log faults so we can see when the MMU traps ----
  always @(posedge clk)
    if (~faultb)
      $display("[mmu] FAULT  AB=%04x  WE=%b  paddr=%05x",
               AB, WE, ram_paddr);

  initial begin
    $dumpfile("trace.vcd");
    $dumpvars(0, tb);
    $readmemh("build/rom.hex", rom);

    stdin_fd = $fopen("/tmp/bb6502_in", "r");
    gpu_fd   = $fopen("/tmp/bb6502_gpu", "w");
    if (stdin_fd == 0 || gpu_fd == 0) begin
      $display("[tb] FIFO open failed");
      $finish;
    end

    reset = 1;
    repeat (16) @(posedge clk);
    reset = 0;
  end
endmodule

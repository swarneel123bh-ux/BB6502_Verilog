`timescale 1ns/1ps

module tb;
  reg clk = 0;
  reg reset = 1;
  always #5 clk = ~clk;

  wire [15:0] AD;
  wire        WE;
  wire [7:0]  DO;
  reg  [7:0]  DI;
  reg         IRQ = 0;
  reg         NMI = 0;
  reg         RDY = 1;
  wire        sync;
  integer stdin_fd;
  integer gpu_fd;

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
    .debug (1'b0)
  );

  reg [7:0] ram [0:32767];
  reg [7:0] rom [0:32511];

  reg [7:0] acia_rx_data = 0;
  reg       acia_rx_valid = 0;

  // Register AD -> AB (Arlet's pattern)
  reg [15:0] AB;
  always @(posedge clk)
    if (RDY) AB <= AD;

  // Synchronous read: DI valid one cycle after AD
  always @(posedge clk) begin
    if (RDY) begin
      if (AD < 16'h8000)         DI <= ram[AD[14:0]];
      else if (AD == 16'h8000)   DI <= acia_rx_data;
      else if (AD == 16'h8001)   DI <= {7'b0, acia_rx_valid};
      else if (AD >= 16'h8100)   DI <= rom[AD - 16'h8100];
      else if (AD == 16'h8003)   DI <= 8'h01;   // GPU TX always ready
      else                       DI <= 8'hFF;
    end
  end

  // Write: registered AB, current WE/DO
  always @(posedge clk) begin
    if (WE & RDY & ~reset) begin
      if (AB < 16'h8000)        ram[AB[14:0]] <= DO;
      else if (AB == 16'h8000)  $write("%c", DO);              // console TX
      else if (AB == 16'h8002) begin                            // GPU TX
        $fwrite(gpu_fd, "%c", DO);
        $fflush(gpu_fd);
      end
    end
  end

  // Clear RX-valid after CPU reads data register
  always @(posedge clk) begin
    if (~WE && AB == 16'h8000 && acia_rx_valid)
      acia_rx_valid <= 0;
  end

  // stdin polling
  integer ch;
  integer poll_counter = 0;
  always @(posedge clk) begin
    poll_counter <= poll_counter + 1;
    if (poll_counter >= 200) begin
      poll_counter <= 0;
      if (!acia_rx_valid) begin
        ch = $fgetc(stdin_fd);
        if (ch != -1) begin
          // $display("[tb] RX got 0x%02x", ch[7:0]);
          acia_rx_data  <= ch[7:0];
          acia_rx_valid <= 1;
        end
      end
    end
  end


  initial begin
    $dumpfile("trace.vcd");
    $dumpvars(0, tb);
    $readmemh("build/rom.hex", rom);
    // File descriptor for the keyboard
    stdin_fd = $fopen("/tmp/bb6502_in", "r");
    if (stdin_fd == 0) begin
      $display("[tb] failed to open /tmp/bb6502_in");
      $finish;
    end
    // File descriptor for the SDL process
    gpu_fd = $fopen("/tmp/bb6502_gpu", "w");
    if (gpu_fd == 0) begin
      $display("[tb] failed to open /tmp/bb6502_gpu");
      $finish;
    end

    reset = 1;
    repeat (16) @(posedge clk);
    reset = 0;

    // #200_000;
    // $display("\n[tb] timeout");
    // $finish;
  end
endmodule

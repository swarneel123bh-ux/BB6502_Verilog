`timescale 1ns / 1ps

module mmu6502 #(
    parameter PPN_WIDTH = 8
) (
    input  wire                  phi2,      // Phi 2 (SysClock)
    input  wire                  resetb,    // Reset Bar
    input  wire                  rwb,       // Read Write Bar
    input  wire                  vpb,       // Vector Pull Bar
    input  wire [          15:0] addr,      // Address bus
    input  wire [           7:0] data_in,   // Data bus for sampling
    output wire [           7:0] data_out,  // Data bus for driving output
    output wire                  data_oe,   // Data bus output enable (when driving output)
    output wire [11+PPN_WIDTH:0] ram_addr,  // Real Ram Address bus
    output wire                  faultb      // Fault pin (traps unauthorized accesses) (Active low)
);

  // ==========================
  // PAGE STATE TRACKING
  // ==========================

  // hardware page table
  // total 8 entries => 8 pages max
  reg [PPN_WIDTH-1:0] ppn[0:7];

  // Write and User Access Permission bits
  // bit[i] is set => User can write/read to i'th page
  // i : 0 -> 7 since there are 8 pages
  reg [7:0] w_bits;  // Writable permission bit per VP
  reg [7:0] u_bits;  // User-Accessable permission bit per VP



  // ==========================
  // ADDRESS DECODE
  // ==========================

  // Virtual Page Number
  // Uses last 3 bits (leaving a15) for page table index
  wire [2:0] vpn = addr[14:12];

  // Check if the address is a MMU Ctrl Register
  // There are a total of 16 ctrl register slots available for now
  wire is_ctrl = (addr[15:4] == 12'h80F);  // Any of $80F0 to $80FF


  // ==========================
  // TRANSLATION (COMBINATIONAL)
  // ==========================

  assign ram_addr = {ppn[vpn], addr[11:0]};  // Real address

  // ==========================
  // MODE FSM
  // ==========================
  wire fault_u, fault_w, fault_ctrl;
  reg kernel;


  // ==========================
  // SEQUENTIAL RESET AND CTRL
  // ==========================

  integer i;
  always @(negedge phi2 or negedge resetb) begin

    // Reset behaviour
    if (!resetb) begin
      for (i = 0; i < 8; i = i + 1) begin
        ppn[i] <= i[PPN_WIDTH-1:0];  // Fill table linearly (truncate high bits)
      end
      w_bits <= 8'hFF;  // All pages writable
      u_bits <= 8'h00;  // No pages user accessible (in kernel mode at reset)
      kernel <= 1'b1;  // Start in kernel mode
    end  // Control Register behaviour
    else begin

      // Sample VPB pin to get back into kernel mode on Traps
      if (!vpb || fault_u || fault_w || fault_ctrl) begin
        kernel <= 1'b1;
      end  // If write to control register (WHEN IN KERNEL MODE)
      else if (is_ctrl && !rwb && kernel) begin
        if (~addr[3]) begin
          ppn[addr[2:0]] <= data_in[PPN_WIDTH-1:0];  // Truncate to correct width
        end else begin
          case (addr[3:0])
            4'h8: w_bits <= data_in;
            4'h9: u_bits <= data_in;
            4'hA: kernel <= data_in[0];  // Just take the LSB, non-zero means kernel mode
            default: begin
            end
          endcase
        end
      end

    end

  end


  // ==========================
  // Combinational things
  // ==========================

  assign data_oe = (is_ctrl & rwb) & phi2;
  assign data_out = (~addr[3]) ? {{(8 - PPN_WIDTH) {1'b0}}, ppn[addr[2:0]]}  // Ctrl register read
      : ((addr[3:0] == 4'h8) ? w_bits  // Write permissions read
      : ((addr[3:0] == 4'h9) ? u_bits  // User access permissions read
      : 8'h0));
  wire ram_access = (addr[15] == 1'b0);

  // Fault testing
  assign fault_u = ram_access & ~kernel & ~u_bits[vpn];  // Fault on illegal access to a page
  assign fault_w = ram_access & ~kernel & ~rwb & ~w_bits[vpn];  // Fault on illegal write to a page
  assign fault_ctrl = is_ctrl & ~kernel & ~rwb;  // Fault on illegal write to ctlr reg

  reg fault_reg;  // Registered fault for making sure there are no false NMI lows
  always @(negedge phi2 or negedge resetb) begin
    if (!resetb) begin
      fault_reg <= 1'b0;
    end
    else begin
      fault_reg <= fault_u | fault_w | fault_ctrl;
    end
  end
  assign faultb = ~fault_reg;	// fault needs to be active low since we connect it to NMIB

endmodule

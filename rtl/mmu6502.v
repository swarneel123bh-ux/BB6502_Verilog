// ============================================================================
// mmu6502.v — BB6502 memory management unit
//
// Splits the CPU's lower 32 KB ($0000-$7FFF) into 32 virtual pages of 1 KB
// (VA[14:10] = virtual page number) and maps each to a physical page through
// a page table. Instantiated in tb.v with PPN_WIDTH = 5 (32 physical
// pages = 32 KB of RAM).
//
//   Kernel mode  no translation (physical = virtual), all accesses allowed.
//   User mode    physical page = ppn[vpn]; u_bits / w_bits gate access and
//                writes per virtual page; violations raise a fault.
//
// Mode changes:
//   - reset, any vector fetch (VPB low: interrupt/BRK/reset) or any fault
//     -> kernel mode
//   - writing $80A8 (kernel only): bit 0 = 1 kernel, 0 user. The boot ROM's
//     ret_user_mode ($FFF8: STZ $80A8; RTI) is how the kernel enters a process.
//
// Control registers ($8080-$80BF, writable in kernel mode only, readable in
// both modes), by offset from $8080:
//   $00-$1F  ppn[0..31]
//   $20-$23  u_bits   byte k bit n = virtual page 8k+n may be accessed by user
//   $24-$27  w_bits   same layout, virtual page may be written by user
//   $28      mode     bit 0: 1 = kernel, 0 = user
//   $29-$3F  reserved (read as 0)
//
// faultb is registered (one cycle late) and active low; tb.v connects it to
// the CPU's NMI input.
// ============================================================================
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
    output wire [9+PPN_WIDTH:0] ram_addr,  // Real Ram Address bus
    output wire                  faultb      // Fault pin (traps unauthorized accesses) (Active low)
);

  // ==========================
  // PAGE STATE TRACKING
  // ==========================

  // hardware page table
  // total 32 entries => 32 pages of 1 KB
  reg [PPN_WIDTH-1:0] ppn[0:31];

  // Write and User Access Permission bits
  // bit[i] is set => User can write/read to i'th page
  // i : 0 -> 31 since there are 32 pages
  reg [31:0] w_bits;  // Writable permission bit per VP
  reg [31:0] u_bits;  // User-Accessable permission bit per VP



  // ==========================
  // ADDRESS DECODE
  // ==========================

  // Virtual Page Number
  // Uses last 5 bits (leaving a15) for page table index
  wire [4:0] vpn = addr[14:10];

  // Check if the address is a MMU Ctrl Register
  // There are a total of 64 ctrl register slots ($8080 to $80BF)
  wire is_ctrl = (addr[15:6] == 10'h202);  // Any of $8080 to $80BF
  wire [5:0] reg_off = addr[5:0];          // Register offset from $8080

  // ==========================
  // MODE FSM
  // ==========================

  wire fault_u, fault_w, fault_ctrl;
  reg kernel;


  // ==========================
  // TRANSLATION (COMBINATIONAL)
  // ==========================
  // wire [PPN_WIDTH-1:0] eff_ppn = (kernel == 1) ? addr[14:12] : ppn[vpn];
  // assign ram_addr = {eff_ppn, addr[11:0]};

  assign ram_addr = {((kernel) ? addr[14:10] : ppn[vpn]), addr[9:0]};



  // ==========================
  // SEQUENTIAL RESET AND CTRL
  // ==========================

  integer i;
  always @(negedge phi2 or negedge resetb) begin

    if (!resetb) begin	// Reset behaviour
      for (i = 0; i < 32; i = i + 1) begin
        ppn[i] <= i[PPN_WIDTH-1:0];  // Fill table linearly (truncate high bits)
      end
      w_bits <= 32'hFFFF_FFFF;  // All pages writable
      u_bits <= 32'h0000_0000;  // No pages user accessible (in kernel mode at reset)
      kernel <= 1'b1;  // Start in kernel mode
    end
    else begin	// Control Register behaviour

      // Sample VPB pin to get back into kernel mode on Traps
      if (!vpb || fault_u || fault_w || fault_ctrl) begin
        kernel <= 1'b1;
      end  // If write to control register (WHEN IN KERNEL MODE)
      else if (is_ctrl && !rwb && kernel) begin
        if (~reg_off[5]) begin                       // $00-$1F: page table
          ppn[reg_off[4:0]] <= data_in[PPN_WIDTH-1:0];  // Truncate to correct width
        end else begin
          case (reg_off)
            6'h20: u_bits[ 7: 0] <= data_in;           // pages  0- 7
            6'h21: u_bits[15: 8] <= data_in;           // pages  8-15
            6'h22: u_bits[23:16] <= data_in;           // pages 16-23
            6'h23: u_bits[31:24] <= data_in;           // pages 24-31
            6'h24: w_bits[ 7: 0] <= data_in;
            6'h25: w_bits[15: 8] <= data_in;
            6'h26: w_bits[23:16] <= data_in;
            6'h27: w_bits[31:24] <= data_in;
            6'h28: kernel <= data_in[0];  // Just take the LSB, non-zero means kernel mode
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
  // Ctrl register read, same offsets as the write side (one byte at a time)
  // (array read as a continuous assign so the always block below isn't
  //  sensitive to every ppn entry, like the read mux in tb.v)
  wire [PPN_WIDTH-1:0] ppn_rd = ppn[reg_off[4:0]];
  reg [7:0] ctrl_rd;
  always @(*) begin
    if (~reg_off[5]) ctrl_rd = {{(8 - PPN_WIDTH) {1'b0}}, ppn_rd};
    else case (reg_off)
      6'h20: ctrl_rd = u_bits[ 7: 0];
      6'h21: ctrl_rd = u_bits[15: 8];
      6'h22: ctrl_rd = u_bits[23:16];
      6'h23: ctrl_rd = u_bits[31:24];
      6'h24: ctrl_rd = w_bits[ 7: 0];
      6'h25: ctrl_rd = w_bits[15: 8];
      6'h26: ctrl_rd = w_bits[23:16];
      6'h27: ctrl_rd = w_bits[31:24];
      6'h28: ctrl_rd = {7'b0, kernel};
      default: ctrl_rd = 8'h00;           // $29-$3F reserved
    endcase
  end
  assign data_out = ctrl_rd;
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

// timer6502.v
//
// Four independent programmable timers ("channels") with a 4-bit address bus.
// Each channel raises a sticky pending flag once per programmed period. The
// flag stays set until the CPU clears it (write 1 to the matching ST bit).
//
// Bus interface
//   cs    chip select (from the address decoder)
//   we    1 = write, 0 = read
//   addr  register offset (see map below)
//   din   write data
//   dout  read data, combinational (valid in the same cycle as the address)
//
// Register map
//   0      CTL      R/W    [3:0] mode per channel: 1 = Hz, 0 = ms
//                          [7:4] IRQ enable per channel: 1 = enabled
//   1      ST       R/W1C  [3:0] pending flag per channel (write 1 to clear)
//                          [4]   BUSY (read only): Hz divider is running
//   2..4   CONF0    R/W    channel 0 config, 24 bits: byte 0 (LSB) at 2, byte 2 at 4
//   5..7   CONF1    R/W    channel 1 config
//   8..10  CONF2    R/W    channel 2 config
//   11..13 CONF3    R/W    channel 3 config
//   14, 15          reserved, read 0
//
// Channel period
//   conf == 0        channel disabled (no events, counter held at 0)
//   ms mode (0)      period = conf milliseconds. The ms tick is a shared
//                    prescaler, CLK_HZ/1000 clocks, so the channel counts ticks.
//   Hz mode (1)      period = CLK_HZ / conf clocks. A shared sequential divider
//                    computes this once per config write, 25 clocks per divide.
//
//   The Hz period is latched when its divide finishes. A Hz channel does not
//   fire until the latched value is valid. ST[4] (BUSY) is 1 while the divider
//   runs. The divider starts on the final byte (byte 2) of a config write, so a
//   partially written value never reaches it.
//
//   Pending divide requests are a 4-bit mask, one bit per channel. A second
//   write to a channel that is already pending merges into the same bit, and
//   the divider reads conf when it starts. A write that arrives during a divide
//   sets the bit again, so the channel is recomputed afterwards.
//
//   CLK_HZ must be a multiple of 1000 for exact ms periods, and below 2^24 for
//   the Hz divider. Periods are 24 bits, so the longest period is 2^24 - 1 ticks
//   (ms) or clocks (Hz).
//
// Each event occurs once per full period.
//
// If an event and a clear land on the same clock, the event wins and the flag
// stays set.

`timescale 1ns / 1ps

module timer6502 #(
  parameter CLK_HZ = 1_000_000 	 // system clock frequency in Hz (must be < 2^24)
) (
  input  wire       clk,
  input  wire       rst_n,       // synchronous, active-low reset
  input  wire       cs,          // chip select (from address decoder)
  input  wire       we,          // 1 = write, 0 = read
  input  wire [3:0] addr,        // register offset
  input  wire [7:0] din,         // write data
  output reg  [7:0] dout,        // read data (combinational)
  output wire       irq_n        // active-low: asserted while any enabled flag is set
);

  localparam [3:0]  OFF_CTL  = 4'd0;
  localparam [3:0]  OFF_ST   = 4'd1;
  localparam [23:0] CLK_HZ24 = CLK_HZ;
  localparam        MS_DIV   = CLK_HZ / 1000;          // clocks per millisecond
  localparam        MSW      = (MS_DIV > 2) ? $clog2(MS_DIV) : 1;
  localparam        MS_LAST  = MS_DIV - 1;

  reg  [7:0]  ctl;
  reg  [3:0]  st;
  reg  [3:0]  req;               // channel needs its Hz period recomputed
  reg  [3:0]  hz_rdy;            // Hz period is valid (computed since last request)
  reg  [23:0] conf   [0:3];
  reg  [23:0] cnt    [0:3];
  reg  [23:0] per_hz [0:3];      // latched Hz periods (clocks)

  // Shared 1 ms tick
  reg  [MSW-1:0] ms_div;
  wire           ms_tick = (ms_div == MS_LAST[MSW-1:0]);

  // Shared restoring divider: quotient = CLK_HZ / conf
  reg         dv_busy;
  reg  [1:0]  dv_ch;
  reg  [23:0] dv_rem;            // remainder is always below the divisor
  reg  [23:0] dv_q;
  reg  [23:0] dv_d;
  reg  [4:0]  dv_i;

  integer     g;

  // Config address decode: {channel[1:0], byte[1:0]} for addresses 2..13
  function [3:0] cfg_map;
    input [3:0] a;
    begin
      case (a)
        4'd2:  cfg_map = 4'b0000;
        4'd3:  cfg_map = 4'b0001;
        4'd4:  cfg_map = 4'b0010;
        4'd5:  cfg_map = 4'b0100;
        4'd6:  cfg_map = 4'b0101;
        4'd7:  cfg_map = 4'b0110;
        4'd8:  cfg_map = 4'b1000;
        4'd9:  cfg_map = 4'b1001;
        4'd10: cfg_map = 4'b1010;
        4'd11: cfg_map = 4'b1100;
        4'd12: cfg_map = 4'b1101;
        4'd13: cfg_map = 4'b1110;
        default: cfg_map = 4'b0000;
      endcase
    end
  endfunction

  // Bus decode
  wire       wr      = cs & we;
  wire       rd      = cs & ~we;
  wire       is_cfg  = (addr >= 4'd2) && (addr <= 4'd13);
  wire [3:0] cmap    = cfg_map(addr);
  wire [3:0] clr_w   = (wr && addr == OFF_ST) ? din[3:0] : 4'd0;

  // Requests: a config write to byte 2 of channel n, or a switch of channel n
  // from ms to Hz, asks for its Hz period to be recomputed.
  wire [3:0] req_set;
  assign req_set[0] = (wr && is_cfg && cmap == 4'b0010) || (wr && addr == OFF_CTL && din[0] && !ctl[0]);
  assign req_set[1] = (wr && is_cfg && cmap == 4'b0110) || (wr && addr == OFF_CTL && din[1] && !ctl[1]);
  assign req_set[2] = (wr && is_cfg && cmap == 4'b1010) || (wr && addr == OFF_CTL && din[2] && !ctl[2]);
  assign req_set[3] = (wr && is_cfg && cmap == 4'b1110) || (wr && addr == OFF_CTL && din[3] && !ctl[3]);

  // Pick the lowest pending request when the divider is idle
  wire       any_req = |req;
  wire [1:0] sel     = req[0] ? 2'd0 : req[1] ? 2'd1 : req[2] ? 2'd2 : 2'd3;
  wire       pop     = !dv_busy && any_req;
  wire       go      = pop && ctl[{1'b0, sel}] && (conf[sel] != 24'd0);

  // Restoring divider step (one quotient bit per clock)
  wire [24:0] rem_sh   = {dv_rem, dv_q[23]};
  wire        ge       = (rem_sh >= {1'b0, dv_d});
  wire [23:0] rem_diff = rem_sh[23:0] - dv_d;
  wire [23:0] rem_n    = ge ? rem_diff : rem_sh[23:0];
  wire [23:0] q_n      = {dv_q[22:0], ge};

  // Per-channel target, terminal count and event
  wire [3:0] fire_w;
  genvar k;
  generate
    for (k = 0; k < 4; k = k + 1) begin : g_ch
      wire        inc    = ctl[k] | ms_tick;               // Hz: every clock; ms: every tick
      wire [23:0] target = ctl[k] ? per_hz[k] : conf[k];   // clocks (Hz) or ticks (ms)
      wire [23:0] lastw  = (target == 24'd0) ? 24'd0 : (target - 24'd1);
      // A Hz channel does not fire until its divider result is valid.
      assign fire_w[k] = (conf[k] != 24'd0) && (!ctl[k] || hz_rdy[k]) && inc && (cnt[k] >= lastw);
    end
  endgenerate

  // ------------------------------------------------------------------
  // Counters, divider, sticky flags, and bus writes
  // ------------------------------------------------------------------
  always @(posedge clk) begin
    if (!rst_n) begin
      ctl     <= 8'd0;
      st      <= 4'd0;
      req     <= 4'd0;
      hz_rdy  <= 4'd0;
      ms_div  <= {MSW{1'b0}};
      dv_busy <= 1'b0;
      dv_ch   <= 2'd0;
      dv_rem  <= 24'd0;
      dv_q    <= 24'd0;
      dv_d    <= 24'd0;
      dv_i    <= 5'd0;
      for (g = 0; g < 4; g = g + 1) begin
        conf[g]   <= 24'd0;
        cnt[g]    <= 24'd0;
        per_hz[g] <= 24'd0;
      end
    end else begin
      ms_div <= ms_tick ? {MSW{1'b0}} : ms_div + {{(MSW-1){1'b0}}, 1'b1};

      for (g = 0; g < 4; g = g + 1) begin
          if (conf[g] == 24'd0 || fire_w[g])
              cnt[g] <= 24'd0;
          else if (ctl[g] | ms_tick)
              cnt[g] <= cnt[g] + 24'd1;
      end

      // Divider
      if (dv_busy) begin
        dv_rem <= rem_n;
        dv_q   <= q_n;
        dv_i   <= dv_i - 5'd1;
        if (dv_i == 5'd1) begin
          dv_busy          <= 1'b0;
          per_hz[dv_ch]    <= q_n;
        end
      end else if (go) begin
        dv_busy <= 1'b1;
        dv_ch   <= sel;
        dv_rem  <= 24'd0;
        dv_q    <= CLK_HZ24;
        dv_d    <= conf[sel];
        dv_i    <= 5'd24;
      end

      // A head request is popped whether or not it starts a divide.
      // A request raised on the same clock is kept.
      req <= (req & ~(pop ? (4'd1 << sel) : 4'd0)) | req_set;

      // Hz ready: set when a divide completes, cleared by a new request.
      // A request on the same clock as a completion wins.
      hz_rdy <= ((hz_rdy | (dv_busy && dv_i == 5'd1 ? (4'd1 << dv_ch) : 4'd0)) & ~req_set);

      if (wr && addr == OFF_CTL) ctl <= din;
      if (wr && is_cfg) conf[cmap[3:2]][8*cmap[1:0] +: 8] <= din;

      st <= (st & ~clr_w) | fire_w;
    end
  end

  // ------------------------------------------------------------------
  // Combinational read mux (no side effects)
  // ------------------------------------------------------------------
  always @(*) begin
    dout = 8'h00;
    if (rd) begin
      if (addr == OFF_CTL) dout = ctl;
      else if (addr == OFF_ST) dout = {3'd0, dv_busy, st};
      else if (is_cfg) dout = conf[cmap[3:2]][8*cmap[1:0] +: 8];
    end
  end

  assign irq_n = ~|(st & ctl[7:4]);

endmodule

// Controller for IS61LPS12836A SRAM for single (non-burst) reads and writes
//   It is pipelined SRAM with 2 or 3 stages (for single write or read, correspondingly):
//     - ADSC pulse to latch address
//     - GW/BWE pulse to set kind of operation and latch data (for writes)
//     - Data capture (for reads)

module sram_controller (
  input wire clk,
  input wire rst_n,

  // internal interface
  input  wire [15:0] addr,
  input  wire [15:0] wdata,
  input  wire        wr,
  input  wire        rd,
  output reg  [15:0] rdata,
  output reg         valid,
  output reg         busy,

  // SRAM Interface
                     output wire        sram_clk_io,
  (* IOB = "TRUE" *) output reg  [15:0] sram_addr_io,
  (* IOB = "TRUE" *) inout  wire [15:0] sram_data_io,

  (* IOB = "TRUE" *) output reg sram_we_n_io,
  (* IOB = "TRUE" *) output reg sram_adsc_n_io,
  (* IOB = "TRUE" *) output reg sram_oe_n_io
);

  wire req = (wr | rd);

  // registered inputs
  reg [15:0] wdata_s;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) wdata_s <= 0;
    else wdata_s <= wdata;
  end

  // state for FSM: IDLE -> issue ADSC -> issue GW -> wait data (1 cycle) -> capture data -> back to IDLE
  reg  [4:0] state;

  wire       in_idle = state[0];
  wire       in_issue_adsc = state[1];
  wire       in_issue_gw = state[2];
  wire       in_data_valid = state[4];

  reg        is_write_l;
  wire       latch_write_flag = in_idle && req;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      is_write_l <= 0;
    end
    else if (latch_write_flag) begin
      is_write_l <= wr;
    end
  end

  reg data_oe;
  assign sram_data_io = data_oe ? wdata_s : {16{1'bz}};
  assign sram_oe_n_io = data_oe;

  // FSM
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= 5'b00001;  // IDLE
    end
    else begin
      if (in_idle) begin
        state <= req ? 5'b00010 : 5'b00001;
      end
      else begin
        if (in_data_valid) state <= 5'b00001;  // back IDLE
        else state <= (state << 1);
      end
    end
  end

  // Outputs / SRAM control
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sram_addr_io   <= 0;
      sram_adsc_n_io <= 1;
      sram_we_n_io   <= 1;

      data_oe        <= 0;
      rdata          <= 0;
      valid          <= 0;
      busy           <= 0;
    end
    else begin
      // always capture data bus, valid signal is set when we actually have read data
      rdata          <= sram_data_io;
      // always outputs address
      sram_addr_io   <= addr;

      busy           <= !in_idle || req;
      valid          <= in_data_valid;

      sram_adsc_n_io <= !in_issue_adsc;
      // we don't need to rely on SRAM OE signal, we can just assert "write" signal one cycle earlier to avoid bus contention
      sram_we_n_io   <= (is_write_l && (in_issue_adsc || in_issue_gw)) ? 0 : 1;
      // data should be outputted earlier, because wdata_s is clocked by FPGA clock
      // but SRAM expects data to be seen on it's own rising edge
      data_oe        <= is_write_l && (in_issue_adsc || in_issue_gw);
    end
  end

`ifdef ICE40
  // inverted clock (180deg phase shift)
  //   signals are outputed on the rising edge of the FPGA clock, but we want to have some time to
  //   stabilize them before raising edge of the SRAM clock
  SB_IO #(
    .PIN_TYPE(6'b010000),  // PIN_OUTPUT_DDR
    .PULLUP(1'b0),
    .NEG_TRIGGER(1'b0),
    .IO_STANDARD("SB_LVCMOS")
  ) sram_clk_driver (
    .PACKAGE_PIN  (sram_clk_io),
    .OUTPUT_CLK   (clk),
    .CLOCK_ENABLE (1'b1),
    .INPUT_CLK    (1'b0),
    .OUTPUT_ENABLE(1'b1),
    .D_OUT_0      (1'b0),         // Rising Edge Data: Drive 0
    .D_OUT_1      (1'b1),         // Falling Edge Data: Drive 1
    .D_IN_0       (),
    .D_IN_1       ()
  );
`else
  assign sram_clk_io = clk;
`endif

endmodule

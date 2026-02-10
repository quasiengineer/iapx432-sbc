module sram_mux (
  input wire clk,   // 250Mhz
  input wire rst_n,

  // Internal interface (from core logic)
  input  wire        req0,
  input  wire        req1,
  input  wire [15:0] addr0,
  input  wire [15:0] addr1,
  input  wire [15:0] wdata0,
  input  wire [15:0] wdata1,
  input  wire        wr0,
  input  wire        wr1,
  input  wire        rd0,
  input  wire        rd1,
  output reg  [15:0] rdata0,
  output reg  [15:0] rdata1,
  output             valid,
  output             busy,

  // SRAM interface
  output reg  [15:0] sram_addr_io,
  inout  wire [15:0] sram_data_io,
  output reg         sram_we_n_io,
  output reg         sram_adsc_n_io,
  output reg         sram_clk_io
);

  reg wr, rd;
  reg [15:0] addr;
  reg [15:0] wdata;
  // registered inputs to controller to shorten combinational path
  reg wr_r, rd_r;
  reg [15:0] addr_r;
  reg [15:0] wdata_r;
  wire [15:0] rdata;
  reg sel;

  sram_controller controller (
    .clk(clk),
    .rst_n(rst_n),
    .addr(addr_r),
    .wdata(wdata_r),
    .wr(wr_r),
    .rd(rd_r),
    .rdata(rdata),
    .valid(valid),
    .busy(busy),
    .sram_addr_io(sram_addr_io),
    .sram_data_io(sram_data_io),
    .sram_we_n_io(sram_we_n_io),
    .sram_adsc_n_io(sram_adsc_n_io),
    .sram_clk_io(sram_clk_io)
  );

  // main routing logic
  always @(*) begin
    // avoid latches
    wr = 0;
    rd = 0;
    addr = 0;
    wdata = 0;

    if (req0) begin
      wr = wr0;
      rd = rd0;
      addr = addr0;
      wdata = wdata0;
    end
    else if (req1) begin
      wr = wr1;
      rd = rd1;
      addr = addr1;
      wdata = wdata1;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_r    <= 1'b0;
      rd_r    <= 1'b0;
      addr_r  <= {16{1'b0}};
      wdata_r <= {16{1'b0}};
    end
    else begin
      wr_r    <= wr;
      rd_r    <= rd;
      addr_r  <= addr;
      wdata_r <= wdata;
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      rdata0 <= {16{1'b0}};
      rdata1 <= {16{1'b0}};
    end
    else begin
      rdata0 <= valid ? rdata : rdata0;
      rdata1 <= valid ? rdata : rdata1;
    end
  end

endmodule

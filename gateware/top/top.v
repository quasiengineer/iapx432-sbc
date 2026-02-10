module top (
    input         CLK_250,

    // SRAM interface
    inout  [15:0] SRAM_D,
    output [15:0] SRAM_A,
    output        SRAM_STROBE,
    output        SRAM_WR,
    output        SRAM_OE,
    output        SRAM_CLK,

    // GDP interface
    input         BOUT,
    input         FATAL,
    input         PRQ,
    output        PCLK,
    output        CLR,
    output        INIT,
    output        ICS,
    output        CLKA,
    output        CLKB,
    output        ACD_DIRECTION,
    inout [15:0]  ACD,

    input         UART_RX,
    output        UART_TX,
    output        LED
);

  // clock generation
  wire clk_50;
  wire rst_n;
  wire clka;
  wire clkb;
  clock_gen u_clock_gen (
    .clk_250(CLK_250),
    .clk_50(clk_50),
    .rst_n(rst_n),
    .clka(clka),
    .clkb(clkb)
  );
  assign CLKA = clka;
  assign CLKB = clkb;

  // LED flickering
  reg [24:0] counter;
  always @(posedge clk_50) counter <= counter + 1;
  assign LED = ~counter[24];

  // PCLK/ generator (1 kHz, active-low pulse)
  localparam integer PCLK_DIV = 5000; // 5 MHz / 5000 = 1 kHz
  reg [12:0] pclk_div;
  reg pclk_n;
  always @(posedge clka or negedge rst_n) begin
    if (!rst_n) begin
      pclk_div <= 13'd0;
      pclk_n   <= 1'b1;
    end
    else begin
      if (pclk_div == PCLK_DIV - 1) pclk_div <= 13'd0;
      else pclk_div <= pclk_div + 1'b1;
      pclk_n <= (pclk_div == 13'd0) ? 1'b0 : 1'b1;
    end
  end
  assign PCLK = pclk_n;

  // access log storage
  wire [9:0]  u_log_addr;
  wire [23:0] u_log_data_in;
  wire [23:0] u_log_data_out;
  wire u_log_wr, u_log_rd, u_log_data_valid;
  wire log_wr;
  wire [7:0] log_type;
  wire [15:0] log_addr;
  bram_log #(
    .ADDR_WIDTH(10)
  ) log_storage (
    .clk(clk_50),
    .rst_n(rst_n),
    .u_addr(u_log_addr),
    .u_data_in(u_log_data_in),
    .u_wr(u_log_wr),
    .u_rd(u_log_rd),
    .u_data_out(u_log_data_out),
    .u_data_valid(u_log_data_valid),
    .log_write_clk(clkb),
    .log_wr(log_wr),
    .log_type(log_type),
    .log_addr(log_addr),
    .trigger_init(gdp_trigger_init)
  );

  // ====================================================================================================
  // UART control module (50Mhz) -> CDC bridge -> SRAM mux port 0 (250 Mhz) -> SRAM controller (250 Mhz)
  // GDP memory controller (5Mhz) -> CDC bridge -> SRAM mux port 1 (250 Mhz) -> SRAM controller (250 Mhz)
  // ====================================================================================================

  // SRAM multiplexer ports
  wire sram_req0, sram_req1;
  wire sram_wr0, sram_wr1;
  wire sram_rd0, sram_rd1;
  wire [15:0] sram_addr0;
  wire [15:0] sram_addr1;
  wire [15:0] sram_wdata0;
  wire [15:0] sram_wdata1;
  wire [15:0] sram_rdata0;
  wire [15:0] sram_rdata1;
  // SRAM multiplexer generic outputs
  wire sram_valid;
  wire sram_busy;

  // SRAM signals for UART control module
  wire sram_u_req;
  wire sram_u_wr;
  wire sram_u_rd;
  wire [15:0] sram_u_addr;
  wire [15:0] sram_u_wdata;
  wire [15:0] sram_u_rdata;
  wire sram_u_valid;
  wire sram_u_busy;

  // SRAM signals for GDP memory controller
  wire sram_g_req;
  wire sram_g_wr;
  wire sram_g_rd;
  wire [15:0] sram_g_addr;
  wire [15:0] sram_g_wdata;
  wire [15:0] sram_g_rdata;
  wire sram_g_valid;
  wire sram_g_busy;

  sram_mux sram_ctrl (
    .clk(CLK_250),
    .rst_n(rst_n),
    .req0(sram_req0),
    .wr0(sram_wr0),
    .rd0(sram_rd0),
    .addr0(sram_addr0),
    .wdata0(sram_wdata0),
    .rdata0(sram_rdata0),
    .req1(sram_req1),
    .wr1(sram_wr1),
    .rd1(sram_rd1),
    .addr1(sram_addr1),
    .wdata1(sram_wdata1),
    .rdata1(sram_rdata1),
    .valid(sram_valid),
    .busy(sram_busy),
    .sram_addr_io(SRAM_A),
    .sram_data_io(SRAM_D),
    .sram_we_n_io(SRAM_WR),
    .sram_adsc_n_io(SRAM_STROBE),
    .sram_clk_io(SRAM_CLK)
  );

  // XXX: SRAM OE is always low (active), SRAM controller does not use it, could be changed later
  assign SRAM_OE = 1'b0;

  // CDC bridge from 50 MHz control to 250 MHz SRAM (port0)
  sram_uart_cdc_bridge sram_uart_cdc (
    .u_clk(clk_50),
    .u_rst_n(rst_n),
    .u_req(sram_u_req),
    .u_wr_req(sram_u_wr),
    .u_rd_req(sram_u_rd),
    .u_addr(sram_u_addr),
    .u_wdata(sram_u_wdata),
    .u_rdata(sram_u_rdata),
    .u_done(sram_u_valid),
    .u_busy(sram_u_busy),
    .s_clk(CLK_250),
    .s_rst_n(rst_n),
    .s_req(sram_req0),
    .s_wr_req(sram_wr0),
    .s_rd_req(sram_rd0),
    .s_addr(sram_addr0),
    .s_wdata(sram_wdata0),
    .s_rdata(sram_rdata0),
    .s_valid(sram_valid)
  );

  control_interface control_interface (
    .clk(clk_50),
    .rst_n(rst_n),
    .uart_rx_io(UART_RX),
    .uart_tx_io(UART_TX),
    .sram_req(sram_u_req),
    .sram_wr(sram_u_wr),
    .sram_rd(sram_u_rd),
    .sram_addr(sram_u_addr),
    .sram_rdata(sram_u_rdata),
    .sram_wdata(sram_u_wdata),
    .sram_busy(sram_u_busy),
    .sram_data_valid(sram_u_valid),
    .u_log_addr(u_log_addr),
    .u_log_data_in(u_log_data_in),
    .u_log_data_out(u_log_data_out),
    .u_log_data_valid(u_log_data_valid),
    .u_log_wr(u_log_wr),
    .u_log_rd(u_log_rd),
    .gdp_trigger_init(gdp_trigger_init)
  );

  sram_gdp_cdc_bridge sram_gdp_cdc (
    .gdp_req(sram_g_req),
    .gdp_wr_req(sram_g_wr),
    .gdp_rd_req(sram_g_rd),
    .gdp_addr(sram_g_addr),
    .gdp_wdata(sram_g_wdata),
    .gdp_rdata(sram_g_rdata),
    .gdp_done(sram_g_valid),
    .gdp_busy(sram_g_busy),
    .s_clk(CLK_250),
    .s_rst_n(rst_n),
    .s_req(sram_req1),
    .s_wr_req(sram_wr1),
    .s_rd_req(sram_rd1),
    .s_addr(sram_addr1),
    .s_wdata(sram_wdata1),
    .s_rdata(sram_rdata1),
    .s_valid(sram_valid),
    .s_busy(sram_busy)
  );

  // GDP wiring
  reg gdp_trigger_init;
  gdp_interface gdp (
    .u_clk(clk_50),
    .rst_n(rst_n),
    .led_io(LED),
    .clka(clka),
    .clkb(clkb),
    .bout_io(BOUT),
    .fatal_io(FATAL),
    .prq_io(PRQ),
    .acd_io(ACD),
    .acd_direction_io(ACD_DIRECTION),
    .clr_io(CLR),
    .init_io(INIT),
    .ics_io(ICS),
    .sram_req(sram_g_req),
    .sram_wr(sram_g_wr),
    .sram_rd(sram_g_rd),
    .sram_addr(sram_g_addr),
    .sram_rdata(sram_g_rdata),
    .sram_wdata(sram_g_wdata),
    .sram_busy(sram_g_busy),
    .sram_data_valid(sram_g_valid),
    .log_wr(log_wr),
    .log_type(log_type),
    .log_addr(log_addr),
    .trigger_init(gdp_trigger_init)
  );

endmodule

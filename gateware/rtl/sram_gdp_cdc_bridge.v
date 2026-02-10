module sram_gdp_cdc_bridge (
  // GDP Domain (slow)
  input  wire        gdp_req,
  input  wire        gdp_wr_req,  // Pulse
  input  wire        gdp_rd_req,  // Pulse
  input  wire [15:0] gdp_addr,
  input  wire [15:0] gdp_wdata,
  output reg  [15:0] gdp_rdata,
  output reg         gdp_done,    // Pulse when operation finishes
  output wire        gdp_busy,    // High during operation

  // SRAM Domain (fast)
  input  wire        s_clk,
  input  wire        s_rst_n,
  output reg         s_req,
  output reg         s_wr_req,  // Pulse
  output reg         s_rd_req,  // Pulse
  output reg  [15:0] s_addr,
  output reg  [15:0] s_wdata,
  input  wire [15:0] s_rdata,
  input  wire        s_valid,   // Pulse
  input  wire        s_busy
);

  // regular 2-FF synchronizer for gdp_req
  reg req_sync0, req_sync1;
  always @(posedge s_clk or negedge s_rst_n) begin
    if (!s_rst_n) begin
      s_req <= 0;
    end
    else begin
      req_sync0 <= gdp_req;
      req_sync1 <= req_sync0;
      s_req <= req_sync1;
    end
  end

  // Synchronize inputs to fast clock domain
  reg [15:0] gdp_addr_sync1, gdp_addr_sync2;
  reg gdp_req_sync1, gdp_req_sync2, gdp_req_sync3;
  reg gdp_wr_sync1, gdp_wr_sync2;
  reg gdp_rd_sync1, gdp_rd_sync2;
  reg [15:0] gdp_wdata_sync1, gdp_wdata_sync2;

  always @(posedge s_clk or negedge s_rst_n) begin
    if (~s_rst_n) begin
      gdp_req_sync1 <= 0;
      gdp_req_sync2 <= 0;
      gdp_req_sync3 <= 0;
      gdp_addr_sync1 <= 0;
      gdp_addr_sync2 <= 0;
      gdp_wr_sync1 <= 0;
      gdp_wr_sync2 <= 0;
      gdp_rd_sync1 <= 0;
      gdp_rd_sync2 <= 0;
      gdp_wdata_sync1 <= 0;
      gdp_wdata_sync2 <= 0;
    end
    else begin
      gdp_req_sync1 <= gdp_wr_req | gdp_rd_req;
      gdp_req_sync2 <= gdp_req_sync1;
      gdp_req_sync3 <= gdp_req_sync2;
      gdp_addr_sync1 <= gdp_addr;
      gdp_addr_sync2 <= gdp_addr_sync1;
      gdp_wr_sync1 <= gdp_wr_req;
      gdp_wr_sync2 <= gdp_wr_sync1;
      gdp_rd_sync1 <= gdp_rd_req;
      gdp_rd_sync2 <= gdp_rd_sync1;
      gdp_wdata_sync1 <= gdp_wdata;
      gdp_wdata_sync2 <= gdp_wdata_sync1;
    end
  end

  wire gdp_req_rising = gdp_req_sync2 & ~gdp_req_sync3;

  reg processing;
  reg [15:0] last_addr;  // Still kept for potential future use, but not in condition
  reg [15:0] data_out_int;
  reg valid_int;
  reg busy_int;

  always @(posedge s_clk or negedge s_rst_n) begin
    if (~s_rst_n) begin
      processing <= 0;
      last_addr <= 0;
      data_out_int <= 0;
      valid_int <= 0;
      busy_int <= 0;
      s_wr_req <= 0;
      s_rd_req <= 0;
      s_addr <= 0;
      s_wdata <= 0;
    end
    else begin
      s_wr_req <= 0;
      s_rd_req <= 0;
      if (gdp_req_rising) begin
        if (processing) begin
          // retry, do nothing (removed addr check)
        end
        else begin
          last_addr <= gdp_addr_sync2;
          busy_int <= 1;
          valid_int <= 0;
          processing <= 1;
          s_addr <= gdp_addr_sync2;
          s_wr_req <= gdp_wr_sync2;
          s_rd_req <= gdp_rd_sync2;
          s_wdata <= gdp_wdata_sync2;
        end
      end
      if (processing) begin
        if (gdp_rd_sync2) begin
          if (s_valid) begin
            data_out_int <= s_rdata;
            valid_int <= 1;
            busy_int <= 0;
            processing <= 0;
          end
        end
        else begin
          if (~s_busy) begin
            busy_int   <= 0;
            processing <= 0;
          end
        end
      end
      if (~processing && ~gdp_req_sync2) begin
        valid_int <= 0;
      end
    end
  end

  // Directly use fast domain signals in slow domain (assuming synchronous domains)
  assign gdp_busy = busy_int;
  assign gdp_done = valid_int;
  assign gdp_rdata = data_out_int;
endmodule
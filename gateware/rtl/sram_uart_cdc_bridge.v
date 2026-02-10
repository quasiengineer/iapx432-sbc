module sram_uart_cdc_bridge (
  // UART Domain (slow)
  input  wire        u_clk,
  input  wire        u_rst_n,
  input  wire        u_req,
  input  wire        u_wr_req,  // Pulse
  input  wire        u_rd_req,  // Pulse
  input  wire [15:0] u_addr,
  input  wire [15:0] u_wdata,
  output reg  [15:0] u_rdata,
  output reg         u_done,    // Pulse when operation finishes
  output reg         u_busy,    // High during operation

  // SRAM Domain (fast)
  input  wire        s_clk,
  input  wire        s_rst_n,
  output reg         s_req,
  output reg         s_wr_req,  // Pulse
  output reg         s_rd_req,  // Pulse
  output reg  [15:0] s_addr,
  output reg  [15:0] s_wdata,
  input  wire [15:0] s_rdata,
  input  wire        s_valid    // Pulse
);

  // ============================================================
  // 1. UART -> SRAM (Request Path)
  // ============================================================
  reg req_toggle_u;
  reg req_meta_s, req_sync_s, req_prev_s;

  reg [15:0] u_addr_hold;
  reg [15:0] u_wdata_hold;
  reg        u_is_read_hold;

  // UART Side
  always @(posedge u_clk or negedge u_rst_n) begin
    if (!u_rst_n) begin
      u_busy <= 0;
      req_toggle_u <= 0;
      u_addr_hold <= 0;
      u_wdata_hold <= 0;
      u_is_read_hold <= 0;
    end
    else begin
      if (u_done) begin
        u_busy <= 0;
      end
      else if ((u_wr_req || u_rd_req) && !u_busy) begin
        u_busy <= 1;
        u_addr_hold <= u_addr;
        u_wdata_hold <= u_wdata;
        u_is_read_hold <= u_rd_req;
        req_toggle_u <= ~req_toggle_u;
      end
    end
  end


  // regular 2-FF synchronizer for u_req
  reg req_sync0, req_sync1;
  always @(posedge s_clk or negedge s_rst_n) begin
    if (!s_rst_n) begin
      s_req <= 0;
    end
    else begin
      req_sync0 <= u_req;
      req_sync1 <= req_sync0;
      s_req <= req_sync1;
    end
  end

  // SRAM Side
  always @(posedge s_clk or negedge s_rst_n) begin
    if (!s_rst_n) begin
      req_meta_s <= 0;
      req_sync_s <= 0;
      req_prev_s <= 0;
      s_wr_req <= 0;
      s_rd_req <= 0;
      s_addr <= 0;
      s_wdata <= 0;
    end
    else begin
      req_meta_s <= req_toggle_u;
      req_sync_s <= req_meta_s;
      req_prev_s <= req_sync_s;

      s_wr_req <= 0;
      s_rd_req <= 0;

      if (req_sync_s != req_prev_s) begin
        s_addr  <= u_addr_hold;
        s_wdata <= u_wdata_hold;
        if (u_is_read_hold) s_rd_req <= 1;
        else s_wr_req <= 1;
      end
    end
  end

  // ============================================================
  // 2. SRAM -> UART (Response Path)
  // ============================================================
  reg data_valid_toggle_s;
  reg data_valid_sync0, data_valid_sync1, data_valid_sync2;
  reg [15:0] s_rdata_hold;

  // SRAM Side
  always @(posedge s_clk or negedge s_rst_n) begin
    if (!s_rst_n) begin
      data_valid_toggle_s <= 0;
      s_rdata_hold <= 0;
    end
    else begin
      if (s_valid) begin
        s_rdata_hold <= s_rdata;
        data_valid_toggle_s <= ~data_valid_toggle_s;
      end
    end
  end

  // UART Side
  always @(posedge u_clk or negedge u_rst_n) begin
    if (!u_rst_n) begin
      data_valid_sync0 <= 0;
      data_valid_sync1 <= 0;
      data_valid_sync2 <= 0;
      u_done <= 0;
      u_rdata <= 0;
    end
    else begin
      data_valid_sync0 <= data_valid_toggle_s;
      data_valid_sync1 <= data_valid_sync0;
      data_valid_sync2 <= data_valid_sync1;

      u_done <= 0;
      if (data_valid_sync1 != data_valid_sync2) begin
        u_rdata <= s_rdata_hold;
        u_done  <= 1;
      end
    end
  end

endmodule

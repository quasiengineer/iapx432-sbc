module sram_cdc_bridge (
  // Target domain (slow)
  input  wire        tgt_clk,
  input  wire        tgt_rst_n,
  input  wire        tgt_req,
  input  wire        tgt_wr_req,  // Pulse
  input  wire        tgt_rd_req,  // Pulse
  input  wire [15:0] tgt_addr,
  input  wire [15:0] tgt_wdata,
  output reg  [15:0] tgt_rdata,
  output reg         tgt_done,    // Pulse when operation finishes
  output reg         tgt_busy,    // High during operation

  // SRAM domain (fast)
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
  // 1. Target -> SRAM (Request Path)
  // ============================================================
  reg req_toggle_u;
  reg req_meta_s, req_sync_s, req_prev_s;

  reg [15:0] tgt_addr_hold;
  reg [15:0] tgt_wdata_hold;
  reg        tgt_is_read_hold;

  always @(posedge tgt_clk or negedge tgt_rst_n) begin
    if (!tgt_rst_n) begin
      tgt_busy <= 0;
      req_toggle_u <= 0;
      tgt_addr_hold <= 0;
      tgt_wdata_hold <= 0;
      tgt_is_read_hold <= 0;
    end
    else begin
      if (tgt_done) begin
        tgt_busy <= 0;
      end
      else if ((tgt_wr_req || tgt_rd_req) && !tgt_busy) begin
        tgt_busy <= 1;
        tgt_addr_hold <= tgt_addr;
        tgt_wdata_hold <= tgt_wdata;
        tgt_is_read_hold <= tgt_rd_req;
        req_toggle_u <= ~req_toggle_u;
      end
    end
  end


  // regular 2-FF synchronizer for tgt_req
  reg req_sync0, req_sync1;
  always @(posedge s_clk or negedge s_rst_n) begin
    if (!s_rst_n) begin
      s_req <= 0;
    end
    else begin
      req_sync0 <= tgt_req;
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
        s_addr  <= tgt_addr_hold;
        s_wdata <= tgt_wdata_hold;
        if (tgt_is_read_hold) s_rd_req <= 1;
        else s_wr_req <= 1;
      end
    end
  end

  // ============================================================
  // 2. SRAM -> Target (Response Path)
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

  // Target side
  always @(posedge tgt_clk or negedge tgt_rst_n) begin
    if (!tgt_rst_n) begin
      data_valid_sync0 <= 0;
      data_valid_sync1 <= 0;
      data_valid_sync2 <= 0;
      tgt_done <= 0;
      tgt_rdata <= 0;
    end
    else begin
      data_valid_sync0 <= data_valid_toggle_s;
      data_valid_sync1 <= data_valid_sync0;
      data_valid_sync2 <= data_valid_sync1;

      tgt_done <= 0;
      if (data_valid_sync1 != data_valid_sync2) begin
        tgt_rdata <= s_rdata_hold;
        tgt_done  <= 1;
      end
    end
  end
endmodule

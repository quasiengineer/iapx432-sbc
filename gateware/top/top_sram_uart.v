// Simple UART interface:
//   - Heartbeat: send 0xAA every 2s (toggleable with cmd 0x01)
//   - Cmd 0x01               : toggle heartbeat enable/disable
//   - Cmd 0x02 aH aL dH dL   : write 16-bit data to 16-bit address
//   - Cmd 0x03 aH aL         : read 16-bit data from 16-bit address (TX high byte then low byte)
//   - Cmd 0x04               : ping (respond with 0xEE)
module top_sram_uart (
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
  wire clk_50;
  wire rst_n;
  clock_gen u_clock_gen (
    .clk_250(CLK_250),
    .clk_50(clk_50),
    .rst_n  (rst_n)
  );

  reg clk_25, clk_12, clk_6;
  always @(posedge clk_50) clk_25 <= ~clk_25;
  always @(posedge clk_25) clk_12 <= ~clk_12;
  always @(posedge clk_12) clk_6 <= ~clk_6;
  // wire        sram_ctrl_clk = CLK_250;
  wire        sram_ctrl_clk = clk_50;
  wire        uart_clk = clk_50;

  localparam UART_FREQ = 50_000_000;

  wire [15:0] sram_data_out;
  wire        sram_valid;
  wire        sram_busy;
  reg         sram_wr_req;
  reg         sram_rd_req;
  reg  [15:0] sram_addr;
  reg  [15:0] sram_data;

  sram_controller u_sram_controller (
    .clk(sram_ctrl_clk),
    .rst_n(rst_n),
    .addr(sram_addr),
    .wdata(sram_data),
    .wr(sram_wr_req),
    .rd(sram_rd_req),
    .rdata(sram_data_out),
    .valid(sram_valid),
    .busy(sram_busy),
    .sram_addr_io(SRAM_A),
    .sram_data_io(SRAM_D),
    .sram_we_n_io(SRAM_WR),
    .sram_adsc_n_io(SRAM_STROBE),
    .sram_clk_io(SRAM_CLK)
  );

  reg         u_sram_req;
  reg         u_sram_wr_req;
  reg         u_sram_rd_req;
  reg  [15:0] u_sram_addr;
  reg  [15:0] u_sram_wdata;
  wire [15:0] u_sram_rdata;
  wire        u_sram_done;
  wire        u_sram_busy;
  sram_uart_cdc_bridge u_sram_cdc_bridge (
    // UART side
    .u_clk(uart_clk),
    .u_rst_n(rst_n),
    .u_req(u_sram_req),
    .u_wr_req(u_sram_wr_req),
    .u_rd_req(u_sram_rd_req),
    .u_addr(u_sram_addr),
    .u_wdata(u_sram_wdata),
    .u_rdata(u_sram_rdata),
    .u_done(u_sram_done),
    .u_busy(u_sram_busy),
    // SRAM side
    .s_clk(sram_ctrl_clk),
    .s_rst_n(rst_n),
    .s_wr_req(sram_wr_req),
    .s_rd_req(sram_rd_req),
    .s_addr(sram_addr),
    .s_wdata(sram_data),
    .s_rdata(sram_data_out),
    .s_valid(sram_valid)
  );


  // ------------------------------------------------------------
  // UART RX
  // ------------------------------------------------------------
  wire [7:0] rx_byte;
  wire       rx_valid;
  wire       rx_busy;
  uart_rx #(
    .CLK_FREQ(UART_FREQ),
    .BAUD_RATE(115200)
  ) u_uart_rx (
    .clk(uart_clk),
    .rst_n(rst_n),
    .rx_io(UART_RX),
    .data_out(rx_byte),
    .data_valid(rx_valid),
    .busy(rx_busy)
  );

  // ------------------------------------------------------------
  // Heartbeat generator (1s)
  // ------------------------------------------------------------
  localparam integer HB_DIV = UART_FREQ;
  reg [31:0] hb_ctr;
  reg        hb_tick;
  reg        hb_en;

  always @(posedge uart_clk or negedge rst_n) begin
    if (!rst_n) begin
      hb_ctr  <= 0;
      hb_tick <= 1'b0;
    end
    else begin
      hb_tick <= 1'b0;
      if (hb_ctr == HB_DIV - 1) begin
        hb_ctr  <= 0;
        hb_tick <= 1;
      end
      else begin
        hb_ctr <= hb_ctr + 1;
      end
    end
  end

  // ------------------------------------------------------------
  // Command parser (UART RX side)
  // ------------------------------------------------------------
  localparam CMD_IDLE = 3'd0, CMD_WR_AH = 3'd1, CMD_WR_AL = 3'd2, CMD_WR_DH = 3'd3, CMD_WR_DL = 3'd4, CMD_RD_AH = 3'd5, CMD_RD_AL = 3'd6;
  localparam CMD_TYPE_OTHER = 2'd0, CMD_TYPE_READ = 2'd1, CMD_TYPE_WRITE = 2'd2, CMD_TYPE_PING = 2'd3;

  reg [2:0] cmd_state;
  reg [1:0] cmd_type;
  reg       cmd_resp_req;
  reg       cmd_resp_ack;

  always @(posedge uart_clk or negedge rst_n) begin
    if (!rst_n) begin
      cmd_state     <= CMD_IDLE;
      u_sram_wr_req <= 1'b0;
      u_sram_rd_req <= 1'b0;
      u_sram_addr   <= 16'h0000;
      u_sram_wdata  <= 16'h0000;
      hb_en         <= 1'b1;
      cmd_type      <= CMD_TYPE_OTHER;
      cmd_resp_req  <= 1'b0;
    end
    else begin
      u_sram_req    <= 1'b1;
      u_sram_rd_req <= 1'b0;
      u_sram_wr_req <= 1'b0;

      if (cmd_resp_ack) cmd_resp_req <= 1'b0;

      if (rx_valid) begin
        case (cmd_state)
          CMD_IDLE: begin
            if (rx_byte) cmd_type <= CMD_TYPE_OTHER;

            case (rx_byte)
              8'h01:   hb_en <= ~hb_en;  // toggle heartbeat
              8'h02:   cmd_state <= CMD_WR_AH;  // write command
              8'h03:   cmd_state <= CMD_RD_AH;  // read command
              8'h04: begin
                cmd_type <= CMD_TYPE_PING;  // ping command
                cmd_resp_req <= 1'b1;
              end
              default: cmd_state <= CMD_IDLE;
            endcase
          end
          CMD_WR_AH: begin
            u_sram_addr[15:8] <= rx_byte;
            cmd_state <= CMD_WR_AL;
          end
          CMD_WR_AL: begin
            u_sram_addr[7:0] <= rx_byte;
            cmd_state <= CMD_WR_DH;
          end
          CMD_WR_DH: begin
            u_sram_wdata[15:8] <= rx_byte;
            cmd_state <= CMD_WR_DL;
          end
          CMD_WR_DL: begin
            u_sram_wdata[7:0] <= rx_byte;
            u_sram_wr_req <= 1'b1;
            cmd_type <= CMD_TYPE_WRITE;
            cmd_resp_req <= 1'b1;
            cmd_state <= CMD_IDLE;
          end
          CMD_RD_AH: begin
            u_sram_addr[15:8] <= rx_byte;
            cmd_state <= CMD_RD_AL;
          end
          CMD_RD_AL: begin
            u_sram_addr[7:0] <= rx_byte;
            u_sram_rd_req <= 1'b1;
            cmd_type <= CMD_TYPE_READ;
            cmd_resp_req <= 1'b1;
            cmd_state <= CMD_IDLE;
          end
          default: cmd_state <= CMD_IDLE;
        endcase
      end
    end
  end

  // ------------------------------------------------------------
  // UART TX queue (small 3-byte queue for responses/heartbeat)
  // Priority: command responses > heartbeat
  // ------------------------------------------------------------
  reg [7:0] tx_q0, tx_q1, tx_q2;
  reg  [1:0] tx_count;  // 0..3
  reg        uart_send;
  reg  [7:0] uart_data;
  wire       uart_busy;
  uart_tx #(
    .CLK_FREQ (UART_FREQ),
    .BAUD_RATE(115200)
  ) u_uart_tx (
    .clk(uart_clk),
    .rst_n(rst_n),
    .data_in(uart_data),
    .send(uart_send),
    .busy(uart_busy),
    .tx_io(UART_TX)
  );

  reg tx_wait;
  // enqueue helper tasks in behavioral style
  always @(posedge uart_clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_q0 <= 8'h0;
      tx_q1 <= 8'h0;
      tx_q2 <= 8'h0;
      tx_count <= 2'd0;
      uart_send <= 1'b0;
      uart_data <= 1'b0;
      cmd_resp_ack <= 1'b0;
    end
    else begin
      uart_send <= 1'b0;
      cmd_resp_ack <= 1'b0;

      if (tx_count == 0) begin
        if (cmd_resp_req) begin
          // Enqueue command responses (overwrite heartbeat queue if idle)
          if (cmd_type == CMD_TYPE_WRITE && u_sram_done) begin
            tx_q0    <= 8'hAC; // write ack
            tx_q1    <= 8'h0;
            tx_q2    <= 8'h0;
            tx_count <= 2'd1;
            cmd_resp_ack <= 1'b1;
          end
          else if (cmd_type == CMD_TYPE_READ && u_sram_done) begin
            tx_q0    <= u_sram_rdata[15:8];
            tx_q1    <= u_sram_rdata[7:0];
            tx_q2    <= 8'h0;
            tx_count <= 2'd2;
            cmd_resp_ack <= 1'b1;
          end
          else if (cmd_type == CMD_TYPE_PING) begin
            tx_q0    <= 8'hEE; // write response for the ping command
            tx_q1    <= 8'h0;
            tx_q2    <= 8'h0;
            tx_count <= 2'd1;
            cmd_resp_ack <= 1'b1;
          end
        end
        // Heartbeat only if no pending response
        else if (hb_en && hb_tick) begin
          tx_q0    <= 8'hAA;
          tx_q1    <= 8'h0;
          tx_q2    <= 8'h0;
          tx_count <= 2'd1;
        end
      end

      // 1-cycle delay to let busy flag to be set by UART tranmitter
      if (tx_wait) tx_wait <= 1'b0;
      else if (tx_count != 0 && !uart_busy) begin
        uart_data <= tx_q0;
        uart_send <= 1'b1;
        // Shift queue
        tx_q0 <= tx_q1;
        tx_q1 <= tx_q2;
        tx_q2 <= 8'h0;
        tx_count <= tx_count - 1'b1;
        tx_wait <= 1'b1;
      end
    end
  end
endmodule

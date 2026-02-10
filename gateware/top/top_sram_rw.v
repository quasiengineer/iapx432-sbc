// Simple top-level self-test:
// - write some data to address specific address in SRAM, then read it back
// - cross the read value into 50 MHz domain and send over UART once per 2 seconds
module top_sram_rw (
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

  reg [4:0] sram_clk_ctr;
  always @(posedge clk_50 or negedge rst_n) begin
    if (!rst_n) sram_clk_ctr <= 0;
    else sram_clk_ctr <= sram_clk_ctr + 1'b1;
  end
  // wire sram_ctrl_clk = sram_clk_ctr[4];  // 3.125Mhz
  // wire sram_ctrl_clk = clk_50; // 50Mhz
  wire sram_ctrl_clk = CLK_250; // 250Mhz

  localparam [15:0] TEST_ADDR = 16'hFF11;
  localparam [15:0] TEST_DATA = 16'hFFAA;

//  wire [15:0] addr_req = TEST_ADDR;
  reg  [15:0] addr_req;
  wire [15:0] data_req = TEST_DATA;

  wire [15:0] sram_data_out;
  wire        sram_valid;
  wire        sram_busy;
  wire        wr_req;
  wire        rd_req;

  sram_controller u_sram_controller (
    .clk(sram_ctrl_clk),
    .rst_n(rst_n),
    .addr(addr_req),
    .wdata(data_req),
    .wr(wr_req),
    .rd(rd_req),
    .rdata(sram_data_out),
    .valid(sram_valid),
    .busy(sram_busy),
    .sram_addr_io(SRAM_A),
    .sram_data_io(SRAM_D),
    .sram_we_n_io(SRAM_WR),
    .sram_adsc_n_io(SRAM_STROBE),
    .sram_clk_io(SRAM_CLK),
    .sram_oe_n_io(SRAM_OE)
  );

  localparam S_IDLE = 3'd0,
             S_WRITE_REQ = 3'd1,
             S_WRITE_WAIT = 3'd2,
             S_WRITE_GAP = 3'd3,
             S_READ_REQ = 3'd4,
             S_READ_WAIT = 3'd5,
             S_DONE = 3'd6;

  reg [15:0] read_reg;

  reg [ 2:0] state;
  reg [ 4:0] wr_gap_ctr;
  always @(posedge sram_ctrl_clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;
      read_reg <= 0;
      addr_req <= 16'hFF11;
    end
    else begin
      wr_req <= 0;
      rd_req <= 0;
      wr_gap_ctr <= wr_gap_ctr << 1;
      read_reg <= (state == S_READ_WAIT && sram_valid) ? sram_data_out : read_reg;
      addr_req <= state >= S_WRITE_GAP ? 16'hFF22 : 16'hFF11;
      // addr_req <= state >= S_WRITE_GAP ? 16'hFF11 : 16'hFF11;

      case (state)
        S_IDLE: state <= sram_busy ? S_IDLE : S_WRITE_REQ;

        S_WRITE_REQ: begin
          wr_req <= 1;
          state  <= S_WRITE_WAIT;
        end

        S_WRITE_WAIT: begin
          if (!sram_busy) begin
            state <= S_WRITE_GAP;
            wr_gap_ctr <= 5'b00001;
          end
        end

        // wait few cycles between write and read operations
        S_WRITE_GAP: begin
          state <= wr_gap_ctr == 0 ? S_READ_REQ : S_WRITE_GAP;
        end

        S_READ_REQ: begin
          rd_req <= 1;
          state  <= S_READ_WAIT;
        end

        S_READ_WAIT: begin
          if (sram_valid) begin
            state <= S_DONE;
          end
        end
      endcase
    end
  end

  wire data_toggle = state == S_DONE;

  // 2-ff sync
  (* ASYNC_REG="TRUE" *) reg t_sync1, t_sync2, t_sync3;
  (* ASYNC_REG="TRUE" *) reg [15:0] r_sync1, r_sync2;

  reg        data_latched;
  reg [15:0] read_reg_sync;
  always @(posedge clk_50 or negedge rst_n) begin
    if (!rst_n) begin
      t_sync1       <= 1'b0;
      t_sync2       <= 1'b0;
      t_sync3       <= 1'b0;
      r_sync1       <= 16'h0000;
      r_sync2       <= 16'h0000;
      data_latched  <= 1'b0;
      read_reg_sync <= 16'h0000;
    end
    else begin
      t_sync1 <= data_toggle;
      t_sync2 <= t_sync1;
      t_sync3 <= t_sync2;

      r_sync1 <= read_reg;
      r_sync2 <= r_sync1;

      if (t_sync2 ^ t_sync3) begin
        read_reg_sync <= r_sync2;
        data_latched  <= 1'b1;
      end
    end
  end

  localparam integer UART_HZ_DIV = 100_000_000;  // 2 second at 50 MHz
  reg [31:0] uart_div_ctr;
  reg        tick_05hz;

  always @(posedge clk_50 or negedge rst_n) begin
    if (!rst_n) begin
      uart_div_ctr <= 0;
      tick_05hz    <= 1'b0;
    end
    else begin
      if (uart_div_ctr == UART_HZ_DIV - 1) begin
        uart_div_ctr <= 0;
        tick_05hz    <= 1'b1;
      end
      else begin
        uart_div_ctr <= uart_div_ctr + 1'b1;
        tick_05hz    <= 1'b0;
      end
    end
  end

  wire uart_busy;
  reg uart_send;
  reg [7:0] uart_data;
  reg [2:0] uart_phase;  // 0 idle, 1 send high, 2 gap, 3 send low, 4 gap

  uart_tx #(
    .CLK_FREQ (50_000_000),
    .BAUD_RATE(115200)
  ) u_uart_tx (
    .clk(clk_50),
    .rst_n(rst_n),
    .data_in(uart_data),
    .send(uart_send),
    .busy(uart_busy),
    .tx_io(UART_TX)
  );

  always @(posedge clk_50 or negedge rst_n) begin
    if (!rst_n) begin
      uart_phase <= 0;
      uart_send  <= 0;
      uart_data  <= 8'h00;
    end
    else begin
      uart_send <= 0;

      case (uart_phase)
        0: begin
          if (data_latched && tick_05hz && !uart_busy) begin
            uart_data  <= read_reg_sync[15:8];
            uart_send  <= 1;
            uart_phase <= 1;
          end
        end
        1: uart_phase <= 2;
        2: begin
          if (!uart_busy) begin
            uart_data  <= read_reg_sync[7:0];
            uart_send  <= 1;
            uart_phase <= 3;
          end
        end
        3: uart_phase <= 4;
        4: begin
          if (!uart_busy) begin
            uart_phase <= 0;
          end
        end
        default: uart_phase <= 0;
      endcase
    end
  end
endmodule

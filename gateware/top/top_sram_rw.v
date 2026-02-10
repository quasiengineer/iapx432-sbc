// Simple top-level self-test:
// - write some data to address specific address in SRAM, then read it back
// - cross the read value into 50 MHz domain and send over UART once per 2 seconds
module top_sram_rw (
  input CLK_250,

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
  inout  [15:0] ACD,

  input  UART_RX,
  output UART_TX,
  output LED
);
  wire clk_50;
  wire clk_125;
  wire rst_n;
  clock_gen u_clock_gen (
    .clk_250(CLK_250),
    .clk_125(clk_125),
    .clk_50 (clk_50),
    .rst_n  (rst_n)
  );

  reg [4:0] sram_clk_ctr;
  always @(posedge clk_50 or negedge rst_n) begin
    if (!rst_n) sram_clk_ctr <= 0;
    else sram_clk_ctr <= sram_clk_ctr + 1'b1;
  end
  wire sram_ctrl_clk = clk_125;  // 125Mhz

  localparam [15:0] TEST_ADDR0 = 16'h1111;
  localparam [15:0] TEST_DATA0 = 16'hAAAA;
  localparam [15:0] TEST_ADDR1 = 16'h2222;
  localparam [15:0] TEST_DATA1 = 16'hBBBB;

  reg  [15:0] sram_addr;
  reg  [15:0] sram_wdata;
  wire [15:0] sram_rdata;
  wire        sram_valid;
  wire        sram_busy;
  wire        wr_req;
  wire        rd_req;

  sram_controller u_sram_controller (
    .clk(sram_ctrl_clk),
    .rst_n(rst_n),
    .addr(sram_addr),
    .wdata(sram_wdata),
    .wr(wr_req),
    .rd(rd_req),
    .rdata(sram_rdata),
    .valid(sram_valid),
    .busy(sram_busy),
    .sram_addr_io(SRAM_A),
    .sram_data_io(SRAM_D),
    .sram_we_n_io(SRAM_WR),
    .sram_adsc_n_io(SRAM_STROBE),
    .sram_clk_io(SRAM_CLK),
    .sram_oe_n_io(SRAM_OE)
  );

  localparam S_IDLE = 4'd0,
             S_WRITE_REQ0 = 4'd1,
             S_WRITE_WAIT0 = 4'd2,
             S_WRITE_GAP0 = 4'd3,
             S_WRITE_REQ1 = 4'd4,
             S_WRITE_WAIT1 = 4'd5,
             S_WRITE_GAP1 = 4'd6,
             S_READ_REQ = 4'd7,
             S_READ_WAIT = 4'd8,
             S_DONE = 4'd9;

  reg [15:0] read_reg;

  reg [ 3:0] state;
  reg [ 7:0] wr_gap_ctr;
  always @(posedge sram_ctrl_clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;
      read_reg <= 0;
      sram_addr <= 0;
      sram_wdata <= 0;
    end
    else begin
      wr_req <= 0;
      rd_req <= 0;
      wr_gap_ctr <= wr_gap_ctr << 1;

      case (state)
        S_IDLE: state <= sram_busy ? S_IDLE : S_WRITE_REQ0;

        S_WRITE_REQ0: begin
          sram_addr <= TEST_ADDR0;
          sram_wdata <= TEST_DATA0;
          wr_req <= 1;
          state  <= S_WRITE_WAIT0;
        end

        S_WRITE_WAIT0: begin
          if (!sram_busy) begin
            state <= S_WRITE_GAP0;
            wr_gap_ctr <= 8'b00000001;
          end
        end

        // wait few cycles between write operations
        S_WRITE_GAP0: begin
          state <= wr_gap_ctr == 0 ? S_WRITE_REQ1 : S_WRITE_GAP0;
        end

        S_WRITE_REQ1: begin
          sram_addr <= TEST_ADDR1;
          sram_wdata <= TEST_DATA1;
          wr_req <= 1;
          state  <= S_WRITE_WAIT1;
        end

        S_WRITE_WAIT1: begin
          if (!sram_busy) begin
            state <= S_WRITE_GAP1;
            wr_gap_ctr <= 8'b00000001;
          end
        end

        // wait few cycles between write and read operations
        S_WRITE_GAP1: begin
          state <= wr_gap_ctr == 0 ? S_READ_REQ : S_WRITE_GAP1;
        end

        S_READ_REQ: begin
          sram_addr <= TEST_ADDR0;
          rd_req <= 1;
          state  <= S_READ_WAIT;
        end

        S_READ_WAIT: begin
          if (sram_valid) begin
            read_reg <= sram_data_out;
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

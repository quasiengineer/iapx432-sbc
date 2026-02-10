module top_blinky (
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
  clock_gen u_clock_gen (
    .clk_250(CLK_250),
    .clk_50(clk_50),
    .rst_n(rst_n)
  );

  // LED flickering
  reg [24:0] counter;
  always @(posedge clk_50) counter <= counter + 1;
  assign LED = ~counter[24];

  // UART heartbeat

  localparam integer UART_HZ_DIV = 200_000_000;  // 4 seconds at 50 MHz
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
  reg [2:0] uart_phase;

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

  wire [7:0] rx_byte;
  wire       rx_valid;
  wire       rx_busy;
  uart_rx #(
    .CLK_FREQ (50_000_000),
    .BAUD_RATE(115200)
  ) u_uart_rx (
    .clk(clk_50),
    .rst_n(rst_n),
    .rx_io(UART_RX),
    .data_out(rx_byte),
    .data_valid(rx_valid),
    .busy(rx_busy)
  );

  reg [7:0] latched_data;
  always @(posedge clk_50 or negedge rst_n) begin
    if (!rst_n) latched_data <= 8'hAA;
    else latched_data <= rx_valid ? rx_byte : latched_data;
  end

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
          if (tick_05hz && !uart_busy) begin
            uart_data  <= latched_data;
            uart_send  <= 1;
            uart_phase <= 1;
          end
        end
        1: uart_phase <= 2;
        2: begin
          if (!uart_busy) begin
            uart_phase <= 0;
          end
        end
      endcase
    end
  end

endmodule

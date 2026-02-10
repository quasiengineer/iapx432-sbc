module top_acd_test (
    input         CLK_250,
    input         UART_RX,
    output        UART_TX,
    output        LED,
    output        ACD_DIRECTION,
    inout [15:0]  ACD,

    // unused here, but want to avoid errors
    input         SRAM_STROBE,
    input         SRAM_CLK,
    input         SRAM_OE,
    input         SRAM_WR,
    input  [15:0] SRAM_A,
    inout  [15:0] SRAM_D,
    input         PCLK,
    input         CLR,
    input         INIT,
    input         ICS,
    input         BOUT,
    input         FATAL,
    input         PRQ,
    input         CLKA,
    input         CLKB
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

  wire uart_busy;
  reg uart_send;
  reg [7:0] uart_data;
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

  reg [2:0] uart_phase;
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
          if (rx_valid) begin
            case (rx_byte)
              8'h01: begin
                ACD_DIRECTION <= 1;
                ACD <= 16'hAA55;
              end

              8'h02: begin
                ACD_DIRECTION <= 0;
              end

              8'h03: begin
                uart_data <= ACD[7:0];
                uart_send <= 1;
                uart_phase <= 1;
              end

              8'h04: begin
                uart_data <= ACD[15:8];
                uart_send <= 1;
                uart_phase <= 1;
              end

              8'h05: begin
                uart_data <= 8'hBB;
                uart_send <= 1;
                uart_phase <= 1;
              end
            endcase
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

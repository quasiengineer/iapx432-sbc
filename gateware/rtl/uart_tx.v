module uart_tx #(
  parameter CLK_FREQ  = 50_000_000,
  parameter BAUD_RATE = 115200
) (
  input clk,
  input rst_n,
  input [7:0] data_in,
  input send,
  output reg busy,

  output reg tx_io
);
  localparam CLK_PER_BIT = CLK_FREQ / BAUD_RATE;

  reg [ 3:0] bit_index;
  reg [ 8:0] tx_data;
  reg [11:0] clk_counter;

  always @(posedge clk) begin
    if (!rst_n) begin
      tx_io <= 1;
      busy <= 0;
      bit_index <= 0;
      clk_counter <= 0;
    end
    else begin
      if (busy) begin
        if (clk_counter == CLK_PER_BIT - 1) begin
          clk_counter <= 0;
          if (bit_index < 9) begin
            tx_io <= tx_data[bit_index];
            bit_index <= bit_index + 1;
          end
          else begin
            busy  <= 0;
            tx_io <= 1;
          end
        end
        else begin
          clk_counter <= clk_counter + 1;
        end
      end
      else if (send) begin
        busy <= 1;
        tx_data <= {1'b1, data_in};
        bit_index <= 0;
        clk_counter <= 0;
        tx_io <= 0;
      end
    end
  end
endmodule

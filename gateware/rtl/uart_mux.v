module uart_tx_mux (
  input wire uart_clk,
  input wire rst_n,

  input wire [7:0] data0,
  input wire       req0,
  input wire [7:0] data1,
  input wire       req1,

  output wire tx_busy,
  output wire uart_tx_io
);
  reg [7:0] tx_data;
  reg tx_send = 0;

  uart_tx uart_transmitter (
    .clk(uart_clk),
    .rst_n(rst_n),
    .data_in(tx_data),
    .send(tx_send),
    .tx_io(uart_tx_io),
    .busy(tx_busy)
  );

  always @(*) begin
    if (req0) begin
      tx_data = data0;
      tx_send = 1;
    end
    else if (req1) begin
      tx_data = data1;
      tx_send = 1;
    end
    else begin
      tx_send = 0;
      tx_data = 0;
    end
  end
endmodule

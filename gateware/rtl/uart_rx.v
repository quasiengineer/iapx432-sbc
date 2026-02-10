module uart_rx #(
  parameter CLK_FREQ  = 50_000_000,
  parameter BAUD_RATE = 115200
) (
  input wire clk,
  input wire rst_n,

  input  wire       rx_io,
  output reg  [7:0] data_out,
  output reg        data_valid,
  output reg        busy
);

  localparam CLK_PER_BIT = CLK_FREQ / BAUD_RATE;
  localparam CLK_PER_HALF_BIT = CLK_PER_BIT / 2;

  reg rx_sync1, rx_sync2;
  always @(posedge clk) begin
    rx_sync1 <= rx_io;
    rx_sync2 <= rx_sync1;
  end

  localparam [1:0] IDLE = 2'd0;
  localparam [1:0] START = 2'd1;
  localparam [1:0] DATA = 2'd2;
  localparam [1:0] STOP = 2'd3;

  reg [ 1:0] state;
  reg [ 3:0] bit_idx;  // 0..7
  reg [ 7:0] shift_reg;
  reg [15:0] cnt;  // enough bits for 50 MHz / 115200 ≈ 434

  always @(posedge clk) begin
    if (!rst_n) begin
      state      <= IDLE;
      data_valid <= 1'b0;
      busy       <= 1'b0;
      bit_idx    <= 4'd0;
      cnt        <= 16'd0;
      shift_reg  <= 8'd0;
      data_out   <= 8'd0;
    end
    else begin
      data_valid <= 1'b0;  // one-cycle pulse only

      case (state)
        IDLE: begin
          busy    <= 1'b0;
          bit_idx <= 4'd0;
          cnt     <= 16'd0;

          if (rx_sync2 == 1'b0) begin  // start bit detected (low)
            busy  <= 1'b1;
            state <= START;
          end
        end

        START: begin  // wait half-bit to sample in the middle of start bit
          if (cnt == CLK_PER_HALF_BIT - 1) begin
            cnt <= 16'd0;
            if (rx_sync2 == 1'b0) begin  // genuine start bit
              state <= DATA;
            end
            else begin  // noise/glitch → abort
              state <= IDLE;
            end
          end
          else begin
            cnt <= cnt + 1'd1;
          end
        end

        DATA: begin
          if (cnt == CLK_PER_BIT - 1) begin
            cnt <= 16'd0;
            shift_reg[bit_idx] <= rx_sync2;

            if (bit_idx == 4'd7) begin
              bit_idx <= 4'd0;
              state   <= STOP;
            end
            else begin
              bit_idx <= bit_idx + 1'd1;
            end
          end
          else begin
            cnt <= cnt + 1'd1;
          end
        end

        STOP: begin
          if (cnt == CLK_PER_BIT - 1) begin
            cnt <= 16'd0;

            if (rx_sync2 == 1'b1) begin  // valid stop bit
              data_out   <= shift_reg;
              data_valid <= 1'b1;
            end
            // if stop bit is low → framing error, we just ignore the byte
            state <= IDLE;
          end
          else begin
            cnt <= cnt + 1'd1;
          end
        end

        default: state <= IDLE;

      endcase
    end
  end

endmodule

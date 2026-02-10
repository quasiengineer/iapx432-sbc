module control_interface (
  input wire clk,   // 50Mhz
  input wire rst_n,

  // UART interface
  input  uart_rx_io,
  output uart_tx_io,

  // SRAM interface (16-bit wide external SRAM; UART still moves 8-bit payloads)
  output reg         sram_req,
  output reg         sram_wr,
  output reg         sram_rd,
  output reg  [15:0] sram_addr,
  output reg  [15:0] sram_wdata,
  input  wire [15:0] sram_rdata,
  input  wire        sram_busy,
  input  wire        sram_data_valid,

  // UART log access to BRAM
  output reg [ 9:0] u_log_addr,
  output reg [23:0] u_log_data_in,
  input      [23:0] u_log_data_out,
  input             u_log_data_valid,
  output reg        u_log_wr,
  output reg        u_log_rd,

  // signals to GDP interface
  output reg gdp_trigger_init
);
  wire [7:0] uart_rx_data;
  wire uart_rx_valid;
  wire uart_rx_busy;
  uart_rx uart_receiver (
    .clk(clk),
    .rst_n(rst_n),
    .rx_io(uart_rx_io),
    .data_out(uart_rx_data),
    .data_valid(uart_rx_valid),
    .busy(uart_rx_busy)
  );

  reg [7:0] uart_tx_data;
  reg uart_tx_req;
  wire uart_tx_busy;
  uart_tx uart_transmitter (
    .clk(clk),
    .rst_n(rst_n),
    .data_in(uart_tx_data),
    .send(uart_tx_req),
    .busy(uart_tx_busy),
    .tx_io(uart_tx_io)
  );

  // output command opcodes
  localparam CMD_OUT_ACK = 8'h01, CMD_OUT_RESULT = 8'h02, CMD_OUT_ERR = 8'hFF;

  // input command opcodes
  localparam CMD_IN_WRITE_DUMP = 8'h01,
             CMD_IN_WRITE_BYTE = 8'h02,
             CMD_IN_READ_BYTE = 8'h03,
             CMD_IN_LOG_WR = 8'h10,
             CMD_IN_LOG_RD = 8'h11,
             CMD_IN_PING = 8'h80,
             CMD_IN_GDP_START = 8'h81;

  // common command FSM
  localparam CMD_STATE_IDLE = 3'd0,
             CMD_STATE_READ_DATA = 3'd1,
             CMD_STATE_READY = 3'd2,
             CMD_STATE_FINISHED = 3'd3,
             CMD_STATE_ACKED = 3'd4,
             CMD_STATE_ERROR = 3'd5;

  // FSM for READ_DATA command
  localparam CMD_READ_DATA_STATE_RAM_REQ = 4'd0, CMD_READ_DATA_STATE_DATA = 4'd1,
        CMD_READ_DATA_STATE_UART_OPCODE = 4'd2, CMD_READ_DATA_STATE_UART_OPCODE_SENT = 4'd3, CMD_READ_DATA_STATE_UART_DATA = 4'd4, CMD_READ_DATA_STATE_UART_DATA_SENT = 4'd5;

  // FSM for WRITE_DATA command
  localparam CMD_WRITE_DATA_STATE_RAM_REQ = 4'd0, CMD_WRITE_DATA_STATE_DATA = 4'd1;

  // FSM for WRITE_DUMP command
  localparam CMD_WRITE_DUMP_STATE_READ_DATA = 4'd0, CMD_WRITE_DUMP_STATE_WRITE_MEM = 4'd1, CMD_WRITE_DUMP_STATE_WRITTEN = 4'd2;

  // FSM for LOG_RD
  localparam LOG_RD_REQ       = 5'd0,
             LOG_RD_OPCODE    = 5'd1,
             LOG_RD_OPCODE_GAP= 5'd2,
             LOG_RD_TYPE      = 5'd3,
             LOG_RD_TYPE_GAP  = 5'd4,
             LOG_RD_ADDR_HI   = 5'd5,
             LOG_RD_ADDR_HI_GAP = 5'd6,
             LOG_RD_ADDR_LO   = 5'd7,
             LOG_RD_ADDR_LO_GAP = 5'd8;

  // FSM for LOG_WR
  localparam LOG_WR_WRITE = 5'd0, LOG_WR_DONE = 5'd1;

  reg [ 2:0] in_state;
  reg [ 4:0] in_cmd_state;
  reg [ 7:0] in_cmd_opcode;
  reg [15:0] in_cmd_addr;
  reg [ 7:0] in_cmd_value;
  reg [ 2:0] in_byte_count;
  reg [23:0] in_log_value;
  reg [23:0] log_rd_data;
  reg        log_rd_valid;

  localparam [7:0] LOG_TYPE_WRITE = 8'h01;
  localparam [7:0] LOG_TYPE_READ = 8'h02;

  always @(posedge clk) begin
    if (!rst_n) begin
      in_state <= CMD_STATE_IDLE;
      in_byte_count <= 0;
      in_cmd_state <= 0;
      in_cmd_opcode <= 0;
      in_cmd_addr <= 0;
      in_cmd_value <= 0;
      in_log_value <= 0;
      log_rd_data <= 0;
      log_rd_valid <= 1'b0;
      sram_rd <= 0;
      sram_wr <= 0;
      u_log_wr <= 0;
      u_log_rd <= 0;
    end
    else begin
      // pulses
      gdp_trigger_init <= 0;
      u_log_wr <= 0;
      u_log_rd <= 0;

      if (u_log_data_valid) begin
        log_rd_data  <= u_log_data_out;
        log_rd_valid <= 1'b1;
      end
      case (in_state)
        CMD_STATE_IDLE: begin
          sram_req <= 0;
          in_byte_count <= 0;
          // assume that first state for each command is idle state
          in_cmd_state <= 0;

          if (uart_rx_valid) begin
            sram_req <= 1;
            in_cmd_opcode <= uart_rx_data;
            // commands without parameters
            if (uart_rx_data[7] == 1'b1) in_state <= CMD_STATE_READY;
            else in_state <= CMD_STATE_READ_DATA;
          end
        end

        CMD_STATE_READ_DATA: begin
          // WRITE_DUMP 0x01 size1 size0 data[N] data[N-1] .... data[1] data[0]
          if (in_cmd_opcode == CMD_IN_WRITE_DUMP && in_byte_count == 2) begin
            case (in_cmd_state)
              CMD_WRITE_DUMP_STATE_READ_DATA: begin
                if (uart_rx_valid) begin
                  in_cmd_value <= uart_rx_data;
                  in_cmd_addr  <= in_cmd_addr - 1;
                  in_cmd_state <= CMD_WRITE_DUMP_STATE_WRITE_MEM;
                end
              end

              CMD_WRITE_DUMP_STATE_WRITE_MEM: begin
                sram_wdata <= {8'h00, in_cmd_value};  // lower byte used for UART writes
                sram_wr <= 1;
                sram_rd <= 0;
                sram_addr <= in_cmd_addr;
                if (!sram_busy) begin
                  in_cmd_state <= CMD_WRITE_DUMP_STATE_WRITTEN;
                end
              end

              CMD_WRITE_DUMP_STATE_WRITTEN: begin
                sram_wr <= 0;

                if (in_cmd_addr == 0) in_state <= CMD_STATE_FINISHED;
                else in_cmd_state <= CMD_WRITE_DUMP_STATE_READ_DATA;
              end
            endcase
          end
          else if (uart_rx_valid) begin
            if (in_byte_count == 0) in_cmd_addr[15:8] <= uart_rx_data;
            else if (in_byte_count == 1) begin
              in_cmd_addr[7:0] <= uart_rx_data;
              if (in_cmd_opcode == CMD_IN_READ_BYTE || in_cmd_opcode == CMD_IN_LOG_RD)
                in_state <= CMD_STATE_READY;
            end
            else if (in_cmd_opcode == CMD_IN_LOG_WR) begin
              if (in_byte_count == 2) in_log_value[23:16] <= uart_rx_data;
              else if (in_byte_count == 3) in_log_value[15:8] <= uart_rx_data;
              else begin
                in_log_value[7:0] <= uart_rx_data;
                in_state <= CMD_STATE_READY;
              end
            end
            else begin
              in_cmd_value <= uart_rx_data;
              in_state <= CMD_STATE_READY;
            end

            in_byte_count <= in_byte_count + 1;
          end
        end

        CMD_STATE_READY: begin
          case (in_cmd_opcode)
            // PING 0x80
            CMD_IN_PING: begin
              in_state <= CMD_STATE_FINISHED;
            end

            // GDP_START 0x81
            CMD_IN_GDP_START: begin
              gdp_trigger_init <= 1;
              in_state <= CMD_STATE_FINISHED;
            end

            // WRITE_BYTE 0x02 addr1 addr0 data0
            CMD_IN_WRITE_BYTE: begin
              case (in_cmd_state)
                CMD_WRITE_DATA_STATE_RAM_REQ: begin
                  sram_wdata <= {8'h00, in_cmd_value};
                  sram_wr <= 1;
                  sram_rd <= 0;
                  sram_addr <= in_cmd_addr;
                  if (!sram_busy) begin
                    in_cmd_state <= CMD_WRITE_DATA_STATE_DATA;
                  end
                end

                CMD_WRITE_DATA_STATE_DATA: begin
                  sram_wr  <= 0;
                  in_state <= CMD_STATE_FINISHED;
                end
              endcase
            end

            // READ_BYTE 0x03 addr1 addr0
            CMD_IN_READ_BYTE: begin
              case (in_cmd_state)
                CMD_READ_DATA_STATE_RAM_REQ: begin
                  if (!sram_busy) begin
                    sram_addr <= in_cmd_addr;
                    sram_rd <= 1;
                    in_cmd_state <= CMD_READ_DATA_STATE_DATA;
                  end
                end

                CMD_READ_DATA_STATE_DATA: begin
                  sram_rd <= 0;
                  if (sram_data_valid) begin
                    in_cmd_state <= CMD_READ_DATA_STATE_UART_OPCODE;
                  end
                end

                CMD_READ_DATA_STATE_UART_OPCODE: begin
                  // read data from SRAM one cycle after valid pulse
                  in_cmd_value <= sram_rdata[7:0];

                  if (!uart_tx_busy) begin
                    uart_tx_data <= CMD_OUT_RESULT;
                    uart_tx_req  <= 1;
                    in_cmd_state <= CMD_READ_DATA_STATE_UART_OPCODE_SENT;
                  end
                end

                CMD_READ_DATA_STATE_UART_OPCODE_SENT: begin
                  uart_tx_req  <= 0;
                  in_cmd_state <= CMD_READ_DATA_STATE_UART_DATA;
                end

                CMD_READ_DATA_STATE_UART_DATA: begin
                  if (!uart_tx_busy) begin
                    uart_tx_data <= in_cmd_value;
                    uart_tx_req  <= 1;
                    in_cmd_state <= CMD_READ_DATA_STATE_UART_DATA_SENT;
                  end
                end

                CMD_READ_DATA_STATE_UART_DATA_SENT: begin
                  uart_tx_req <= 0;
                  in_state <= CMD_STATE_FINISHED;
                end
              endcase
            end

            // LOG_RD 0x11 addr1 addr0 -> returns 3 bytes (type, addr_hi, addr_lo)
            CMD_IN_LOG_RD: begin
              case (in_cmd_state)
                LOG_RD_REQ: begin
                  u_log_addr <= in_cmd_addr[9:0];
                  u_log_rd <= 1;
                  log_rd_valid <= 1'b0;
                  in_cmd_state <= LOG_RD_OPCODE;
                end
                LOG_RD_OPCODE: begin
                  u_log_rd <= 0;
                  if (!uart_tx_busy) begin
                    uart_tx_data <= CMD_OUT_RESULT;
                    uart_tx_req  <= 1;
                    in_cmd_state <= LOG_RD_OPCODE_GAP;
                  end
                end
                LOG_RD_OPCODE_GAP: begin
                  uart_tx_req  <= 0;
                  in_cmd_state <= LOG_RD_TYPE;
                end
                LOG_RD_TYPE: begin
                  if (!uart_tx_busy && log_rd_valid) begin
                    uart_tx_data <= log_rd_data[23:16];
                    uart_tx_req  <= 1;
                    in_cmd_state <= LOG_RD_TYPE_GAP;
                  end
                end
                LOG_RD_TYPE_GAP: begin
                  uart_tx_req  <= 0;
                  in_cmd_state <= LOG_RD_ADDR_HI;
                end
                LOG_RD_ADDR_HI: begin
                  if (!uart_tx_busy) begin
                    uart_tx_data <= log_rd_data[15:8];
                    uart_tx_req  <= 1;
                    in_cmd_state <= LOG_RD_ADDR_HI_GAP;
                  end
                end
                LOG_RD_ADDR_HI_GAP: begin
                  uart_tx_req  <= 0;
                  in_cmd_state <= LOG_RD_ADDR_LO;
                end
                LOG_RD_ADDR_LO: begin
                  if (!uart_tx_busy) begin
                    uart_tx_data <= log_rd_data[7:0];
                    uart_tx_req  <= 1;
                    in_cmd_state <= LOG_RD_ADDR_LO_GAP;
                  end
                end
                LOG_RD_ADDR_LO_GAP: begin
                  uart_tx_req <= 0;
                  in_state <= CMD_STATE_FINISHED;
                end
              endcase
            end

            // LOG_WR 0x10 addr1 addr0 type addr_hi addr_lo
            CMD_IN_LOG_WR: begin
              case (in_cmd_state)
                LOG_WR_WRITE: begin
                  u_log_data_in <= in_log_value;
                  u_log_wr <= 1;
                  u_log_addr <= in_cmd_addr[9:0];
                  in_cmd_state <= LOG_WR_DONE;
                end
                LOG_WR_DONE: begin
                  u_log_wr <= 0;
                  in_state <= CMD_STATE_FINISHED;
                end
              endcase
            end

            default: in_state <= CMD_STATE_ERROR;
          endcase
        end

        CMD_STATE_FINISHED: begin
          if (!uart_tx_busy) begin
            uart_tx_data <= CMD_OUT_ACK;
            uart_tx_req <= 1;
            in_state <= CMD_STATE_ACKED;
          end
        end

        CMD_STATE_ERROR: begin
          if (!uart_tx_busy) begin
            uart_tx_data <= CMD_OUT_ERR;
            uart_tx_req <= 1;
            in_state <= CMD_STATE_ACKED;
          end
        end

        CMD_STATE_ACKED: begin
          uart_tx_req <= 0;
          in_state <= CMD_STATE_IDLE;
        end
      endcase
    end
  end
endmodule

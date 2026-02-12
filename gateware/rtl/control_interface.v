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
  localparam CMD_OUT_ACK = 8'h01, CMD_OUT_ERR = 8'hFF;

  // input command opcodes
  localparam CMD_IN_SRAM_BULK_WRITE = 8'h01,
             CMD_IN_SRAM_WRITE = 8'h02,
             CMD_IN_SRAM_READ = 8'h03,
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
  localparam SRAM_RD_REQ = 4'd0,
             SRAM_RD_READ = 4'd1,
             SRAM_RD_DATA_HI = 4'd2,
             SRAM_RD_DATA_HI_GAP = 4'd3,
             SRAM_RD_DATA_LO = 4'd4,
             SRAM_RD_DATA_LO_GAP = 4'd5;

  // FSM for WRITE_DUMP command
  localparam SRAM_BLKWR_READ_WORD = 4'd0,
             SRAM_BLKWR_WRITE_WORD = 4'd1,
             SRAM_BLKWR_NEXT_WORD = 4'd2;

  // FSM for LOG_RD
  localparam LOG_RD_REQ         = 5'd0,
             LOG_RD_TYPE        = 5'd1,
             LOG_RD_TYPE_GAP    = 5'd2,
             LOG_RD_ADDR_HI     = 5'd3,
             LOG_RD_ADDR_HI_GAP = 5'd4,
             LOG_RD_ADDR_LO     = 5'd5,
             LOG_RD_ADDR_LO_GAP = 5'd6;

  reg [ 2:0] in_state;
  reg [ 4:0] in_cmd_state;
  reg [ 7:0] in_cmd_opcode;
  reg [15:0] in_cmd_addr;
  reg [23:0] in_cmd_value;
  reg [ 2:0] in_byte_count;
  reg [23:0] log_rd_data;
  reg        log_rd_valid;
  reg [15:0] sram_rd_data;
  reg        bulk_write_wait_low_byte;

  localparam [7:0] LOG_TYPE_WRITE = 8'h01;
  localparam [7:0] LOG_TYPE_READ = 8'h02;

  always @(posedge clk) begin
    if (!rst_n) begin
      in_state <= CMD_STATE_IDLE;
      in_byte_count <= 3'd0;
      in_cmd_state <= 0;
      in_cmd_opcode <= 0;
      in_cmd_addr <= 0;
      in_cmd_value <= 0;
      log_rd_data <= 0;
      log_rd_valid <= 1'b0;
      sram_rd <= 0;
      sram_wr <= 0;
      u_log_wr <= 0;
      u_log_rd <= 0;
      bulk_write_wait_low_byte <= 1'b0;
    end
    else begin
      // pulses
      gdp_trigger_init <= 0;
      u_log_wr <= 0;
      u_log_rd <= 0;
      sram_wr <= 0;
      sram_rd <= 0;

      if (u_log_data_valid) begin
        log_rd_data  <= u_log_data_out;
        log_rd_valid <= 1'b1;
      end
      case (in_state)
        CMD_STATE_IDLE: begin
          sram_req <= 0;
          in_byte_count <= 3'd0;
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
          // BULK_WRITE 0x01 wordCountHi wordCountLo dataHi[N] dataLo[N] dataHi[N-1] dataLo[N-1] .... dataHi[0] dataLo[0]
          if (in_cmd_opcode == CMD_IN_SRAM_BULK_WRITE && in_byte_count == 3'd2) begin
            case (in_cmd_state)
              SRAM_BLKWR_READ_WORD: begin
                if (uart_rx_valid) begin
                  if (!bulk_write_wait_low_byte) begin
                    in_cmd_value[15:8]       <= uart_rx_data;
                    bulk_write_wait_low_byte <= 1'b1;
                  end else begin
                    in_cmd_value[7:0]        <= uart_rx_data;
                    in_cmd_addr              <= in_cmd_addr - 1;
                    in_cmd_state             <= SRAM_BLKWR_WRITE_WORD;
                    bulk_write_wait_low_byte <= 1'b0;
                  end
                end
              end

              SRAM_BLKWR_WRITE_WORD: begin
                sram_wdata <= in_cmd_value[15:0];
                sram_wr <= 1;
                sram_addr <= in_cmd_addr;
                if (!sram_busy) begin
                  in_cmd_state <= SRAM_BLKWR_NEXT_WORD;
                end
              end

              SRAM_BLKWR_NEXT_WORD: begin
                if (in_cmd_addr == 0) in_state <= CMD_STATE_FINISHED;
                else in_cmd_state <= SRAM_BLKWR_READ_WORD;
              end
            endcase
          end
          else if (uart_rx_valid) begin
            case (in_byte_count)
              3'd0: in_cmd_addr[15:8] <= uart_rx_data;
              3'd1: begin
                in_cmd_addr[7:0] <= uart_rx_data;
                if (in_cmd_opcode == CMD_IN_SRAM_READ || in_cmd_opcode == CMD_IN_LOG_RD) in_state <= CMD_STATE_READY;
              end
              3'd2: in_cmd_value[15:8] <= uart_rx_data;
              3'd3: begin
                in_cmd_value[7:0] <= uart_rx_data;
                if (in_cmd_opcode == CMD_IN_SRAM_WRITE) in_state <= CMD_STATE_READY;
              end
              3'd4: begin
                in_cmd_value[23:16] <= uart_rx_data;
                in_state <= CMD_STATE_READY;
              end
            endcase

            in_byte_count <= in_byte_count + 1'b1;
          end
        end

        CMD_STATE_READY: begin
          case (in_cmd_opcode)
            // PING 0x80
            CMD_IN_PING: in_state <= CMD_STATE_FINISHED;

            // GDP_START 0x81
            CMD_IN_GDP_START: begin
              gdp_trigger_init <= 1;
              in_state         <= CMD_STATE_FINISHED;
            end

            // WRITE_BYTE 0x02 addr1 addr0 data1 data0
            CMD_IN_SRAM_WRITE: begin
              sram_wdata <= in_cmd_value[15:0];
              sram_wr    <= 1;
              sram_addr  <= in_cmd_addr;
              in_state   <= CMD_STATE_FINISHED;
            end

            // READ_BYTE 0x03 addr1 addr0 -> returns 2 bytes (data_hi, data_lo)
            CMD_IN_SRAM_READ: begin
              case (in_cmd_state)
                SRAM_RD_REQ: begin
                  if (!sram_busy) begin
                    sram_addr <= in_cmd_addr;
                    sram_rd <= 1;
                    in_cmd_state <= SRAM_RD_READ;
                  end
                end

                SRAM_RD_READ: begin
                  if (sram_data_valid) begin
                    sram_rd_data <= sram_rdata;
                    in_cmd_state <= SRAM_RD_DATA_HI;
                  end
                end

                SRAM_RD_DATA_HI: begin
                  if (!uart_tx_busy) begin
                    uart_tx_data <= sram_rd_data[15:8];
                    uart_tx_req  <= 1;
                    in_cmd_state <= SRAM_RD_DATA_HI_GAP;
                  end
                end

                SRAM_RD_DATA_HI_GAP: begin
                  uart_tx_req <= 0;
                  in_cmd_state <= SRAM_RD_DATA_LO;
                end

                SRAM_RD_DATA_LO: begin
                  if (!uart_tx_busy) begin
                    uart_tx_data <= sram_rd_data[7:0];
                    uart_tx_req  <= 1;
                    in_cmd_state <= SRAM_RD_DATA_LO_GAP;
                  end
                end

                SRAM_RD_DATA_LO_GAP: begin
                  uart_tx_req <= 0;
                  in_state <= CMD_STATE_FINISHED;
                end
              endcase
            end

            // LOG_RD 0x11 addr1 addr0 -> returns 3 bytes (addr_hi, addr_lo, type)
            CMD_IN_LOG_RD: begin
              case (in_cmd_state)
                LOG_RD_REQ: begin
                  u_log_addr <= in_cmd_addr[9:0];
                  u_log_rd <= 1;
                  log_rd_valid <= 1'b0;
                  in_cmd_state <= LOG_RD_TYPE;
                end
                LOG_RD_TYPE: begin
                  if (!uart_tx_busy && log_rd_valid) begin
                    uart_tx_data <= log_rd_data[15:8];
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
                    uart_tx_data <= log_rd_data[7:0];
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
                    uart_tx_data <= log_rd_data[23:16];
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

            // LOG_WR 0x10 addr1 addr0 addr_hi addr_lo type
            CMD_IN_LOG_WR: begin
              u_log_data_in <= in_cmd_value;
              u_log_wr <= 1;
              u_log_addr <= in_cmd_addr[9:0];
              in_state <= CMD_STATE_FINISHED;
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

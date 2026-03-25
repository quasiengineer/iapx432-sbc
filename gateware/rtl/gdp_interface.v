module gdp_interface #(
  parameter BUS_LOG_ADDR_WIDTH = 10
)(
  input  wire u_clk,  // 50Mhz
  input  wire rst_n,
  output reg  led_io,

  // interface with GDP
  input wire clka,
  input wire clkb,
  input wire bout_io,
  input wire fatal_io,
  input wire prq_io,
  inout wire [15:0] acd_io,
  output reg acd_direction_io,
  output reg clr_io,
  output reg init_io,
  output reg ics_io,

  // UART
  output reg       uart_send,
  output reg [7:0] uart_data,
  input            uart_busy,

  // interface with SRAM
  output reg [15:0] sram_addr,
  output reg        sram_wr,
  output reg        sram_rd,
  output reg        sram_req,
  output reg [15:0] sram_wdata,
  input      [15:0] sram_rdata,

  // Access log writer (same clock domain)
  output reg         log_wr,
  output reg  [ 7:0] log_type,
  output reg  [15:0] log_addr,
  input  wire [BUS_LOG_ADDR_WIDTH-1:0] log_wr_ptr,

  // Write log writer (same clock domain)
  output reg        wlog_wr,
  output reg [15:0] wlog_data,
  output reg [15:0] wlog_addr,

  // signals from control module
  input wire trigger_init
);

  assign clr_io = rst_n;
  assign acd_direction_io = acd_oe;

  wire [15:0] acd_in = acd_io;
  assign acd_io = acd_oe ? acd_out : 16'bz;

  reg acd_oe;
  reg [15:0] acd_out;

  reg [7:0] addr_low;
  reg [7:0] spec;
  reg [4:0] init_cnt;
  reg fatal_recorded;
  reg [BUS_LOG_ADDR_WIDTH-1:0] log_ref;

  reg [47:0] tick_counter;

  reg spec_wr;

  // IPC register access
  reg [15:0] interconn_reg;
  reg [15:0] interconn_reg_addr;
  reg interconn_reg_read;
  reg interconn_reg_write_trigger;
  reg ipc_ticks_trigger;

  // for SRAM transfers
  reg [2:0] sram_transfer_cnt;
  reg sram_transfer;

  reg [3:0] state;
  localparam IDLE = 3'd0,
             T2_STATE = 3'd1,
             T3_STATE = 3'd2,
             T3_STATE_WRITE_BYTE = 3'd3,
             T3_STATE_WRITE_REG = 3'd4,
             HOLD_INIT = 3'd5,
             RECORD_FATAL = 3'd6;

  // rise of CLKB is in the middle of CLKA high period
  always @(posedge clkb or negedge rst_n)
    if (!rst_n) begin
      init_io <= 1'b0;
      state <= IDLE;
      ics_io <= 1'b1;
      acd_oe <= 1'b0;
      acd_out <= 16'b0;
      sram_addr <= 16'b0;
      sram_wr <= 1'b0;
      sram_rd <= 1'b0;
      sram_req <= 1'b0;
      sram_wdata <= 16'b0;
      addr_low <= 8'b0;
      spec <= 8'b0;
      init_cnt <= 5'b0;
      fatal_recorded <= 1'b0;
      sram_transfer_cnt <= 3'b0;
      sram_transfer <= 1'b0;
      spec_wr <= 1'b0;
      interconn_reg_read <= 1'b0;
      interconn_reg_write_trigger <= 1'b0;
      interconn_reg <= 16'b0;
      interconn_reg_addr <= 16'b0;
      log_ref <= {BUS_LOG_ADDR_WIDTH{1'b0}};
      ipc_ticks_trigger <= 1'b0;
    end
    else begin
      log_wr  <= 1'b0;
      wlog_wr <= 1'b0;
      sram_rd <= 1'b0;
      sram_wr <= 1'b0;
      acd_oe  <= 1'b0;
      ics_io  <= 1'b1;

      case (state)
        IDLE: begin
          sram_req <= 1'b0;

          if (!fatal_recorded) begin
            if (prq_io) begin
              // T1 state
              // Spec:
              //   bits 0, 1     modifier (if space is special, then it should be 11, otherwise: 00 = instruction segment, 01 = stack segment, 10 = context control segment, 11 = other)
              //   bits 2, 3, 4  length (000 = 1 byte, 001 = 2 bytes, 010 = 4 bytes, 011 = 6 bytes, 100 = 8 bytes, 101 = 10 bytes)
              //   bit 5         RMW flag to lock address for read-modify-write operation
              //   bit 6         operation (0 = read, 1 = write)
              //   bit 7         space (0 = memory, 1 = special)
              // we don't care about RMW flag and modifier (don't know how it has been used)
              spec <= acd_in[15:8];
              spec_wr <= acd_in[14];
              addr_low <= acd_in[7:0];
              sram_req <= 1'b1;
              sram_transfer <= 1'b0;
              interconn_reg_read <= 1'b0;
              state <= T2_STATE;
            end

            // write an error log entry
            if (!fatal_io) begin
              state <= RECORD_FATAL;
              fatal_recorded <= 1'b1;
            end
          end

          if (init_toggle_sync1 != init_toggle_sync2) begin
            init_cnt <= 5'b0;
            init_io <= 1'b0;
            fatal_recorded <= 1'b0;
            state <= HOLD_INIT;

            // write information about init toggle to log
            log_wr <= 1'b1;
            log_addr <= 16'h0000;
            log_type <= 8'b11110100;
          end
        end

        T2_STATE: begin
          if (prq_io) begin
            state <= IDLE;  // cancel
          end
          else begin
            state <= T3_STATE;

            if (spec[7] == 1'b1) begin
              if (!spec_wr) begin
                if (addr_low == 8'h02) interconn_reg <= 16'h0001;  // local IPC arrived
                else if (addr_low == 8'h00) interconn_reg <= 16'h0001;  // processor ID
                else interconn_reg <= 16'h0000;  // default
                interconn_reg_read <= 1'b1;
              end
              else begin
                interconn_reg_addr <= {acd_in[7:0], addr_low[7:0]};
                state <= T3_STATE_WRITE_REG;
              end
            end
            else begin
              if (spec[4:2] == 3'b000 && spec_wr) begin
                // need to read RAM first to modify single byte
                sram_addr <= {1'b0, acd_in[7:0], addr_low[7:1]};
                sram_rd   <= 1'b1;
                state     <= T3_STATE_WRITE_BYTE;
              end
              else begin
                sram_transfer <= 1'b1;
                // for write operation we need to decrement address by 1, because write operation one cycle behind
                // read operation in terms of addressing (we read SRAM on T2, but write on T3)
                sram_transfer_cnt <= spec[4:2] == 3'b000 ? 3'b000 : (spec[4:2] - (!spec_wr));
                // XXX: support only 16-bit space, so we don't care about high portion of address
                // SRAM keeps 16-bit words, but GDP accesses bytes, so we need to shift address (discard LSB)
                sram_addr <= {1'b0, acd_in[7:0], addr_low[7:1]} - spec_wr;
                sram_rd <= !spec_wr;
              end
            end

            // log access
            log_wr   <= 1'b1;
            log_addr <= {acd_in[7:0], addr_low[7:0]};
            log_type <= spec;
            log_ref  <= log_wr_ptr;
          end
        end

        T3_STATE: begin
          if (interconn_reg_read) begin
            acd_out <= interconn_reg;
            acd_oe  <= 1'b1;
          end

          if (sram_transfer) begin
            if (spec_wr) begin
              sram_wr    <= 1'b1;
              sram_wdata <= acd_in;
              wlog_wr <= 1'b1;
              wlog_data <= acd_in;
              wlog_addr <= {sram_transfer_cnt[2:0], {(16-BUS_LOG_ADDR_WIDTH-3){1'b0}}, log_ref[BUS_LOG_ADDR_WIDTH-1:0]};
            end
            else begin
              if (spec[4:2] == 3'b000) begin
                acd_out <= addr_low[0] ? {8'h00, sram_rdata[15:8]} : {8'h00, sram_rdata[7:0]};
              end
              else begin
                acd_out <= sram_rdata;
              end

              acd_oe  <= 1'b1;
            end

            if (sram_transfer_cnt) begin
              sram_transfer_cnt <= sram_transfer_cnt - 1'b1;
              sram_addr         <= sram_addr + 1'b1;
              sram_rd           <= !spec_wr;
            end
          end

          // need to drive ICS earlier for write operations, because actual write performs on next cycle
          if (!sram_transfer || sram_transfer_cnt == {3'b000, spec_wr}) begin
            // due Tv/Tvo states ICS represents bus error, so need to drive it low
            ics_io <= 1'b0;
            state  <= IDLE;
          end
        end

        T3_STATE_WRITE_REG: begin
          interconn_reg <= acd_in;
          if (interconn_reg_addr == 16'h1000)
            ipc_ticks_trigger <= ~ipc_ticks_trigger;
          else
            interconn_reg_write_trigger <= ~interconn_reg_write_trigger;
          ics_io <= 1'b0;
          state <= IDLE;
        end

        T3_STATE_WRITE_BYTE: begin
          sram_wdata <= addr_low[0] ? {acd_in[7:0], sram_rdata[7:0]} : {sram_rdata[15:8], acd_in[7:0]};
          sram_wr <= 1'b1;
          wlog_wr <= 1'b1;
          wlog_data <= {8'b0, acd_in[7:0]};
          wlog_addr <= {{(16-BUS_LOG_ADDR_WIDTH){1'b0}}, log_ref[BUS_LOG_ADDR_WIDTH-1:0]};
          ics_io <= 1'b0;
          state <= IDLE;
        end

        HOLD_INIT: begin
          init_cnt <= init_cnt + 1'b1;
          if (init_cnt == 5'd25) begin
            init_io <= 1'b1;
            state   <= IDLE;
          end
        end

        RECORD_FATAL: begin
          // write information about fatal error to log
          log_wr <= 1'b1;
          log_addr <= 16'hFFFF;
          log_type <= 8'b11110000;
          state <= IDLE;
        end
      endcase
    end

  reg init_toggle_u, init_toggle_sync0, init_toggle_sync1, init_toggle_sync2;
  always @(posedge u_clk or negedge rst_n) begin
    if (!rst_n) init_toggle_u <= 1'b0;
    else if (trigger_init) begin
      init_toggle_u <= ~init_toggle_u;
    end
  end

  always @(posedge clkb or negedge rst_n) begin
    if (!rst_n) begin
      init_toggle_sync0 <= 1'b0;
      init_toggle_sync1 <= 1'b0;
      init_toggle_sync2 <= 1'b0;
    end
    else begin
      init_toggle_sync0 <= init_toggle_u;
      init_toggle_sync1 <= init_toggle_sync0;
      init_toggle_sync2 <= init_toggle_sync1;
    end
  end

  // CLKB tick counter
  always @(posedge clkb or negedge rst_n) begin
    if (!rst_n) begin
      tick_counter <= 48'b0;
    end else begin
      if (init_toggle_sync1 != init_toggle_sync2) begin
        tick_counter <= 48'b0;
      end else begin
        tick_counter <= tick_counter + 1;
      end
    end
  end

  /*
   * Send data via UART about IPC register write operation
   */

  reg [7:0] uart_fifo_data;
  reg uart_fifo_req;
  uart_fifo u_uart_fifo (
    .clk(u_clk),
    .rst_n(rst_n),
    .data_in(uart_fifo_data),
    .write_req(uart_fifo_req),
    .data_out(uart_data),
    .send(uart_send),
    .uart_busy(uart_busy)
  );

  reg [1:0] uart_state;
  reg [7:0] send_bytes [0:8];
  reg [3:0] send_counter;
  reg [3:0] max_count;
  localparam UART_IDLE = 1'd0,
             UART_SENDING = 1'd1,
             UART_GAP = 2'd2;

  reg ipc_reg_write_sync0, ipc_reg_write_sync1, ipc_reg_write_sync2;
  reg ipc_ticks_reg_write_sync0, ipc_ticks_reg_write_sync1, ipc_ticks_reg_write_sync2;
  reg fatal_sync0, fatal_sync1, prev_fatal_sync;
  always @(posedge u_clk or negedge rst_n) begin
    if (!rst_n) begin
      ipc_reg_write_sync0 <= 1'b0;
      ipc_reg_write_sync1 <= 1'b0;
      ipc_reg_write_sync2 <= 1'b0;
      ipc_ticks_reg_write_sync0 <= 1'b0;
      ipc_ticks_reg_write_sync1 <= 1'b0;
      ipc_ticks_reg_write_sync2 <= 1'b0;
      fatal_sync0 <= 1'b0;
      fatal_sync1 <= 1'b0;
      prev_fatal_sync <= 1'b0;
      uart_state <= UART_IDLE;
      send_counter <= 0;
      max_count <= 0;
    end
    else begin
      // pulses
      uart_fifo_req <= 1'b0;

      ipc_reg_write_sync0 <= interconn_reg_write_trigger;
      ipc_reg_write_sync1 <= ipc_reg_write_sync0;
      ipc_reg_write_sync2 <= ipc_reg_write_sync1;

      ipc_ticks_reg_write_sync0 <= ipc_ticks_trigger;
      ipc_ticks_reg_write_sync1 <= ipc_ticks_reg_write_sync0;
      ipc_ticks_reg_write_sync2 <= ipc_ticks_reg_write_sync1;

      fatal_sync0 <= fatal_io;
      fatal_sync1 <= fatal_sync0;
      prev_fatal_sync <= fatal_sync1;

      if (ipc_reg_write_sync1 != ipc_reg_write_sync2) begin
        send_bytes[0] <= 8'h02;
        send_bytes[1] <= interconn_reg_addr[15:8];
        send_bytes[2] <= interconn_reg_addr[7:0];
        send_bytes[3] <= interconn_reg[15:8];
        send_bytes[4] <= interconn_reg[7:0];
        send_counter <= 0;
        max_count <= 4'd5;
        uart_state <= UART_SENDING;
      end
      else if (ipc_ticks_reg_write_sync1 != ipc_ticks_reg_write_sync2) begin
        send_bytes[0] <= 8'h03;
        send_bytes[1] <= interconn_reg[15:8];
        send_bytes[2] <= interconn_reg[7:0];
        send_bytes[3] <= tick_counter[47:40];
        send_bytes[4] <= tick_counter[39:32];
        send_bytes[5] <= tick_counter[31:24];
        send_bytes[6] <= tick_counter[23:16];
        send_bytes[7] <= tick_counter[15:8];
        send_bytes[8] <= tick_counter[7:0];
        send_counter <= 0;
        max_count <= 4'd9;
        uart_state <= UART_SENDING;
      end
      else if (prev_fatal_sync && !fatal_sync1) begin
        send_bytes[0] <= 8'h04;
        send_counter <= 0;
        max_count <= 4'd1;
        uart_state <= UART_SENDING;
      end

      case (uart_state)
        UART_SENDING: begin
          uart_fifo_data <= send_bytes[send_counter];
          uart_fifo_req <= 1'b1;
          uart_state <= UART_GAP;
          send_counter <= send_counter + 1;
        end
        UART_GAP: begin
          if (send_counter == max_count) begin
            uart_state <= UART_IDLE;
            send_counter <= 0;
          end else begin
            uart_state <= UART_SENDING;
          end
        end
      endcase
    end
  end

endmodule

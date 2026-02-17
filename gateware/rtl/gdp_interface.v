module gdp_interface (
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

  // interface with SRAM
  output reg [15:0] sram_addr,
  output reg sram_wr,
  output reg sram_rd,
  output reg sram_req,
  output reg [15:0] sram_wdata,
  input [15:0] sram_rdata,

  // Access log writer (same clock domain)
  output reg        log_wr,
  output reg [ 7:0] log_type,
  output reg [15:0] log_addr,
  input wire [ 9:0] log_wr_ptr,

  // Write log writer (same clock domain)
  output reg        wlog_wr,
  output reg [15:0] wlog_data,
  output reg [15:0] wlog_addr,

  // signals from control module
  input wire trigger_init,
  input wire [15:0] local_comms_addr
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
  reg [9:0] log_ref;

  reg spec_wr;

  // IPC register access
  reg [2:0] interconn_req_cnt;
  reg [15:0] interconn_reg;
  reg interconn_reg_read;

  localparam IPC_MESSAGE_ENTER_NORMAL_MODE = 16'd4;
  localparam IPC_MESSAGE_START_PROCESSOR = 16'd14;

  // for SRAM transfers
  reg [2:0] sram_transfer_cnt;
  reg sram_transfer;

  reg [3:0] state;
  localparam IDLE = 3'd0,
             T2_STATE = 3'd1,
             T3_STATE = 3'd2,
             T3_STATE_WRITE_BYTE = 3'd3,
             T3_STATE_UPDATE_IPC_DATA = 3'd4,
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
      interconn_reg <= 16'b0;
      log_ref <= 10'b0;
      interconn_req_cnt <= 3'b0;
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
            interconn_req_cnt <= 3'd0;
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
              // XXX: support only read operation from interconnect registers
              if (!spec_wr) begin
                if (addr_low == 8'h02) begin
                  state <= T3_STATE_UPDATE_IPC_DATA;
                  // need to reset "semaphore" in local communication segment for processor to let it process IPC
                  sram_wr <= 1'b1;
                  sram_addr <= {1'b0, local_comms_addr[15:1]} + 16'd2;
                  sram_wdata <= 16'h0001;
                end
                else if (addr_low == 8'h00) interconn_reg <= 16'h0001;  // processor ID
                else interconn_reg <= 16'h0000;  // default
                interconn_reg_read <= 1'b1;
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
                sram_transfer_cnt <= spec[4:2] - (!spec_wr);
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

          // TODO: support 1-byte reads properly
          if (sram_transfer) begin
            if (spec_wr) begin
              sram_wr    <= 1'b1;
              sram_wdata <= acd_in;
              wlog_wr <= 1'b1;
              wlog_data <= acd_in;
              wlog_addr <= {3'b0, sram_transfer_cnt[2:0], log_ref[9:0]};
            end
            else begin
              acd_out <= sram_rdata;
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

        T3_STATE_WRITE_BYTE: begin
          sram_wdata <= addr_low[0] ? {acd_in[7:0], sram_rdata[7:0]} : {sram_rdata[15:8], acd_in[7:0]};
          sram_wr <= 1'b1;
          wlog_wr <= 1'b1;
          wlog_data <= {8'b0, acd_in[7:0]};
          wlog_addr <= {6'b0, log_ref[9:0]};
          ics_io <= 1'b0;
          state <= IDLE;
        end

        T3_STATE_UPDATE_IPC_DATA: begin
          acd_oe  <= 1'b1;

          if (interconn_req_cnt > 3'd1) begin
            // no IPC anymore
            acd_out <= 16'h0000;
          end
          else begin
            // local IPC arrived
            acd_out <= 16'h0001;
            // set IPC message in local communication segment for processor
            sram_wr <= 1'b1;
            sram_addr <= {1'b0, local_comms_addr[15:1]} + 16'd1;
            sram_wdata <= interconn_req_cnt == 3'd0 ? IPC_MESSAGE_START_PROCESSOR : IPC_MESSAGE_ENTER_NORMAL_MODE;
            interconn_req_cnt <= interconn_req_cnt + 1'b1;
          end

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

endmodule

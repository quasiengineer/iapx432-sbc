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
  output reg [15:0] sram_rdata,
  input [15:0] sram_wdata,
  input sram_busy,
  input sram_data_valid,

  // Access log writer (same clock domain)
  output reg        log_wr,
  output reg [ 7:0] log_type,
  output reg [15:0] log_addr,

  // signals from control module
  input wire trigger_init
);

  assign clr_io = rst_n;
  assign acd_direction_io = acd_oe;

  wire [15:0] acd_in = acd_io;
  assign acd_io = acd_oe ? acd_out : 16'bz;

  reg acd_oe;
  reg [15:0] acd_out;

  reg [3:0] state;
  reg [7:0] addr_low;
  reg [7:0] spec;
  reg [4:0] init_cnt;
  reg fatal_recorded;

  localparam IDLE = 0, T2_STATE = 1, T3_STATE = 2, HOLD_INIT = 3, RECORD_FATAL = 4;

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
      sram_rdata <= 16'b0;
      addr_low <= 8'b0;
      spec <= 8'b0;
      init_cnt <= 5'b0;
      fatal_recorded <= 1'b0;
    end
    else begin
      log_wr  <= 1'b0;
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
              addr_low <= acd_in[7:0];
              sram_req <= 1'b1;
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
            if (spec[7] == 1'b1) begin
              // support only read operation from interconnect registers
              if (spec[6] == 1'b0) begin
                if (addr_low == 8'h02) acd_out <= 16'h0001;  // IPC state, always mark that local IPC arrived
                else if (addr_low == 8'h00) acd_out <= 16'h0001;  // processor ID
                else acd_out <= 16'h0000;  // default
                acd_oe <= 1'b1;
              end
            end
            else begin
              // TODO: need to support data length (spec[4:2])
              if (spec[6] == 1'b1) begin
                // TODO: implement write access
              end
              else begin
                // TODO: read data from SRAM
                // XXX: we support only 16-bit memory space, so we don't care about high portion of address
                acd_out <= 16'h0000; // default
                acd_oe <= 1'b1;
              end
            end

            // log access
            log_wr <= 1'b1;
            log_addr <= {acd_in[7:0], addr_low[7:0]};
            log_type <= spec;

            state <= T3_STATE;
          end
        end

        T3_STATE: begin
          // due Tv/Tvo states ICS represents bus error
          ics_io <= 1'b0;
          state  <= IDLE;
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

module bram_log #(
  parameter ADDR_WIDTH = 10
) (
  input wire clk,
  input wire rst_n,
  input wire trigger_init,

  // UART domain
  input  wire                  u_wr,
  input  wire                  u_rd,
  input  wire [ADDR_WIDTH-1:0] u_addr,
  input  wire [          23:0] u_data_in,
  output reg  [          23:0] u_data_out,
  output reg                   u_data_valid,

  // Log writer
  input wire        log_write_clk,
  input wire        log_wr,
  input wire [ 7:0] log_type,
  input wire [15:0] log_addr
);
  localparam integer DEPTH = (1 << ADDR_WIDTH);
  localparam integer MAX_ADDR = DEPTH - 1;

  reg [23:0] log_mem[0:DEPTH-1];

  reg ram_we;
  reg [ADDR_WIDTH-1:0] ram_waddr;
  reg [23:0] ram_wdata;

  always @(posedge clk) begin
    if (ram_we) begin
      log_mem[ram_waddr] <= ram_wdata;
    end

    if (u_rd_pending) begin
      u_data_out <= log_mem[u_rd_addr];
    end
  end

  reg [ADDR_WIDTH-1:0] log_wr_ptr_f;
  reg                  u_rd_pending;
  reg [ADDR_WIDTH-1:0] u_rd_addr;

  reg                  req_toggle_s;
  reg [          23:0] req_data_s;
  reg                  log_wr_prev_s;

  reg req_sync_f_0, req_sync_f_1;
  reg prev_req_sync_f;
  reg [23:0] sampled_req_data_f;

  reg do_log_write;

  reg [23:0] req_data_sync_0;
  reg [23:0] req_data_sync_1;

  reg pending;

  always @(posedge log_write_clk or negedge rst_n) begin
    if (!rst_n) begin
      req_toggle_s  <= 1'b0;
      req_data_s    <= 24'h0;
      log_wr_prev_s <= 1'b0;
      pending       <= 1'b0;
    end
    else begin
      log_wr_prev_s <= log_wr;
      pending       <= 1'b0;

      if (pending) begin
        req_toggle_s <= ~req_toggle_s;
      end

      if (log_wr && !log_wr_prev_s) begin
        req_data_s <= {log_type[7:0], log_addr[15:0]};
        pending    <= 1'b1;
      end
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      req_sync_f_0 <= 1'b0;
      req_sync_f_1 <= 1'b0;
      prev_req_sync_f <= 1'b0;
      sampled_req_data_f <= 24'h0;
      log_wr_ptr_f <= {ADDR_WIDTH{1'b0}};

      u_data_valid <= 1'b0;
      u_rd_pending <= 1'b0;
      u_rd_addr    <= {ADDR_WIDTH{1'b0}};

      do_log_write <= 1'b0;

      req_data_sync_0 <= 24'h0;
      req_data_sync_1 <= 24'h0;
    end
    else begin
      if (trigger_init) log_wr_ptr_f <= {ADDR_WIDTH{1'b0}};

      req_sync_f_0 <= req_toggle_s;
      req_sync_f_1 <= req_sync_f_0;

      req_data_sync_0 <= req_data_s;
      req_data_sync_1 <= req_data_sync_0;

      do_log_write <= 1'b0;

      if (req_sync_f_1 ^ prev_req_sync_f) begin
        sampled_req_data_f <= req_data_sync_1;

        if (log_wr_ptr_f < MAX_ADDR) begin
          do_log_write <= 1'b1;
        end
      end
      prev_req_sync_f <= req_sync_f_1;

      if (do_log_write) begin
        log_wr_ptr_f <= log_wr_ptr_f + 1'b1;
      end

      u_data_valid <= 1'b0;
      if (u_rd) begin
        u_rd_pending <= 1'b1;
        u_rd_addr <= u_addr;
      end

      if (u_rd_pending) begin
        u_data_valid <= 1'b1;
        u_rd_pending <= 1'b0;
      end
    end
  end

  always @(*) begin
    ram_we    = 1'b0;
    ram_waddr = log_wr_ptr_f;
    ram_wdata = sampled_req_data_f;

    if (do_log_write) begin
      ram_we    = 1'b1;
      ram_waddr = log_wr_ptr_f;
      ram_wdata = sampled_req_data_f;
    end
    else if (u_wr) begin
      ram_we    = 1'b1;
      ram_waddr = u_addr;
      ram_wdata = u_data_in;
    end
  end

endmodule

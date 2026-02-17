module write_log #(
  parameter ADDR_WIDTH = 6  // 64 entries by default
) (
  input wire clk,
  input wire rst_n,
  input wire trigger_init,

  // UART domain
  input  wire                  u_rd,
  input  wire [ADDR_WIDTH-1:0] u_addr,
  output reg  [          31:0] u_data_out,

  // Log writer
  input wire        log_write_clk,
  input wire        log_wr,
  input wire [15:0] log_data,
  input wire [15:0] log_addr
);
  localparam integer DEPTH = (1 << ADDR_WIDTH);

  reg [31:0] log_mem[0:DEPTH-1];

  reg ram_we;
  reg [ADDR_WIDTH-1:0] ram_waddr;
  reg [31:0] ram_wdata;

  always @(posedge clk) begin
    if (ram_we) begin
      log_mem[ram_waddr] <= ram_wdata;
    end
  end

  reg [ADDR_WIDTH-1:0] log_wr_ptr_f;

  reg                  req_toggle_s;
  reg [          31:0] req_data_s;

  reg req_sync_f_0, req_sync_f_1;
  reg prev_req_sync_f;
  reg [31:0] sampled_req_data_f;

  reg do_log_write;

  reg [31:0] req_data_sync_0;
  reg [31:0] req_data_sync_1;

  always @(posedge log_write_clk or negedge rst_n) begin
    if (!rst_n) begin
      req_toggle_s <= 1'b0;
      req_data_s   <= 32'h0;
    end
    else begin
      if (log_wr) begin
        req_data_s   <= {log_data[15:0], log_addr[15:0]};
        req_toggle_s <= ~req_toggle_s;
      end
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      req_sync_f_0 <= 1'b0;
      req_sync_f_1 <= 1'b0;
      prev_req_sync_f <= 1'b0;
      sampled_req_data_f <= 32'h0;
      log_wr_ptr_f <= {ADDR_WIDTH{1'b0}};

      do_log_write <= 1'b0;

      req_data_sync_0 <= 32'h0;
      req_data_sync_1 <= 32'h0;
    end
    else begin
      if (trigger_init) log_wr_ptr_f <= {ADDR_WIDTH{1'b0}};

      req_sync_f_0 <= req_toggle_s;
      req_sync_f_1 <= req_sync_f_0;
      prev_req_sync_f <= req_sync_f_1;

      req_data_sync_0 <= req_data_s;
      req_data_sync_1 <= req_data_sync_0;

      if (req_sync_f_1 ^ prev_req_sync_f) begin
        sampled_req_data_f <= req_data_sync_1;
        do_log_write <= 1'b1;
      end
      else begin
        do_log_write <= 1'b0;
      end

      // increment write pointer after actual write to log
      if (do_log_write) log_wr_ptr_f <= log_wr_ptr_f + 1'b1;

      if (u_rd) begin
        u_data_out <= log_mem[u_addr];
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
  end

endmodule

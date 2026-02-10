module clock_gen (
  input  wire clk_250,
  output wire clk_125,
  output wire clk_50,
  output wire rst_n,
  output reg  clka,
  output reg  clkb
);

  reg  clk_125_reg;
  wire pll_locked;

  // simple /2 divider for 125 MHz reference
  always @(posedge clk_250) begin
    clk_125_reg <= ~clk_125_reg;
  end
  assign clk_125 = clk_125_reg;

  // SB_PLL40_CORE configuration:
  // Reference: 125 MHz / (DIVR+1) = 25 MHz
  // VCO:      25 MHz * (DIVF+1) = 800 MHz
  // Output:   800 MHz / 2^DIVQ
  // For 50 MHz we need divide by 16 -> DIVQ = 4 (2^4 = 16)
  SB_PLL40_CORE #(
    .FEEDBACK_PATH("SIMPLE"),
    .PLLOUT_SELECT("GENCLK"),
    .DIVR         (4'd4),      // Reference divider: 125 / (4+1) = 25 MHz
    .DIVF         (7'd31),     // Feedback multiplier: 25 * (31+1) = 800 MHz VCO
    .DIVQ         (3'd4),      // Output divider: 800 / 16 = 50 MHz
    .FILTER_RANGE (3'b001)     // For 25 MHz ref
  ) pll_inst (
    .REFERENCECLK(clk_125),
    .PLLOUTGLOBAL(clk_50),
    .LOCK(pll_locked),
    .BYPASS(1'b0),
    .RESETB(1'b1)
  );

  // active-low, if rst_n = 1, then device is ready to be run
  assign rst_n = pll_locked;

  localparam integer CLKA_DIV = 50;  // 250 MHz / 50 = 5 MHz
  localparam integer CLKB_OFFSET = 12; // Approx 48 ns (close to 50 ns) at 250 MHz (4 ns period)
  reg [5:0] clka_div;

  always @(posedge clk_250 or negedge rst_n) begin
    if (!rst_n) clka_div <= 6'd0;
    else if (clka_div == CLKA_DIV - 1) clka_div <= 6'd0;
    else clka_div <= clka_div + 1'b1;
  end

  always @(posedge clk_250 or negedge rst_n) begin
    if (!rst_n) begin
      clka <= 1'b0;
      clkb <= 1'b0;
    end
    else begin
      clka <= (clka_div < (CLKA_DIV / 2));
      clkb <= ((clka_div >= CLKB_OFFSET) && (clka_div < (CLKB_OFFSET + (CLKA_DIV / 2))));
    end
  end

endmodule
module BB(
    // Input Ports
    input        clk,
    input        rst_n,
    input        in_valid,
    input  [1:0] inning,   // Current inning number
    input        half,     // 0: top of the inning, 1: bottom of the inning
    input  [2:0] action,   // Action code

    // Output Ports
    output reg        out_valid,  // Result output valid
    output reg [7:0]  score_A,    // Score of team A (guest team)
    output reg [7:0]  score_B,    // Score of team B (home team)
    output reg [1:0]  result      // 0: Team A wins, 1: Team B wins, 2: Draw
);

endmodule

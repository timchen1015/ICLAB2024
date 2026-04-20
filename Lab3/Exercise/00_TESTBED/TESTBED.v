`timescale 1ns/10ps

`include "PATTERN.v"
`ifdef RTL
	`include "../01_RTL/TETRIS.v"
`endif
`ifdef GATE
    `include "TETRIS_SYN.v"
`endif

module TESTBED;

wire 			rst_n, clk, in_valid;
wire 	[2:0]	tetrominoes;
wire	[2:0]	position;
wire			tetris_valid, score_valid, fail;
wire	[3:0]	score;
wire	[71:0]	tetris;




initial begin
    `ifdef RTL
		`ifndef NO_FSDB
        $fsdbDumpfile("TETRIS.fsdb");
        $fsdbDumpvars(0,"+mda");
		`endif
    `endif
    `ifdef GATE
        $sdf_annotate("TETRIS_SYN.sdf", u_TETRIS);
		`ifndef NO_FSDB
        $fsdbDumpfile("TETRIS_SYN.fsdb");
        $fsdbDumpvars(0,"+mda"); 
		`endif
    `endif
end

TETRIS u_TETRIS(
	.rst_n(rst_n),
	.clk(clk),
	.in_valid(in_valid),
	.tetrominoes(tetrominoes),
	.position(position),
	.tetris_valid(tetris_valid),
	.score_valid(score_valid),
	.fail(fail),
	.score(score),
	.tetris(tetris)
);
    
PATTERN u_PATTERN(
    .rst_n(rst_n),
	.clk(clk),
	.in_valid(in_valid),
	.tetrominoes(tetrominoes),
	.position(position),
	.tetris_valid(tetris_valid),
	.score_valid(score_valid),
	.fail(fail),
	.score(score),
	.tetris(tetris)
);

endmodule

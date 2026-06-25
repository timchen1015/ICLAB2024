module CLK_1_MODULE (
    input clk,
    input rst_n,
    input in_valid,
    input [17:0] in_row,
    input [11:0] in_kernel,
    input out_idle,
    output handshake_sready,
    output reg [29:0] handshake_din,
    input  flag_handshake_to_clk1,
    output flag_clk1_to_handshake,
    input fifo_empty,
    input [7:0] fifo_rdata,
    output fifo_rinc,
    output reg out_valid,
    output reg [7:0] out_data,
    output flag_clk1_to_fifo,
    input flag_fifo_to_clk1
);
endmodule

module CLK_2_MODULE (
    input clk,
    input rst_n,
    input in_valid,
    input fifo_full,
    input [29:0] in_data,
    output reg out_valid,
    output reg [7:0] out_data,
    output reg busy,
    input  flag_handshake_to_clk2,
    output flag_clk2_to_handshake,
    input  flag_fifo_to_clk2,
    output flag_clk2_to_fifo
);
endmodule

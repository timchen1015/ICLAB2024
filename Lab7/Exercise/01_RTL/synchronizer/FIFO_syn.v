module FIFO_syn #(parameter WIDTH=8, parameter WORDS=64) (
    input wclk,
    input rclk,
    input rst_n,
    input winc,
    input [WIDTH-1:0] wdata,
    output reg wfull,
    input rinc,
    output reg [WIDTH-1:0] rdata,
    output reg rempty,
    input  flag_clk1_to_fifo,
    input  flag_clk2_to_fifo,
    output flag_fifo_to_clk1,
    output flag_fifo_to_clk2
);

endmodule

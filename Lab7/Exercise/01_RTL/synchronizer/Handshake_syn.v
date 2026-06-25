module Handshake_syn #(parameter WIDTH=8) (
    input sclk,
    input dclk,
    input rst_n,
    input sready,
    input [WIDTH-1:0] din,
    input dbusy,
    output sidle,
    output reg dvalid,
    output reg [WIDTH-1:0] dout,
    input  flag_clk1_to_handshake,
    input  flag_clk2_to_handshake,
    output flag_handshake_to_clk1,
    output flag_handshake_to_clk2
);

endmodule

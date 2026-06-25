module Handshake_syn #(
    parameter WIDTH = 8
)(
    input  wire             sclk,
    input  wire             dclk,
    input  wire             rst_n,

    // source domain
    input  wire             svalid,   // source has valid data
    input  wire [WIDTH-1:0] din,
    output wire             sready,   // handshake module can accept data

    // destination domain
    output reg              dvalid,   // destination data valid
    output reg  [WIDTH-1:0] dout,
    input  wire             dready    // destination can accept data
);

/*
Handshake flow:
1. The source asserts svalid when it has valid data.
2. If the handshake module is idle, it asserts sready.
3. When svalid && sready is true, the source data is latched.
4. A request is sent to the destination clock domain.
5. After the destination receives the request, it samples the latched data into dout.
6. The destination asserts dvalid to indicate that dout is valid.
7. When dvalid && dready is true, the destination has accepted the data.
8. An acknowledge signal is sent back to the source clock domain.
9. After the source receives the acknowledge, it can send the next data.
*/

// Use toggle based handshake signals to cross clock domains
reg sreq;                //request toggles while send data
wire dreq;               // module output use wire only
reg dack;               // acknowledge toggles while receive data
wire sack;               // module output use wire only


reg [WIDTH-1:0] dhold;    // hold data to send to destination

NDFF_syn u_req (
    .D(sreq),
    .clk(dclk),
    .rst_n(rst_n),
    .Q(dreq)
);

NDFF_syn u_ack (
    .D(dack),
    .clk(sclk),
    .rst_n(rst_n),
    .Q(sack)
);

assign sready = (sack == sreq);


//----------Source Clock Domain Logic----------
always @(posedge sclk or negedge rst_n) begin
    if (!rst_n) begin
        dhold <= 0;
        sreq <= 0;
    end else if (svalid && sready) begin
        dhold <= din;
        sreq <= ~sreq;                      // toggle request when data is sent
    end
end



// ---------Destination Clock Domain Logic----------

// New request arrive → latch dhold into dout → assert dvalid
// Destination accept data → deassert dvalid -> toggle dack

always @(posedge dclk or negedge rst_n) begin
    if (!rst_n) begin
        dout <= 0;
        dvalid <= 0;
        dack <= 0;
    end else if (!dvalid && (dreq != dack)) begin         // new request arrive
        dout <= dhold;                                    // latch data
        dvalid <= 1;                                      // assert dvalid
    end else if (dvalid && dready) begin
        dvalid <= 0;                        // deassert dvalid when destination accepts data
        dack <= dreq;                      // Acknowledge the request
    end
end
endmodule
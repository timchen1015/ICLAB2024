module FIFO_syn #(
    parameter WIDTH = 8,
    parameter WORDS = 64
)(
    input  wire             wclk,
    input  wire             rclk,
    input  wire             rst_n,

    // write domain
    input  wire             winc,      // write request
    input  wire [WIDTH-1:0] wdata,
    output reg              wfull,

    // read domain
    input  wire             rinc,      // read request
    output reg  [WIDTH-1:0] rdata,
    output reg              rempty
);

// --------------------------------------------------------
localparam ADDR_WIDTH = $clog2(WORDS);
reg [WIDTH-1:0] mem [0:WORDS-1];

// write pointer(All pointer got extra 1 bit to distinguish between full and empty)
reg [ADDR_WIDTH:0] wptr_bin;
reg [ADDR_WIDTH:0] wptr_bin_next;
reg [ADDR_WIDTH:0] wptr_gray;
reg [ADDR_WIDTH:0] wptr_gray_next;


// read pointer
reg [ADDR_WIDTH:0] rptr_bin;
reg [ADDR_WIDTH:0] rptr_bin_next;
reg [ADDR_WIDTH:0] rptr_gray;
reg [ADDR_WIDTH:0] rptr_gray_next;


// synchronized pointers
wire [ADDR_WIDTH:0] wptr_gray_sync;
wire [ADDR_WIDTH:0] rptr_gray_sync;


NDFF_BUS_syn #(.WIDTH(ADDR_WIDTH+1)) u_wptr_sync (
    .D(wptr_gray),
    .Q(wptr_gray_sync),
    .clk(rclk),
    .rst_n(rst_n)
);

NDFF_BUS_syn #(.WIDTH(ADDR_WIDTH+1)) u_rptr_sync (
    .D(rptr_gray),
    .Q(rptr_gray_sync),
    .clk(wclk),
    .rst_n(rst_n)
);

wire rempty_next = (rptr_gray_next == wptr_gray_sync);

// For full detection, invert the two MSBs of the synchronized read pointer and keep the remaining lower bits unchanged
wire wfull_next = (wptr_gray_next == {
    ~rptr_gray_sync[ADDR_WIDTH:ADDR_WIDTH-1],
     rptr_gray_sync[ADDR_WIDTH-2:0]
});

wire r_en = rinc && !rempty;
wire w_en = winc && !wfull;


// Write Domain logic
always @(posedge wclk or negedge rst_n) begin
    if (!rst_n) begin
        wptr_bin  <= 0;
        wptr_gray <= 0;
        wfull     <= 1'b0;
    end else begin
        wptr_bin  <= wptr_bin_next;
        wptr_gray <= wptr_gray_next;
        wfull     <= wfull_next;
    end
end

// Memory write
always @(posedge wclk) begin
    if (w_en) begin
        mem[wptr_bin[ADDR_WIDTH-1:0]] <= wdata;
    end
end


// Read Domain logic
always @(posedge rclk or negedge rst_n) begin
    if (!rst_n) begin
        rptr_bin  <= 0;
        rptr_gray <= 0;
        rempty    <= 1'b1;
    end else begin
        rptr_bin  <= rptr_bin_next;
        rptr_gray <= rptr_gray_next;
        rempty    <= rempty_next;
    end
end

// Memory read
always @(posedge rclk or negedge rst_n) begin
    if (!rst_n) begin
        rdata <= {WIDTH{1'b0}};
    end else if (r_en) begin
        rdata <= mem[rptr_bin[ADDR_WIDTH-1:0]];
    end
end


// Calculate next pointers and gray codes
always @(*)begin
    wptr_bin_next = w_en ? wptr_bin + 1'b1 : wptr_bin;
    wptr_gray_next = (wptr_bin_next >> 1) ^ wptr_bin_next;
    rptr_bin_next = r_en ? rptr_bin + 1'b1 : rptr_bin;
    rptr_gray_next = (rptr_bin_next >> 1) ^ rptr_bin_next;
end

endmodule

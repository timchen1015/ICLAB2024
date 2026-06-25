module CLK_1_MODULE (
    input clk,
    input rst_n,
    input in_valid,
    input [17:0] in_row,
    input [11:0] in_kernel,
    input out_idle,
    output reg handshake_sready,
    output reg [29:0] handshake_din,
    input fifo_empty,
    input [7:0] fifo_rdata,
    output fifo_rinc,
    output reg out_valid,
    output reg [7:0] out_data
);

reg [29:0] in_buffer [0:5];
reg [2:0]  in_count;
reg [2:0]  send_count;

reg [7:0]  fifo_read_count;
reg [7:0]  output_count;
reg        fifo_rinc_d;
reg        wait_fifo_empty;
reg        wait_handshake_ack;

wire [29:0] in_combine = {in_row, in_kernel};
wire        send_fire = handshake_sready & out_idle;
wire [2:0]  load_count = send_count + {2'b0, send_fire};
wire [2:0]  available_count_next = in_count + {2'b0, in_valid};
wire        load_valid = (load_count < available_count_next);
wire        load_current = in_valid & (load_count == in_count);
wire [29:0] load_data = load_current ? in_combine :
                         ((load_count < 3'd6) ? in_buffer[load_count] : 30'd0);
wire        can_load_handshake = !handshake_sready & !wait_handshake_ack & out_idle;
wire        input_clear = !in_valid & (in_count == 3'd6) & (send_count == 3'd6) &
                          !handshake_sready & !wait_handshake_ack;
wire        output_last = fifo_rinc_d & (output_count == 8'd149);

assign fifo_rinc = !wait_fifo_empty & !fifo_empty & (fifo_read_count < 8'd150);

integer i;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        in_count <= 3'd0;
        for (i = 0; i < 6; i = i + 1) begin
            in_buffer[i] <= 30'd0;
        end
    end
    else if (input_clear) begin
        in_count <= 3'd0;
    end
    else if (in_valid) begin
        in_buffer[in_count] <= in_combine;
        in_count <= in_count + 3'd1;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        send_count <= 3'd0;
        handshake_sready <= 1'b0;
        handshake_din <= 30'd0;
        wait_handshake_ack <= 1'b0;
    end
    else if (input_clear) begin
        send_count <= 3'd0;
        handshake_sready <= 1'b0;
        handshake_din <= 30'd0;
        wait_handshake_ack <= 1'b0;
    end
    else begin
        if (send_fire) begin
            send_count <= send_count + 3'd1;
            handshake_sready <= 1'b0;
            wait_handshake_ack <= 1'b1;
        end
        else if (wait_handshake_ack && out_idle) begin
            wait_handshake_ack <= 1'b0;
        end
        else if (can_load_handshake) begin
            handshake_sready <= load_valid;
            if (load_valid) begin
                handshake_din <= load_data;
            end
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fifo_read_count <= 8'd0;
        wait_fifo_empty <= 1'b0;
    end
    else if (output_last) begin
        fifo_read_count <= 8'd0;
        wait_fifo_empty <= 1'b1;
    end
    else begin
        if (fifo_empty) begin
            wait_fifo_empty <= 1'b0;
        end
        if (fifo_rinc) begin
            fifo_read_count <= fifo_read_count + 8'd1;
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fifo_rinc_d <= 1'b0;
        output_count <= 8'd0;
        out_valid <= 1'b0;
        out_data <= 8'd0;
    end
    else begin
        fifo_rinc_d <= fifo_rinc;
        out_valid <= fifo_rinc_d;
        out_data <= fifo_rinc_d ? fifo_rdata : 8'd0;

        if (output_last) begin
            output_count <= 8'd0;
        end
        else if (fifo_rinc_d) begin
            output_count <= output_count + 8'd1;
        end
    end
end

endmodule

module CLK_2_MODULE (
    input clk,
    input rst_n,
    input in_valid,
    input fifo_full,
    input [29:0] in_data,
    output reg out_valid,
    output reg [7:0] out_data,
    output reg busy
);

reg [2:0] ifmap_reg  [0:5][0:5];
reg [2:0] kernel_reg [0:3][0:5];

reg [2:0] in_count;
reg [2:0] ifmap_x;
reg [2:0] ifmap_y;
reg [2:0] kernel_idx;
reg [1:0] acc_count;
reg [7:0] psum_reg;

wire       load_fire = in_valid & !busy;
wire       calc_fire = busy & !fifo_full;
wire       acc_done = (acc_count == 2'd3);
wire       ifmap_x_done = (ifmap_x == 3'd4);
wire       ifmap_y_done = (ifmap_y == 3'd4);
wire       kernel_done = (kernel_idx == 3'd5);
wire       all_done = acc_done & ifmap_x_done & ifmap_y_done & kernel_done;

wire [2:0] ifmap_row = ifmap_x + {2'b0, acc_count[0]};
wire [2:0] ifmap_col = ifmap_y + {2'b0, acc_count[1]};
wire [5:0] product = ifmap_reg[ifmap_row][ifmap_col] * kernel_reg[acc_count][kernel_idx];
wire [7:0] psum_next = (acc_count == 2'd0) ? {2'b0, product} : (psum_reg + {2'b0, product});

integer row_idx;
integer col_idx;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        in_count <= 3'd0;
        busy <= 1'b0;
        for (row_idx = 0; row_idx < 6; row_idx = row_idx + 1) begin
            for (col_idx = 0; col_idx < 6; col_idx = col_idx + 1) begin
                ifmap_reg[row_idx][col_idx] <= 3'd0;
            end
        end
        for (row_idx = 0; row_idx < 4; row_idx = row_idx + 1) begin
            for (col_idx = 0; col_idx < 6; col_idx = col_idx + 1) begin
                kernel_reg[row_idx][col_idx] <= 3'd0;
            end
        end
    end
    else if (load_fire) begin
        kernel_reg[0][in_count] <= in_data[2:0];
        kernel_reg[1][in_count] <= in_data[5:3];
        kernel_reg[2][in_count] <= in_data[8:6];
        kernel_reg[3][in_count] <= in_data[11:9];
        ifmap_reg[0][in_count] <= in_data[14:12];
        ifmap_reg[1][in_count] <= in_data[17:15];
        ifmap_reg[2][in_count] <= in_data[20:18];
        ifmap_reg[3][in_count] <= in_data[23:21];
        ifmap_reg[4][in_count] <= in_data[26:24];
        ifmap_reg[5][in_count] <= in_data[29:27];

        if (in_count == 3'd5) begin
            in_count <= 3'd6;
            busy <= 1'b1;
        end
        else begin
            in_count <= in_count + 3'd1;
        end
    end
    else if (calc_fire & all_done) begin
        in_count <= 3'd0;
        busy <= 1'b0;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ifmap_x <= 3'd0;
        ifmap_y <= 3'd0;
        kernel_idx <= 3'd0;
        acc_count <= 2'd0;
        psum_reg <= 8'd0;
    end
    else if (load_fire & (in_count == 3'd5)) begin
        ifmap_x <= 3'd0;
        ifmap_y <= 3'd0;
        kernel_idx <= 3'd0;
        acc_count <= 2'd0;
        psum_reg <= 8'd0;
    end
    else if (calc_fire) begin
        psum_reg <= psum_next;

        if (acc_done) begin
            acc_count <= 2'd0;

            if (ifmap_x_done) begin
                ifmap_x <= 3'd0;

                if (ifmap_y_done) begin
                    ifmap_y <= 3'd0;
                    kernel_idx <= kernel_done ? 3'd0 : (kernel_idx + 3'd1);
                end
                else begin
                    ifmap_y <= ifmap_y + 3'd1;
                end
            end
            else begin
                ifmap_x <= ifmap_x + 3'd1;
            end
        end
        else begin
            acc_count <= acc_count + 2'd1;
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        out_valid <= 1'b0;
        out_data <= 8'd0;
    end
    else begin
        out_valid <= calc_fire & acc_done;
        out_data <= (calc_fire & acc_done) ? psum_next : 8'd0;
    end
end

endmodule

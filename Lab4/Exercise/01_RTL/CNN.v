module CNN
(
    //Input Port
    input clk,
    input rst_n,
    input in_valid,
    input [31:0] Img,
    input [31:0] Kernel_ch1,
    input [31:0] Kernel_ch2,
    input [31:0] Weight,
    input Opt,

    //Output Port
    output reg out_valid,
    output reg [31:0] out
    );


// IEEE floating point parameter
parameter inst_sig_width = 23;
parameter inst_exp_width = 8;
parameter inst_ieee_compliance = 0;
parameter inst_arch_type = 0;
parameter inst_arch = 0;
parameter inst_faithful_round = 0;

localparam  Input_R         = 4'd0,
            Input_G         = 4'd1,
            Input_B         = 4'd2,
            Padding         = 4'd3,
            Convolution     = 4'd4,
            MaxPooling      = 4'd5,
            Activation      = 4'd6,
            FullyConnected  = 4'd7,
            Softmax         = 4'd8,
            OUT             = 4'd9;
            
reg [3:0] state, next_state;
reg [2:0] x, y;
reg [2:0] x_d1, y_d1;
reg opt_reg;
reg [3:0] kernel_cnt;           //  3 channels 4 each
reg [4:0] weight_cnt;           //  8 weight 3 pairs
reg [2:0] act_cnt;              //  8 activation count
reg act_busy;
reg [2:0] fc_cycle;             //  1 warmup + 3 output neurons
reg [2:0] soft_cnt;             //  softmax compute counter
reg [1:0] out_cnt;              //  softmax output counter
integer i, j;
wire act_done;                  //  activation done signal (assign by activation module)
wire soft_div_done;
wire [1:0] soft_div_arrive_id;
wire [31:0] k1_final_conv_total, k2_final_conv_total;
wire mp_x, mp_y;
wire [1:0] mp_idx;
wire [31:0] act_data_in, act_data_out;
wire act_start;
reg [31:0] softmax_buffer [0:2];


always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        state <= Input_R;
    end
    else begin
        state <= next_state;
    end
end

always @(*) begin
    case(state)
        Input_R: begin
            next_state = (x == 3'd4 && y == 3'd4) ? Input_G : Input_R;
        end
        Input_G: begin
            next_state = (x == 3'd4 && y == 3'd4) ? Input_B : Input_G;
        end
        Input_B: begin
            next_state = (x == 3'd4 && y == 3'd4) ? Padding : Input_B;
        end
        Padding: begin
            next_state = Convolution;
        end
        Convolution: begin
            next_state = (x_d1 == 3'd5 && y_d1 == 3'd5) ? MaxPooling : Convolution;
        end
        MaxPooling: begin
            next_state = (x == 3'd3 && y == 3'd3) ? Activation : MaxPooling;
        end
        Activation: begin
            next_state = (act_cnt == 3'd7 && act_done) ? FullyConnected : Activation;
        end
        FullyConnected: begin // 4 cycles
            next_state = (fc_cycle == 3'd3) ? Softmax : FullyConnected;
        end
        Softmax: begin       // 3 cycles for exp, 3 launches for divider, then wait final arrive
            next_state = (soft_cnt == 3'd6 && soft_div_done && soft_div_arrive_id == 2'd2) ? OUT : Softmax;
        end
        OUT: begin          // 3 cycles
            next_state = (out_cnt == 2'd2) ? Input_R : OUT;
        end
        default: begin
            next_state = Input_R;
        end
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        opt_reg <= 1'b0;
    end else if(state == Input_R && in_valid && x == 3'd0 && y == 3'd0) begin       // first valid cycle
        opt_reg <= Opt;
    end else if(state == OUT && out_cnt == 2'd2) begin                              // Clear in last output cycle
        opt_reg <= 1'b0;
    end
end

// x_d1 : x delay 1 cycle, y_d1 : y delay 1 cycle
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        x_d1 <= 3'd0; 
        y_d1 <= 3'd0;
    end else begin
        x_d1 <= x;    
        y_d1 <= y;    
    end
end

// Count for state transition
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        fc_cycle <= 3'd0;
    end else if(state == FullyConnected) begin
        fc_cycle <= fc_cycle == 3'd3 ? 3'd0 : fc_cycle + 3'd1;
    end else begin
        fc_cycle <= 3'd0;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        out_cnt <= 2'd0;
    end else if(state == OUT) begin
        out_cnt <= out_cnt == 2'd2 ? 2'd0 : out_cnt + 2'd1;
    end else begin
        out_cnt <= 2'd0;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        soft_cnt <= 3'd0;
    end else if(state == Softmax) begin
        soft_cnt <= (soft_cnt == 3'd6) ? 3'd6 : soft_cnt + 3'd1;
    end else begin
        soft_cnt <= 3'd0;
    end
end

//kernel_cnt
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        kernel_cnt <= 4'd0;
    end
    else if(state == OUT) begin
        kernel_cnt <= 4'd0;                                                     // reset kernel_cnt after output
    end
    else if (in_valid == 1'b1) begin
        kernel_cnt <= kernel_cnt < 4'd12 ? kernel_cnt + 4'd1 : kernel_cnt;     // 12 kernels in total
    end 
    else begin
        kernel_cnt <= kernel_cnt;
    end
end

reg  [31:0] kernel1_R[0:3], 
            kernel1_G[0:3], 
            kernel1_B[0:3],
            kernel2_R[0:3],
            kernel2_G[0:3],
            kernel2_B[0:3];

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        for(i = 0; i < 4; i = i + 1) begin
            kernel1_R[i] <= 32'd0;
            kernel1_G[i] <= 32'd0;
            kernel1_B[i] <= 32'd0;
            kernel2_R[i] <= 32'd0;
            kernel2_G[i] <= 32'd0;
            kernel2_B[i] <= 32'd0;
        end
    end else begin
        if(kernel_cnt < 4'd4) begin             //R channel
            kernel1_R[kernel_cnt] <= Kernel_ch1;
            kernel2_R[kernel_cnt] <= Kernel_ch2; 
        end
        else if(kernel_cnt < 4'd8) begin        //G channel
            kernel1_G[kernel_cnt - 4] <= Kernel_ch1;
            kernel2_G[kernel_cnt - 4] <= Kernel_ch2;
        end
        else if(kernel_cnt < 4'd12) begin       //B channel
            kernel1_B[kernel_cnt - 8] <= Kernel_ch1;
            kernel2_B[kernel_cnt - 8] <= Kernel_ch2;
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        weight_cnt <= 5'd0;
    end
    else if(state == OUT) begin
        weight_cnt <= 5'd0;                                                     // Clear weight_cnt after output
    end
    else if (in_valid == 1'b1) begin
        weight_cnt <= weight_cnt < 5'd24 ? weight_cnt + 5'd1 : weight_cnt;    // 24 weights in total
    end 
    else begin
        weight_cnt <= weight_cnt;
    end
end

reg  [31:0] weight1 [0:7],
            weight2 [0:7],
            weight3 [0:7];

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        for(i = 0; i < 8; i = i + 1) begin
            weight1[i] <= 32'd0;
            weight2[i] <= 32'd0;
            weight3[i] <= 32'd0;
        end
    end
    else begin
        if(weight_cnt < 5'd8) begin
            weight1[weight_cnt] <= Weight;
        end
        else if(weight_cnt < 5'd16) begin
            weight2[weight_cnt - 8] <= Weight;
        end
        else if(weight_cnt < 5'd24) begin
            weight3[weight_cnt - 16] <= Weight;
        end
    end
end                  
        


//x, y
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        x <= 3'd0;
        y <= 3'd0;
    end
    else begin
        case(state)
            Input_R, Input_G, Input_B: begin
                if(in_valid) begin
                    if(x == 3'd4 && y == 3'd4) begin
                        x <= 3'd0;
                        y <= 3'd0;
                    end else if(x == 3'd4) begin
                        x <= 3'd0;
                        y <= y + 3'd1;
                    end
                    else begin
                        x <= x + 3'd1;
                        y <= y;
                    end
                end
            end
            Padding: begin
                x <= 3'd0;
                y <= 3'd0;
            end
            Convolution: begin
                if(x == 3'd5 && y == 3'd5) begin
                    x <= 3'd0;
                    y <= 3'd0;
                end else if(x == 3'd5 && y == 3'd5) begin
                    x <= 3'd0;
                    y <= 3'd0;
                end else if(x == 3'd5) begin
                    x <= 3'd0;
                    y <= y + 3'd1;
                end
                else begin
                    x <= x + 3'd1;
                    y <= y;
                end
            end
            MaxPooling: begin
                if(x == 3'd3 && y == 3'd3) begin
                    x <= 3'd0;
                    y <= 3'd0;
                end else if(x == 3'd3) begin
                    x <= 3'd0;
                    y <= y + 3'd3;
                end
                else begin
                    x <= x + 3'd3;
                    y <= y;
                end
            end
            default: begin
                x <= x;
                y <= y;
            end
        endcase
    end
end

reg [31:0] imgR [0:6][0:6];                                   
reg [31:0] imgG [0:6][0:6];
reg [31:0] imgB [0:6][0:6];
reg [31:0] pixel_buffer [0:7];          // store data after max pooling/activation
reg [31:0] fc_buffer [0:2];             // store data after fully connected layer (input of softmax)


always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        for(i = 0; i < 7; i = i + 1) begin
            for(j = 0; j < 7; j = j + 1) begin
                imgR[i][j] <= 32'd0;
                imgG[i][j] <= 32'd0;
                imgB[i][j] <= 32'd0;
            end
        end
    end
    else begin
        case(state)
            Input_R: begin
                if(in_valid) begin
                    imgR[y + 3'd1][x + 3'd1] <= Img;
                end
            end
            Input_G: begin
                if(in_valid) begin
                    imgG[y + 3'd1][x + 3'd1] <= Img;
                end
            end
            Input_B: begin
                if(in_valid) begin
                    imgB[y + 3'd1][x + 3'd1] <= Img;
                end
            end
            Padding: begin
                if(opt_reg == 1'b1) begin                  // Replication Padding
                    imgR[0][0] <= imgR[1][1];              // 4 Corners
                    imgR[0][6] <= imgR[1][5];
                    imgR[6][0] <= imgR[5][1];
                    imgR[6][6] <= imgR[5][5];

                    imgG[0][0] <= imgG[1][1];
                    imgG[0][6] <= imgG[1][5];
                    imgG[6][0] <= imgG[5][1];
                    imgG[6][6] <= imgG[5][5];

                    imgB[0][0] <= imgB[1][1];
                    imgB[0][6] <= imgB[1][5];
                    imgB[6][0] <= imgB[5][1];
                    imgB[6][6] <= imgB[5][5];

                    for(i = 1; i < 6; i = i + 1) begin
                        imgR[0][i] <= imgR[1][i];           // Top row
                        imgR[6][i] <= imgR[5][i];           // Bottom row
                        imgR[i][0] <= imgR[i][1];           // Left column
                        imgR[i][6] <= imgR[i][5];           // Right column
                        
                        imgG[0][i] <= imgG[1][i];
                        imgG[6][i] <= imgG[5][i];
                        imgG[i][0] <= imgG[i][1];
                        imgG[i][6] <= imgG[i][5];
                        
                        imgB[0][i] <= imgB[1][i];
                        imgB[6][i] <= imgB[5][i];
                        imgB[i][0] <= imgB[i][1];
                        imgB[i][6] <= imgB[i][5];
                    end
                end else begin                             // Zero padding
                    imgR[0][0] <= 32'd0;
                    imgR[0][6] <= 32'd0;
                    imgR[6][0] <= 32'd0;
                    imgR[6][6] <= 32'd0;

                    imgG[0][0] <= 32'd0;
                    imgG[0][6] <= 32'd0;
                    imgG[6][0] <= 32'd0;
                    imgG[6][6] <= 32'd0;

                    imgB[0][0] <= 32'd0;
                    imgB[0][6] <= 32'd0;
                    imgB[6][0] <= 32'd0;
                    imgB[6][6] <= 32'd0;

                    for(i = 1; i < 6; i = i + 1) begin
                        imgR[0][i] <= 32'd0;
                        imgR[6][i] <= 32'd0;
                        imgR[i][0] <= 32'd0;
                        imgR[i][6] <= 32'd0;

                        imgG[0][i] <= 32'd0;
                        imgG[6][i] <= 32'd0;
                        imgG[i][0] <= 32'd0;
                        imgG[i][6] <= 32'd0;

                        imgB[0][i] <= 32'd0;
                        imgB[6][i] <= 32'd0;
                        imgB[i][0] <= 32'd0;
                        imgB[i][6] <= 32'd0;
                    end
                end
            end
            Convolution: begin
                imgR[y_d1][x_d1] <= k1_final_conv_total;
                imgG[y_d1][x_d1] <= k2_final_conv_total;
            end
            OUT: begin              // Clear
                for(i = 0; i < 7; i = i + 1) begin
                    for(j = 0; j < 7; j = j + 1) begin
                        imgR[i][j] <= 32'd0;
                        imgG[i][j] <= 32'd0;
                        imgB[i][j] <= 32'd0;
                    end
                end
            end

        endcase
    end
end

// Convolution

wire [31:0] k1_conv_R0, k1_conv_R1, k1_conv_R2, k1_conv_R3,
            k1_conv_G0, k1_conv_G1, k1_conv_G2, k1_conv_G3,
            k1_conv_B0, k1_conv_B1, k1_conv_B2, k1_conv_B3;
reg  [31:0] k1_conv_R0_reg, k1_conv_R1_reg, k1_conv_R2_reg, k1_conv_R3_reg,
            k1_conv_G0_reg, k1_conv_G1_reg, k1_conv_G2_reg, k1_conv_G3_reg,
            k1_conv_B0_reg, k1_conv_B1_reg, k1_conv_B2_reg, k1_conv_B3_reg;           
wire [31:0] k2_conv_R0, k2_conv_R1, k2_conv_R2, k2_conv_R3,
            k2_conv_G0, k2_conv_G1, k2_conv_G2, k2_conv_G3,
            k2_conv_B0, k2_conv_B1, k2_conv_B2, k2_conv_B3;
reg  [31:0] k2_conv_R0_reg, k2_conv_R1_reg, k2_conv_R2_reg, k2_conv_R3_reg,
            k2_conv_G0_reg, k2_conv_G1_reg, k2_conv_G2_reg, k2_conv_G3_reg,
            k2_conv_B0_reg, k2_conv_B1_reg, k2_conv_B2_reg, k2_conv_B3_reg;             


reg  [31:0] mul0a, mul0b, mul1a, mul1b, mul2a,  mul2b,  mul3a, mul3b,
            mul4a, mul4b, mul5a, mul5b, mul6a,  mul6b,  mul7a, mul7b,
            mul8a, mul8b, mul9a, mul9b, mul10a, mul10b, mul11a, mul11b,
            mul12a, mul12b, mul13a, mul13b, mul14a, mul14b, mul15a, mul15b,
            mul16a, mul16b, mul17a, mul17b, mul18a, mul18b, mul19a, mul19b,
            mul20a, mul20b, mul21a, mul21b, mul22a, mul22b, mul23a, mul23b;

wire [31:0] mul0z, mul1z, mul2z, mul3z, mul4z, mul5z, mul6z, mul7z, mul8z, mul9z, mul10z, mul11z,
            mul12z, mul13z, mul14z, mul15z, mul16z, mul17z, mul18z, mul19z, mul20z, mul21z, mul22z, mul23z;
reg  [31:0] mul0z_reg, mul1z_reg, mul2z_reg, mul3z_reg, mul4z_reg, mul5z_reg, mul6z_reg, mul7z_reg,
            mul8z_reg, mul9z_reg, mul10z_reg, mul11z_reg, mul12z_reg, mul13z_reg, mul14z_reg, mul15z_reg,
            mul16z_reg, mul17z_reg, mul18z_reg, mul19z_reg, mul20z_reg, mul21z_reg, mul22z_reg, mul23z_reg;

assign k1_conv_R0 = mul0z;
assign k1_conv_R1 = mul1z;
assign k1_conv_R2 = mul2z;
assign k1_conv_R3 = mul3z;
assign k1_conv_G0 = mul4z;
assign k1_conv_G1 = mul5z;
assign k1_conv_G2 = mul6z;
assign k1_conv_G3 = mul7z;
assign k1_conv_B0 = mul8z;
assign k1_conv_B1 = mul9z;
assign k1_conv_B2 = mul10z;
assign k1_conv_B3 = mul11z;
assign k2_conv_R0 = mul12z;
assign k2_conv_R1 = mul13z;
assign k2_conv_R2 = mul14z;
assign k2_conv_R3 = mul15z;
assign k2_conv_G0 = mul16z;
assign k2_conv_G1 = mul17z;
assign k2_conv_G2 = mul18z;
assign k2_conv_G3 = mul19z;
assign k2_conv_B0 = mul20z;
assign k2_conv_B1 = mul21z;
assign k2_conv_B2 = mul22z;
assign k2_conv_B3 = mul23z;

always @(*) begin
    if(state == Convolution) begin
        // kernel 1
        mul0a = imgR[y][x];     mul0b = kernel1_R[0];
        mul1a = imgR[y][x+1];   mul1b = kernel1_R[1];
        mul2a = imgR[y+1][x];   mul2b = kernel1_R[2];
        mul3a = imgR[y+1][x+1]; mul3b = kernel1_R[3];

        mul4a = imgG[y][x];     mul4b = kernel1_G[0];
        mul5a = imgG[y][x+1];   mul5b = kernel1_G[1];
        mul6a = imgG[y+1][x];   mul6b = kernel1_G[2];
        mul7a = imgG[y+1][x+1]; mul7b = kernel1_G[3];

        mul8a = imgB[y][x];     mul8b = kernel1_B[0];
        mul9a = imgB[y][x+1];   mul9b = kernel1_B[1];
        mul10a = imgB[y+1][x];  mul10b = kernel1_B[2];
        mul11a = imgB[y+1][x+1];mul11b = kernel1_B[3];

        // kernel 2
        mul12a = imgR[y][x];     mul12b = kernel2_R[0];
        mul13a = imgR[y][x+1];   mul13b = kernel2_R[1];
        mul14a = imgR[y+1][x];   mul14b = kernel2_R[2];
        mul15a = imgR[y+1][x+1]; mul15b = kernel2_R[3];

        mul16a = imgG[y][x];     mul16b = kernel2_G[0];
        mul17a = imgG[y][x+1];   mul17b = kernel2_G[1];
        mul18a = imgG[y+1][x];   mul18b = kernel2_G[2];
        mul19a = imgG[y+1][x+1]; mul19b = kernel2_G[3];

        mul20a = imgB[y][x];     mul20b = kernel2_B[0];
        mul21a = imgB[y][x+1];   mul21b = kernel2_B[1];
        mul22a = imgB[y+1][x];   mul22b = kernel2_B[2];
        mul23a = imgB[y+1][x+1]; mul23b = kernel2_B[3];
    end else if(state == FullyConnected) begin
        mul0a = pixel_buffer[0]; mul0b = weight1[0];
        mul1a = pixel_buffer[0]; mul1b = weight2[0];
        mul2a = pixel_buffer[0]; mul2b = weight3[0];

        mul3a = pixel_buffer[1]; mul3b = weight1[1];
        mul4a = pixel_buffer[1]; mul4b = weight2[1];
        mul5a = pixel_buffer[1]; mul5b = weight3[1];

        mul6a = pixel_buffer[2]; mul6b = weight1[2];
        mul7a = pixel_buffer[2]; mul7b = weight2[2];
        mul8a = pixel_buffer[2]; mul8b = weight3[2];

        mul9a  = pixel_buffer[3]; mul9b = weight1[3];
        mul10a = pixel_buffer[3]; mul10b = weight2[3];
        mul11a = pixel_buffer[3]; mul11b = weight3[3];

        mul12a = pixel_buffer[4]; mul12b = weight1[4];
        mul13a = pixel_buffer[4]; mul13b = weight2[4];
        mul14a = pixel_buffer[4]; mul14b = weight3[4];

        mul15a = pixel_buffer[5]; mul15b = weight1[5];
        mul16a = pixel_buffer[5]; mul16b = weight2[5];
        mul17a = pixel_buffer[5]; mul17b = weight3[5];

        mul18a = pixel_buffer[6]; mul18b = weight1[6];
        mul19a = pixel_buffer[6]; mul19b = weight2[6];
        mul20a = pixel_buffer[6]; mul20b = weight3[6];

        mul21a = pixel_buffer[7]; mul21b = weight1[7];
        mul22a = pixel_buffer[7]; mul22b = weight2[7];
        mul23a = pixel_buffer[7]; mul23b = weight3[7];
    end else begin
        mul0a = 32'd0; mul0b = 32'd0; mul1a = 32'd0; mul1b = 32'd0;
        mul2a = 32'd0; mul2b = 32'd0; mul3a = 32'd0; mul3b = 32'd0;
        mul4a = 32'd0; mul4b = 32'd0; mul5a = 32'd0; mul5b = 32'd0;
        mul6a = 32'd0; mul6b = 32'd0; mul7a = 32'd0; mul7b = 32'd0;
        mul8a = 32'd0; mul8b = 32'd0; mul9a = 32'd0; mul9b = 32'd0;
        mul10a = 32'd0; mul10b = 32'd0; mul11a = 32'd0; mul11b = 32'd0;
        mul12a = 32'd0; mul12b = 32'd0; mul13a = 32'd0; mul13b = 32'd0;
        mul14a = 32'd0; mul14b = 32'd0; mul15a = 32'd0; mul15b = 32'd0;
        mul16a = 32'd0; mul16b = 32'd0; mul17a = 32'd0; mul17b = 32'd0;
        mul18a = 32'd0; mul18b = 32'd0; mul19a = 32'd0; mul19b = 32'd0;
        mul20a = 32'd0; mul20b = 32'd0; mul21a = 32'd0; mul21b = 32'd0;
        mul22a = 32'd0; mul22b = 32'd0; mul23a = 32'd0; mul23b = 32'd0;
    end
end

//24 FP multipliers (Reuse for convolution and fully connected layer)
DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_mult_inst0 (.a(mul0a),  .b(mul0b),  .rnd(3'b000), .z(mul0z), .status());
DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_mult_inst1 (.a(mul1a),  .b(mul1b),  .rnd(3'b000), .z(mul1z), .status());
DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_mult_inst2 (.a(mul2a),  .b(mul2b),  .rnd(3'b000), .z(mul2z), .status());
DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_mult_inst3 (.a(mul3a),  .b(mul3b),  .rnd(3'b000), .z(mul3z), .status());

DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_mult_inst4 (.a(mul4a),  .b(mul4b),  .rnd(3'b000), .z(mul4z), .status());
DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_mult_inst5 (.a(mul5a),  .b(mul5b),  .rnd(3'b000), .z(mul5z), .status());
DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_mult_inst6 (.a(mul6a),  .b(mul6b),  .rnd(3'b000), .z(mul6z), .status());
DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_mult_inst7 (.a(mul7a),  .b(mul7b),  .rnd(3'b000), .z(mul7z), .status());

DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_mult_inst8 (.a(mul8a),  .b(mul8b),  .rnd(3'b000), .z(mul8z), .status());
DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_mult_inst9 (.a(mul9a),  .b(mul9b),  .rnd(3'b000), .z(mul9z), .status());
DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_mult_inst10(.a(mul10a), .b(mul10b), .rnd(3'b000), .z(mul10z), .status());
DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_mult_inst11(.a(mul11a), .b(mul11b), .rnd(3'b000), .z(mul11z), .status());


DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_mult_inst12 (.a(mul12a), .b(mul12b), .rnd(3'b000), .z(mul12z), .status());
DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_mult_inst13 (.a(mul13a), .b(mul13b), .rnd(3'b000), .z(mul13z), .status());
DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_mult_inst14 (.a(mul14a), .b(mul14b), .rnd(3'b000), .z(mul14z), .status());
DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_mult_inst15 (.a(mul15a), .b(mul15b), .rnd(3'b000), .z(mul15z), .status());

DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_mult_inst16 (.a(mul16a), .b(mul16b), .rnd(3'b000), .z(mul16z), .status());
DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_mult_inst17 (.a(mul17a), .b(mul17b), .rnd(3'b000), .z(mul17z), .status());
DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_mult_inst18 (.a(mul18a), .b(mul18b), .rnd(3'b000), .z(mul18z), .status());
DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_mult_inst19 (.a(mul19a), .b(mul19b), .rnd(3'b000), .z(mul19z), .status());

DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_mult_inst20 (.a(mul20a), .b(mul20b), .rnd(3'b000), .z(mul20z), .status());
DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_mult_inst21 (.a(mul21a), .b(mul21b), .rnd(3'b000), .z(mul21z), .status());
DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_mult_inst22 (.a(mul22a), .b(mul22b), .rnd(3'b000), .z(mul22z), .status());
DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_mult_inst23 (.a(mul23a), .b(mul23b), .rnd(3'b000), .z(mul23z), .status());

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        mul0z_reg <= 32'd0;
        mul1z_reg <= 32'd0;
        mul2z_reg <= 32'd0;
        mul3z_reg <= 32'd0;
        mul4z_reg <= 32'd0;
        mul5z_reg <= 32'd0;
        mul6z_reg <= 32'd0;
        mul7z_reg <= 32'd0;
        mul8z_reg <= 32'd0;
        mul9z_reg <= 32'd0;
        mul10z_reg <= 32'd0;
        mul11z_reg <= 32'd0;
        mul12z_reg <= 32'd0;
        mul13z_reg <= 32'd0;
        mul14z_reg <= 32'd0;
        mul15z_reg <= 32'd0;
        mul16z_reg <= 32'd0;
        mul17z_reg <= 32'd0;
        mul18z_reg <= 32'd0;
        mul19z_reg <= 32'd0;
        mul20z_reg <= 32'd0;
        mul21z_reg <= 32'd0;
        mul22z_reg <= 32'd0;
        mul23z_reg <= 32'd0;
    end else begin
        mul0z_reg <= mul0z;
        mul1z_reg <= mul1z;
        mul2z_reg <= mul2z;
        mul3z_reg <= mul3z;
        mul4z_reg <= mul4z;
        mul5z_reg <= mul5z;
        mul6z_reg <= mul6z;
        mul7z_reg <= mul7z;
        mul8z_reg <= mul8z;
        mul9z_reg <= mul9z;
        mul10z_reg <= mul10z;
        mul11z_reg <= mul11z;
        mul12z_reg <= mul12z;
        mul13z_reg <= mul13z;
        mul14z_reg <= mul14z;
        mul15z_reg <= mul15z;
        mul16z_reg <= mul16z;
        mul17z_reg <= mul17z;
        mul18z_reg <= mul18z;
        mul19z_reg <= mul19z;
        mul20z_reg <= mul20z;
        mul21z_reg <= mul21z;
        mul22z_reg <= mul22z;
        mul23z_reg <= mul23z;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        k1_conv_R0_reg <= 32'd0;  k1_conv_R1_reg <= 32'd0;  k1_conv_R2_reg <= 32'd0;  k1_conv_R3_reg <= 32'd0;
        k1_conv_G0_reg <= 32'd0;  k1_conv_G1_reg <= 32'd0;  k1_conv_G2_reg <= 32'd0;  k1_conv_G3_reg <= 32'd0;
        k1_conv_B0_reg <= 32'd0;  k1_conv_B1_reg <= 32'd0;  k1_conv_B2_reg <= 32'd0;  k1_conv_B3_reg <= 32'd0;
        k2_conv_R0_reg <= 32'd0;  k2_conv_R1_reg <= 32'd0;  k2_conv_R2_reg <= 32'd0;  k2_conv_R3_reg <= 32'd0;
        k2_conv_G0_reg <= 32'd0;  k2_conv_G1_reg <= 32'd0;  k2_conv_G2_reg <= 32'd0;  k2_conv_G3_reg <= 32'd0;
        k2_conv_B0_reg <= 32'd0;  k2_conv_B1_reg <= 32'd0;  k2_conv_B2_reg <= 32'd0;  k2_conv_B3_reg <= 32'd0;
    end else begin
        k1_conv_R0_reg <= k1_conv_R0;  k1_conv_R1_reg <= k1_conv_R1;  k1_conv_R2_reg <= k1_conv_R2;  k1_conv_R3_reg <= k1_conv_R3;
        k1_conv_G0_reg <= k1_conv_G0;  k1_conv_G1_reg <= k1_conv_G1;  k1_conv_G2_reg <= k1_conv_G2;  k1_conv_G3_reg <= k1_conv_G3;
        k1_conv_B0_reg <= k1_conv_B0;  k1_conv_B1_reg <= k1_conv_B1;  k1_conv_B2_reg <= k1_conv_B2;  k1_conv_B3_reg <= k1_conv_B3;
        k2_conv_R0_reg <= k2_conv_R0;  k2_conv_R1_reg <= k2_conv_R1;  k2_conv_R2_reg <= k2_conv_R2;  k2_conv_R3_reg <= k2_conv_R3;
        k2_conv_G0_reg <= k2_conv_G0;  k2_conv_G1_reg <= k2_conv_G1;  k2_conv_G2_reg <= k2_conv_G2;  k2_conv_G3_reg <= k2_conv_G3;
        k2_conv_B0_reg <= k2_conv_B0;  k2_conv_B1_reg <= k2_conv_B1;  k2_conv_B2_reg <= k2_conv_B2;  k2_conv_B3_reg <= k2_conv_B3;
    end
end



wire [31:0] k1_temp_convsum0, k1_temp_convsum1, k1_temp_convsum2, k1_temp_convsum3,
            k1_final_conv0,   k1_final_conv1,   k1_final_conv2,   k1_final_conv3;
wire [31:0] k1_final_conv_sum0, k1_final_conv_sum1;
wire [31:0] k2_temp_convsum0, k2_temp_convsum1, k2_temp_convsum2, k2_temp_convsum3,
            k2_final_conv0,   k2_final_conv1,   k2_final_conv2,   k2_final_conv3;
wire [31:0] k2_final_conv_sum0, k2_final_conv_sum1;

// Fully Connected shared adder tree inputs
reg [31:0] fc_add0_in, fc_add1_in, fc_add2_in, fc_add3_in,
           fc_add4_in, fc_add5_in, fc_add6_in, fc_add7_in;
reg [31:0] shared_add_a0, shared_add_a1, shared_add_a2, shared_add_a3;
reg [31:0] shared_add_a4, shared_add_a5, shared_add_a6, shared_add_a7;
reg [31:0] shared_add_b0, shared_add_b1, shared_add_b2, shared_add_b3;
reg [31:0] shared_add_b4, shared_add_b5, shared_add_b6, shared_add_b7;
wire [31:0] shared_add_z0, shared_add_z1, shared_add_z2, shared_add_z3;
wire [31:0] shared_add_z4, shared_add_z5, shared_add_z6, shared_add_z7;

assign k1_temp_convsum0 = shared_add_z0;
assign k1_final_conv0   = shared_add_z1;
assign k1_temp_convsum1 = shared_add_z2;
assign k1_final_conv1   = shared_add_z3;
assign k1_temp_convsum2 = shared_add_z4;
assign k1_final_conv2   = shared_add_z5;
assign k1_temp_convsum3 = shared_add_z6;
assign k1_final_conv3   = shared_add_z7;

always @(*) begin
    shared_add_a0 = 32'd0; shared_add_b0 = 32'd0;
    shared_add_a1 = 32'd0; shared_add_b1 = 32'd0;
    shared_add_a2 = 32'd0; shared_add_b2 = 32'd0;
    shared_add_a3 = 32'd0; shared_add_b3 = 32'd0;
    shared_add_a4 = 32'd0; shared_add_b4 = 32'd0;
    shared_add_a5 = 32'd0; shared_add_b5 = 32'd0;
    shared_add_a6 = 32'd0; shared_add_b6 = 32'd0;
    shared_add_a7 = 32'd0; shared_add_b7 = 32'd0;

    case(state)
        Convolution: begin
            shared_add_a0 = k1_conv_R0_reg;   shared_add_b0 = k1_conv_G0_reg;
            shared_add_a1 = shared_add_z0;    shared_add_b1 = k1_conv_B0_reg;
            shared_add_a2 = k1_conv_R1_reg;   shared_add_b2 = k1_conv_G1_reg;
            shared_add_a3 = shared_add_z2;    shared_add_b3 = k1_conv_B1_reg;
            shared_add_a4 = k1_conv_R2_reg;   shared_add_b4 = k1_conv_G2_reg;
            shared_add_a5 = shared_add_z4;    shared_add_b5 = k1_conv_B2_reg;
            shared_add_a6 = k1_conv_R3_reg;   shared_add_b6 = k1_conv_G3_reg;
            shared_add_a7 = shared_add_z6;    shared_add_b7 = k1_conv_B3_reg;
        end
        FullyConnected: begin
            shared_add_a0 = fc_add0_in;       shared_add_b0 = fc_add1_in;
            shared_add_a1 = fc_add2_in;       shared_add_b1 = fc_add3_in;
            shared_add_a2 = fc_add4_in;       shared_add_b2 = fc_add5_in;
            shared_add_a3 = fc_add6_in;       shared_add_b3 = fc_add7_in;
            shared_add_a4 = shared_add_z0;    shared_add_b4 = shared_add_z1;
            shared_add_a5 = shared_add_z2;    shared_add_b5 = shared_add_z3;
            shared_add_a6 = shared_add_z4;    shared_add_b6 = shared_add_z5;
            shared_add_a7 = 32'd0;            shared_add_b7 = 32'd0;
        end
    endcase
end

DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_add_inst0 (
    .a(shared_add_a0), .b(shared_add_b0), .rnd(3'b000), .z(shared_add_z0), .status()
);
DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_add_inst1 (
    .a(shared_add_a1), .b(shared_add_b1), .rnd(3'b000), .z(shared_add_z1), .status()
);
DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_add_inst2 (
    .a(shared_add_a2), .b(shared_add_b2), .rnd(3'b000), .z(shared_add_z2), .status()
);
DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_add_inst3 (
    .a(shared_add_a3), .b(shared_add_b3), .rnd(3'b000), .z(shared_add_z3), .status()
);
DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_add_inst4 (
    .a(shared_add_a4), .b(shared_add_b4), .rnd(3'b000), .z(shared_add_z4), .status()
);
DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_add_inst5 (
    .a(shared_add_a5), .b(shared_add_b5), .rnd(3'b000), .z(shared_add_z5), .status()
);
DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_add_inst6 (
    .a(shared_add_a6), .b(shared_add_b6), .rnd(3'b000), .z(shared_add_z6), .status()
);
DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_add_inst7 (
    .a(shared_add_a7), .b(shared_add_b7), .rnd(3'b000), .z(shared_add_z7), .status()
);

// kernel1: Conv0 + Conv1 + Conv3 + Conv4
DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_add_inst8 (.a(k1_final_conv0),     .b(k1_final_conv1),     .rnd(3'b000), .z(k1_final_conv_sum0), .status());
DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_add_inst9 (.a(k1_final_conv2),     .b(k1_final_conv3),     .rnd(3'b000), .z(k1_final_conv_sum1), .status());
DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_add_inst10(.a(k1_final_conv_sum0), .b(k1_final_conv_sum1), .rnd(3'b000), .z(k1_final_conv_total), .status());

DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_add_inst11 (.a(k2_conv_R0_reg),   .b(k2_conv_G0_reg), .rnd(3'b000), .z(k2_temp_convsum0), .status());
DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_add_inst12 (.a(k2_temp_convsum0), .b(k2_conv_B0_reg), .rnd(3'b000), .z(k2_final_conv0), .status());
DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_add_inst13(.a(k2_conv_R1_reg),   .b(k2_conv_G1_reg), .rnd(3'b000), .z(k2_temp_convsum1), .status());
DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_add_inst14(.a(k2_temp_convsum1), .b(k2_conv_B1_reg), .rnd(3'b000), .z(k2_final_conv1), .status());
DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_add_inst15(.a(k2_conv_R2_reg),   .b(k2_conv_G2_reg), .rnd(3'b000), .z(k2_temp_convsum2), .status());
DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_add_inst16(.a(k2_temp_convsum2), .b(k2_conv_B2_reg), .rnd(3'b000), .z(k2_final_conv2), .status());
DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_add_inst17(.a(k2_conv_R3_reg),   .b(k2_conv_G3_reg), .rnd(3'b000), .z(k2_temp_convsum3), .status());
DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_add_inst18(.a(k2_temp_convsum3), .b(k2_conv_B3_reg), .rnd(3'b000), .z(k2_final_conv3), .status());

// kernel2: Conv0 + Conv1 + Conv3 + Conv4
DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_add_inst19 (.a(k2_final_conv0),     .b(k2_final_conv1),     .rnd(3'b000), .z(k2_final_conv_sum0), .status());
DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_add_inst20 (.a(k2_final_conv2),     .b(k2_final_conv3),     .rnd(3'b000), .z(k2_final_conv_sum1), .status());
DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_add_inst21(.a(k2_final_conv_sum0),  .b(k2_final_conv_sum1), .rnd(3'b000), .z(k2_final_conv_total), .status());

always @(*) begin
    case(fc_cycle)
        3'd1: begin
            fc_add0_in = mul0z_reg;   fc_add1_in = mul3z_reg;   fc_add2_in = mul6z_reg;   fc_add3_in = mul9z_reg;
            fc_add4_in = mul12z_reg;  fc_add5_in = mul15z_reg;  fc_add6_in = mul18z_reg;  fc_add7_in = mul21z_reg;
        end
        3'd2: begin
            fc_add0_in = mul1z_reg;   fc_add1_in = mul4z_reg;   fc_add2_in = mul7z_reg;   fc_add3_in = mul10z_reg;
            fc_add4_in = mul13z_reg;  fc_add5_in = mul16z_reg;  fc_add6_in = mul19z_reg;  fc_add7_in = mul22z_reg;
        end
        3'd3: begin
            fc_add0_in = mul2z_reg;   fc_add1_in = mul5z_reg;   fc_add2_in = mul8z_reg;   fc_add3_in = mul11z_reg;
            fc_add4_in = mul14z_reg;  fc_add5_in = mul17z_reg;  fc_add6_in = mul20z_reg;  fc_add7_in = mul23z_reg;
        end
        default: begin
            fc_add0_in = 32'd0;  fc_add1_in = 32'd0;  fc_add2_in = 32'd0;  fc_add3_in = 32'd0;
            fc_add4_in = 32'd0;  fc_add5_in = 32'd0;  fc_add6_in = 32'd0;  fc_add7_in = 32'd0;
        end
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        fc_buffer[0] <= 32'd0;
        fc_buffer[1] <= 32'd0;
        fc_buffer[2] <= 32'd0;
    end else if(state == FullyConnected && fc_cycle != 3'd0) begin
        case(fc_cycle)
            3'd1: fc_buffer[0] <= k1_temp_convsum3;
            3'd2: fc_buffer[1] <= k1_temp_convsum3;
            3'd3: fc_buffer[2] <= k1_temp_convsum3;
        endcase
    end else if(state == OUT && out_cnt == 2'd2) begin
        fc_buffer[0] <= 32'd0;
        fc_buffer[1] <= 32'd0;
        fc_buffer[2] <= 32'd0;
    end
end

// Softmax
// exp(zi) / (exp(z1) + exp(z2) + exp(z3))

reg [31:0]  softmax_exp_buffer [0:2];
wire [31:0] softmax_sum0, softmax_den;
reg [31:0]  softmax_exp_in;
wire [31:0] softmax_exp_out;
reg [31:0]  softmax_num_in;
wire [31:0] softmax_div_out;
wire [1:0]  soft_div_launch_id;
wire        soft_div_launch;

DW_fp_exp #(inst_sig_width, inst_exp_width, inst_ieee_compliance, 1) DW_fp_exp_soft0 (.a(softmax_exp_in), .z(softmax_exp_out), .status());
DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_add_soft0 (.a(softmax_exp_buffer[0]), .b(softmax_exp_buffer[1]), .rnd(3'b000), .z(softmax_sum0), .status());
DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_add_soft1 (.a(softmax_sum0), .b(softmax_exp_buffer[2]), .rnd(3'b000), .z(softmax_den), .status());
assign soft_div_launch = (state == Softmax) && (soft_cnt >= 3'd3) && (soft_cnt <= 3'd5);

assign soft_div_launch_id = (soft_cnt == 3'd3) ? 2'd0 :
                            (soft_cnt == 3'd4) ? 2'd1 :
                            (soft_cnt == 3'd5) ? 2'd2 : 2'd0;

always @(*) begin
    case(soft_cnt)
        3'd0: softmax_exp_in = fc_buffer[0];
        3'd1: softmax_exp_in = fc_buffer[1];
        3'd2: softmax_exp_in = fc_buffer[2];
        default: softmax_exp_in = 32'd0;
    endcase
end

always @(*) begin
    case(soft_cnt)
        3'd3: softmax_num_in = softmax_exp_buffer[0];
        3'd4: softmax_num_in = softmax_exp_buffer[1];
        3'd5: softmax_num_in = softmax_exp_buffer[2];
        default: softmax_num_in = 32'd0;
    endcase
end

localparam soft_op_iso_mode = 0;
localparam soft_id_width = 2;
localparam soft_in_reg = 0;
localparam soft_stages = 2;
localparam soft_out_reg = 0;
localparam soft_no_pm = 0;
localparam soft_rst_mode = 0;

DW_lp_piped_fp_div #(
    inst_sig_width, inst_exp_width, inst_ieee_compliance, inst_faithful_round, soft_op_iso_mode, soft_id_width, soft_in_reg, soft_stages, soft_out_reg, soft_no_pm, soft_rst_mode
) DW_fp_div_soft0 (
    .clk(clk),
    .rst_n(rst_n),
    .a(softmax_num_in),
    .b(softmax_den),
    .rnd(3'd0),
    .z(softmax_div_out),
    .launch(soft_div_launch),
    .launch_id(soft_div_launch_id),
    .accept_n(1'b0),
    .arrive(soft_div_done),
    .arrive_id(soft_div_arrive_id)
);

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        softmax_exp_buffer[0] <= 32'd0;
        softmax_exp_buffer[1] <= 32'd0;
        softmax_exp_buffer[2] <= 32'd0;
        softmax_buffer[0] <= 32'd0;
        softmax_buffer[1] <= 32'd0;
        softmax_buffer[2] <= 32'd0;
    end else if(state == Softmax) begin
        case(soft_cnt)
            3'd0: softmax_exp_buffer[0] <= softmax_exp_out;
            3'd1: softmax_exp_buffer[1] <= softmax_exp_out;
            3'd2: softmax_exp_buffer[2] <= softmax_exp_out;
        endcase
        if(soft_div_done) begin
            case(soft_div_arrive_id)
                2'd0: softmax_buffer[0] <= softmax_div_out;
                2'd1: softmax_buffer[1] <= softmax_div_out;
                2'd2: softmax_buffer[2] <= softmax_div_out;
            endcase
        end
    end else if(state == OUT && out_cnt == 2'd2) begin              // Clear
        softmax_exp_buffer[0] <= 32'd0;
        softmax_exp_buffer[1] <= 32'd0;
        softmax_exp_buffer[2] <= 32'd0;
        softmax_buffer[0] <= 32'd0;
        softmax_buffer[1] <= 32'd0;
        softmax_buffer[2] <= 32'd0;
    end
end


// Max Pooling
wire [31:0] k1_m0, k1_m1, k1_m2, k1_m3, k1_m4, k1_m5, k1_m6, k1_m7;
// level 1
DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_cmp_inst0 (.a(imgR[y][x]),     .b(imgR[y][x+1]),        .zctr(1'b1), .z0(k1_m0),  .status0());
DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_cmp_inst1 (.a(imgR[y][x+2]),   .b(imgR[y+1][x]),        .zctr(1'b1), .z0(k1_m1),  .status0());
DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_cmp_inst2 (.a(imgR[y+1][x+1]), .b(imgR[y+1][x+2]),      .zctr(1'b1), .z0(k1_m2),  .status0());
DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_cmp_inst3 (.a(imgR[y+2][x]),   .b(imgR[y+2][x+1]),      .zctr(1'b1), .z0(k1_m3),  .status0());
// level 2
DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_cmp_inst4 (.a(k1_m0),          .b(k1_m1),               .zctr(1'b1), .z0(k1_m4),  .status0());
DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_cmp_inst5 (.a(k1_m2),          .b(k1_m3),               .zctr(1'b1), .z0(k1_m5),  .status0());
// level 3
DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_cmp_inst6 (.a(k1_m4),          .b(k1_m5),               .zctr(1'b1), .z0(k1_m6),  .status0());
DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_cmp_inst7 (.a(k1_m6),          .b(imgR[y+2][x+2]),      .zctr(1'b1), .z0(k1_m7),  .status0());

wire [31:0] k2_m0, k2_m1, k2_m2, k2_m3, k2_m4, k2_m5, k2_m6, k2_m7;
// level 1
DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_cmp_inst8 (.a(imgG[y][x]),     .b(imgG[y][x+1]),        .zctr(1'b1), .z0(k2_m0),  .status0());
DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_cmp_inst9 (.a(imgG[y][x+2]),   .b(imgG[y+1][x]),        .zctr(1'b1), .z0(k2_m1),  .status0());
DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_cmp_inst10(.a(imgG[y+1][x+1]), .b(imgG[y+1][x+2]),      .zctr(1'b1), .z0(k2_m2),  .status0());
DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_cmp_inst11(.a(imgG[y+2][x]),   .b(imgG[y+2][x+1]),      .zctr(1'b1), .z0(k2_m3),  .status0());
// level 2
DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_cmp_inst12(.a(k2_m0),          .b(k2_m1),               .zctr(1'b1), .z0(k2_m4),  .status0());
DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_cmp_inst13(.a(k2_m2),          .b(k2_m3),               .zctr(1'b1), .z0(k2_m5),  .status0());
// level 3
DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_cmp_inst14 (.a(k2_m4),          .b(k2_m5),               .zctr(1'b1), .z0(k2_m6),  .status0());
DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance) DW_fp_cmp_inst15 (.a(k2_m6),          .b(imgG[y+2][x+2]),      .zctr(1'b1), .z0(k2_m7),  .status0());

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        pixel_buffer[0] <= 32'd0;
        pixel_buffer[1] <= 32'd0;
        pixel_buffer[2] <= 32'd0;
        pixel_buffer[3] <= 32'd0;
        pixel_buffer[4] <= 32'd0;
        pixel_buffer[5] <= 32'd0;
        pixel_buffer[6] <= 32'd0;
        pixel_buffer[7] <= 32'd0;
    end else begin
        case(state)
            MaxPooling: begin
                pixel_buffer[mp_idx] <= k1_m7;
                pixel_buffer[mp_idx + 3'd4] <= k2_m7;
            end
            Activation: begin
                if(act_done) begin
                    pixel_buffer[act_cnt] <= act_data_out;
                end
            end
            OUT: begin
                pixel_buffer[0] <= 32'd0;
                pixel_buffer[1] <= 32'd0;
                pixel_buffer[2] <= 32'd0;
                pixel_buffer[3] <= 32'd0;
                pixel_buffer[4] <= 32'd0;
                pixel_buffer[5] <= 32'd0;
                pixel_buffer[6] <= 32'd0;
                pixel_buffer[7] <= 32'd0;
            end
        endcase
    end
end

assign mp_x = x == 3'd3 ? 1'd1 : 1'd0;
assign mp_y = y == 3'd3 ? 1'd1 : 1'd0;
assign mp_idx = {mp_y, mp_x};

// Activation
assign act_data_in = pixel_buffer[act_cnt];
assign act_start = (state == Activation) && !act_busy;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        act_cnt <= 3'd0;
        act_busy <= 1'b0;
    end else if(state != Activation) begin
        act_cnt <= 3'd0;
        act_busy <= 1'b0;
    end else begin
        if(!act_busy) begin
            act_busy <= 1'b1;
        end else if(act_done) begin
            act_busy <= 1'b0;
            act_cnt <= (act_cnt == 3'd7) ? 3'd0 : act_cnt + 3'd1;
        end
    end
end

Activation_module Activation_inst (
    .clk(clk),
    .rst_n(rst_n),
    .in(act_data_in),
    .activation_in_valid(act_start),
    .activation_type(opt_reg),  // 0 for Sigmoid, 1 for tanh
    .out(act_data_out),
    .activation_done(act_done)
);

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        out_valid <= 1'b0;
        out <= 32'd0;
    end else if(state == OUT) begin
        out_valid <= 1'b1;
        case(out_cnt)
            2'd0: out <= softmax_buffer[0];
            2'd1: out <= softmax_buffer[1];
            2'd2: out <= softmax_buffer[2];
            default: out <= 32'd0;
        endcase
    end else begin
        out_valid <= 1'b0;
        out <= 32'd0;
    end
end


endmodule


module Activation_module(
    input clk,
    input rst_n,
    input [31:0] in,
    input activation_in_valid,
    input activation_type,      // 0 for Sigmoid, 1 for tanh
    output [31:0] out,
    output activation_done
);


// wire signed [65:0] neg_in = -in;                  Cannot use in fixed-point.
wire [31:0] neg_in = {~in[31], in[30:0]};            // IEEE754 floating point negation
wire [31:0] neg_2in;
wire [31:0] exp_neg_in, exp_neg_2in;
wire [31:0] tanh_neg_exp;
wire [31:0] sigmoid_denominator, tanh_numerator, tanh_denominator;
wire [31:0] div_result;
localparam  ONE = 32'h3F800000;                     // 1.0 in IEEE754 floating point

reg [31:0] div_numerator_reg, div_denominator_reg;
reg activation_valid_d1, activation_valid_d2;      // activation_valid delay1 and delay2

// For low power pipelined divider
localparam act_op_iso_mode = 0;
localparam act_id_width = 1;
localparam act_in_reg = 0;
localparam act_stages = 2;
localparam act_out_reg = 0;
localparam act_no_pm = 0;
localparam act_rst_mode = 0;

// Sigmoid : f(x) = 1 / (1 + exp(-x))
// Tanh : f(x) = (1 - exp(-2x)) / (1 + exp(-2x))

// -2x
DW_fp_add #(23, 8, 0) DW_fp_add_neg2x (
    .a(neg_in),
    .b(neg_in),
    .z(neg_2in),
    .rnd(3'b000),
    .status()
);

// e^(-x)
DW_fp_exp #(23, 8, 0, 1) DW_fp_exp_neg_inst (
    .a(neg_in),
    .z(exp_neg_in),
    .status()
);
// e^(-2x)
DW_fp_exp #(23, 8, 0, 1) DW_fp_exp_neg2_inst (
    .a(neg_2in),
    .z(exp_neg_2in),
    .status()
);
// -e^(-2x)
assign tanh_neg_exp = {~exp_neg_2in[31], exp_neg_2in[30:0]};
// Sigmoid denominator : 1 + exp(-x)
DW_fp_add #(23, 8, 0) DW_fp_add_act0 (
    .a(ONE),
    .b(exp_neg_in),
    .z(sigmoid_denominator),
    .rnd(3'b000),
    .status()
);

// Tanh denominator : 1 + e^(-2x)
DW_fp_add #(23, 8, 0) DW_fp_add_act1 (
    .a(ONE),
    .b(exp_neg_2in),
    .z(tanh_denominator),
    .rnd(3'b000),
    .status()
);
//Tanh numerator : 1 - e^(-2x)
DW_fp_add #(23, 8, 0) DW_fp_add_act2 (
    .a(ONE),
    .b(tanh_neg_exp),
    .z(tanh_numerator),
    .rnd(3'b000),
    .status()
);
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        div_numerator_reg <= 32'd0;
        div_denominator_reg <= 32'd0;
        activation_valid_d1 <= 1'b0;
        activation_valid_d2 <= 1'b0;
    end else begin
        activation_valid_d1 <= activation_in_valid;
        activation_valid_d2 <= activation_valid_d1;

        if(activation_in_valid) begin
            div_numerator_reg <= (activation_type == 1'b0) ? ONE : tanh_numerator;
            div_denominator_reg <= (activation_type == 1'b0) ? sigmoid_denominator : tanh_denominator;
        end
    end
end

DW_lp_piped_fp_div #(
    23, 8, 0, 0, act_op_iso_mode, act_id_width, act_in_reg, act_stages, act_out_reg, act_no_pm, act_rst_mode
) DW_lp_piped_fp_div_act_inst (
    .clk(clk),
    .rst_n(rst_n),
    .a(div_numerator_reg),
    .b(div_denominator_reg),
    .rnd(3'd0),
    .z(div_result),
    .launch(1'b1),
    .launch_id(1'd0),
    .accept_n(1'b0)
);

assign out = div_result;
assign activation_done = activation_valid_d2;

endmodule



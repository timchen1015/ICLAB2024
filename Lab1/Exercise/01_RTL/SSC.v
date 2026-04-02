module SSC(
    // Input signals
    input  [63:0]   card_num,
    input  [8:0]    input_money,
    input  [31:0]   snack_num,
    input  [31:0]   price,
    // Output signals
    output reg       out_valid,
    output reg [8:0] out_change
);


// assign card number in each digit
wire [3:0] card_num0 = card_num[3:0];
wire [3:0] card_num1 = card_num[7:4];
wire [3:0] card_num2 = card_num[11:8];
wire [3:0] card_num3 = card_num[15:12];
wire [3:0] card_num4 = card_num[19:16];
wire [3:0] card_num5 = card_num[23:20];
wire [3:0] card_num6 = card_num[27:24];
wire [3:0] card_num7 = card_num[31:28];
wire [3:0] card_num8 = card_num[35:32];
wire [3:0] card_num9 = card_num[39:36];
wire [3:0] card_num10 = card_num[43:40];
wire [3:0] card_num11 = card_num[47:44];
wire [3:0] card_num12 = card_num[51:48];
wire [3:0] card_num13 = card_num[55:52];
wire [3:0] card_num14 = card_num[59:56];
wire [3:0] card_num15 = card_num[63:60];  

//assign snack number in each type and price in each type
wire [3:0] snack_num0 = snack_num[3:0];
wire [3:0] snack_num1 = snack_num[7:4];
wire [3:0] snack_num2 = snack_num[11:8];
wire [3:0] snack_num3 = snack_num[15:12];
wire [3:0] snack_num4 = snack_num[19:16];
wire [3:0] snack_num5 = snack_num[23:20];
wire [3:0] snack_num6 = snack_num[27:24];
wire [3:0] snack_num7 = snack_num[31:28];

wire [3:0] price0 = price[3:0];
wire [3:0] price1 = price[7:4];
wire [3:0] price2 = price[11:8];
wire [3:0] price3 = price[15:12];
wire [3:0] price4 = price[19:16];
wire [3:0] price5 = price[23:20];
wire [3:0] price6 = price[27:24];
wire [3:0] price7 = price[31:28];

wire [7:0] total_price0 = snack_num0 * price0;
wire [7:0] total_price1 = snack_num1 * price1;
wire [7:0] total_price2 = snack_num2 * price2;
wire [7:0] total_price3 = snack_num3 * price3;
wire [7:0] total_price4 = snack_num4 * price4;
wire [7:0] total_price5 = snack_num5 * price5;
wire [7:0] total_price6 = snack_num6 * price6;
wire [7:0] total_price7 = snack_num7 * price7;

//function to double the value of card number in odd position, and its value is the sum of each digit if the result is larger than 9
// max value is 9
function [3:0] double_card_num_value;
    input [3:0] card_digit;
    begin
        case (card_digit)
            4'd0: double_card_num_value = 4'd0;
            4'd1: double_card_num_value = 4'd2;
            4'd2: double_card_num_value = 4'd4;
            4'd3: double_card_num_value = 4'd6;
            4'd4: double_card_num_value = 4'd8;
            4'd5: double_card_num_value = 4'd1;     // 1 + 0
            4'd6: double_card_num_value = 4'd3;     // 1 + 2
            4'd7: double_card_num_value = 4'd5;     // 1 + 4
            4'd8: double_card_num_value = 4'd7;     // 1 + 6
            4'd9: double_card_num_value = 4'd9;     // 1 + 8
            default: double_card_num_value = 4'd0; 
        endcase      
    end
endfunction

wire [7:0] total_card_num_value;           //max 9*16 = 144
assign total_card_num_value = card_num0 + double_card_num_value(card_num1) + card_num2 + double_card_num_value(card_num3) 
                            + card_num4 + double_card_num_value(card_num5) + card_num6 + double_card_num_value(card_num7) 
                            + card_num8 + double_card_num_value(card_num9) + card_num10 + double_card_num_value(card_num11) 
                            + card_num12 + double_card_num_value(card_num13) + card_num14 + double_card_num_value(card_num15);

//outvalid
always @(*) begin
    case(total_card_num_value)
        8'd0: out_valid = 1'b1;
        8'd10: out_valid = 1'b1;
        8'd20: out_valid = 1'b1;
        8'd30: out_valid = 1'b1;
        8'd40: out_valid = 1'b1;
        8'd50: out_valid = 1'b1;
        8'd60: out_valid = 1'b1;
        8'd70: out_valid = 1'b1;
        8'd80: out_valid = 1'b1;
        8'd90: out_valid = 1'b1;
        8'd100: out_valid = 1'b1;
        8'd110: out_valid = 1'b1;
        8'd120: out_valid = 1'b1;
        8'd130: out_valid = 1'b1;
        8'd140: out_valid = 1'b1;
        default: out_valid = 1'b0;
    endcase
end

//sort total price max 15*15 = 225
wire [7:0] max_total_price0, max_total_price1, max_total_price2, max_total_price3, max_total_price4, max_total_price5, max_total_price6, max_total_price7;
Sort8 sort(
    .in0(total_price0),
    .in1(total_price1),
    .in2(total_price2),
    .in3(total_price3),
    .in4(total_price4),
    .in5(total_price5),
    .in6(total_price6),
    .in7(total_price7),
    .out0(max_total_price0),   //max_total_price0 is the largest, max_total_price7 is the smallest
    .out1(max_total_price1),
    .out2(max_total_price2),
    .out3(max_total_price3),
    .out4(max_total_price4),
    .out5(max_total_price5),
    .out6(max_total_price6),
    .out7(max_total_price7) 
);

//total cost
reg [10:0] total_cost;  // max total cost is 225 * 8 = 1800
wire [10:0] buy0 = max_total_price0;
wire [10:0] buy1 = buy0 + max_total_price1;
wire [10:0] buy2 = buy1 + max_total_price2;
wire [10:0] buy3 = buy2 + max_total_price3;
wire [10:0] buy4 = buy3 + max_total_price4;
wire [10:0] buy5 = buy4 + max_total_price5;
wire [10:0] buy6 = buy5 + max_total_price6;
wire [10:0] buy7 = buy6 + max_total_price7;

always @(*) begin
    if(input_money >= buy7) total_cost = buy7;
    else if(input_money >= buy6) total_cost = buy6;
    else if(input_money >= buy5) total_cost = buy5;
    else if(input_money >= buy4) total_cost = buy4;
    else if(input_money >= buy3) total_cost = buy3;
    else if(input_money >= buy2) total_cost = buy2;
    else if(input_money >= buy1) total_cost = buy1;
    else if(input_money >= buy0) total_cost = buy0;
    else total_cost = 11'd0;
end


// ====================================================
// Use 7 + 6 + 5 + ... + 1 = 28 Adder
// ====================================================
// always @(*) begin
//     if(input_money >= (11'd0 + max_total_price0 + max_total_price1 + max_total_price2 + max_total_price3 + max_total_price4 + max_total_price5 + max_total_price6 + max_total_price7)) begin
//         total_cost = max_total_price0 + max_total_price1 + max_total_price2 + max_total_price3 + max_total_price4 + max_total_price5 + max_total_price6 + max_total_price7;
//     end
//     else if(input_money >= (11'd0 + max_total_price0 + max_total_price1 + max_total_price2 + max_total_price3 + max_total_price4 + max_total_price5 + max_total_price6))begin
//         total_cost = max_total_price0 + max_total_price1 + max_total_price2 + max_total_price3 + max_total_price4 + max_total_price5 + max_total_price6;
//     end
//     else if(input_money >= (11'd0 + max_total_price0 + max_total_price1 + max_total_price2 + max_total_price3 + max_total_price4 + max_total_price5)) begin
//         total_cost = max_total_price0 + max_total_price1 + max_total_price2 + max_total_price3 + max_total_price4 + max_total_price5;
//     end
//     else if(input_money >= (11'd0 + max_total_price0 + max_total_price1 + max_total_price2 + max_total_price3 + max_total_price4)) begin
//         total_cost = max_total_price0 + max_total_price1 + max_total_price2 + max_total_price3 + 	max_total_price4;
//     end
//     else if(input_money >= (11'd0 + max_total_price0 + max_total_price1 + max_total_price2 + max_total_price3)) begin
//         total_cost = max_total_price0 + max_total_price1 + 	max_total_price2 + 	max_total_price3;
//     end
//     else if(input_money >= (11'd0 + max_total_price0 + max_total_price1 + max_total_price2)) begin
//         total_cost = max_total_price0 + max_total_price1 + max_total_price2;
//     end
//     else if(input_money >= (11'd0 + max_total_price0 + max_total_price1)) begin
//         total_cost = max_total_price0 + max_total_price1;
//     end
//     else if(input_money >= (11'd0 + max_total_price0)) begin
//         total_cost = max_total_price0;
//     end
//     else total_cost = 11'd0;
// end

//outchange
always @(*) begin
    if(out_valid == 1'b0) begin
        out_change = input_money; //if card number is invalid, return all money
    end
    else begin
        out_change = input_money - total_cost; 
    end
end
endmodule


// bubble sort
module Sort8(
    input       [7:0] in0,
    input       [7:0] in1,
    input       [7:0] in2,
    input       [7:0] in3,
    input       [7:0] in4,
    input       [7:0] in5,
    input       [7:0] in6,
    input       [7:0] in7,
    output  reg [7:0] out0,   //out0 is the largest, out7 is the smallest
    output  reg [7:0] out1,
    output  reg [7:0] out2,
    output  reg [7:0] out3,
    output  reg [7:0] out4,
    output  reg [7:0] out5,
    output  reg [7:0] out6,
    output  reg [7:0] out7
);

//variable must declare outside always block
integer i, j;
reg [7:0] temp;
reg [7:0] val [0:7];

always @(*) begin
    //initialize the array
    val[0] = in0;
    val[1] = in1;
    val[2] = in2;
    val[3] = in3;
    val[4] = in4;
    val[5] = in5;
    val[6] = in6;
    val[7] = in7;

    for (i = 0; i < 8; i = i + 1) begin
        for (j = 0; j < 7 - i; j = j + 1) begin
            if (val[j] < val[j + 1]) begin
                //swap
                temp = val[j];
                val[j] = val[j + 1];
                val[j + 1] = temp;
            end
        end
    end
    out0 = val[0];
    out1 = val[1];
    out2 = val[2];
    out3 = val[3];
    out4 = val[4];
    out5 = val[5];
    out6 = val[6];
    out7 = val[7];
end
endmodule

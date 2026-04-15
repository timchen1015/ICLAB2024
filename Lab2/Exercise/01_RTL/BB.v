module BB(
    // Input Ports
    input        clk,
    input        rst_n,
    input        in_valid,
    input  [1:0] inning,   // Current inning number
    input        half,     // 0: top of the inning, 1: bottom of the inning
    input  [2:0] action,   // Action code

    // Output Ports
    output            out_valid,  // Result output valid
    output reg [7:0]  score_A,    // Score of team A (guest team)
    output reg [7:0]  score_B,    // Score of team B (home team)
    output     [1:0]  result      // 0: Team A wins, 1: Team B wins, 2: Draw
);

// Action parameters
localparam  WALK       = 3'd0,      // 保送
            SINGLE     = 3'd1,      // 1壘安打
            DOUBLE     = 3'd2,
            TRIPLE     = 3'd3,
            HOMERUN    = 3'd4,
            BUNT       = 3'd5,      // 犧牲打
            GROUNDBALL = 3'd6,      // 滾地球
            FLYBALL    = 3'd7;      // 飛球


reg [2:0]  base;            // base occupancy: 000-> no runner, 001-> base 1 occupied, 010-> base 2 occupied, 100-> base 3 occupied
reg [2:0] out_num;          //out number in current inning

reg [1:0]  next_state, state;
localparam  INIT =      2'd0, 
            A_ATTACK =  2'd1,
            B_ATTACK =  2'd2,
            DONE =      2'd3;
            
//helper wire, reg
wire double_play = (action == GROUNDBALL) && (out_num < 2'd2 && base[0] == 1'b1); 
reg stop_cal_score; // Stop when inning 3 and team B is attacking (Called game)
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        stop_cal_score <= 1'b0;
    end else if (inning == 2'd3 && half == 1'b0 && next_state == B_ATTACK && score_B > score_A) begin
        stop_cal_score <= 1'b1; // Stop calculating score when team B leading and is attacking in the 3rd inning
    end else if (state == DONE) begin
        stop_cal_score <= 1'b0; // Reset stop_cal_score for the next game
    end
end

// State transition
always @(negedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= INIT;
    end else begin
        state <= next_state;
    end
end

// Next state logic (may be double play in GROUNDBALL)
always @(*) begin
    case (state)
        INIT: begin
            next_state = A_ATTACK;
        end
        A_ATTACK: begin
            if (in_valid) begin
                if((out_num == 2'd2 && (action == BUNT || action == GROUNDBALL || action == FLYBALL)) || (out_num == 2'd1 && double_play)) next_state = B_ATTACK; // Switch to team B
                else next_state = A_ATTACK; // Stay in team A
            end
        end
        B_ATTACK: begin
            if (in_valid) begin
                if(out_num == 2'd2 && (action == BUNT || action == GROUNDBALL || action == FLYBALL) || (out_num == 2'd1 && double_play)) begin
                    if(inning == 2'd3 && half == 1'b1) next_state = DONE; // Game over after 3rd inning
                    else next_state = A_ATTACK; // Switch to team A
                end
                else next_state = B_ATTACK; // Stay in team B
            end
        end
        DONE: begin
            next_state = INIT; // Transition back to INIT after game is done to start a new game
        end
        default: next_state = A_ATTACK;
    endcase
end

//outnum
always @(negedge clk or negedge rst_n) begin
    if (!rst_n) begin
        out_num <= 2'd0;
    end else begin
        case (action)
            BUNT : begin
                if(out_num < 2'd2) out_num <= out_num + 1'd1;                   // Increment out number
                else out_num <= 2'd0;                                           // Reset out number after 3 outs
            end
            GROUNDBALL : begin
                if(out_num == 2'd0) begin                           
                    if(base[0] == 1'b1) out_num <= out_num + 2'd2;              // double play if runner on 1st base
                    else out_num <= out_num + 2'd1;
                end
                else if (out_num  == 2'd1) begin
                    if(base[0] == 1'b1) out_num <= 2'd0;                         // double play and reset out number if runner on 2nd base
                    else out_num <= out_num + 2'd1;
                end
                else out_num <=2'd0;                                           // Reset out number after 3 outs
            end
            FLYBALL : begin
                if(out_num < 2'd2) out_num <= out_num + 1'd1;                   // Increment out number
                else out_num <= 2'd0;                                           // Reset out number after 3 outs
            end
            default: out_num <= out_num; // No change in out number for other actions
        endcase
    end
end

//base, scoreA, scoreB
always @(negedge clk or negedge rst_n) begin
    if (!rst_n) begin
        base <= 3'b000;
        score_A <= 8'd0;
        score_B <= 8'd0;
    end else if (state == DONE) begin
        base <= 3'b000;                                                     // reset to start a new game
        score_A <= 8'd0;
        score_B <= 8'd0;
    end
    else if ((state == A_ATTACK && next_state == B_ATTACK) || (state == B_ATTACK && next_state == A_ATTACK) || (state == B_ATTACK && next_state == DONE)) begin
        base <= 3'b000;     // Reset base occupancy and keep score unchanged when switching teams
        score_A <= score_A; 
        score_B <= score_B;
    end else begin
        case(action)
            WALK: begin
                if(half == 1'b0) score_A <= score_A + (base == 3'b111);                 // Score only if all bases are occupied               
                else score_B <= score_B + (base == 3'b111);
                
                base[0] <= 1'b1;                                                        // Add new runner on 1st base
                base[1] <= base[1] | base[0];                                           // 2nd base occupied or base1 walk                 
                base[2] <= base[2] | (base[1] & base[0]);                               // 3rd base occupied or both base1 and base2 walk
            end
            SINGLE: begin
                if(half == 1'b0) score_A <= score_A + (base[2] == 1'b1) + (base[1] == 1'b1 && out_num == 2'd2); // Score if there's a runner on 3rd base or if there's a runner on 2nd base and early run
                else if(!stop_cal_score) score_B <= score_B + (base[2] == 1'b1) + (base[1] == 1'b1 && out_num == 2'd2);

                if(out_num == 2'd2) base <= (base << 2) | 3'b001;                       // Run early case : Shift base occupancy left by 2 and add new runner on 1st base
                else base <= (base << 1) | 3'b001;                                      // Shift base occupancy left and add new runner on 1st base
            end
            DOUBLE: begin
                if(half == 1'b0) score_A <= score_A + (base[2] == 1'b1) + (base[1] == 1'b1) + (base[0] == 1'b1 && out_num == 2'd2); // Score if there's a runner on 3rd base or 2nd base or 1st base and early run
                else if(!stop_cal_score) score_B <= score_B + (base[2] == 1'b1) + (base[1] == 1'b1) + (base[0] == 1'b1 && out_num == 2'd2);

                if(out_num == 2'd2) base <= (base << 3) | 3'b010;   // Run early case : Shift base occupancy left by 3 and add new runner on 2nd base
                else base <= (base << 2) | 3'b010;                  // Shift base occupancy left by 2 and add new runner on 2nd base
            end
            TRIPLE: begin
                if(half == 1'b0) score_A <= score_A + (base[2] == 1'b1) + (base[1] == 1'b1) + (base[0] == 1'b1); // Score if there's a runner on any base
                else if(!stop_cal_score) score_B <= score_B + (base[2] == 1'b1) + (base[1] == 1'b1) + (base[0] == 1'b1);
                base <= 3'b100;                                                                                  // New runner on 3rd base
            end
            HOMERUN: begin
                if(half == 1'b0) score_A <= score_A + (base[2] == 1'b1) + (base[1] == 1'b1) + (base[0] == 1'b1) + 1; // Score if there's a runner on any base plus the batter
                else if(!stop_cal_score) score_B <= score_B + (base[2] == 1'b1) + (base[1] == 1'b1) + (base[0] == 1'b1) + 1;
                base <= 3'b000;   // Clear bases after a home run
            end
            BUNT: begin
                if(half == 1'b0) score_A <= score_A + (base[2] == 1'b1);
                else if(!stop_cal_score) score_B <= score_B + (base[2] == 1'b1);
                base <= (base << 1);                            // Shift base occupancy left
            end
            GROUNDBALL: begin
                if(half == 1'b0) score_A <= score_A + (base[2] == 1'b1);
                else if(!stop_cal_score) score_B <= score_B + (base[2] == 1'b1);
                base <= (base << 1) & 3'b100;                   // Shift base occupancy left and mask base 1 and base 2
            end
            FLYBALL: begin
                if(half == 1'b0) score_A <= score_A + (base[2] == 1'b1);    //runner on 3rd base can score
                else if(!stop_cal_score) score_B <= score_B + (base[2] == 1'b1);
                base <= base & 3'b011;                                      // Clear runner on 3rd base, other bases remain unchanged
            end
        endcase
    end
end

//output result
assign out_valid = (state == DONE);
assign result = (out_valid) ? ((score_A > score_B) ? 2'b00 : (score_A < score_B) ? 2'b01 : 2'b10) : 2'b00; 

endmodule

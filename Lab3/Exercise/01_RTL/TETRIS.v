module TETRIS (
	//INPUT
	input rst_n,
	input clk,
	input in_valid,
	input [2:0] tetrominoes,
	input [2:0] position,
	//OUTPUT
	output reg tetris_valid,
	output reg score_valid,
	output reg fail,
	output reg [3:0] score,
	output reg [71:0] tetris
);

localparam  IDLE 	 = 2'd0,						// Wait for input
			DROP 	 = 2'd1,						// Process the dropping of the tetromino
			CLEAR	 = 2'd2;						// Clear lines and output

reg [1:0] 	state, next_state;
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		state <= IDLE;
	end else begin
		state <= next_state;
	end
end

always @(*) begin
	case(state)
		IDLE: begin
			next_state = in_valid ? DROP : IDLE; // Transition to DROP when in_valid is high
		end
		DROP: begin
			next_state = CLEAR; 				// Transition to CLEAR after processing the drop action
		end
		CLEAR: begin
			next_state = IDLE; 				    // Transition to IDLE after clearing the line
		end
		default: begin
			next_state = IDLE;
		end
	endcase
end

reg [3:0]   round;							   								// Count of rounds in current game(drop actions)
wire        game_end = ((state == CLEAR) && (round == 4'd15)) | fail;	    // The game ends after 16 rounds or when fail is true

always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		round <= 4'd0;
	end else if(state == CLEAR) begin
		round <= game_end ? 4'd0 : round + 4'd1;   							// Increment round after clear state, reset to 0 if game ends
	end
end


// Capture tetrominoes and position when in_valid is high
reg [2:0] t_reg, p_reg;
always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		t_reg <= 3'd0;
		p_reg <= 3'd0;
	end else if (in_valid && state == IDLE) begin
		t_reg <= tetrominoes;
		p_reg <= position;
	end
end

//shape define
reg [2:0] width, 									 	// width of the tetromino
		  bottom0_y, bottom1_y, bottom2_y, bottom3_y, 	// the distance of vertical axis to the bottom 4*4 base block
		  y0, y1, y2, y3; 								// the height of each column of the tetromino

reg [1:0] dot0_x, dot0_y, 								// each x, y coordinate of the 4 squares in the tetromino range(0-3)
		  dot1_x, dot1_y, 
		  dot2_x, dot2_y, 
		  dot3_x, dot3_y;	

// Shape definition for each tetromino type
always @(*) begin
	// Default values to avoid latches
	width 	= 3'd0;
	bottom0_y = 3'd0;
	bottom1_y = 3'd0;
	bottom2_y = 3'd0;
	bottom3_y = 3'd0;
	y0 = 3'd0;
	y1 = 3'd0;
	y2 = 3'd0;
	y3 = 3'd0;

	dot0_x = 2'd0;
	dot0_y = 2'd0;
	dot1_x = 2'd0;
	dot1_y = 2'd0;
	dot2_x = 2'd0;
	dot2_y = 2'd0;
	dot3_x = 2'd0;
	dot3_y = 2'd0;

	
	case(t_reg)
		3'd0: begin
			width = 3'd2;
			bottom0_y = 3'd0;
			bottom1_y = 3'd0;
			y0 = 3'd2;
			y1 = 3'd2;

			dot0_x = 2'd0; dot0_y = 2'd0;
			dot1_x = 2'd0; dot1_y = 2'd1;
			dot2_x = 2'd1; dot2_y = 2'd0;
			dot3_x = 2'd1; dot3_y = 2'd1;			
		end
		3'd1: begin
			width = 3'd1;
			bottom0_y = 3'd0;
			y0 = 3'd4;

			dot0_x = 2'd0; dot0_y = 2'd0;
			dot1_x = 2'd0; dot1_y = 2'd1;
			dot2_x = 2'd0; dot2_y = 2'd2;
			dot3_x = 2'd0; dot3_y = 2'd3;
		end
		3'd2: begin
			width = 3'd4;
			bottom0_y = 3'd0;
			bottom1_y = 3'd0;
			bottom2_y = 3'd0;
			bottom3_y = 3'd0;
			y0 = 3'd1;
			y1 = 3'd1;
			y2 = 3'd1;
			y3 = 3'd1;

			dot0_x = 2'd0; dot0_y = 2'd0;
			dot1_x = 2'd1; dot1_y = 2'd0;
			dot2_x = 2'd2; dot2_y = 2'd0;
			dot3_x = 2'd3; dot3_y = 2'd0;
		end
		3'd3: begin
			width = 3'd2;
			bottom0_y = 3'd2;
			bottom1_y = 3'd0;
			y0 = 3'd1;
			y1 = 3'd3;

			dot0_x = 2'd0; dot0_y = 2'd2;
			dot1_x = 2'd1; dot1_y = 2'd0;
			dot2_x = 2'd1; dot2_y = 2'd1;
			dot3_x = 2'd1; dot3_y = 2'd2;			
		end
		3'd4: begin
			width = 3'd3;
			bottom0_y = 3'd0;
			bottom1_y = 3'd1;
			bottom2_y = 3'd1;
			y0 = 3'd2;
			y1 = 3'd1;
			y2 = 3'd1;

			dot0_x = 2'd0; dot0_y = 2'd0;
			dot1_x = 2'd0; dot1_y = 2'd1;
			dot2_x = 2'd1; dot2_y = 2'd1;
			dot3_x = 2'd2; dot3_y = 2'd1;
		end
		3'd5: begin
			width = 3'd2;
			bottom0_y = 3'd0;
			bottom1_y = 3'd0;
			y0 = 3'd3;
			y1 = 3'd1;

			dot0_x = 2'd0; dot0_y = 2'd0;
			dot1_x = 2'd0; dot1_y = 2'd1;
			dot2_x = 2'd0; dot2_y = 2'd2;
			dot3_x = 2'd1; dot3_y = 2'd0;
		end
		3'd6: begin
			width = 3'd2;
			bottom0_y = 3'd1;
			bottom1_y = 3'd0;
			y0 = 3'd2;
			y1 = 3'd2;

			dot0_x = 2'd0; dot0_y = 2'd1;
			dot1_x = 2'd0; dot1_y = 2'd2;
			dot2_x = 2'd1; dot2_y = 2'd0;
			dot3_x = 2'd1; dot3_y = 2'd1;
		end
		3'd7: begin
			width = 3'd3;
			bottom0_y = 3'd0;
			bottom1_y = 3'd0;
			bottom2_y = 3'd1;
			y0 = 3'd1;
			y1 = 3'd2;
			y2 = 3'd1;

			dot0_x = 2'd0; dot0_y = 2'd0;
			dot1_x = 2'd1; dot1_y = 2'd0;
			dot2_x = 2'd1; dot2_y = 2'd1;
			dot3_x = 2'd2; dot3_y = 2'd1;
		end
	endcase
end

reg signed [4:0] Y0, Y1, Y2, Y3, Ybase; // Ybase is the base y-coordinate of the bottom of 4*4 base block
reg signed [5:0] top [0:5];				// Store 6 column heights (0-5)
reg [5:0] map [0:15];					// Extend 0:11 to 0:15 to avoid the boundary condition when dropping tetromino with height of 4
reg [5:0] next_map [0:15];				// Extend 0:11 to 0:15 to avoid boundary conditions when row overflow after dropping tetromino with height of 4

//map
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		for (integer i = 0; i < 16; i = i + 1) begin
			map[i] <= 6'd0;
		end
	end else begin
		case(state)
			IDLE: begin
				// No change to map in IDLE state
			end
			DROP: begin
				map[Ybase + dot0_y][p_reg + dot0_x] <= 1'b1;
				map[Ybase + dot1_y][p_reg + dot1_x] <= 1'b1;
				map[Ybase + dot2_y][p_reg + dot2_x] <= 1'b1;
				map[Ybase + dot3_y][p_reg + dot3_x] <= 1'b1;
			end
			CLEAR: begin
				for (integer i = 0; i < 16; i = i + 1) begin
					if (game_end) begin
						map[i] <= 6'd0; // Reset map when game ends
					end else begin
						map[i] <= next_map[i];
					end
				end
			end
		endcase
	end
end


// helper reg 
reg [3:0] filled_rows;			// count the number of filled next_map rows after clearing
reg [3:0] lines_cleared;				// count the number of lines cleared in the current drop action

//next map
always @(*) begin
	// Initialize next_map
	for (integer i = 0; i < 16; i = i + 1) begin
		next_map[i] = 6'b000000;
	end
	filled_rows   = 4'd0;
	lines_cleared = 4'd0;
	// Check for full lines and update next_map
	for (integer i = 0; i < 16; i = i + 1) begin
		if (map[i] != 6'b111111) begin
			// If the line not full, copy it to the next_map with the offset of filled_rows
			next_map[filled_rows] = map[i];
			filled_rows = filled_rows + 4'd1;
		end else begin
			// If the line is full, don't copy.
			lines_cleared = lines_cleared + 4'd1;
		end
	end
end


// Formula for calculating the drop position:
// Yi = top[x+i] - bottom_i_y    (i = 0, 1, 2, 3)  How much space can Ybase drop before the tetromino touches the existing blocks.
// Ybase = Max(Y0, Y1, Y2, Y3)   : baesment of 4*4 block
always @(*) begin
	Y0 = top[p_reg] 	 - $signed({1'b0, bottom0_y});
	// Add Condition to avoid calculating column larger than 5 (width of the map) and avoid calculating non-existing column in the tetromino (width of the tetromino)
	Y1 = (p_reg + 1 <= 5 && width > 3'd1) ? (top[p_reg + 1]  - $signed({1'b0, bottom1_y})) : 6'sd0;
	Y2 = (p_reg + 2 <= 5 && width > 3'd2) ? (top[p_reg + 2]  - $signed({1'b0, bottom2_y})) : 6'sd0;
	Y3 = (p_reg + 3 <= 5 && width > 3'd3) ? (top[p_reg + 3]  - $signed({1'b0, bottom3_y})) : 6'sd0;

	Ybase = Y0;
	if (Y1 > Ybase) Ybase = Y1; 
	if (Y2 > Ybase) Ybase = Y2;
	if (Y3 > Ybase) Ybase = Y3; 
end

// top update
//[Drop] Formula: top[i] =  Ybase + yi + bottom_i_y after dropping the tetromino
//[Clear] Scan next_map to update top 
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		for (integer i = 0; i < 6; i = i + 1) begin
			top[i] <= 6'd0;
		end
	end else begin
		case(state)
			IDLE: begin
			end
			DROP: begin
				top[p_reg] 	   <= Ybase + $signed({1'b0, y0}) + $signed({1'b0, bottom0_y}); // Update top for the column where the tetromino is dropped

				// Add condition to avoid updating others top column larger than width of the tetromino
				if (width > 3'd1) top[p_reg + 1] <= Ybase + $signed({1'b0, y1}) + $signed({1'b0, bottom1_y});
				if (width > 3'd2) top[p_reg + 2] <= Ybase + $signed({1'b0, y2}) + $signed({1'b0, bottom2_y});
				if (width > 3'd3) top[p_reg + 3] <= Ybase + $signed({1'b0, y3}) + $signed({1'b0, bottom3_y});
			end
			CLEAR: begin
				for (integer i = 0; i < 6; i = i + 1) begin
					if (game_end) begin
						top[i] <= 6'd0; // Reset top when game ends
					end else begin
						// Update top by scan next map
						for (integer j = 15; j >= 0; j = j - 1) begin
							if (next_map[j][i] == 1'b1) begin
								top[i] <= j + 1; // Update top to the highest occupied block in the column
								break; // Break after finding the highest occupied block
							end else if (j == 0) begin
								top[i] <= 6'd0; // If no blocks are occupied, reset top to 0
							end
						end
					end
				end
			end
			default: begin
				// No change to top in other states
			end
		endcase
	end
end




//stored score
reg signed [3:0] stored_score;
always @(posedge clk or negedge rst_n) begin
	if (!rst_n) begin
		stored_score <= 4'd0;
	end
	else if (state == CLEAR) begin
		if(game_end) begin
			stored_score <= 4'd0; 							// Reset stored_score when game ends
		end else begin
			stored_score <= stored_score + lines_cleared; 	// Score is the number of lines cleared in the current drop action
		end
	end
end

//output
always @(*) begin
	if(state == CLEAR) begin
		score_valid = 1'b1;
		score = stored_score + lines_cleared; 

		fail = ( (top[0] - $signed({1'b0, lines_cleared})) > 5'sd12 ) ||
               ( (top[1] - $signed({1'b0, lines_cleared})) > 5'sd12 ) ||
               ( (top[2] - $signed({1'b0, lines_cleared})) > 5'sd12 ) ||
               ( (top[3] - $signed({1'b0, lines_cleared})) > 5'sd12 ) ||
               ( (top[4] - $signed({1'b0, lines_cleared})) > 5'sd12 ) ||
               ( (top[5] - $signed({1'b0, lines_cleared})) > 5'sd12 );

		if(!fail && game_end) begin
			tetris = {next_map[11], next_map[10], next_map[9], next_map[8], next_map[7], next_map[6], next_map[5], next_map[4], next_map[3], next_map[2], next_map[1], next_map[0]};
			tetris_valid = 1'b1;
		end else begin
			tetris = 72'd0;
			tetris_valid = 1'b0;
		end	   
	end
	else begin
		score_valid = 1'b0;
		score = 4'd0;
		fail = 1'b0;
		tetris = 72'd0;
		tetris_valid = 1'b0;
	end
end



endmodule




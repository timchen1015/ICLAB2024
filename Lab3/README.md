# Lab3 TETRIS and PATTERN Design

## Part 1: TETRIS.v Design

###  Module Overview

The TETRIS module receives one tetromino input at a time (tetromino, position) and updates a 6-column playfield.
It outputs score-related signals every clear stage, and outputs final board data only when the game ends without fail.

### I/O Ports

| Port | Dir | Width | Description |
|---|---|---:|---|
| `rst_n` | In | `1` | Active-low reset. |
| `clk` | In | `1` | System clock. |
| `in_valid` | In | `1` | Input valid for one tetromino command. |
| `tetrominoes` | In | `[2:0]` | Tetromino type code (`0~7`). |
| `position` | In | `[2:0]` | Left anchor x-position (`0~5`) used for placement. |
| `tetris_valid` | Out | `1` | Final board valid flag. Asserted only at game end when `fail = 0`. |
| `score_valid` | Out | `1` | Score/fail output valid in CLEAR stage. |
| `fail` | Out | `1` | Overflow/game-over indicator. |
| `score` | Out | `[3:0]` | Accumulated cleared-line score. |
| `tetris` | Out | `[71:0]` | Packed 12x6 board snapshot at valid final output. |


###  View of Board and type Tetrominoes

![Board and Tetrominoes](img/board_and_tetrimino.png)


### Register Definition and Formula

![Variable Definition](img/variable.png)

Variables example in tetromino type 6:
- Yi (i = 0, 1, 2, 3) : Candidate landing Y-coordinates for the tetromino base in each column.
- Ybase : Reference Y-coordinate of the $4 \times 4$ bounding box.
- bottom_i_y (i = 0, 1, 2, 3) : Vertical offset from the $Y_{base}$ to the first occupied block in column $i$.
- yi (i = 0, 1, 2, 3) : The effective height (thickness) of the tetromino in column $i$.
- doti_x, doti_y (i = 0, 1, 2, 3) : Coordinates of the i-th block in the tetromino.


Formulas:
1. Formula for calculating the drop position:
```
	Yi = top[x+i] - bottom_i_y, for i = 0, 1, 2, 3
	Ybase = Max(Y0, Y1, Y2, Y3)
```    

2. Formula for updating top in DROP stage:
```
	top[i] = Ybase + yi + bottom_i_y
```

### Implementation Notes

1. Signed and unsigned arithmetic must be aligned with explicit signed extension.

```verilog
top[p_reg] <= Ybase + $signed({1'b0, y0}) + $signed({1'b0, bottom0_y});
```

2. When comparing against signed values, use signed literals (`'sd`) instead of unsigned (`'d`).

```verilog
((top[0] - $signed({1'b0, lines_cleared})) > 5'sd12)
```

3. Watch out for map out-of-bounds conditions. Even though the visible board is rows `0~11`, the implementation allocates 4 extra rows (`0~15`) to avoid overflow in intermediate cycles between DROP and CLEAR, especially when a new piece has just been dropped and has not been compacted yet.
```verilog
// reg [5:0] map [0:11];	
reg [5:0] map [0:15];	
```




## Part 2: PATTERN.v Design

// Undo yet

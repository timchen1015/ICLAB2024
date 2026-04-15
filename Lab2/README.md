# Lab 2: Baseball Game (BB)

## Design Concept

This implementation focuses on strictly following the specification without special tricks:

- Read `action` cycle by cycle and update base occupancy and score according to the rules.
- Use `out_num` to track outs and switch offense/defense when three outs are reached.
- Use `state` to control the game flow: `INIT -> A_ATTACK -> B_ATTACK -> DONE`.
- Output `out_valid` and `result` at game end, then reset internal states for the next game.

## I/O Ports

| Port | Dir | Width | Description |
|---|---|---:|---|
| `clk` | In | `1` | System clock |
| `rst_n` | In | `1` | Active-low reset |
| `in_valid` | In | `1` | Input valid |
| `inning` | In | `[1:0]` | Inning number |
| `half` | In | `1` | `0`: top (team A attacks), `1`: bottom (team B attacks) |
| `action` | In | `[2:0]` | Play action code |
| `out_valid` | Out | `1` | Result valid |
| `score_A` | Out | `[7:0]` | Team A score |
| `score_B` | Out | `[7:0]` | Team B score |
| `result` | Out | `[1:0]` | `00`: A wins, `01`: B wins, `10`: draw |

## Action Mapping

- `0`: WALK
- `1`: SINGLE
- `2`: DOUBLE
- `3`: TRIPLE
- `4`: HOMERUN
- `5`: BUNT
- `6`: GROUNDBALL
- `7`: FLYBALL

## Core Registers

- `out_num`: Number of outs in the current half-inning.
- `base[2:0]`: Base occupancy (`base[0]`: 1st, `base[1]`: 2nd, `base[2]`: 3rd).
- `score_A/score_B`: Team scores.

## Implementation Notes

- All baseball events (hit, walk, ground ball, fly ball, bunt) are handled with one consistent update rule set.
- `GROUNDBALL` includes double-play handling.
- Pay special attention to early-run behavior when `out_num == 2`: runners can advance more aggressively.

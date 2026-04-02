# Lab 1: Snack Shopping and Calculator(SSC)
## I/O Ports

| Port | Dir | Width | Description |
|---|---|---:|---|
| `card_num` | In | `[63:0]` | 16-digit credit card number, 4 bits per digit. Packing order (same as testbench): digit0 = `card_num[63:60]` ... digit15 = `card_num[3:0]`. |
| `input_money` | In | `[8:0]` | Money inserted. |
| `snack_num` | In | `[31:0]` | Quantities of 8 snack types, 4 bits per type. |
| `price` | In | `[31:0]` | Prices of 8 snack types, 4 bits per type. |
| `out_valid` | Out | `[0:0]` | `1` if the credit card number is valid, else `0`. |
| `out_change` | Out | `[8:0]` | Change after buying snacks from the highest total price to the lowest. If `out_valid == 0`, keep `out_change` the same as `input_money`. |

## Implementation Notes
- **Total cost (prefix-sum optimization)**: sort 8 snack total prices (high → low), build cumulative sums `buy0..buy7` (`buyk = buy(k-1) + max_total_pricek`), then pick the largest `buyk` such that `input_money >= buyk` as `total_cost`.

---



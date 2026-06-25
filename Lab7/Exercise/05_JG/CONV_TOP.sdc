create_clock -name clk1 -period 47.1 [get_ports clk1]
create_clock -name clk2 -period 10.1 [get_ports clk2]

set_clock_groups -asynchronous \
    -group [get_clocks clk1] \
    -group [get_clocks clk2]

set_input_delay  0 -clock clk1 [remove_from_collection [all_inputs] [get_ports {clk1 clk2 rst_n}]]
set_output_delay 0 -clock clk1 [all_outputs]

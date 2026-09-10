# Educational block budget, NOT the board XDC or an ASIC signoff constraint.
# 25 MHz: one rising-edge-to-rising-edge combinational budget per iteration.
create_clock -name divider_clk -period 40.000 [get_ports clk_i]
set_clock_uncertainty -setup 0.100 [get_clocks divider_clk]
set_clock_uncertainty -hold 0.050 [get_clocks divider_clk]

# Illustrative neighboring-register/board budgets, not measured interfaces.
set data_inputs [get_ports {start_i kill_i signed_i dividend_i[*] divisor_i[*]}]
set_input_delay -clock divider_clk -max 5.000 $data_inputs
set_input_delay -clock divider_clk -min 0.500 $data_inputs
set_output_delay -clock divider_clk -max 5.000 [all_outputs]
# A positive 0.5 ns external hold requirement is a NEGATIVE min output delay.
set_output_delay -clock divider_clk -min -0.500 [all_outputs]

# Functional-mode exercise: exclude the asynchronous reset port. This does
# NOT verify reset release/recovery/removal or an upstream reset synchronizer.
set_false_path -from [get_ports rst_ni]

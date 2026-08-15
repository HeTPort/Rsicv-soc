# Bo Chen Jing Xin ZYNQ MINI, PCB version 20240221/REVB.
# Device/package: XC7Z010-CLG400.  The package marking supplied with this board
# does not show a readable speed grade, so build.tcl targets conservative -1.
# Pins were transcribed from ZYNQ_MINI_REVB schematic and checked against the
# PCB silk.  Banks 34 and 35 use 3.3 V VCCO.

# Direct programmable-logic oscillator: X1, PL_CLK_50M, Bank 35 MRCC.
set_property -dict {PACKAGE_PIN K17 IOSTANDARD LVCMOS33} [get_ports clk_50m_i]
create_clock -name clk_50m -period 20.000 -waveform {0.000 10.000} [get_ports clk_50m_i]

# PL K2 / FPGA_PL_KEY1.  The board has a 4.7 kohm pull-up and the button pulls
# the signal low.  The internal pull-up keeps the input defined during handling.
set_property -dict {PACKAGE_PIN M20 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports reset_n_i]

# PL LEDs D1-D4 are active high through their series resistors.
set_property -dict {PACKAGE_PIN T12 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports {led_o[0]}]
set_property -dict {PACKAGE_PIN U12 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports {led_o[1]}]
set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports {led_o[2]}]
set_property -dict {PACKAGE_PIN W13 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports {led_o[3]}]

# External 3.3 V TTL UART on EXT IO/CAM1.  The onboard CH340 UART is connected
# to PS MIO48/MIO49 and cannot be driven by this PL-only top.
#   adapter TX -> U15 -> uart_rx_i
#   adapter RX <- W15 <- uart_tx_o
#   adapter GND -> EXT IO GND; leave adapter VCC disconnected.
set_property -dict {PACKAGE_PIN U15 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports uart_rx_i]
set_property -dict {PACKAGE_PIN W15 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports uart_tx_o]

# reset_n_i reaches only asynchronous reset controls/MMCM reset; release into
# the SoC is synchronized in top.sv.
set_false_path -from [get_ports reset_n_i]

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

# CrossyRoad-FPGA

Crossy Road hardware clone implemented in Verilog on the **Nexys 4DDR** (xc7a100tcsg324-1) FPGA development board.

**Module:** ES3B2 Digital Systems Design — University of Warwick

## Game Overview

A top-down scrolling game where the player controls a chicken navigating through procedurally generated lanes of traffic (cars, trucks), rivers (logs), and safe grass zones. Players can hop upward using the D-pad, or physically **flick the FPGA board** to perform a 2-lane Super Jump over dangerous chasms using the onboard accelerometer.
Hardware Requirements
Nexys 4DDR (Digilent) with Artix-7 xc7a100tcsg324-1

VGA monitor + VGA cable (or HDMI-to-VGA adapter)

Vivado 2024.1

Vivado Setup
Create new RTL project targeting xc7a100tcsg324-1

Add all .v files from src/ as design sources

Add constraints/crossy_road.xdc as constraints

Add testbench/tb_vga.v as simulation source

IP Catalog → Clocking Wizard:

Output clock clk_out1 = 106.47 MHz

Uncheck reset and locked

Click Generate

Set game_top.v as the top module

Run Synthesis → Implementation → Generate Bitstream

Program device via Hardware Manager

Input,Function
Flick Board,"Super Jump (Instantly clears 2 lanes, 2-sec cooldown)"
BTNU,Hop up (one lane)
BTND,Hop down
BTNL,Hop left
BTNR,Hop right
BTNC,Start / Restart
SW[0:2],Difficulty (future)
CPU_RESETN,Hardware reset
## Project Structure

```text
CrossyRoad-FPGA/
├── src/                        # Verilog source modules
│   ├── game_top.v              # Top-level: FSM, clock crossing, integration
│   ├── vga.v                   # VGA controller (1440×900 @ 60Hz)
│   ├── drawcon.v               # Pixel rendering engine (priority mux)
│   ├── player_ctrl.v           # Chicken movement, flick-jump math & boundary logic
│   ├── lane_manager.v          # LFSR procedural generation & world tracking
│   ├── adxl362_ctrl.v          # SPI Master for ADXL362 accelerometer
│   ├── camera_smoother.v       # Hardware interpolation for smooth screen panning
│   ├── score_display.v         # 7-segment multiplexed score display
│   └── debounce.v              # Button debounce (2-FF sync + counter)
├── constraints/
│   └── crossy_road.xdc         # Pin assignments for Nexys 4DDR
├── testbench/
│   └── tb_vga.v                # VGA timing verification testbench
├── coe/                        # Sprite data (.mem and .coe files for Block RAM)
├── docs/                       # Architecture diagrams & planning docs
└── README.md



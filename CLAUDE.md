# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a university research project for 3D magnetic force sensor visualization. It consists of two components:

1. **Arduino firmware** (`Qual_Sensor/Qual_Sensor.ino`) — reads 4x MLX90393 3-axis magnetic sensors over I2C and streams data via serial.
2. **Processing sketch** (`Three_Dimension_Force_Visualization.pde`) — currently empty; intended for real-time 3D visualization of sensor data.
3. **Data files** (`Data_Optimized.xlsx`, `Data_Processed.xlsx`) — calibration/measurement data for sensors H2, H4, H6 under applied forces (0.5 N steps) on X, Y, Z axes.

## Hardware Setup

- 4x MLX90393 sensors on a single I2C bus, addresses 0x0C–0x0F (set by A0/A1 pins)
- Unified config: digital filter level = 3, oversampling = 1, gain = `MLX90393_GAIN_5X`
- Baud rate: 115200
- Serial output: 12-column semicolon-delimited stream (`S1_X;S1_Y;S1_Z;...;S4_Z`)

## Arduino Firmware

- Toggle `DEBUG_MODE` (0/1) in `Qual_Sensor.ino` to switch between human-readable debug output and plotter-only mode
- Build/upload via Arduino IDE — target board should be compatible with `Wire.h` and `Adafruit_MLX90393` library
- Required libraries: `Wire` (built-in), `Adafruit_MLX90393`

## Data Analysis Context

The Excel files contain force calibration data for sensors H2, H4, H6. The analysis goal (from `Prompt.txt`) is:
- Use least-squares regression to compute per-axis sensitivity (output per unit force, in µT/N)
- Visualize sensitivity across sensors and axes
- Export a CSV summarizing cross-axis sensitivity (e.g., when Z-axis force is applied to H2, what are the X and Y sensitivities?)

CSV schema:
```
Sensor, Force Axis, Main Axis Sensitivity, Cross Axis 1, Cross Axis 1 Sensitivity, Cross Axis 2, Cross Axis 2 Sensitivity
```

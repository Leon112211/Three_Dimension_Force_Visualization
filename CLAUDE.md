# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**TDF_Visual** is a [Processing](https://processing.org/) sketch for visualizing three-dimensional magnetic force sensor data. Sensors measure magnetic field (uT) in response to applied force (N) along X/Y/Z axes. Three sensor models are used: **H2, H4, H6**.

The end goal is to compute per-axis sensitivity (uT/N) via least-squares regression and visualize cross-axis coupling between the primary loaded axis and the two orthogonal axes.

## Running the Sketch

Open the `TDF_Visual/` folder in the **Processing IDE** (4.x recommended) and press Run. There is no build step — Processing compiles all `.pde` tabs in the folder together as one program.

To run headless or via CLI:
```
processing-java --sketch=/path/to/TDF_Visual --run
```

## File Architecture

Each `.pde` file is a **tab** compiled into the same sketch. Execution starts in `TDF_Visual.pde`.

| File | Role |
|------|------|
| `TDF_Visual.pde` | Main entry — `setup()` and `draw()` loop. Calls `initReceiver()` in setup and `updateReceiver()` in draw. Add visualization draw calls here. |
| `SensorReceiver.pde` | Serial port manager. Reads CSV lines from the connected sensor via `serialEvent()`. Exposes globals `sensorBx/By/Bz`, `newDataAvailable`, and helper `isReceiverReady()`. |

**Data flow:** `Single_Sensor` firmware → USB Serial → `serialEvent()` → `parseCSVLine()` → globals → `draw()` renders.

## Serial / Data Format

- Baud rate: `115200` (constant `BAUD_RATE` in `SensorReceiver.pde`)
- Port: auto-detected by matching `PORT_HINT = "COM"` against `Serial.list()`
- Accepted CSV line formats (3, 4, or 6 columns):
  - `Bx,By,Bz`
  - `SensorID,Bx,By,Bz`
  - `Bx,By,Bz,Fx,Fy,Fz`

## Coding Rules

- **No Chinese characters in any `text()` calls, `println()` output, or string literals rendered on-screen.** Use English only in all visual HUD elements and console output to prevent encoding/garbled-text issues on Windows.
- Chinese is acceptable in comments only.
- All sensitivity analysis output targets a CSV with columns: sensor model → primary axis → sensitivity (uT/N) → coupling axis 1 → sensitivity → coupling axis 2 → sensitivity.

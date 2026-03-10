# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**TDF_Visual** is a [Processing](https://processing.org/) sketch for visualizing three-dimensional magnetic force sensor data. Sensors measure magnetic field (uT) in response to applied force (N) along X/Y/Z axes. Three sensor models are used: **H2, H4, H6**.

Core math: given a sensitivity matrix **S** (uT/N) mapping force → magnetic field, the decoupling matrix **D = S⁻¹** (N/uT) recovers real force from magnetic readings via **F = D × ΔV**, where ΔV is the baseline-subtracted magnetic field vector.

## Running the Sketch

Open the `TDF_Visual/` folder in the **Processing IDE** (4.x recommended) and press Run. There is no build step — Processing compiles all `.pde` tabs in the folder together as one program.

```
processing-java --sketch=/path/to/TDF_Visual --run
```

## File Architecture

Each `.pde` file is a **tab** compiled into the same sketch. Execution starts in `TDF_Visual.pde`.

| File | Role |
|------|------|
| `TDF_Visual.pde` | Main entry — `setup()`, `draw()`, `keyPressed()`. Orchestrates all modules. |
| `SensorReceiver.pde` | Serial port manager. Reads CSV from sensor via `serialEvent()`. Globals: `sensorBx/By/Bz`, `newDataAvailable`. |
| `Baseline.pde` | Collects 300 samples on startup to compute zero-force baseline (`baselineX/Y/Z`). Shows 3 parallel progress bars. |
| `Decoupling.pde` | Stores S and D=S⁻¹ matrices for H2/H4/H6. `computeForce(dVx, dVy, dVz)` → `forceX/Y/Z`. Includes `invert3x3()` / `det3x3()` utilities. |
| `MatrixHUD.pde` | Interactive overlay to inspect S and D matrices. Toggle with [M], switch sensor [1/2/3], toggle S/D [T]. |

**Data flow:**
```
Serial CSV → SensorReceiver → Baseline (300 samples) → Decoupling (F = D × ΔV) → draw() HUD
                                                          ↕
                                                    MatrixHUD (interactive)
```

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `M` | Show / hide matrix panel |
| `T` | Toggle between S (uT/N) and D (N/uT) view |
| `1` / `2` / `3` | Select sensor H2 / H4 / H6 |

## Serial / Data Format

- Baud rate: `115200` (constant `BAUD_RATE` in `SensorReceiver.pde`)
- Port: auto-detected by matching `PORT_HINT = "COM"` against `Serial.list()`
- Accepted CSV line formats (3, 4, or 6 columns):
  - `Bx,By,Bz`
  - `SensorID,Bx,By,Bz`
  - `Bx,By,Bz,Fx,Fy,Fz`

## Sensitivity Data

Stored in `Processed_Data.xlsx`. Format per sensor block (6 columns):
```
Primary_Axis | Sensitivity | Coupling1 | Sensitivity | Coupling2 | Sensitivity
```
Sensitivity values in uT/N. Empty cells default to 0. The matrices are hardcoded in `Decoupling.pde` after extraction.

## Coding Rules

- **No Chinese characters in any `text()` calls, `println()` output, or string literals rendered on-screen.** Use English only in all visual HUD elements and console output to prevent encoding/garbled-text issues on Windows.
- Chinese is acceptable in code comments only.

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**TDF_Visual** is a [Processing](https://processing.org/) sketch that visualizes three-dimensional magnetic-force sensor data in real time. A magnetic sensor (MLX90393) measures field strength (uT) that varies with applied force (N) along X/Y/Z. Three sensor *models* are supported — **H2, H4, H6** — each with its own calibration.

Core math: given a sensitivity matrix **S** (uT/N) mapping force → field, the decoupling matrix **D = S⁻¹** (N/uT) recovers force from field readings via **F = D × ΔV**, where ΔV is the baseline-subtracted field vector. See `Math_Principle.png`.

## Running the Sketch

Open the `TDF_Visual/` folder in the **Processing IDE** (4.x) and press Run. There is no build step — Processing compiles every `.pde` tab in the folder together as one program. Execution starts in `TDF_Visual.pde`.

```
processing-java --sketch=/path/to/TDF_Visual --run
```

The Arduino firmware in `Single_Sensor/Single_Sensor.ino` is the data source: an MLX90393 streaming `x,y,z` numeric frames at 115200 baud. Keep its `DEBUG_MODE` at `0` so the stream stays machine-readable (debug lines are `#`-prefixed and ignored by the receiver, but `0` avoids the overhead).

## Sensitivity Data Pipeline

Matrices are **not** hardcoded — they are loaded at runtime. On every startup `initDecoupling()` (in `Decoupling.pde`):

1. **`runDataConversion()`** shells out to `convert_data.py` via `ProcessBuilder`, trying `python`, `python3`, then `C:\Program Files\Python3xx\python.exe`. The script reads `Processed_Data.xlsx` (needs `openpyxl`) and rewrites `sensitivity_data.csv`. If no Python is found it logs a warning and continues with the existing CSV.
2. **`loadSensitivityCSV("sensitivity_data.csv")`** parses the CSV into `S_ALL[sensor][row][col]`. Format is a `# Name` header line followed by 3 rows of `v,v,v` per sensor (S rows = Bx/By/Bz, cols = Fx/Fy/Fz, uT/N; empty/`N/A` → 0).
3. **`D_ALL[s] = invert3x3(S_ALL[s])`** — a singular matrix logs a warning and falls back to a zero matrix.

To change calibration values: edit `Processed_Data.xlsx` and ensure Python+openpyxl are installed, **or** edit `sensitivity_data.csv` directly (the source of truth the sketch actually reads). The xlsx block layout is documented in `convert_data.py` (3 sensor blocks at column offsets 0/6/12, rows 3–5).

## File Architecture

Each `.pde` file is a **tab** in one sketch (shared global namespace).

| File | Role |
|------|------|
| `TDF_Visual.pde` | Main entry — `settings/setup/draw`, all input handlers (`keyPressed`, `mousePressed/Dragged/Released`), top HUD, design-space scaling, no-connection screen. |
| `SensorReceiver.pde` | Serial manager. `serialEvent()` parses CSV → `sensorBx/By/Bz`, `newDataAvailable`. Skips/counts bad frames. |
| `Baseline.pde` | Averages 100 valid samples on startup → `baselineX/Y/Z`. Shows 3 progress bars; state machine `BS_IDLE/SAMPLING/DONE`. |
| `Decoupling.pde` | Builds/loads S and D=S⁻¹ for H2/H4/H6. `computeForce()` → `forceX/Y/Z`. Holds `invert3x3()`/`det3x3()`. |
| `ForceView.pde` | Left: 3D force arrows (offscreen P3D buffer `_pg3d`, drag to rotate). Right: bidirectional bar chart Fx/Fy/Fz/\|F\|. |
| `PressureGrid.pde` | Z-axis "pressure pad" — dot matrix swelling green→red with `forceZ` (offscreen P3D `_pgGrid`, free-orbit drag, Reset button, threshold slider `pgFzRef`). |
| `TangentialCompass.pde` | XY force as a center-pivot compass arrow, color cyan→red with magnitude. Threshold slider `tcFxyRef`. |
| `SensorPlot.pde` | Scrolling Bx/By/Bz waveform from a ring buffer (`PLOT_HISTORY=300`, baseline-subtracted). |
| `MatrixHUD.pde` | Always-visible S/D matrix overlay (top-right). Clickable sensor tabs + S/D toggle. |
| `Theme.pde` | Shared palette (`UI_*` colors), fonts, and panel/badge drawing helpers. |

**Data flow:**
```
xlsx → convert_data.py → sensitivity_data.csv ─┐ (startup, once)
                                               v
Serial CSV → SensorReceiver → Baseline (100) → Decoupling (F = D×ΔV) → draw() panels
                                                                          |
                                              MatrixHUD / PressureGrid / Compass (interactive)
```

## Rendering Architecture (read before touching any UI)

All drawing happens in a **fixed design space** of `DESIGN_W × DESIGN_H = 1350 × 940`. `draw()` wraps every panel in `translate(_uiOffsetX, _uiOffsetY); scale(_uiScale)` to letterbox-fit the resizable window (`updateUILayout()`). Consequences:

- **Always position panels in design coordinates** (the constants like `FV_3D_X`, `SP_Y`, etc.). Never use raw `width`/`height` for layout.
- **Hit-test mouse with `uiMouseX()/uiMouseY()`** (and `uiPMouseX/Y` for deltas), which convert window pixels back into design space. Using raw `mouseX/mouseY` for clicks/drags will be wrong whenever the window isn't at 1× scale.
- The main canvas is **P2D**; `ForceView` and `PressureGrid` render to **offscreen P3D** `PGraphics`, then `image()`-blit onto the P2D canvas.

`draw()` gates on phase: if serial isn't ready → no-connection screen; else feed the plot buffer; if baseline not done → calibration HUD; else compute force and draw all panels. On a non-finite serial frame `computeForce` is skipped and the **last valid force is held** (`_lastDV*`).

### UI conventions (Theme.pde)
- Colors: per-axis `UI_X/UI_Y/UI_Z` (blue/green/orange), plus `UI_BG/PANEL/TEXT/MUTED/BORDER/GOOD/WARN/DANGER`.
- Fonts: call `useUIFont(size)` (Segoe UI) or `useMonoFont(size)` (Cascadia Mono) — don't set fonts manually.
- Panels: build with `drawPanelBase()` (filled) / `drawPanelFrame()` (border-only) / `drawPanelTitle()` / `drawBadge()` so every panel looks consistent.
- After custom text, reset with `textAlign(LEFT, BASELINE); useUIFont(14);` (the established pattern at the end of each draw fn).

## Controls

Keyboard (`keyPressed` in `TDF_Visual.pde` → `handleMatrixKey`):

| Key | Action |
|-----|--------|
| `T` | Toggle S (uT/N) ↔ D (N/uT) matrix view |
| `1` / `2` / `3` | Select sensor H2 / H4 / H6 |
| `C` | Recalibrate baseline (`initBaseline()`) |

Mouse (only active after baseline + serial ready): **Calibration** button (top HUD), MatrixHUD **sensor tabs** + **S/D toggle**, drag the 3D Force panel to rotate, free-orbit + **Reset** the Pressure panel, and drag the **Threshold sliders** on the Pressure (`pgFzRef`) and Compass (`tcFxyRef`) panels. The `mousePressed`/`mouseDragged`/`mouseReleased` dispatchers live in `TDF_Visual.pde`.

> Note: the code is authoritative where docs disagree — `README.md` is in Chinese and slightly stale (it says 300 baseline samples and an `M` panel toggle; neither matches current code).

## Serial / Data Format

- Baud: `115200` (`BAUD_RATE`). Port: auto-selected by matching `PORT_HINT = "COM"` in `Serial.list()`, else the last port.
- Accepted frames (`;` is normalized to `,`): `Bx,By,Bz` · `SensorID,Bx,By,Bz` (col 0 dropped) · `Bx,By,Bz,Fx,Fy,Fz` (trailing force cols currently unused).
- Lines starting with `#`, or containing `:`/`=`, are treated as debug/header and skipped; non-finite values are rejected and counted (`receiverBadFrameCount()`).

## Coding Rules

- **No Chinese characters in any `text()` call, `println()` output, or on-screen string literal.** English only in all HUD elements and console output — prevents garbled text / encoding issues on Windows. Chinese is fine in code comments.
- Globals are shared across all tabs; follow the existing `_lowerCamel` convention for module-private state and `UPPER_CASE` for `static final` layout/config constants.

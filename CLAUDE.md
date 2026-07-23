# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**TDF_Visual** is a [Processing](https://processing.org/) sketch that visualizes three-dimensional magnetic-force sensor data in real time. A magnetic sensor (MLX90393) embedded under a magnet-in-PDMS structure measures field strength (uT) that varies with applied force (N) along X/Y/Z. Three sensor *models* are supported — **H2, H4, H6** — each with its own calibration.

Core math: given a sensitivity matrix **S** (uT/N) mapping force → field, the decoupling matrix **D = S⁻¹** (N/uT) recovers force from field readings via **F = D × ΔV**, where ΔV is the baseline-subtracted field vector. See `Math_Principle.png`.

This is a **single git repository** (branches: `main`, `dev`; remote on GitHub) containing two parts:

```
TDF_Visual/            ← Processing sketch (visualization) + host-side bridges
└── TDF_DataProcess/   ← calibration data pipeline (raw data + Python analysis)
```

`TDF_DataProcess` was formerly a separate repo; its pre-merge standalone history lives in `D:\FILES\Projects\_backup_TDF_DataProcess_20260630\` (full `.git` preserved — do not delete that folder).

## Running the Sketch

Open the `TDF_Visual/` folder in the **Processing IDE** (4.x) and press Run. There is no build step — Processing compiles every `.pde` tab in the folder together as one program (subfolders like `TDF_DataProcess/` are ignored by Processing). Execution starts in `TDF_Visual.pde`.

On startup the sketch shows a **data-source chooser** (two cards): **Serial (USB)** or **Bluetooth LE**. Keys `S`/`B` work too. Baseline calibration starts after a source is picked. `ESC` (or the top-HUD SOURCE button) returns to the chooser at any time (hot-swap).

### Firmware (two variants, same `x,y,z` text protocol)

| Sketch | Transport | Notes |
|---|---|---|
| `Single_Sensor/Single_Sensor.ino` | USB serial, 115200 baud | Original wired firmware. |
| `BLE_Arduino/BLE_Arduino.ino` | BLE (ESP32-C3, Nordic UART Service) | Device name `TDF_Sensor`; notifies `x,y,z\n` frames at **100 Hz** (`OUTPUT_INTERVAL_MS=10`). I2C on GPIO8/9 at 100 kHz; MLX address auto-probed 0x0C–0x0F (100/50 kHz). A failed sensor read emits the sentinel `-1,-1,-1`; an absent sensor streams `0,0,0`. BLE init runs before sensor init so the device always advertises. |

Keep `DEBUG_MODE` at `0` in both so the stream stays machine-readable (debug lines are `#`-prefixed and ignored by the receiver).

BLE reaches Processing via **`ble_bridge.py`** (Python + `bleak`, launched automatically by the sketch like `convert_data.py`): it scans by name/service-UUID, subscribes to the NUS TX characteristic, forwards frames verbatim to stdout (data) and status lines to stderr, and reconnects forever with 2 s backoff. NUS UUIDs are documented in both the bridge and the firmware and must match.

## Sensitivity Data Pipeline

Two stages, upstream → downstream:

**Stage 1 — calibration analysis (`TDF_DataProcess/`, run manually when calibration data changes):**
`python process_sensitivity.py` (console output is **Chinese**; needs numpy/pandas/matplotlib/openpyxl) reads the 158 raw CSVs under `Raw_Data/`, computes per-level means, fits least-squares sensitivities **with R²/max-residual reporting** (warns when main-channel R² < `R2_WARN_THRESHOLD = 0.98`), regenerates `Plots/sensitivity_H*.png`, rewrites the idempotent `Computed_Means` sheet in `Raw_Data/xyz_H2H4H6数据汇总.xlsx`, and writes the S matrices into `TDF_DataProcess/Processed_Data.xlsx` (rolling `.bak` backups before each save; layout: 3 sensor blocks at column offsets 0/6/12, rows 3–5).

**Stage 2 — sketch startup (`initDecoupling()` in `Decoupling.pde`):**
1. `runDataConversion()` shells out to `convert_data.py` (tries `python`, `python3`, then `C:\Program Files\Python3xx\python.exe`), which reads **the repo-root `Processed_Data.xlsx`** and rewrites `sensitivity_data.csv`. If no Python is found it logs a warning and continues with the existing CSV.
2. `loadSensitivityCSV("sensitivity_data.csv")` parses into `S_ALL[sensor][row][col]` (rows Bx/By/Bz, cols Fx/Fy/Fz; empty/`N/A` → 0).
3. `D_ALL[s] = invert3x3(S_ALL[s])` — singular → warning + zero matrix.

⚠️ **Two copies of `Processed_Data.xlsx` exist**: the repo root one (read by `convert_data.py`) and `TDF_DataProcess/Processed_Data.xlsx` (written by the pipeline). They are synced manually — keep this in mind when calibration values change.

### Raw calibration data facts (matter for any ML/analysis work)

- Layout: `Raw_Data/<date folder>/<prefix>/<prefix>_<sensor>/<force>.csv`, force names use `_` for the decimal (`0_5.csv` = 0.5 N). X: 0–3 N ×7 levels (H2/H4/H6); Y: 0–3 N ×7 (H2/H6 — **Y-H4 raw CSVs are lost**; its 7 per-level By means survive in the summary xlsx rows 11–19); Z: 0–20 N ×41 (H2/H4/H6). ~500 static frames per file, all values in uT.
- **Every CSV's last line is a logger-appended column-mean row, not a sample** — always load via `read_raw_csv()` in `process_sensitivity.py` (importable: the module has a `main()` guard).
- Known data issues: Z-H2 has a fixture-shift artifact between the 15 N and 15.5 N files (~-134 uT step); Y-H6's z1 cross response exceeds its main channel (calibration geometry suspect); linearity is **sensor-dependent** (H6 essentially linear, H2/H4 genuinely nonlinear at high Z loads).
- `TDF_DataProcess/AI_Calibration_Plan.pdf` documents the planned ML-calibration experiments (residual learning vs polynomial vs MLP, level-held-out splits) and paper strategy.

## File Architecture

Each `.pde` file is a **tab** in one sketch (shared global namespace).

| File | Role |
|------|------|
| `TDF_Visual.pde` | Main entry — `settings/setup/draw`, input dispatchers, top HUD (readouts + right-side control column: REC / SOURCE / FPS / Calibration), design-space scaling, no-connection screen. |
| `Connection.pde` | Data-source state machine (`CONN_NONE/SERIAL/BLE`), startup chooser UI, BLE bridge process management (launch `ble_bridge.py`, stdout→parser / stderr→status threads, shutdown hook), Back button, `isConnectionReady()`, `resetToChooser()` hot-swap. |
| `SensorReceiver.pde` | Frame parser shared by both transports. `parseCSVLine()` → `sensorBx/By/Bz`, `newDataAvailable`; accepts `Bx,By,Bz` · `SensorID,Bx,By,Bz` · `Bx,By,Bz,Fx,Fy,Fz`. Time-based `isStreamLive()` (400 ms window) drives the LIVE/HOLD badge. |
| `CsvExport.pde` | Manual CSV recording. REC/STOP button; rows appended on the **data thread** at full sample rate into `csv_export/` (`rec_<ts>.tmp.csv` → renamed on stop); name dialog runs async on the AWT EDT (never block the animation thread — it deadlocks NEWT); crash-rescue of leftover tmp files. Columns: epoch_ms, t_ms, B, ΔB, F. |
| `Baseline.pde` | Averages 100 valid samples → `baselineX/Y/Z`; progress bars; state machine `BS_IDLE/SAMPLING/DONE`. |
| `Decoupling.pde` | Loads S, computes D=S⁻¹, `computeForce()` → `forceX/Y/Z` (Z clamped ≥ 0). `invert3x3()`/`det3x3()`. |
| `ForceView.pde` | Left: 3D force arrows (offscreen P3D `_pg3d`, drag to rotate). Right: bar chart Fx/Fy/Fz/\|F\|. |
| `PressureGrid.pde` | Z-axis dot-matrix pressure pad (offscreen P3D, free-orbit drag, Reset). Visual dent scale = `forceZ * FZ_SCALE * pgZGain` — `pgZGain` is display-only, never touches computed values. |
| `TangentialCompass.pde` | XY force as a center-pivot compass arrow. |
| `SensorPlot.pde` | Scrolling ΔB waveform (ring buffer, points slider + Reset). |
| `RangePanel.pde` | Global per-axis display ranges (X/Y/Z sliders + XY lock + Reset) **plus the DENT slider** (`pgZGain`, 0.2–5×, geometric map). Right edge aligned at x=1320 with the panels above. |
| `MatrixHUD.pde` | S/D matrix overlay, sensor tabs + S/D toggle. |
| `Theme.pde` | Palette (`UI_*`), fonts (`useUIFont/useMonoFont`), panel/badge helpers. |

**Data flow:**
```
TDF_DataProcess: Raw_Data CSVs → process_sensitivity.py → Processed_Data.xlsx
                                     (manual sync to repo-root copy)
repo root: Processed_Data.xlsx → convert_data.py → sensitivity_data.csv → Decoupling
Serial: Single_Sensor.ino ──USB──► serialEvent ─┐
BLE:    BLE_Arduino.ino ──NUS──► ble_bridge.py ──stdout thread─┤
                                                               ▼
                              parseCSVLine → Baseline → F = D×ΔV → draw() panels
                                        └─→ CsvExport (REC) → csv_export/*.csv
```

## Rendering Architecture (read before touching any UI)

All drawing happens in a **fixed design space** of `DESIGN_W × DESIGN_H = 1350 × 940`. `draw()` wraps every panel in `translate(_uiOffsetX, _uiOffsetY); scale(_uiScale)` to letterbox-fit the resizable window. Consequences:

- **Always position panels in design coordinates** (constants like `FV_3D_X`, `RP_X`). Never use raw `width`/`height` for layout.
- **Hit-test mouse with `uiMouseX()/uiMouseY()`** (and `uiPMouseX/Y` for deltas). Raw `mouseX/mouseY` is wrong whenever the window isn't at 1× scale.
- Main canvas is **P2D**; `ForceView` and `PressureGrid` render to offscreen **P3D** `PGraphics`, then `image()`-blit.
- Top-HUD control column: four equal controls (`HUD_BTN_W=200`, `H=30`, gap 8) stacked at x=634..834, rows y=38/76/114/152 — all derived from `HUD_BTN_*` constants in `TDF_Visual.pde`.

`draw()` gates in order: chooser (if `connMode == CONN_NONE`) → no-connection screen (+Back) → BLE waiting-for-first-frame screen (+Back) → baseline HUD → panels. On a non-finite frame `computeForce` is skipped and the last valid force is held.

### UI conventions (Theme.pde)
- Colors: per-axis `UI_X/UI_Y/UI_Z` (blue/green/orange), plus `UI_BG/PANEL/TEXT/MUTED/BORDER/GOOD/WARN/DANGER`.
- Fonts: `useUIFont(size)` / `useMonoFont(size)` — don't set fonts manually.
- Panels: `drawPanelBase()` / `drawPanelFrame()` / `drawPanelTitle()` / `drawBadge()`.
- After custom text, reset with `textAlign(LEFT, BASELINE); useUIFont(14);`.

## Controls

Keyboard (`keyPressed` in `TDF_Visual.pde`):

| Key | Context | Action |
|-----|---------|--------|
| `S` / `B` | chooser screen | Pick Serial / BLE |
| `ESC` | connected | Back to source chooser (does not quit) |
| `T` | running | Toggle S ↔ D matrix view |
| `1` / `2` / `3` | running | Select sensor H2 / H4 / H6 |
| `C` | running | Recalibrate baseline |

Mouse (active after baseline + connection ready): **REC** (start/stop CSV recording → name dialog), **SOURCE** (hot-swap transport via chooser), **Calibration**, MatrixHUD sensor tabs + S/D toggle, drag 3D Force panel, free-orbit + Reset on Pressure panel, RangePanel sliders (X/Y/Z ranges, XY lock, DENT, Reset), waveform points slider. Dispatchers live in `TDF_Visual.pde`.

## Serial / Data Format

- Serial: baud `115200`, port auto-selected by `PORT_HINT = "COM"`, else last port.
- BLE: `ble_bridge.py` prints the same frames to stdout; `Connection.pde` reads them on a daemon thread and calls the same `parseCSVLine()`.
- Accepted frames (`;` normalized to `,`): `Bx,By,Bz` · `SensorID,Bx,By,Bz` (col 0 dropped) · `Bx,By,Bz,Fx,Fy,Fz` (trailing force cols currently unused).
- Lines starting with `#`, or containing `:`/`=`, are skipped; non-finite values rejected and counted (`receiverBadFrameCount()`).

## Coding Rules

- **No Chinese characters in any `text()` call, `println()` output, or on-screen string literal in the Processing sketch.** English only in HUD elements and console output — prevents garbled text on Windows. Chinese is fine in code comments. (**Exception:** the Python pipeline in `TDF_DataProcess/` deliberately prints Chinese console output; its plot labels stay English.)
- Globals are shared across all tabs; follow `_lowerCamel` for module-private state and `UPPER_CASE` for `static final` constants.
- Swing/AWT dialogs must never run on the Processing animation thread (deadlocks against the NEWT window) — use `SwingUtilities.invokeLater` (see `CsvExport.pde`).

> Note: the code is authoritative where docs disagree — `README.md` is in Chinese and stale.

// ============================================================
// SensorPlot.pde
// Real-time scrolling waveform of Bx / By / Bz sensor readings.
// Ring buffer holds the most recent PLOT_HISTORY frames.
// Auto-scales Y axis to fit data range with padding.
//
// Public API:
//   initPlot()    — call in setup()
//   updatePlot()  — call in draw() each frame (pushes new data)
//   drawPlot()    — call in draw() to render the chart
//
// Reads globals: sensorBx, sensorBy, sensorBz,
//                baselineX/Y/Z, isBaselineDone()
// ============================================================

// --- layout ---
static final int SP_X = 30;
static final int SP_Y = 630;
static final int SP_W = 1290;
static final int SP_H = 280;

// --- data ---
static final int PLOT_HISTORY = 300;   // frames to keep

float[] _spBx, _spBy, _spBz;
int     _spHead  = 0;    // next write index (ring buffer)
int     _spCount = 0;    // total samples stored (up to PLOT_HISTORY)

// --- colors (project palette) ---
color SP_COL_BX = 0xFF508CFF;   // (80, 140, 255)
color SP_COL_BY = 0xFF64DC64;   // (100, 220, 100)
color SP_COL_BZ = 0xFFFFA03C;   // (255, 160, 60)

// ============================================================
void initPlot() {
  _spBx = new float[PLOT_HISTORY];
  _spBy = new float[PLOT_HISTORY];
  _spBz = new float[PLOT_HISTORY];
  _spHead  = 0;
  _spCount = 0;
  println("[SensorPlot] Ring buffer ready (" + PLOT_HISTORY + " frames)");
}

// ============================================================
// Push current sensor reading into ring buffer
// ============================================================
void updatePlot() {
  _spBx[_spHead] = sensorBx;
  _spBy[_spHead] = sensorBy;
  _spBz[_spHead] = sensorBz;
  _spHead = (_spHead + 1) % PLOT_HISTORY;
  if (_spCount < PLOT_HISTORY) _spCount++;
}

// ============================================================
// Draw the waveform chart
// ============================================================
void drawPlot() {
  if (_spCount < 2) return;

  // --- panel background ---
  fill(20, 22, 30);
  noStroke();
  rect(SP_X, SP_Y, SP_W, SP_H, 6);

  // --- compute Y range across all stored data ---
  float yMin = Float.MAX_VALUE;
  float yMax = -Float.MAX_VALUE;
  for (int i = 0; i < _spCount; i++) {
    int idx = ringIndex(i);
    yMin = min(yMin, min(_spBx[idx], min(_spBy[idx], _spBz[idx])));
    yMax = max(yMax, max(_spBx[idx], max(_spBy[idx], _spBz[idx])));
  }

  // pad range by 10%
  float yRange = yMax - yMin;
  if (yRange < 0.1) yRange = 0.1;
  float padding = yRange * 0.1;
  yMin -= padding;
  yMax += padding;

  // --- chart area (inside panel, leave margin for labels) ---
  int cLeft   = SP_X + 60;
  int cRight  = SP_X + SP_W - 20;
  int cTop    = SP_Y + 28;
  int cBottom = SP_Y + SP_H - 24;
  int cW = cRight - cLeft;
  int cH = cBottom - cTop;

  // --- grid lines + Y axis ticks ---
  stroke(50, 52, 65);
  strokeWeight(0.5);
  int numTicks = 5;
  textSize(9);
  textAlign(RIGHT, CENTER);
  fill(100);
  for (int t = 0; t <= numTicks; t++) {
    float frac = (float) t / numTicks;
    int ly = cBottom - (int)(frac * cH);
    line(cLeft, ly, cRight, ly);
    float val = yMin + frac * (yMax - yMin);
    text(nf(val, 1, 1), cLeft - 4, ly);
  }

  // --- baseline reference lines (dashed style: short segments) ---
  if (isBaselineDone()) {
    float[] baselines = { baselineX, baselineY, baselineZ };
    color[] blColors  = { SP_COL_BX, SP_COL_BY, SP_COL_BZ };
    for (int b = 0; b < 3; b++) {
      float bVal = baselines[b];
      if (bVal >= yMin && bVal <= yMax) {
        float by = map(bVal, yMin, yMax, cBottom, cTop);
        stroke(blColors[b], 60);
        strokeWeight(0.5);
        // dashed line
        for (int dx = cLeft; dx < cRight; dx += 8) {
          line(dx, by, min(dx + 4, cRight), by);
        }
      }
    }
  }

  // --- draw waveform lines ---
  noFill();
  strokeWeight(1.5);

  drawWaveLine(_spBx, SP_COL_BX, cLeft, cRight, cTop, cBottom, yMin, yMax);
  drawWaveLine(_spBy, SP_COL_BY, cLeft, cRight, cTop, cBottom, yMin, yMax);
  drawWaveLine(_spBz, SP_COL_BZ, cLeft, cRight, cTop, cBottom, yMin, yMax);

  noStroke();

  // --- legend (top-left of chart) ---
  int legX = cLeft + 8;
  int legY = cTop + 4;
  textSize(11);
  textAlign(LEFT, TOP);

  fill(SP_COL_BX);
  text("Bx: " + nf(sensorBx, 1, 2), legX, legY);
  fill(SP_COL_BY);
  text("By: " + nf(sensorBy, 1, 2), legX + 130, legY);
  fill(SP_COL_BZ);
  text("Bz: " + nf(sensorBz, 1, 2), legX + 260, legY);

  // --- unit label ---
  fill(80);
  textSize(9);
  textAlign(LEFT, TOP);
  text("uT", SP_X + 10, cTop);

  // --- bottom label ---
  fill(90);
  textSize(10);
  textAlign(CENTER, TOP);
  text("Sensor Waveform (last " + _spCount + " frames)", SP_X + SP_W / 2, SP_Y + SP_H - 18);

  // --- reset text state ---
  textAlign(LEFT, BASELINE);
  textSize(14);
  noStroke();
}

// ============================================================
// Draw a single axis waveform from the ring buffer
// ============================================================
void drawWaveLine(float[] buf, color col, int cL, int cR, int cT, int cB,
                  float yMin, float yMax) {
  stroke(col);
  beginShape();
  for (int i = 0; i < _spCount; i++) {
    int idx = ringIndex(i);
    float xPos = map(i, 0, _spCount - 1, cL, cR);
    float yPos = map(buf[idx], yMin, yMax, cB, cT);
    vertex(xPos, yPos);
  }
  endShape();
}

// ============================================================
// Ring buffer index: sample 0 = oldest, sample _spCount-1 = newest
// ============================================================
int ringIndex(int sampleAge) {
  return (_spHead - _spCount + sampleAge + PLOT_HISTORY) % PLOT_HISTORY;
}

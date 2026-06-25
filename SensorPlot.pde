// ============================================================
// SensorPlot.pde
// Real-time scrolling waveform of Bx / By / Bz sensor readings.
// ============================================================

static final int SP_X = 450;
static final int SP_Y = 630;
static final int SP_W = 610;   // widened into the space freed by compacting Axis Ranges
static final int SP_H = 280;

static final int PLOT_HISTORY = 600;   // ring-buffer capacity (max points the slider can show)

float[] _spBx, _spBy, _spBz;
int _spHead = 0;
int _spCount = 0;

// --- display-count control (how many of the buffered points to draw) ---
static final int SP_PTS_MIN = 50;
static final int SP_PTS_MAX = 600;
static final int SP_PTS_DEFAULT = 200;
int spDisplayCount = SP_PTS_DEFAULT;
boolean _spSliderDragging = false;

// points slider (horizontal) + reset button, in the panel's bottom strip
static final int SP_SLD_L = SP_X + 60;
static final int SP_SLD_R = SP_X + 60 + 340;
static final int SP_SLD_Y = SP_Y + SP_H - 12;
static final int SP_RST_W = 58;
static final int SP_RST_H = 18;
static final int SP_RST_X = SP_X + SP_W - SP_RST_W - 12;
static final int SP_RST_Y = SP_Y + SP_H - 22;

color SP_COL_BX = 0xFF5A92FF;
color SP_COL_BY = 0xFF66E07D;
color SP_COL_BZ = 0xFFFFA23D;

void initPlot() {
  _spBx = new float[PLOT_HISTORY];
  _spBy = new float[PLOT_HISTORY];
  _spBz = new float[PLOT_HISTORY];
  _spHead = 0;
  _spCount = 0;
  println("[SensorPlot] Ring buffer ready (" + PLOT_HISTORY + " frames)");
}

void updatePlot() {
  if (!isCurrentSensorFrameFinite()) {
    println("[SensorPlot] Skipped invalid waveform sample.");
    return;
  }

  _spBx[_spHead] = sensorBx;
  _spBy[_spHead] = sensorBy;
  _spBz[_spHead] = sensorBz;
  _spHead = (_spHead + 1) % PLOT_HISTORY;
  if (_spCount < PLOT_HISTORY) _spCount++;
}

void drawPlot() {
  if (_spCount < 2) return;

  drawPanelBase(SP_X, SP_Y, SP_W, SP_H, "Magnetic Delta Waveform");

  int shown = min(spDisplayCount, _spCount);   // draw only the last N points
  int startAge = _spCount - shown;

  float yMin = Float.MAX_VALUE;
  float yMax = -Float.MAX_VALUE;
  int finiteCount = 0;

  for (int k = 0; k < shown; k++) {
    int idx = ringIndex(startAge + k);
    if (!areFiniteValues(_spBx[idx], _spBy[idx], _spBz[idx])) continue;

    float bx = plotDelta(_spBx[idx], baselineX);
    float by = plotDelta(_spBy[idx], baselineY);
    float bz = plotDelta(_spBz[idx], baselineZ);
    yMin = min(yMin, min(bx, min(by, bz)));
    yMax = max(yMax, max(bx, max(by, bz)));
    finiteCount++;
  }

  if (finiteCount < 2) return;

  yMin = min(yMin, 0);
  yMax = max(yMax, 0);
  float yRange = yMax - yMin;
  if (yRange < 0.1) yRange = 0.1;
  float padding = yRange * 0.1;
  yMin -= padding;
  yMax += padding;

  int cLeft = SP_X + 60;
  int cRight = SP_X + SP_W - 20;
  int cTop = SP_Y + 28;
  int cBottom = SP_Y + SP_H - 24;
  int cH = cBottom - cTop;

  stroke(UI_GRID);
  strokeWeight(0.5);
  int numTicks = 5;
  useMonoFont(9);
  textAlign(RIGHT, CENTER);
  fill(UI_DIM);
  for (int t = 0; t <= numTicks; t++) {
    float frac = (float) t / numTicks;
    int ly = cBottom - (int)(frac * cH);
    line(cLeft, ly, cRight, ly);
    float val = yMin + frac * (yMax - yMin);
    text(nf(val, 1, 1), cLeft - 4, ly);
  }

  if (yMin <= 0 && yMax >= 0) {
    float zeroY = map(0, yMin, yMax, cBottom, cTop);
    stroke(UI_BORDER, 190);
    strokeWeight(1);
    for (int dx = cLeft; dx < cRight; dx += 10) {
      line(dx, zeroY, min(dx + 5, cRight), zeroY);
    }
  }

  noFill();
  strokeWeight(1.7);
  drawWaveLine(_spBx, baselineX, SP_COL_BX, cLeft, cRight, cTop, cBottom, yMin, yMax, startAge, shown);
  drawWaveLine(_spBy, baselineY, SP_COL_BY, cLeft, cRight, cTop, cBottom, yMin, yMax, startAge, shown);
  drawWaveLine(_spBz, baselineZ, SP_COL_BZ, cLeft, cRight, cTop, cBottom, yMin, yMax, startAge, shown);
  noStroke();

  int legX = cLeft + 8;
  int legY = cTop + 4;
  useMonoFont(11);
  textAlign(LEFT, TOP);

  fill(SP_COL_BX);
  text("dBx " + nf(sensorBx - baselineX, 1, 2), legX, legY);
  fill(SP_COL_BY);
  text("dBy " + nf(sensorBy - baselineY, 1, 2), legX + 160, legY);
  fill(SP_COL_BZ);
  text("dBz " + nf(sensorBz - baselineZ, 1, 2), legX + 320, legY);

  fill(UI_DIM);
  useUIFont(9);
  textAlign(LEFT, TOP);
  text("uT", SP_X + 14, cTop);

  // points control: horizontal slider (display count) + reset
  drawPlotSlider();
  drawPlotReset(isPlotResetHit(uiMouseX(), uiMouseY()));

  textAlign(LEFT, BASELINE);
  useUIFont(14);
  noStroke();
}

float plotDelta(float value, float baseline) {
  return isBaselineDone() ? value - baseline : value;
}

void drawWaveLine(float[] buf, float baseline, color col, int cL, int cR, int cT, int cB,
                  float yMin, float yMax, int startAge, int shown) {
  stroke(col);
  boolean drawing = false;

  for (int k = 0; k < shown; k++) {
    int idx = ringIndex(startAge + k);
    float value = plotDelta(buf[idx], baseline);

    if (!isFiniteValue(value)) {
      if (drawing) {
        endShape();
        drawing = false;
      }
      continue;
    }

    if (!drawing) {
      beginShape();
      drawing = true;
    }

    float xPos = map(k, 0, shown - 1, cL, cR);
    float yPos = map(value, yMin, yMax, cB, cT);
    vertex(xPos, yPos);
  }

  if (drawing) endShape();
}

int ringIndex(int sampleAge) {
  return (_spHead - _spCount + sampleAge + PLOT_HISTORY) % PLOT_HISTORY;
}

// ============================================================
// Points control — horizontal slider (display count) + reset
// ============================================================
void drawPlotSlider() {
  noStroke();
  fill(UI_PANEL_HI);
  rect(SP_SLD_L, SP_SLD_Y - 2.5, SP_SLD_R - SP_SLD_L, 5, 3);

  float frac = constrain((spDisplayCount - SP_PTS_MIN) / (float)(SP_PTS_MAX - SP_PTS_MIN), 0, 1);
  float hx = SP_SLD_L + frac * (SP_SLD_R - SP_SLD_L);
  boolean hover = isPlotSliderHit(uiMouseX(), uiMouseY()) || _spSliderDragging;
  fill(hover ? UI_BORDER_ACTIVE : UI_TEXT);
  ellipse(hx, SP_SLD_Y, 13, 13);

  fill(UI_MUTED);
  useMonoFont(10);
  textAlign(LEFT, CENTER);
  text(spDisplayCount + " pts", SP_SLD_R + 14, SP_SLD_Y + 1);
  textAlign(LEFT, BASELINE);
  useUIFont(14);
}

boolean isPlotSliderHit(float mx, float my) {
  return mx >= SP_SLD_L - 8 && mx <= SP_SLD_R + 8 &&
         my >= SP_SLD_Y - 10 && my <= SP_SLD_Y + 10;
}

void updatePlotSlider() {
  float frac = constrain((uiMouseX() - SP_SLD_L) / (float)(SP_SLD_R - SP_SLD_L), 0, 1);
  spDisplayCount = round(lerp(SP_PTS_MIN, SP_PTS_MAX, frac));
}

void endPlotSliderDrag() {
  _spSliderDragging = false;
}

void resetPlotPoints() {
  spDisplayCount = SP_PTS_DEFAULT;
}

boolean isPlotResetHit(float mx, float my) {
  return mx >= SP_RST_X && mx <= SP_RST_X + SP_RST_W &&
         my >= SP_RST_Y && my <= SP_RST_Y + SP_RST_H;
}

void drawPlotReset(boolean hover) {
  noStroke();
  fill(hover ? UI_BORDER_ACTIVE : UI_PANEL_HI);
  rect(SP_RST_X, SP_RST_Y, SP_RST_W, SP_RST_H, 5);
  fill(UI_TEXT);
  useUIFont(11);
  textAlign(CENTER, CENTER);
  text("Reset", SP_RST_X + SP_RST_W / 2.0, SP_RST_Y + SP_RST_H / 2.0 + 1);
  textAlign(LEFT, BASELINE);
  useUIFont(14);
  noStroke();
}

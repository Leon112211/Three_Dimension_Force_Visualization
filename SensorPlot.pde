// ============================================================
// SensorPlot.pde
// Real-time scrolling waveform of Bx / By / Bz sensor readings.
// ============================================================

static final int SP_X = 450;
static final int SP_Y = 630;
static final int SP_W = 870;
static final int SP_H = 280;

static final int PLOT_HISTORY = 300;

float[] _spBx, _spBy, _spBz;
int _spHead = 0;
int _spCount = 0;

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

  float yMin = Float.MAX_VALUE;
  float yMax = -Float.MAX_VALUE;
  int finiteCount = 0;

  for (int i = 0; i < _spCount; i++) {
    int idx = ringIndex(i);
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
  drawWaveLine(_spBx, baselineX, SP_COL_BX, cLeft, cRight, cTop, cBottom, yMin, yMax);
  drawWaveLine(_spBy, baselineY, SP_COL_BY, cLeft, cRight, cTop, cBottom, yMin, yMax);
  drawWaveLine(_spBz, baselineZ, SP_COL_BZ, cLeft, cRight, cTop, cBottom, yMin, yMax);
  noStroke();

  int legX = cLeft + 8;
  int legY = cTop + 4;
  useMonoFont(11);
  textAlign(LEFT, TOP);

  fill(SP_COL_BX);
  text("dBx " + nf(sensorBx - baselineX, 1, 2), legX, legY);
  fill(SP_COL_BY);
  text("dBy " + nf(sensorBy - baselineY, 1, 2), legX + 140, legY);
  fill(SP_COL_BZ);
  text("dBz " + nf(sensorBz - baselineZ, 1, 2), legX + 280, legY);

  fill(UI_DIM);
  useUIFont(9);
  textAlign(LEFT, TOP);
  text("uT", SP_X + 14, cTop);

  fill(UI_DIM);
  useUIFont(10);
  textAlign(CENTER, TOP);
  text("last " + _spCount + " valid frames", SP_X + SP_W / 2, SP_Y + SP_H - 18);

  textAlign(LEFT, BASELINE);
  useUIFont(14);
  noStroke();
}

float plotDelta(float value, float baseline) {
  return isBaselineDone() ? value - baseline : value;
}

void drawWaveLine(float[] buf, float baseline, color col, int cL, int cR, int cT, int cB,
                  float yMin, float yMax) {
  stroke(col);
  boolean drawing = false;

  for (int i = 0; i < _spCount; i++) {
    int idx = ringIndex(i);
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

    float xPos = map(i, 0, _spCount - 1, cL, cR);
    float yPos = map(value, yMin, yMax, cB, cT);
    vertex(xPos, yPos);
  }

  if (drawing) endShape();
}

int ringIndex(int sampleAge) {
  return (_spHead - _spCount + sampleAge + PLOT_HISTORY) % PLOT_HISTORY;
}

// ============================================================
// SensorPlot.pde
// Real-time scrolling waveform of Bx / By / Bz sensor readings.
// ============================================================

static final int SP_X = 300;
static final int SP_Y = 630;
static final int SP_W = 1020;
static final int SP_H = 280;

static final int PLOT_HISTORY = 300;

float[] _spBx, _spBy, _spBz;
int _spHead = 0;
int _spCount = 0;

color SP_COL_BX = 0xFF508CFF;
color SP_COL_BY = 0xFF64DC64;
color SP_COL_BZ = 0xFFFFA03C;

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

  fill(20, 22, 30);
  noStroke();
  rect(SP_X, SP_Y, SP_W, SP_H, 6);

  float yMin = Float.MAX_VALUE;
  float yMax = -Float.MAX_VALUE;
  int finiteCount = 0;

  for (int i = 0; i < _spCount; i++) {
    int idx = ringIndex(i);
    if (!areFiniteValues(_spBx[idx], _spBy[idx], _spBz[idx])) continue;

    yMin = min(yMin, min(_spBx[idx], min(_spBy[idx], _spBz[idx])));
    yMax = max(yMax, max(_spBx[idx], max(_spBy[idx], _spBz[idx])));
    finiteCount++;
  }

  if (finiteCount < 2) return;

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

  if (isBaselineDone()) {
    float[] baselines = { baselineX, baselineY, baselineZ };
    color[] blColors = { SP_COL_BX, SP_COL_BY, SP_COL_BZ };
    for (int b = 0; b < 3; b++) {
      float bVal = baselines[b];
      if (isFiniteValue(bVal) && bVal >= yMin && bVal <= yMax) {
        float by = map(bVal, yMin, yMax, cBottom, cTop);
        stroke(blColors[b], 60);
        strokeWeight(0.5);
        for (int dx = cLeft; dx < cRight; dx += 8) {
          line(dx, by, min(dx + 4, cRight), by);
        }
      }
    }
  }

  noFill();
  strokeWeight(1.5);
  drawWaveLine(_spBx, SP_COL_BX, cLeft, cRight, cTop, cBottom, yMin, yMax);
  drawWaveLine(_spBy, SP_COL_BY, cLeft, cRight, cTop, cBottom, yMin, yMax);
  drawWaveLine(_spBz, SP_COL_BZ, cLeft, cRight, cTop, cBottom, yMin, yMax);
  noStroke();

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

  fill(80);
  textSize(9);
  textAlign(LEFT, TOP);
  text("uT", SP_X + 10, cTop);

  fill(90);
  textSize(10);
  textAlign(CENTER, TOP);
  text("Sensor Waveform (last " + _spCount + " frames)", SP_X + SP_W / 2, SP_Y + SP_H - 18);

  textAlign(LEFT, BASELINE);
  textSize(14);
  noStroke();
}

void drawWaveLine(float[] buf, color col, int cL, int cR, int cT, int cB,
                  float yMin, float yMax) {
  stroke(col);
  boolean drawing = false;

  for (int i = 0; i < _spCount; i++) {
    int idx = ringIndex(i);
    float value = buf[idx];

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

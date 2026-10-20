// ============================================================
// TengPanel.pde
// Right-hand column: 4-channel triboelectric (TENG) signals.
//
//   header        : "4 ch | peak-hold", event counter, Reset
//   4 strips      : T1..T4 label, activity LED, value + decaying peak, waveform
//   electrode map : 2x2 quadrant tiles (brightness = recent peak) with the
//                   live XY force arrow and an Fz dot on top
//
// Data entry point: pushTengFrame(t1, t2, t3, t4) — volts, one call per frame.
// Today only the demo source (DemoSource.pde) feeds it; real transports will
// call it once a TENG frame format exists (e.g. Bx,By,Bz,T1..T4).
// ============================================================

static final int TP_X = 1340;
static final int TP_Y = 210;   // below the Material card (MaterialPanel.pde), same row as the 3D/bar/pressure panels
static final int TP_W = 360;
static final int TP_H = 700;

static final int TENG_N = 4;
static final int TENG_HISTORY = 300;        // samples per channel in the ring buffer
static final float TENG_RANGE_V = 3.0;      // waveform half-height (V)
static final float TENG_ACTIVE_V = 0.5;     // LED / event threshold (V)
static final float TENG_PEAK_DECAY = 0.985; // per draw frame

// strip + map geometry (design coords)
static final int TP_STRIP_Y0 = TP_Y + 64;
static final int TP_STRIP_STEP = 112;
static final int TP_STRIP_H = 104;
static final int TP_MAP_Y = TP_Y + 508;
static final int TP_MAP_H = 182;

// Reset button (top-right of the panel)
static final int TP_RST_W = 70;
static final int TP_RST_H = 22;
static final int TP_RST_X = TP_X + TP_W - TP_RST_W - 10;
static final int TP_RST_Y = TP_Y + 5;

// Electrode quadrant per channel: {col, row} with col 0 = left, row 0 = top.
// T1 top-left, T2 top-right, T3 bottom-left, T4 bottom-right.
static final int[][] TENG_QUADRANT = { {0, 0}, {1, 0}, {0, 1}, {1, 1} };

float[][] _tpBuf;
int _tpHead = 0;
int _tpCount = 0;
float[] tengV = new float[TENG_N];      // latest value per channel (V)
float[] _tpPeak = new float[TENG_N];    // decaying |peak| per channel (V)
int tengEvents = 0;
boolean _tpAboveThr = false;            // hysteresis state for event counting

void initTengPanel() {
  _tpBuf = new float[TENG_N][TENG_HISTORY];
  clearTengPanel();
}

// Drop all buffered data (new session / source change).
void clearTengPanel() {
  if (_tpBuf == null) return;
  for (int c = 0; c < TENG_N; c++) {
    for (int k = 0; k < TENG_HISTORY; k++) _tpBuf[c][k] = 0;
    tengV[c] = 0;
  }
  _tpHead = 0;
  _tpCount = 0;
  resetTengPeaks();
}

// Reset button: clear peaks and the event counter, keep the waveform.
void resetTengPeaks() {
  for (int c = 0; c < TENG_N; c++) _tpPeak[c] = 0;
  tengEvents = 0;
  _tpAboveThr = false;
}

void pushTengFrame(float t1, float t2, float t3, float t4) {
  if (_tpBuf == null) return;
  float[] v = { t1, t2, t3, t4 };
  float maxAbs = 0;
  for (int c = 0; c < TENG_N; c++) {
    if (!isFiniteValue(v[c])) return;   // drop the whole frame on a bad value
  }
  for (int c = 0; c < TENG_N; c++) {
    tengV[c] = v[c];
    _tpBuf[c][_tpHead] = v[c];
    _tpPeak[c] = max(_tpPeak[c], abs(v[c]));
    maxAbs = max(maxAbs, abs(v[c]));
  }
  _tpHead = (_tpHead + 1) % TENG_HISTORY;
  if (_tpCount < TENG_HISTORY) _tpCount++;

  // one event per pulse: count on crossing the threshold, re-arm below half of it
  if (!_tpAboveThr && maxAbs > TENG_ACTIVE_V) {
    tengEvents++;
    _tpAboveThr = true;
  } else if (_tpAboveThr && maxAbs < TENG_ACTIVE_V * 0.5) {
    _tpAboveThr = false;
  }
}

boolean isTengResetHit(float mx, float my) {
  return mx >= TP_RST_X && mx <= TP_RST_X + TP_RST_W &&
         my >= TP_RST_Y && my <= TP_RST_Y + TP_RST_H;
}

color tengColor(int c) {
  if (c == 0) return UI_T1;
  if (c == 1) return UI_T2;
  if (c == 2) return UI_T3;
  return UI_T4;
}

// ============================================================
void drawTengPanel() {
  for (int c = 0; c < TENG_N; c++) _tpPeak[c] *= TENG_PEAK_DECAY;

  drawPanelBase(TP_X, TP_Y, TP_W, TP_H, "Triboelectric (TENG)");
  drawTengResetButton(isTengResetHit(uiMouseX(), uiMouseY()));

  useUIFont(12);
  textAlign(LEFT, TOP);
  fill(UI_MUTED);
  text("4 ch  |  peak-hold", TP_X + 16, TP_Y + 34);
  textAlign(RIGHT, TOP);
  fill(UI_TEXT);
  text("events " + tengEvents, TP_X + TP_W - 16, TP_Y + 34);

  boolean hasData = _tpCount > 0;
  for (int c = 0; c < TENG_N; c++) {
    drawTengStrip(c, TP_X + 10, TP_STRIP_Y0 + c * TP_STRIP_STEP, TP_W - 20, TP_STRIP_H, hasData);
  }
  drawTengMap(TP_X + 10, TP_MAP_Y, TP_W - 20, TP_MAP_H, hasData);

  if (!hasData) {
    fill(UI_MUTED);
    useUIFont(13);
    textAlign(CENTER, CENTER);
    text("No TENG input", TP_X + TP_W / 2.0, TP_STRIP_Y0 + 2 * TP_STRIP_STEP - 5);
  }

  textAlign(LEFT, BASELINE);
  useUIFont(14);
  noStroke();
}

void drawTengStrip(int c, int x, int y, int w, int h, boolean hasData) {
  color col = tengColor(c);
  noStroke();
  fill(UI_PANEL_2);
  rect(x, y, w, h, 6);

  // label + activity LED
  useUIFont(16);
  textAlign(LEFT, TOP);
  fill(col);
  text("T" + (c + 1), x + 12, y + 10);
  boolean active = hasData && abs(tengV[c]) > TENG_ACTIVE_V;
  fill(active ? col : color(58, 66, 86));
  ellipse(x + 56, y + 19, 10, 10);

  // value + decaying peak (right-aligned)
  if (hasData) {
    useMonoFont(15);
    textAlign(RIGHT, TOP);
    fill(UI_TEXT);
    String sign = tengV[c] >= 0 ? "+" : "";
    text(sign + nf(tengV[c], 1, 2) + " V", x + w - 12, y + 8);
    useUIFont(11);
    fill(UI_MUTED);
    text("peak " + nf(_tpPeak[c], 1, 2) + " V", x + w - 12, y + 30);
  }

  // waveform area with dashed zero line
  float gx = x + 12, gw = w - 24;
  float gy = y + 44, gh = h - 52;
  float zy = gy + gh / 2.0;
  stroke(UI_GRID);
  strokeWeight(1);
  for (float dx = 0; dx < gw; dx += 8) line(gx + dx, zy, gx + min(dx + 4, gw), zy);

  if (hasData && _tpCount >= 2) {
    noFill();
    stroke(col);
    strokeWeight(1.6);
    beginShape();
    int n = _tpCount;
    int start = (_tpHead - n + TENG_HISTORY) % TENG_HISTORY;
    for (int k = 0; k < n; k++) {
      float v = constrain(_tpBuf[c][(start + k) % TENG_HISTORY], -TENG_RANGE_V, TENG_RANGE_V);
      float px = gx + gw * (k + TENG_HISTORY - n) / (float) (TENG_HISTORY - 1);  // newest at right
      vertex(px, zy - v / TENG_RANGE_V * (gh / 2.0));
    }
    endShape();
  }
  noStroke();
}

void drawTengMap(int x, int y, int w, int h, boolean hasData) {
  noStroke();
  fill(UI_PANEL_2);
  rect(x, y, w, h, 6);

  useUIFont(13);
  textAlign(LEFT, TOP);
  fill(UI_TEXT);
  text("Electrode map", x + 12, y + 10);
  useUIFont(11);
  fill(UI_MUTED);
  text("2 x 2 quadrants", x + 12, y + 30);
  // legend for the live force overlay drawn on top of the tiles
  text("dot  = Fz", x + 12, y + h - 44);
  text("line = Fxy", x + 12, y + h - 26);

  float cx = x + w / 2.0;
  float cy = y + h / 2.0 + 14;
  float tw = 60, th = 50, gap = 6;
  for (int c = 0; c < TENG_N; c++) {
    float tx = cx + (TENG_QUADRANT[c][0] == 0 ? -gap / 2 - tw : gap / 2);
    float ty = cy + (TENG_QUADRANT[c][1] == 0 ? -gap / 2 - th : gap / 2);
    float a = hasData ? constrain(_tpPeak[c] / TENG_RANGE_V, 0, 1) : 0;
    color col = tengColor(c);
    fill(red(col), green(col), blue(col), 45 + 210 * a);
    rect(tx, ty, tw, th, 6);
    fill(UI_PANEL);
    useUIFont(12);
    textAlign(LEFT, TOP);
    text("T" + (c + 1), tx + 8, ty + 6);
  }

  // live force overlay: XY arrow (scaled to the X range) + Fz dot (scaled to Z range)
  float reach = tw + gap / 2;
  float ax = constrain(forceX / rangeX, -1, 1) * reach;
  float ay = constrain(forceY / rangeY, -1, 1) * reach;
  stroke(UI_TEXT);
  strokeWeight(2.5);
  line(cx, cy, cx + ax, cy - ay);
  noStroke();
  fill(UI_TEXT);
  float dot = 6 + 12 * constrain(forceZ / rangeZ, 0, 1);
  ellipse(cx, cy, dot, dot);
}

void drawTengResetButton(boolean hover) {
  noStroke();
  fill(hover ? UI_BORDER_ACTIVE : UI_PANEL_HI);
  rect(TP_RST_X, TP_RST_Y, TP_RST_W, TP_RST_H, 4);
  fill(UI_TEXT);
  useUIFont(11);
  textAlign(CENTER, CENTER);
  text("Reset", TP_RST_X + TP_RST_W / 2.0, TP_RST_Y + TP_RST_H / 2.0);
}

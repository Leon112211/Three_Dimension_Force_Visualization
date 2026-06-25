// ============================================================
// RangePanel.pde
// Global per-axis display ranges (full-scale force, N) that drive
// EVERY visualization panel. Three vertical sliders (X / Y / Z) plus
// an XY lock (default on) that keeps the X and Y ranges equal and in
// sync. Sliders use a squared map for fine resolution at low force.
//
// Public API:
//   initRangePanel()  — call in setup()
//   drawRangePanel()  — call in draw()
//   rangeXY()         — combined XY full-scale for the compass
//   Mouse: rangeSliderHit / updateRangeSlider / endRangeDrag
//          isRangeLockHit / toggleRangeLock
//
// Public globals: rangeX, rangeY, rangeZ, rangeXYLocked, _rangeDragging
// ============================================================

float rangeX = 5.0;      // full-scale N for X
float rangeY = 5.0;      // full-scale N for Y
float rangeZ = 20.0;     // full-scale N for Z (compression-only)
boolean rangeXYLocked = true;

static final float RANGE_MIN = 0.2;
static final float RANGE_MAX = 50.0;

// --- panel layout (bottom row, right of the waveform) ---
static final int RP_X = 1080;
static final int RP_Y = 630;
static final int RP_W = 240;
static final int RP_H = 280;

// XY lock button (top-right of the panel)
static final int RP_LOCK_W = 74;
static final int RP_LOCK_H = 22;
static final int RP_LOCK_X = RP_X + RP_W - RP_LOCK_W - 12;
static final int RP_LOCK_Y = RP_Y + 8;

// slider tracks
static final int RP_TRACK_TOP = RP_Y + 64;
static final int RP_TRACK_BOT = RP_Y + RP_H - 44;
static final int RP_TRACK_W   = 6;
int[] _rpColX = { RP_X + 50, RP_X + 120, RP_X + 190 };   // column centers (X, Y, Z)

int _rangeDragging = -1;   // 0=X, 1=Y, 2=Z, -1=none

void initRangePanel() {
  println("[RangePanel] Axis ranges X=" + rangeX + " Y=" + rangeY + " Z=" + rangeZ
          + "  (XY lock = " + rangeXYLocked + ")");
}

// Combined XY full-scale — keeps the compass arrow's true physical direction.
float rangeXY() {
  return sqrt(rangeX * rangeX + rangeY * rangeY);
}

// ============================================================
void drawRangePanel() {
  drawPanelBase(RP_X, RP_Y, RP_W, RP_H, "Axis Ranges");

  drawRangeLockButton(isRangeLockHit(uiMouseX(), uiMouseY()));

  String[] labels = { "X", "Y", "Z" };
  color[]  cols   = { UI_X, UI_Y, UI_Z };
  float[]  vals   = { rangeX, rangeY, rangeZ };
  for (int i = 0; i < 3; i++) {
    drawRangeSlider(i, labels[i], cols[i], vals[i]);
  }

  textAlign(LEFT, BASELINE);
  useUIFont(14);
  noStroke();
}

void drawRangeSlider(int i, String label, color c, float val) {
  float cx = _rpColX[i];
  float trackH = RP_TRACK_BOT - RP_TRACK_TOP;

  // axis letter above
  fill(c);
  useUIFont(13);
  textAlign(CENTER, BASELINE);
  text(label, cx, RP_TRACK_TOP - 10);

  // value below
  fill(UI_TEXT);
  useMonoFont(10);
  textAlign(CENTER, TOP);
  text(nf(val, 1, 1), cx, RP_TRACK_BOT + 8);

  // track
  noStroke();
  fill(UI_PANEL_HI);
  rect(cx - RP_TRACK_W / 2.0, RP_TRACK_TOP, RP_TRACK_W, trackH, 3);

  // filled portion (axis color) from bottom up to the handle
  float frac = sqrt(constrain((val - RANGE_MIN) / (RANGE_MAX - RANGE_MIN), 0, 1));
  float hy = RP_TRACK_BOT - frac * trackH;
  fill(c, 130);
  rect(cx - RP_TRACK_W / 2.0, hy, RP_TRACK_W, RP_TRACK_BOT - hy, 3);

  // handle (X and Y light up together while locked)
  boolean hover = (_rangeDragging == i) || isRangeSliderHit(i, uiMouseX(), uiMouseY());
  if (rangeXYLocked && (i == 0 || i == 1)) {
    if (_rangeDragging == 0 || _rangeDragging == 1 ||
        isRangeSliderHit(0, uiMouseX(), uiMouseY()) ||
        isRangeSliderHit(1, uiMouseX(), uiMouseY())) {
      hover = true;
    }
  }
  fill(hover ? UI_BORDER_ACTIVE : UI_TEXT);
  ellipse(cx, hy, 14, 14);
}

// ============================================================
// Slider hit-testing / dragging (squared map: fine low-end resolution)
// ============================================================
boolean isRangeSliderHit(int i, float mx, float my) {
  float cx = _rpColX[i];
  return mx >= cx - 11 && mx <= cx + 11 &&
         my >= RP_TRACK_TOP - 10 && my <= RP_TRACK_BOT + 10;
}

int rangeSliderHit(float mx, float my) {
  for (int i = 0; i < 3; i++) {
    if (isRangeSliderHit(i, mx, my)) return i;
  }
  return -1;
}

void updateRangeSlider(int i) {
  float frac = constrain((RP_TRACK_BOT - uiMouseY()) /
                         (float)(RP_TRACK_BOT - RP_TRACK_TOP), 0, 1);
  float v = RANGE_MIN + (RANGE_MAX - RANGE_MIN) * frac * frac;   // squared map
  if (i == 0) {
    rangeX = v;
    if (rangeXYLocked) rangeY = v;
  } else if (i == 1) {
    rangeY = v;
    if (rangeXYLocked) rangeX = v;
  } else {
    rangeZ = v;
  }
}

void endRangeDrag() {
  _rangeDragging = -1;
}

// ============================================================
// XY lock button
// ============================================================
boolean isRangeLockHit(float mx, float my) {
  return mx >= RP_LOCK_X && mx <= RP_LOCK_X + RP_LOCK_W &&
         my >= RP_LOCK_Y && my <= RP_LOCK_Y + RP_LOCK_H;
}

void toggleRangeLock() {
  rangeXYLocked = !rangeXYLocked;
  if (rangeXYLocked) rangeY = rangeX;   // snap together when re-locked
  println("[RangePanel] XY lock = " + rangeXYLocked);
}

void drawRangeLockButton(boolean hover) {
  color base = rangeXYLocked ? color(37, 100, 70) : color(64, 68, 78);
  noStroke();
  fill(hover ? lerpColor(base, color(255), 0.18) : base);
  rect(RP_LOCK_X, RP_LOCK_Y, RP_LOCK_W, RP_LOCK_H, 5);
  fill(rangeXYLocked ? UI_GOOD : UI_MUTED);
  useUIFont(11);
  textAlign(CENTER, CENTER);
  text(rangeXYLocked ? "XY Lock" : "XY Free",
       RP_LOCK_X + RP_LOCK_W / 2.0, RP_LOCK_Y + RP_LOCK_H / 2.0 + 1);
  textAlign(LEFT, BASELINE);
  useUIFont(14);
  noStroke();
}

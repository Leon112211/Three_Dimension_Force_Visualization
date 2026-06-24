// ============================================================
// PressureGrid.pde
// Dot-matrix pressure pad: a circular array of green dots that swell
// into force-colored rounded rects (green → red) as local Z-force rises.
//
// Public API:
//   initPressureGrid()   — call in setup()
//   drawPressureGrid()   — call in draw() after baseline done
//   handlePGDrag()       — call from mouseDragged()
//
// Reads globals: forceZ (from Decoupling.pde)
// ============================================================

// --- offscreen P3D buffer ---
PGraphics _pgGrid;

static final int PG_GRID_W = 450;
static final int PG_GRID_H = 400;
static final int PG_GRID_X = 870;
static final int PG_GRID_Y = 210;

// --- mesh parameters ---
static final int   GRID_N     = 30;      // NxN vertices
static final float GRID_SIZE  = 280.0;   // world units extent
static final float PG_SIGMA   = 5.5;     // gaussian spread (grid cells)
static final float FZ_SCALE   = 4.0;     // forceZ -> displacement multiplier
static final float PG_FZ_REF  = 20.0;    // Fz (N) at which center saturates to full red; ≥ this stays red (clamped)

// --- rotation state (free orbit; drag the panel to rotate) ---
static final float PG_DEF_ROTX = 0.0;
static final float PG_DEF_ROTY = 0.0;
float _pgRotX = PG_DEF_ROTX;
float _pgRotY = PG_DEF_ROTY;
boolean _pgDragging = false;

// --- Reset-view button (top-right of the pressure panel) ---
static final int PG_RST_W = 70;
static final int PG_RST_H = 22;
static final int PG_RST_X = PG_GRID_X + PG_GRID_W - PG_RST_W - 10;
static final int PG_RST_Y = PG_GRID_Y + 5;

// --- Deformation-threshold slider (user-adjustable saturation force, N) ---
static final float PG_REF_MIN = 1.0;
static final float PG_REF_MAX = 100.0;
float pgFzRef = PG_FZ_REF;          // current threshold (init = default 20 N)
boolean _pgRefDragging = false;
static final int PG_REF_TRACK_X = PG_GRID_X + PG_GRID_W - 40;   // vertical track x (right side)
static final int PG_REF_TRACK_TOP = PG_GRID_Y + 70;
static final int PG_REF_TRACK_BOT = PG_GRID_Y + PG_GRID_H - 40;
static final int PG_REF_TRACK_W = 6;                            // track thickness

// ============================================================
void initPressureGrid() {
  _pgGrid = createGraphics(PG_GRID_W, PG_GRID_H, P3D);
  println("[PressureGrid] Buffer created (" + PG_GRID_W + "x" + PG_GRID_H + ")");
}

// ============================================================
void drawPressureGrid() {
  float cellSize = GRID_SIZE / GRID_N;
  float halfGrid = GRID_SIZE / 2.0;

  // center displacement driven by Fz
  float centerDisp = forceZ * FZ_SCALE;    // positive Fz = push down

  // --- dot-matrix references (color + size scale with local force) ---
  float refDisp = FZ_SCALE * pgFzRef;    // user-adjustable saturation threshold
  float cx = GRID_N / 2.0;
  float cz = GRID_N / 2.0;
  float sig2 = 2.0 * PG_SIGMA * PG_SIGMA;

  // ---- begin offscreen render ----
  _pgGrid.beginDraw();
  _pgGrid.background(UI_PANEL);
  _pgGrid.noLights();   // flat LED-dot look (no 3D shading)

  _pgGrid.translate(PG_GRID_W / 2, PG_GRID_H * 0.5, 0);
  _pgGrid.rotateX(_pgRotX);
  _pgGrid.rotateY(_pgRotY);

  // === Dot-matrix pressure pad ===
  // Rectangular base (GRID_N×GRID_N dots). Each dot is small + green at rest,
  // and swells into a force-colored rounded rect under the circular Gaussian
  // deformation. Max-size rects keep a gap so they never touch.
  _pgGrid.noStroke();
  float minSize   = cellSize * 0.32;      // rest: small dot
  float maxSize   = cellSize * 0.82;      // max: rounded rect (leaves a gap)
  float maxCorner = cellSize * 0.28;      // caps corner radius -> rounded square
  for (int i = 0; i < GRID_N; i++) {
    for (int j = 0; j < GRID_N; j++) {
      float wx = (i + 0.5) * cellSize - halfGrid;
      float wz = (j + 0.5) * cellSize - halfGrid;
      float dx = (i + 0.5) - cx;
      float dz = (j + 0.5) - cz;
      float disp = centerDisp * exp(-(dx * dx + dz * dz) / sig2);
      float t = constrain(abs(disp) / refDisp, 0, 1);
      float size = lerp(minSize, maxSize, t);
      float cr   = min(size * 0.5, maxCorner);
      _pgGrid.fill(pgHeightColor(disp, refDisp));
      _pgGrid.rect(wx - size / 2, wz - size / 2, size, size, cr);
    }
  }

  _pgGrid.endDraw();

  // ---- blit to main canvas ----
  image(_pgGrid, PG_GRID_X, PG_GRID_Y);

  drawPanelFrame(PG_GRID_X, PG_GRID_Y, PG_GRID_W, PG_GRID_H, "Z-Axis Pressure");
  drawResetViewButton(isResetViewButtonHit(uiMouseX(), uiMouseY()));
  useMonoFont(11);
  fill(UI_TEXT);
  textAlign(RIGHT, TOP);
  text("Fz " + nf(forceZ, 1, 3) + " N", PG_GRID_X + PG_GRID_W - 14, PG_GRID_Y + 32);
  textAlign(LEFT, BASELINE);
  useUIFont(14);

  drawRefSlider();
}

// ============================================================
// Color mapping: force gradient — green (rest) → red (max).
//   t = |displacement| / (FZ_SCALE * pgFzRef)   <- pgFzRef set by the slider
//   t=0   -> green    (no force / rest dot)
//   t=0.5 -> yellow
//   t=1   -> red      (full-scale force)
// ============================================================
color pgHeightColor(float h, float refD) {
  float t = constrain(abs(h) / refD, 0, 1);
  color c0 = color(80, 200, 100);    // green (rest)
  color c1 = color(180, 210, 70);    // yellow-green
  color c2 = color(235, 200, 60);    // yellow
  color c3 = color(240, 140, 60);    // orange
  color c4 = color(240, 74, 62);     // red (max)
  if (t < 0.25f) return lerpColor(c0, c1, t / 0.25f);
  if (t < 0.5f)  return lerpColor(c1, c2, (t - 0.25f) / 0.25f);
  if (t < 0.75f) return lerpColor(c2, c3, (t - 0.5f) / 0.25f);
  return lerpColor(c3, c4, (t - 0.75f) / 0.25f);
}

// ============================================================
// Mouse drag — free orbit of the pressure grid view
// Dragging starts when the press lands inside the panel and continues even if
// the cursor leaves the panel (until release). No pitch clamp -> full 360°.
// ============================================================
void startPGDrag(float mx, float my) {
  if (mx >= PG_GRID_X && mx <= PG_GRID_X + PG_GRID_W &&
      my >= PG_GRID_Y && my <= PG_GRID_Y + PG_GRID_H) {
    _pgDragging = true;
  }
}

void endPGDrag() {
  _pgDragging = false;
}

void handlePGDrag() {
  if (!_pgDragging) return;
  float dx = uiMouseX() - uiPMouseX();
  float dy = uiMouseY() - uiPMouseY();
  _pgRotY += dx * 0.01;          // yaw  (around vertical)
  _pgRotX += dy * 0.01;          // pitch (around horizontal) — unclamped
}

boolean isResetViewButtonHit(float mx, float my) {
  return mx >= PG_RST_X && mx <= PG_RST_X + PG_RST_W &&
         my >= PG_RST_Y && my <= PG_RST_Y + PG_RST_H;
}

void drawResetViewButton(boolean hover) {
  noStroke();
  fill(hover ? UI_BORDER_ACTIVE : UI_PANEL_HI);
  rect(PG_RST_X, PG_RST_Y, PG_RST_W, PG_RST_H, 4);
  fill(UI_TEXT);
  useUIFont(11);
  textAlign(CENTER, CENTER);
  text("Reset", PG_RST_X + PG_RST_W / 2.0, PG_RST_Y + PG_RST_H / 2.0 + 1);
  textAlign(LEFT, BASELINE);
  useUIFont(14);
  noStroke();
}

// Reset the pressure-grid view to the default orbit angle.
void resetPGView() {
  _pgRotX = PG_DEF_ROTX;
  _pgRotY = PG_DEF_ROTY;
}

// ============================================================
// Deformation-threshold slider — user sets the saturation force (N).
// Drag the track/handle to change pgFzRef (force at which color/size max out).
// ============================================================
boolean isRefSliderHit(float mx, float my) {
  return mx >= PG_REF_TRACK_X - 8 && mx <= PG_REF_TRACK_X + PG_REF_TRACK_W + 8 &&
         my >= PG_REF_TRACK_TOP - 10 && my <= PG_REF_TRACK_BOT + 10;
}

void updateRefSlider() {
  float frac = constrain((PG_REF_TRACK_BOT - uiMouseY()) /
                         (float)(PG_REF_TRACK_BOT - PG_REF_TRACK_TOP), 0, 1);
  pgFzRef = lerp(PG_REF_MIN, PG_REF_MAX, frac);   // up = larger threshold
}

void endRefSliderDrag() {
  _pgRefDragging = false;
}

void drawRefSlider() {
  float cx = PG_REF_TRACK_X + PG_REF_TRACK_W / 2.0;
  float trackH = PG_REF_TRACK_BOT - PG_REF_TRACK_TOP;

  // label above, value below
  fill(UI_MUTED);
  useUIFont(11);
  textAlign(CENTER, BASELINE);
  text("Threshold", cx, PG_REF_TRACK_TOP - 8);

  fill(UI_TEXT);
  useMonoFont(10);
  textAlign(CENTER, TOP);
  text(nf(pgFzRef, 1, 1) + "N", cx, PG_REF_TRACK_BOT + 8);

  // track
  noStroke();
  fill(UI_PANEL_HI);
  rect(PG_REF_TRACK_X, PG_REF_TRACK_TOP, PG_REF_TRACK_W, trackH, 3);

  // handle (top = max, bottom = min)
  float frac = constrain((pgFzRef - PG_REF_MIN) / (PG_REF_MAX - PG_REF_MIN), 0, 1);
  float hy = PG_REF_TRACK_BOT - frac * trackH;
  boolean hover = isRefSliderHit(uiMouseX(), uiMouseY()) || _pgRefDragging;
  fill(hover ? UI_BORDER_ACTIVE : UI_TEXT);
  ellipse(cx, hy, 14, 14);

  textAlign(LEFT, BASELINE);
  useUIFont(14);
  noStroke();
}
